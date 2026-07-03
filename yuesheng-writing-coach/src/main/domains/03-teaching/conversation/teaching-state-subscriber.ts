/**
 * TeachingStateSubscriber — 教学状态机事件订阅器 (Sprint 20 A-3 试点)
 *
 * 职责:
 * - 订阅 ChatOrchestratorService 派发的 OrchestratorEvent
 * - 在收到特定事件时调用 TeachingStateService 对应方法
 *
 * 试点范围(本类):
 * - intent:train → 调用 teachingStateService.getContext(sessionId) 验证集成
 *   (纯读,无副作用,只为证明"事件 → 状态机方法"链路可工作)
 *
 * 后续(Sprint 21+):
 * - intent:train → 调用新方法 teachingStateService.flagTrainingIntent(...)
 * - phase_transition → 调用 setPhase(...)
 * - diagnosis_extracted → 调用 recordDiagnosis(...)
 *
 * 依据: dev-docs/tasks/sprint-20-plan.md §A-3 / D-057
 */

import type { OrchestratorEvent } from './orchestrator.types';
import type { TeachingStateService } from '../teaching-state.service';

export interface TrainingIntentRecord {
  sessionId: string;
  syndromeId: string;
  techniqueId?: string;
  receivedAt: number;
}

/** 教学状态机事件订阅器 */
export class TeachingStateSubscriber {
  private readonly teachingStateService: TeachingStateService;
  private lastTrainEvent: TrainingIntentRecord | null = null;

  constructor(teachingStateService: TeachingStateService) {
    this.teachingStateService = teachingStateService;
  }

  /**
   * 事件处理入口
   * @param event OrchestratorEvent
   * @param sessionId 关联会话
   */
  handle(event: OrchestratorEvent, sessionId: string): void {
    if (event.type !== 'intent') return;
    const intent = event.payload;
    if (intent.type !== 'train') return;

    // 1) 记录(测试用 getter 暴露)
    this.lastTrainEvent = {
      sessionId,
      syndromeId: intent.syndromeId,
      techniqueId: intent.techniqueId,
      receivedAt: Date.now(),
    };

    // 2) 试点动作:调用 teachingStateService.getContext 验证集成
    //    真实业务接入在 Sprint 21+ 进行(避免影响 FiveStepFlow E2E)
    try {
      this.teachingStateService.getContext(sessionId);
    } catch (e) {
      console.warn('[TeachingStateSubscriber] handle failed:', e);
    }
  }

  /** 测试用:获取最近一次收到的 train 事件 */
  getLastTrainEvent(): TrainingIntentRecord | null {
    return this.lastTrainEvent;
  }
}
