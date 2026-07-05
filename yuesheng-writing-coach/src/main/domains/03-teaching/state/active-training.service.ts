/**
 * ActiveTrainingService — Sprint 24 A-2
 *
 * 职责: 主进程侧 ActiveTrainingSession 状态机
 * 设计: 封装 ActiveTrainingStore,提供语义化状态机方法
 *   - start()        : None/InProgress → InProgress (创建新训练)
 *   - advanceStep()  : InProgress → InProgress (推进步骤)
 *   - updateDraft()  : InProgress → InProgress (草稿保存,A-3 强化)
 *   - evaluate()     : InProgress → InProgress (评估结果保存)
 *   - complete()     : InProgress → Completed (写入 completedAt + recordId)
 *   - abort()        : InProgress → Aborted (用户主动取消)
 *   - getActive()    : 读当前 in_progress 训练
 *   - getBySession() : 读最新一行(任意状态,审计用)
 *
 * 状态机边界(决策 D-070 §2.2):
 *   - Complete/Abort 不可恢复,行保留供审计
 *   - 新 start() 时若 sessionId 已有 InProgress,先 abort 旧训练
 *   - 已 Complete/Abort 行不能直接回 InProgress,需新 start() 创建新行
 *
 * 异常隔离(R-028):
 *   - 任何状态机方法错误仅 console.error,不抛出
 *   - 非法转换返回 null(调用方处理)
 *
 * Sprint 24 A-4 增强: 添加 onStateChange 订阅接口,所有状态变更后异步发布事件。
 * 用途: ipc-registry 订阅此事件并推送 IPC 到 renderer,实现渲染层订阅模式。
 *
 * 依据: dev-docs/tasks/sprint-24-plan.md §A-2, §A-4
 */

import type {
  ActiveTraining,
  ActiveTrainingStatus,
  CreateActiveTrainingInput,
  StepResponse,
  SubmissionResultSnapshot,
  TrainingStep,
  UpdateActiveTrainingInput,
} from './active-training.types';
import type { ActiveTrainingStore } from './active-training.store';

/**
 * 状态机内部转换类型(用于状态变更订阅)
 *  - 'start'      : 新训练启动 (None/InProgress → InProgress)
 *  - 'updateDraft': 草稿更新(无状态变更,仅数据更新)
 *  - 'advanceStep': 推进步骤(无状态变更,仅数据更新)
 *  - 'submitStep' : C-4 5 步分步提交(无状态变更,仅数据更新)
 *  - 'evaluate'   : 评估完成(无状态变更,仅数据更新)
 *  - 'complete'   : 完成训练(InProgress → Completed)
 *  - 'abort'      : 中止训练(InProgress → Aborted)
 */
export type ActiveTrainingStateChangeType =
  | 'start'
  | 'updateDraft'
  | 'advanceStep'
  | 'submitStep'
  | 'evaluate'
  | 'complete'
  | 'abort';

/** 状态变更事件载荷 */
export interface ActiveTrainingStateChangeEvent {
  type: ActiveTrainingStateChangeType;
  sessionId: string;
  state: ActiveTraining;
}

/** 状态变更监听器 */
export type ActiveTrainingStateChangeListener = (
  event: ActiveTrainingStateChangeEvent,
) => void;

/** 取消订阅函数 */
export type UnsubscribeActiveTraining = () => void;

export interface StartActiveTrainingInput {
  sessionId: string;
  syndromeId: string;
  challengeId: string;
  challengeName?: string;
  mode?: string;
  steps: TrainingStep[];
  flowType?: 'flow5' | 'legacy';
  trainingFlow?: CreateActiveTrainingInput['trainingFlow'];
  originalQuote?: string;
  constraint?: string;
  source: 'training_triggered' | 'user_request' | 'diagnosis_result' | 'prescription';
}

export interface AdvanceStepInput {
  stepIndex: number;
  /** 同步更新步骤状态(active/completed) */
  steps?: TrainingStep[];
}

