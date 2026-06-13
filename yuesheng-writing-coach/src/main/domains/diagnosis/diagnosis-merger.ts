/**
 * 诊断合并服务
 * 负责：将诊断结果合并到教学状态 + 反思门控判定
 * 解耦：diagnosis.handler 不再直接依赖 TeachingStateStore
 *
 * DI 注册名：'diagnosisMerger'
 */

import { TeachingStateService } from '../teaching/teaching-state.service';
import { DiagnosisEntry } from '../../../renderer/shared/types';
import { mergeSyndromesIntoState } from './diagnosis-merger-utils';
import { enterReflectionIfTriggered } from '../teaching/teaching-state/teaching-state-machine';

/**
 * 诊断合并服务
 */
export class DiagnosisMerger {
  private teachingStateService: TeachingStateService;

  constructor(teachingStateService: TeachingStateService) {
    this.teachingStateService = teachingStateService;
  }

  /**
   * 合并诊断结果到教学状态
   *
   * 流程：
   * 1. 合并症候到 activeProblems
   * 2. 检查反思门控：如果存在 L2+ 症候，强制进入 S2_REFLECTION 子阶段
   *
   * @param diagnosis - 诊断结果
   */
  merge(diagnosis: DiagnosisEntry): void {
    const state = this.teachingStateService.getBySession(diagnosis.sessionId);
    if (!state) return;

    // 1. 合并症候
    const updates = mergeSyndromesIntoState(state, diagnosis);
    this.teachingStateService.update(diagnosis.sessionId, updates);

    // 2. 反思门控判定：合并后重新读取状态，检查是否需要进入反思
    const updatedState = this.teachingStateService.getBySession(diagnosis.sessionId);
    if (updatedState) {
      const reflectedState = enterReflectionIfTriggered(updatedState);
      if (reflectedState !== updatedState) {
        this.teachingStateService.update(diagnosis.sessionId, {
          currentSubphase: reflectedState.currentSubphase,
          nextSuggestedActions: reflectedState.nextSuggestedActions,
        });
      }
    }
  }
}
