/**
 * 诊断合并服务
 * 负责：将诊断结果合并到教学状态 + 反思门控判定
 * 解耦：diagnosis.handler 不再直接依赖 TeachingStateStore
 */

import { TeachingStateStore } from './teaching-state.store';
import { DiagnosisEntry } from '../../renderer/shared/types';
import { mergeSyndromesIntoState } from './diagnosis-merger-utils';
import { enterReflectionIfTriggered } from './teaching-state-machine';

/**
 * 诊断合并服务
 */
export class DiagnosisMerger {
  private getStore: () => TeachingStateStore;

  constructor(getStore: () => TeachingStateStore) {
    this.getStore = getStore;
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
    const store = this.getStore();
    const state = store.getBySession(diagnosis.sessionId);
    if (!state) return;

    // 1. 合并症候
    const updates = mergeSyndromesIntoState(state, diagnosis);
    store.update(diagnosis.sessionId, updates);

    // 2. 反思门控判定：合并后重新读取状态，检查是否需要进入反思
    const updatedState = store.getBySession(diagnosis.sessionId);
    if (updatedState) {
      const reflectedState = enterReflectionIfTriggered(updatedState);
      if (reflectedState !== updatedState) {
        store.update(diagnosis.sessionId, {
          currentSubphase: reflectedState.currentSubphase,
          nextSuggestedActions: reflectedState.nextSuggestedActions,
          updatedAt: reflectedState.updatedAt,
        });
      }
    }
  }
}
