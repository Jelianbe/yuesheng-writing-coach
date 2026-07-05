/**
 * TeachingStateSubscriber — 教学状态机事件订阅器 (Sprint 20 A-3 试点 / Sprint 21 D-2 扩展 / Sprint 24 A-2 扩展)
 *
 * 职责:
 * - 订阅 ChatOrchestratorService 派发的 OrchestratorEvent
 * - 在收到特定事件时调用 TeachingStateService / ActiveTrainingService 对应方法
 * - 事件→动作映射由 resources/config/state-machine-event-mapping.json 声明(R-014)
 *
 * 试点范围(Sprint 20 A-3):
 * - intent:train → 记录 lastTrainEvent + 调用 teachingStateService.getContext 验证集成
 *
 * Sprint 21 D-2 扩展:
 * - 引入 config 驱动 dispatch(enabled 控制开关,避免影响既有 E2E)
 * - intent:train → markTrainingIntent (新) + 保留 A-3 读 + 记录
 * - diagnosis_extracted → recordProblem (新)
 * - phase_transition / training_triggered → disabled 留扩展点
 *
 * Sprint 23 G-1 扩展:
 * - training_triggered → setActiveTraining(轻量业务元数据,写入 teaching_state.active_training_meta)
 *
 * Sprint 24 A-2 扩展:
 * - 新增 training_triggered → startActiveTraining(完整状态机入口)
 * - 接收 ActiveTrainingService(可选,未传则跳过完整状态机路径)
 * - 与 G-1 setActiveTraining 共存:前者写业务元数据,后者写 active_training 表
 * - 步骤构造:从 training-library.json 查 syndromeId 匹配的 entry,组装 TrainingStep[]
 *
 * 依据: dev-docs/tasks/sprint-21-plan.md §D-2 + dev-docs/tasks/sprint-24-plan.md §A-2
 */

import * as fs from 'node:fs';
import * as path from 'node:path';
import type {
  ConversationIntent,
  OrchestratorEvent,
  PhaseTransitionEvent,
  SyndromeEvidence,
} from './orchestrator.types';
import type { TeachingStateService } from '../teaching-state.service';
import type { ActiveTrainingService } from '../state/active-training.service';
import type { TrainingTriggeredEvent } from './orchestrator.types';
import type { TrainingStep } from '../state/active-training.types';

export interface TrainingIntentRecord {
  sessionId: string;
  syndromeId: string;
  techniqueId?: string;
  receivedAt: number;
}

/** 单条 subscriber 声明(对应 config JSON) */
export interface SubscriberMapping {
  eventType: string;
  action: string;
  enabled: boolean;
}

/** config 整体结构 */
export interface StateMachineEventMapping {
  version: string;
  subscribers: SubscriberMapping[];
}

/** 简易 config 解析(Sprint 21 D-2:不引入 YAML 库,直接 JSON.parse) */
function loadMapping(configPath: string): StateMachineEventMapping {
  const raw = fs.readFileSync(configPath, 'utf-8');
  const parsed = JSON.parse(raw) as StateMachineEventMapping;
  if (!parsed.subscribers || !Array.isArray(parsed.subscribers)) {
    throw new Error(`[TeachingStateSubscriber] Invalid mapping: subscribers not array`);
  }
  return parsed;
}

/** eventType 解析(支持 "intent:train" 复合形式) */
function eventTypeOf(event: OrchestratorEvent): string {
  if (event.type === 'intent') {
    const intent = event.payload as ConversationIntent;
    return `intent:${intent.type}`;
  }
  return event.type;
}

/** 教学状态机事件订阅器 */
export class TeachingStateSubscriber {
  private readonly teachingStateService: TeachingStateService;
  private readonly activeTrainingService: ActiveTrainingService | null;
  private readonly mapping: SubscriberMapping[];
  private lastTrainEvent: TrainingIntentRecord | null = null;
  private lastDiagnosisRecord: { sessionId: string; syndromeId: string; severity: string | null } | null = null;
  private lastStartActiveTrainingCall: {
    sessionId: string;
    syndromeId: string;
    techniqueId?: string;
    challengeId: string;
    source: string;
  } | null = null;

  constructor(
    teachingStateService: TeachingStateService,
    configPath?: string,
    activeTrainingService?: ActiveTrainingService,
  ) {
    this.teachingStateService = teachingStateService;
    this.activeTrainingService = activeTrainingService ?? null;

    // 默认 config 路径(resources/config/state-machine-event-mapping.json)
    const resolvedPath = configPath ?? this.resolveDefaultConfigPath();
    try {
      const m = loadMapping(resolvedPath);
      this.mapping = m.subscribers;
    } catch (e) {
      console.warn('[TeachingStateSubscriber] failed to load mapping, using empty:', e);
      this.mapping = [];
    }
  }