export interface EvaluateInput {
  passed: boolean;
  feedback: string;
  score?: number;
}

export class ActiveTrainingService {
  private store: ActiveTrainingStore;
  /** Sprint 24 A-4: 状态变更监听器列表 */
  private stateChangeListeners: ActiveTrainingStateChangeListener[] = [];

  constructor(store: ActiveTrainingStore) {
    this.store = store;
  }

  // ─── 状态机入口 ───

  /**
   * 启动新训练(状态机入口)
   * - 业务规则: 若 sessionId 已有 in_progress 训练,先标记为 aborted
   * - 业务规则: 若 sessionId 最新行已 completed/aborted,创建新行(保留历史)
   * - 失败返回 null(异常隔离)
   * - A-4: 成功后发布 'start' 状态变更事件
   */
  start(input: StartActiveTrainingInput): ActiveTraining | null {
    if (!this.validateStartInput(input)) {
      console.error('[ActiveTrainingService] start: invalid input', input);
      return null;
    }

    // 业务规则:步骤列表不能为空
    if (input.steps.length === 0) {
      console.error('[ActiveTrainingService] start: steps cannot be empty');
      return null;
    }

    const created = this.store.create({
      sessionId: input.sessionId,
      challengeId: input.challengeId,
      challengeName: input.challengeName,
      mode: input.mode,
      steps: input.steps,
      flowType: input.flowType,
      trainingFlow: input.trainingFlow,
      syndromeId: input.syndromeId,
      originalQuote: input.originalQuote,
      constraint: input.constraint,
      source: input.source,
    });

    if (created) {
      this.emitStateChange('start', input.sessionId, created);
    }
    return created;
  }

  /**
   * 推进步骤(状态机内转换)
   * - 要求: 当前必须存在 in_progress 训练
   * - 业务规则: stepIndex 必须 >= 0 且 <= steps.length
   * - 业务规则: 同一 session 已 completed/aborted 时拒绝
   * - A-4: 成功后发布 'advanceStep' 状态变更事件
   */
  advanceStep(sessionId: string, input: AdvanceStepInput): ActiveTraining | null {
    const active = this.getActive(sessionId);
    if (!active) {
      console.warn(
        `[ActiveTrainingService] advanceStep: no in_progress training for session ${sessionId}`,
      );
      return null;
    }

    if (input.stepIndex < 0) {
      console.error('[ActiveTrainingService] advanceStep: stepIndex cannot be negative');
      return null;
    }
    if (input.steps && input.stepIndex >= input.steps.length) {
      console.error(
        `[ActiveTrainingService] advanceStep: stepIndex ${input.stepIndex} out of range (steps=${input.steps.length})`,
      );
      return null;
    }

    const updates: UpdateActiveTrainingInput = {
      currentStepIndex: input.stepIndex,
    };
    if (input.steps) {
      updates.steps = input.steps;
    }

    const updated = this.store.update(sessionId, updates);
    if (updated) {
      this.emitStateChange('advanceStep', sessionId, updated);
    }
    return updated;
  }

