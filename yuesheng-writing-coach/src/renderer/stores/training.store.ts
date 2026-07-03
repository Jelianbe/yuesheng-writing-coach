/**
 * 训练状态管理（路径 B：训练工坊）— 核心 Store 定义
 *
 * 类型与常量 → training.types.ts
 * 大型 Action  → training.actions.ts
 * 选择器       → training.selectors.ts
 *
 * Sprint 24 A-4 增强:
 *   - 新增 mountActiveTraining(sessionId) action
 *   - 冷启动时从主进程拉取活跃训练(避免刷新页面后丢失)
 *   - 订阅主进程 activeTraining:updated 事件 → 自动同步本地 state
 *   - activeTraining 初值保持 null(主进程推送填充)
 *
 * 依据: dev-docs/tasks/sprint-24-plan.md §A-4
 */

import { create } from 'zustand';
import type { TrainingState } from './training.types';
import {
  createStartAction,
  createSubmitStepAction,
  createEvaluateTrainingAction,
  createDeriveBehaviorAction,
} from './training.actions';
import { createStartReadingAction } from './training-reading.actions';
import { createLoadHistoryAction, createRefreshFromDiagnosisAction } from './training-data.actions';
import { RetroApi } from '../../shared/api-contracts/retro.contract';
import { getInvoke } from '../utils/ipc';
import { activeTrainingService } from '../services/active-training.service';
import type {
  ActiveTrainingGetResponse,
  ActiveTrainingUpdatedEvent,
} from '../../shared/api-contracts/active-training.contract';
import type { ActiveTrainingSession } from '../shared/types';

export { selectCenterMode, selectActiveTraining, selectErrorCards, selectRecommendations, selectTrainingHistory, selectIsLoading } from './training.selectors';
export type { TrainingState, TrainingSubmissionResult } from './training.types';
export { DEFAULT_STEPS, READING_STEPS } from './training.types';

// ===== A-3 草稿防抖持久化 =====
/** 防抖延时(500ms):用户停止输入 0.5s 后再发 IPC,降低主进程压力 */
const DRAFT_PERSIST_DEBOUNCE_MS = 500;
/** 模块级防抖定时器 — 跨多次 updateDraft 调用复用 */
let draftPersistTimer: ReturnType<typeof setTimeout> | null = null;

// ===== A-4 渲染层订阅模式 =====
/** 当前会话的 activeTraining:updated 事件取消订阅函数(全局唯一) */
let activeTrainingUnsub: (() => void) | null = null;

/**
 * 主进程 ActiveTraining 快照 → renderer ActiveTrainingSession 映射
 *
 * 设计原则:
 *   - 主进程是 source of truth(主进程字段覆盖本地)
 *   - 保留本地 renderer-only 字段(challengeDescription/targetSyndrome/corePatterns/longTermProgress)
 *   - 缺失字段用空值兜底(UI 不会出现 undefined)
 */
function mapRemoteToLocal(
  local: ActiveTrainingSession | null,
  remote: ActiveTrainingGetResponse,
): ActiveTrainingSession {
  return {
    challengeId: remote.challengeId,
    challengeName: remote.challengeName ?? remote.challengeId,
    challengeDescription: local?.challengeDescription ?? '',
    mode: remote.mode ?? 'generic',
    steps: remote.steps,
    currentStepIndex: remote.currentStepIndex,
    originalQuote: remote.originalQuote ?? '',
    constraint: remote.constraint ?? '',
    userDraft: remote.userDraft,
    recordId: remote.recordId ?? undefined,
    syndromeId: remote.syndromeId ?? undefined,
    targetSyndrome: local?.targetSyndrome,
    corePatterns: local?.corePatterns,
    longTermProgress: local?.longTermProgress,
    submissionResult: remote.submissionResult
      ? {
          passed: Boolean((remote.submissionResult as { passed?: boolean }).passed),
          feedback: String((remote.submissionResult as { feedback?: string }).feedback ?? ''),
        }
      : undefined,
    trainingFlow: remote.trainingFlow ?? undefined,
    flowType: (remote.flowType ?? 'legacy') as 'flow5' | 'legacy',
  };
}