  /**
   * 事件处理入口(单一调度)
   * @param event OrchestratorEvent
   * @param sessionId 关联会话
   */
  handle(event: OrchestratorEvent, sessionId: string): void {
    // 1) 查找所有匹配的 subscriber 声明(支持同一事件多个 action)
    const et = eventTypeOf(event);
    const subs = this.mapping.filter(s => s.eventType === et && s.enabled);
    if (subs.length === 0) {
      // 未配置或 disabled:静默跳过(无副作用)
      return;
    }

    // 2) 异常隔离:任何 action 抛错不中断事件流
    for (const sub of subs) {
      try {
        switch (sub.action) {
          case 'markTrainingIntent':
            this.handleMarkTrainingIntent(event, sessionId);
            break;
          case 'recordProblem':
            this.handleRecordProblem(event, sessionId);
            break;
          case 'confirmPhase':
            this.handleConfirmPhase(event, sessionId);
            break;
          case 'setActiveTraining':
            this.handleSetActiveTraining(event, sessionId);
            break;
          case 'startActiveTraining':
            this.handleStartActiveTraining(event, sessionId);
            break;
          default:
            // 未知 action:不抛错,只 warn
            console.warn(`[TeachingStateSubscriber] unknown action: ${sub.action}`);
        }
      } catch (e) {
        console.warn(`[TeachingStateSubscriber] action ${sub.action} failed:`, e);
      }
    }
  }

  // ─── Action handlers ───

  private handleMarkTrainingIntent(event: OrchestratorEvent, sessionId: string): void {
    if (event.type !== 'intent') return;
    const intent = event.payload as ConversationIntent;
    if (intent.type !== 'train') return;

    // A-3 兼容:记录 + 读(getContext)保留为"机制验证"
    this.lastTrainEvent = {
      sessionId,
      syndromeId: intent.syndromeId,
      techniqueId: intent.techniqueId,
      receivedAt: Date.now(),
    };
    try {
      this.teachingStateService.getContext(sessionId);
    } catch (e) {
      console.warn('[TeachingStateSubscriber] getContext failed:', e);
    }

    // D-2 新:写入训练意图到状态
    this.teachingStateService.markTrainingIntent(sessionId, intent.syndromeId, intent.techniqueId);
  }

  private handleRecordProblem(event: OrchestratorEvent, sessionId: string): void {
    if (event.type !== 'diagnosis_extracted') return;
    const evidence = event.payload as SyndromeEvidence;
    this.lastDiagnosisRecord = {
      sessionId,
      syndromeId: evidence.syndromeId,
      severity: evidence.severity,
    };
    this.teachingStateService.recordProblem(
      sessionId,
      evidence.syndromeId,
      evidence.severity,
      evidence.evidenceQuote,
    );
  }

  private handleConfirmPhase(event: OrchestratorEvent, sessionId: string): void {
    if (event.type !== 'phase_transition') return;
    const transition = event.payload as PhaseTransitionEvent;
    // 仅当 to 阶段是已确认阶段时调用 confirmPhase(避免误推进)
    if (!transition.to) return;
    this.teachingStateService.confirmPhase(sessionId);
  }

  private handleSetActiveTraining(event: OrchestratorEvent, sessionId: string): void {
    if (event.type !== 'training_triggered') return;
    const triggered = event.payload as TrainingTriggeredEvent;
    // Sprint 23 G-1: 替换 Sprint 22 F-2 占位实现(markTrainingIntent + console.info)
    // - 业务语义: 主进程侧记录 session 进入 ActiveTraining 状态(业务元数据)
    // - 完整 ActiveTrainingSession 状态机仍在 renderer 侧维护(未变更)
    // - source 字段: 反映触发原因(diagnosis_result / user_request / prescription)
    this.teachingStateService.setActiveTraining(
      sessionId,
      triggered.syndromeId,
      triggered.techniqueId,
      triggered.reason,
    );
  }