  /**
   * C-4: 5 步通用流分步提交
   * - 业务语义: 每步可独立保存回答内容,跨刷新/跨页签存活
   * - 业务规则: stepId 必须 1-5(对应 flow5 的解说/例证/确认/尝试/反馈)
   * - 业务规则: 同一 stepId 多次提交时只保留最后一次
   * - 业务规则: 无 in_progress 训练时拒绝
   * - 不改变 status(始终保持 in_progress)
   *
   * 典型流程(V6.2 FlowPanel):
   *   1. user 在 Step 1(解说)输入理解复述
   *   2. 提交: service.submitFlowStep(sessionId, 1, content)
   *   3. user 跳到 Step 2 → Step 5,每步独立 submitFlowStep
   *   4. Step 5 评估通过后调 complete()
   *
   * @param sessionId 会话 ID
   * @param stepId 1-5 的步骤 ID
   * @param content 用户本步回答内容
   * @returns 更新后的 ActiveTraining
   */
  submitFlowStep(
    sessionId: string,
    stepId: 1 | 2 | 3 | 4 | 5,
    content: string,
  ): ActiveTraining | null {
    if (typeof content !== 'string') {
      console.error('[ActiveTrainingService] submitFlowStep: content must be string');
      return null;
    }
    if (!Number.isInteger(stepId) || stepId < 1 || stepId > 5) {
      console.error(
        `[ActiveTrainingService] submitFlowStep: invalid stepId ${stepId}, must be 1-5`,
      );
      return null;
    }

    const active = this.getActive(sessionId);
    if (!active) {
      console.warn(
        `[ActiveTrainingService] submitFlowStep: no in_progress training for session ${sessionId}`,
      );
      return null;
    }

    // 合并:同 stepId 覆盖,其他保留,按 stepId 升序
    const filtered = active.stepResponses.filter((r) => r.stepId !== stepId);
    const next: StepResponse[] = [
      ...filtered,
      { stepId, content, submittedAt: new Date().toISOString() },
    ].sort((a, b) => a.stepId - b.stepId);

    const updated = this.store.updateStepResponses(sessionId, next);
    if (updated) {
      this.emitStateChange('submitStep', sessionId, updated);
    }
    return updated;
  }

  /**
   * 更新草稿(Sprint 24 A-3 主路径)
   * - 防御性: 内容超过 50K 字符记录 warn(决策 D-070 §2.3)
   * - 异常隔离: 失败仅 console.error
   * - A-4: 成功后发布 'updateDraft' 状态变更事件
   *   (用户继续输入时主进程会高频推送,renderer 应有去抖或合并策略)
   */
  updateDraft(sessionId: string, content: string): ActiveTraining | null {
    if (typeof content !== 'string') {
      console.error('[ActiveTrainingService] updateDraft: content must be string');
      return null;
    }

    const DRAFT_WARN_THRESHOLD = 50_000;
    if (content.length > DRAFT_WARN_THRESHOLD) {
      console.warn(
        `[ActiveTrainingService] updateDraft: draft exceeds ${DRAFT_WARN_THRESHOLD} chars (${content.length})`,
      );
    }

    const active = this.getActive(sessionId);
    if (!active) {
      // 草稿保存失败:可能训练已完成/aborted,静默失败(A-3 防抖场景)
      return null;
    }

    const updated = this.store.update(sessionId, { userDraft: content });
    if (updated) {
      this.emitStateChange('updateDraft', sessionId, updated);
    }
    return updated;
  }

  /**
   * 评估(AI 评分结果)
   * - 不改变状态(保持 in_progress)
   * - 用于 A-2 状态机测试,验证 evaluate 是内部转换
   * - A-4: 成功后发布 'evaluate' 状态变更事件
   */
  evaluate(sessionId: string, result: EvaluateInput): ActiveTraining | null {
    const active = this.getActive(sessionId);
    if (!active) {
      console.warn(
        `[ActiveTrainingService] evaluate: no in_progress training for session ${sessionId}`,
      );
      return null;
    }

    const submissionResult: SubmissionResultSnapshot = {
      passed: result.passed,
      feedback: result.feedback,
      score: result.score,
      evaluatedAt: new Date().toISOString(),
    };

    const updated = this.store.update(sessionId, { submissionResult });
    if (updated) {
      this.emitStateChange('evaluate', sessionId, updated);
    }
    return updated;
  }

  /**
   * 完成训练(InProgress → Completed)
   * - 写入 completedAt + recordId
   * - 业务规则: 同一 session 已 completed/aborted 时拒绝
   * - A-4: 成功后发布 'complete' 状态变更事件
   */
  complete(sessionId: string, recordId: string): ActiveTraining | null {
    if (!recordId || typeof recordId !== 'string') {
      console.error('[ActiveTrainingService] complete: recordId is required');
      return null;
    }

    const active = this.getActive(sessionId);
    if (!active) {
      console.warn(
        `[ActiveTrainingService] complete: no in_progress training for session ${sessionId}`,
      );
      return null;
    }

    const now = new Date().toISOString();
    const updated = this.store.update(sessionId, {
      status: 'completed',
      recordId,
      completedAt: now,
    });
    if (updated) {
      this.emitStateChange('complete', sessionId, updated);
    }
    return updated;
  }

