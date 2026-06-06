/**
 * 诊断合并服务
 * 负责：将诊断结果合并到教学状态
 * 解耦：diagnosis.handler 不再直接依赖 TeachingStateStore
 */

import { TeachingStateStore } from './teaching-state.store';
import { DiagnosisEntry } from '../../renderer/shared/types';
import { mergeSyndromesIntoState } from './diagnosis-merger-utils';

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
   * @param diagnosis - 诊断结果
   */
  merge(diagnosis: DiagnosisEntry): void {
    const store = this.getStore();
    const state = store.getBySession(diagnosis.sessionId);
    if (!state) return;

    const updates = mergeSyndromesIntoState(state, diagnosis);
    store.update(diagnosis.sessionId, updates);
  }
}