  /**
   * Sprint 24 A-2: 启动 ActiveTraining 完整状态机
   * - 接收 training_triggered 事件
   * - 从 training-library.json 查 syndromeId 匹配的训练条目
   * - 组装 TrainingStep[] (3 步通用流:理解 → 尝试 → 确认)
   * - 调用 ActiveTrainingService.start() 写入 active_training 表
   * - 异常隔离: 任何错误仅 console.warn,不抛出
   */
  private handleStartActiveTraining(event: OrchestratorEvent, sessionId: string): void {
    if (event.type !== 'training_triggered') return;
    if (!this.activeTrainingService) {
      // ActiveTrainingService 未注入(测试场景或降级路径),静默跳过
      return;
    }
    const triggered = event.payload as TrainingTriggeredEvent;

    const plan = this.buildTrainingPlan(triggered.syndromeId, triggered.techniqueId);
    this.lastStartActiveTrainingCall = {
      sessionId,
      syndromeId: triggered.syndromeId,
      techniqueId: triggered.techniqueId,
      challengeId: plan.challengeId,
      source: triggered.reason,
    };

    this.activeTrainingService.start({
      sessionId,
      syndromeId: triggered.syndromeId,
      challengeId: plan.challengeId,
      challengeName: plan.challengeName,
      mode: plan.mode,
      steps: plan.steps,
      constraint: plan.constraint,
      source: triggered.reason,
    });
  }

  /**
   * 训练计划构造: 从 training-library.json 查 syndromeId 匹配的训练条目
   * 降级路径: 无匹配时返回通用 3 步计划
   */
  private buildTrainingPlan(
    syndromeId: string,
    techniqueId?: string,
  ): {
    challengeId: string;
    challengeName: string;
    mode: string;
    constraint: string | undefined;
    steps: TrainingStep[];
  } {
    const defaultSteps: TrainingStep[] = [
      { id: 's1', title: '理解挑战', description: '理解训练任务', status: 'active' },
      { id: 's2', title: '尝试改写', description: '按约束改写', status: 'pending' },
      { id: 's3', title: '确认完成', description: '提交评估', status: 'pending' },
    ];

    try {
      const libPath = path.join(
        process.cwd(),
        'resources',
        'config',
        'training-library.json',
      );
      const raw = fs.readFileSync(libPath, 'utf-8');
      const lib = JSON.parse(raw) as {
        entries: Array<{
          id: string;
          syndromeId: string;
          title: string;
          mode?: string;
          constraint?: string;
          expectedOutcome?: string;
        }>;
      };
      const entry = techniqueId
        ? lib.entries.find((e) => e.id === techniqueId)
        : lib.entries.find((e) => e.syndromeId === syndromeId);
      if (entry) {
        return {
          challengeId: entry.id,
          challengeName: entry.title,
          mode: entry.mode ?? 'generic',
          constraint: entry.constraint,
          steps: [
            {
              id: 's1',
              title: '理解挑战',
              description: entry.constraint ?? '理解训练任务',
              status: 'active',
            },
            {
              id: 's2',
              title: '尝试改写',
              description: entry.expectedOutcome ?? '按约束改写',
              status: 'pending',
            },
            {
              id: 's3',
              title: '确认完成',
              description: '提交评估',
              status: 'pending',
            },
          ],
        };
      }
    } catch (e) {
      console.warn('[TeachingStateSubscriber] buildTrainingPlan: training-library load failed, using default:', e);
    }

    return {
      challengeId: `generic-${syndromeId}`,
      challengeName: `${syndromeId} 训练`,
      mode: 'generic',
      constraint: undefined,
      steps: defaultSteps,
    };
  }

  // ─── 测试用 getter ───

  getLastTrainEvent(): TrainingIntentRecord | null {
    return this.lastTrainEvent;
  }

  getLastDiagnosisRecord(): { sessionId: string; syndromeId: string; severity: string | null } | null {
    return this.lastDiagnosisRecord;
  }

  /** Sprint 24 A-2: 测试用 - 最近一次 startActiveTraining 调用 */
  getLastStartActiveTrainingCall(): {
    sessionId: string;
    syndromeId: string;
    techniqueId?: string;
    challengeId: string;
    source: string;
  } | null {
    return this.lastStartActiveTrainingCall;
  }

  getMapping(): SubscriberMapping[] {
    return this.mapping;
  }

  /** 默认 config 路径解析(相对 main 工作目录) */
  private resolveDefaultConfigPath(): string {
    // dev 模式:项目根/resources/config/...
    // 生产模式:resourcesPath/resources/config/...
    // 此处只做 dev 兜底,生产环境由 DI 注入 configPath
    return path.join(process.cwd(), 'resources', 'config', 'state-machine-event-mapping.json');
  }
}