  /**
   * 中止训练(InProgress → Aborted)
   * - 业务规则: 用户主动取消或异常退出
   * - Aborted 后该行保留供审计,新训练需调 start() 创建新行
   * - A-4: 成功后发布 'abort' 状态变更事件
   */
  abort(sessionId: string): ActiveTraining | null {
    const active = this.getActive(sessionId);
    if (!active) {
      console.warn(
        `[ActiveTrainingService] abort: no in_progress training for session ${sessionId}`,
      );
      return null;
    }

    const now = new Date().toISOString();
    const updated = this.store.update(sessionId, {
      status: 'aborted',
      completedAt: now,
    });
    if (updated) {
      this.emitStateChange('abort', sessionId, updated);
    }
    return updated;
  }

  // ─── 读操作 ───

  /**
   * 获取当前进行中的训练(in_progress)
   */
  getActive(sessionId: string): ActiveTraining | null {
    return this.store.getActiveBySession(sessionId);
  }

  /**
   * 获取最新一行(任意状态,供审计/冷启动恢复)
   */
  getBySession(sessionId: string): ActiveTraining | null {
    return this.store.getBySession(sessionId);
  }

  /**
   * 获取所有进行中的训练(全局查询,监控用)
   */
  listActive(): ActiveTraining[] {
    return this.store.listActive();
  }

  /**
   * 按症候查询(诊断联动)
   */
  findBySyndrome(syndromeId: string): ActiveTraining[] {
    return this.store.findBySyndrome(syndromeId);
  }

  /**
   * 获取训练状态字面量(UI 展示用)
   */
  getStatus(sessionId: string): ActiveTrainingStatus | null {
    return this.getBySession(sessionId)?.status ?? null;
  }

  // ─── Sprint 24 A-4: 状态变更订阅接口 ───

  /**
   * 订阅状态变更事件
   * - 所有成功的状态机方法(start/advanceStep/updateDraft/evaluate/complete/abort)
   *   都会触发回调
   * - 回调异常被隔离,不影响其他订阅者
   * - 多次订阅同一 listener 会被注册多次(符合 EventEmitter 行为)
   *
   * @returns 取消订阅函数
   */
  onStateChange(listener: ActiveTrainingStateChangeListener): UnsubscribeActiveTraining {
    this.stateChangeListeners.push(listener);
    return () => {
      const idx = this.stateChangeListeners.indexOf(listener);
      if (idx >= 0) {
        this.stateChangeListeners.splice(idx, 1);
      }
    };
  }

  /**
   * 移除所有状态变更监听器(测试清理用)
   */
  removeAllStateChangeListeners(): void {
    this.stateChangeListeners = [];
  }

  /**
   * 内部工具: 发布状态变更事件
   * - 同步派发所有订阅者
   * - listener 抛错不阻断其他订阅者
   * - 异常隔离(R-028)
   */
  private emitStateChange(
    type: ActiveTrainingStateChangeType,
    sessionId: string,
    state: ActiveTraining,
  ): void {
    const event: ActiveTrainingStateChangeEvent = { type, sessionId, state };
    // 复制一份避免 listener 内部 off 影响本次派发
    for (const listener of [...this.stateChangeListeners]) {
      try {
        listener(event);
      } catch (err) {
        console.error(
          `[ActiveTrainingService] state change listener error on ${type}:`,
          err,
        );
      }
    }
  }

  // ─── 内部工具 ───

  private validateStartInput(input: StartActiveTrainingInput): boolean {
    return Boolean(
      input &&
        input.sessionId &&
        input.challengeId &&
        input.syndromeId &&
        Array.isArray(input.steps) &&
        input.source,
    );
  }
}