// ===== Store =====

export const useTrainingStore = create<TrainingState>((set, get) => ({
  centerMode: 'chat',
  errorCards: [],
  recommendations: [],
  activeTraining: null,
  history: [],
  submissionResult: null,
  evaluationResult: null,
  isLoading: false,
  error: null,
  bridgeRecommendation: null,
  readingDecision: null,
  readingComplete: false,
  // A3: 自荐阅读框架
  lastEvaluationScore: null,
  lastSyndromeId: null,
  derivationLoading: false,
  derivationResult: null,
  derivationError: null,
  retroSummary: null,
  retroLoading: false,

  // ===== 模式切换 =====

  enterWorkshop: async () => {
    set({ centerMode: 'training' });
    await get().refreshFromDiagnosis();
    const { useChatStore } = await import('./chat.store');
    const sessionId = useChatStore.getState().currentSessionId;
    if (sessionId) {
      await get().loadHistory(sessionId);
    }
  },

  backToChat: () => {
    const state = get();
    if (state.evaluationResult || state.submissionResult) {
      set({ centerMode: 'chat', activeTraining: null, submissionResult: null, evaluationResult: null });
    } else {
      set({ centerMode: 'chat' });
    }
  },

  // Sprint 3: 进入编辑器
  enterEditor: () => {
    set({ centerMode: 'editor' });
  },

  // ===== 训练操作（大型 action 从 training.actions.ts 引入） =====

  startTraining: createStartAction(set, get),

  /** B-02: 阅读前置任务 */
  startReading: createStartReadingAction(set, get),

  /** M4: 关闭阅读完成横幅 */
  dismissReadingComplete: () => set({ readingComplete: false }),

  /**
   * A-3: 草稿保存 — 本地状态立即更新 + 500ms 防抖触发 IPC 持久化
   *
   * 关键路径:
   *   1. 同步更新 activeTraining.userDraft(UI 立刻响应)
   *   2. 清除上一轮防抖定时器
   *   3. 启动新定时器 — 500ms 后从 chat store 读 sessionId 并发 IPC
   *   4. IPC 失败时 console.error,不重试(R-028 防御性编码)
   */
  updateDraft: (content: string) => {
    set((state) => {
      if (!state.activeTraining) return {};
      return { activeTraining: { ...state.activeTraining, userDraft: content } };
    });

    // 防抖:清除上一轮,启动新轮
    if (draftPersistTimer !== null) {
      clearTimeout(draftPersistTimer);
    }
    draftPersistTimer = setTimeout(() => {
      draftPersistTimer = null;
      // 二次校验:防抖窗口内 activeTraining 可能被清空
      const { activeTraining: current } = get();
      if (!current) return;
      // chat store 用 lazy import 避免循环依赖
      void import('./chat.store').then(({ useChatStore }) => {
        const sessionId = useChatStore.getState().currentSessionId;
        if (!sessionId) return;
        // 读取最新内容(防抖窗口内可能被多次 updateDraft 覆盖)
        const latest = get().activeTraining;
        if (!latest) return;
        void activeTrainingService.updateDraft({
          sessionId,
          content: latest.userDraft,
        });
      });
    }, DRAFT_PERSIST_DEBOUNCE_MS);
  },

  submitStep: createSubmitStepAction(set, get),

  skipTraining: async () => {
    set({ activeTraining: null, error: null, isLoading: false });
  },

  /**
   * A-4: 挂载活跃训练订阅 — 冷启动恢复 + 跨页签同步
   *
   * 工作流:
   *   1. 清理上一会话的旧订阅(如有)
   *   2. 主动 fetch 当前 session 状态(主进程 → renderer 单向拉取)
   *   3. 订阅 activeTraining:updated 事件(主进程 → renderer 推送)
   *   4. 收到推送后,合并主进程状态到本地 state
   *
   * 设计:
   *   - 不替换本地乐观状态(如 startTraining 已设的 challengeDescription/targetSyndrome)
   *   - 只覆盖主进程负责的字段(challengeId/steps/userDraft/currentStepIndex/status 等)
   *   - 异常隔离: fetch 失败不抛错,仅 console.warn
   *
   * 调用时机:
   *   - App 启动且已知 currentSessionId
   *   - 用户切换 session
   *   - 训练视图 mount 时
   */
  mountActiveTraining: async (sessionId: string) => {
    if (!sessionId) {
      console.warn('[TrainingStore] mountActiveTraining: sessionId is empty');
      return;
    }

    // 1. 清理旧订阅
    if (activeTrainingUnsub) {
      try {
        activeTrainingUnsub();
      } catch (err) {
        console.error('[TrainingStore] cleanup previous subscription failed:', err);
      }
      activeTrainingUnsub = null;
    }

    // 2. 主动 fetch 当前状态(冷启动恢复)
    try {
      const remote = await activeTrainingService.get({ sessionId });
      if (remote) {
        set((state) => ({
          activeTraining: mapRemoteToLocal(state.activeTraining, remote),
        }));
      }
    } catch (err) {
      console.error('[TrainingStore] mountActiveTraining: fetch failed:', err);
    }

    // 3. 订阅推送事件
    activeTrainingUnsub = activeTrainingService.subscribe((event: ActiveTrainingUpdatedEvent) => {
      if (event.sessionId !== sessionId) return;
      if (event.type === 'complete' || event.type === 'abort') {
        // 训练已结束:保持可见但标记状态(由 UI 决定何时清空)
        set((state) => ({
          activeTraining: state.activeTraining
            ? mapRemoteToLocal(state.activeTraining, event.state)
            : mapRemoteToLocal(null, event.state),
        }));
        return;
      }
      set((state) => ({
        activeTraining: mapRemoteToLocal(state.activeTraining, event.state),
      }));
    });
  },

  /**
   * A-4: 卸载活跃训练订阅(组件 unmount / session 切换时)
   */
  unmountActiveTraining: () => {
    if (activeTrainingUnsub) {
      try {
        activeTrainingUnsub();
      } catch (err) {
        console.error('[TrainingStore] unmountActiveTraining failed:', err);
      }
      activeTrainingUnsub = null;
    }
  },

  // ===== 数据加载（大型 action 从 training.actions.ts 引入） =====

  loadHistory: createLoadHistoryAction(set, get),

  refreshFromDiagnosis: createRefreshFromDiagnosisAction(set, get),

  // ===== 桥接推荐 =====

  setBridgeRecommendation: (rec) => { set({ bridgeRecommendation: rec }); },
  dismissBridge: () => { set({ bridgeRecommendation: null }); },

  // ===== 评估（从 training.actions.ts 引入） =====

  evaluateTraining: createEvaluateTrainingAction(set, get),

  // ===== C2: 行为推导（从 training.actions.ts 引入） =====

  deriveBehavior: createDeriveBehaviorAction(set, get),
  resetDerivation: () => { set({ derivationResult: null, derivationError: null, derivationLoading: false }); },

  // ===== X-02: 编辑器写入 =====

  sendToEditor: () => {
    const { activeTraining } = get();
    if (!activeTraining?.userDraft) return;
    // 将改写结果暂存到 chapter store 的 pendingRewrite，由编辑器横幅消费
    void import('./chapter.store').then(({ useChapterStore }) => {
      useChapterStore.setState({ pendingRewrite: activeTraining.userDraft });
    });
  },

  // F-03: 进入复盘总结
  enterRetro: async (sessionId: string) => {
    set({ retroLoading: true });
    try {
      const result = await getInvoke()(RetroApi.generate.channel, { sessionId }) as { success: boolean; data: TrainingState['retroSummary'] };
      if (result.success && result.data) {
        set({ retroSummary: result.data, centerMode: 'retro', retroLoading: false });
      } else {
        set({ retroLoading: false });
      }
    } catch (err) {
      console.error('[TrainingStore] enterRetro failed:', err);
      set({ retroLoading: false });
    }
  },
}));
