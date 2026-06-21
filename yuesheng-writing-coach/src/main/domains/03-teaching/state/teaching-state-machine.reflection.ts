/**
 * 教学状态机 — 反思门控与严重度降级
 * 负责：反思子阶段判定/触发、训练评分降级
 */

import { TeachingPhase, TeachingSubphase } from '../../../../shared/constants';
import { severityToNumber } from '../../../../shared/severity-utils';
import type { TeachingState } from './teaching-state.types';
import { PHASE_SUBPHASES } from './teaching-state-machine.constants';
import { calculateNextActions } from './teaching-state-machine.navigation';

/**
 * 反思门控判定：是否应进入 S2_REFLECTION 子阶段
 *
 * 规则：
 * - 当前处于 P2_PRACTICE_LOOP 阶段
 * - 存在 L2+ 症候（severity ≥ L2）
 * - 当前子阶段在 REFLECTION 之前（IDENTIFY 或尚未进入 REFLECTION）
 *
 * @param state - 当前教学状态
 * @returns 是否应进入反思子阶段
 */
export function shouldEnterReflection(state: TeachingState): boolean {
  // 仅在 P2 阶段生效
  if (state.currentPhase !== TeachingPhase.PRACTICE_LOOP) {
    return false;
  }

  // 已经在反思或之后的阶段，不需要再进入
  const reflectionIndex = PHASE_SUBPHASES[TeachingPhase.PRACTICE_LOOP].indexOf(TeachingSubphase.PRACTICE_REFLECTION);
  const currentIndex = PHASE_SUBPHASES[TeachingPhase.PRACTICE_LOOP].indexOf(state.currentSubphase);
  if (currentIndex >= reflectionIndex) {
    return false;
  }

  // 检查是否存在 L2+ 症候
  const hasSignificantSyndrome = state.activeProblems.some(
    (p) => p.status !== 'resolved' && severityToNumber(p.severity) >= severityToNumber('L2'),
  );

  return hasSignificantSyndrome;
}

/**
 * 强制进入反思子阶段
 *
 * @param state - 当前教学状态
 * @returns 更新后的教学状态（如果门控未触发则返回原状态）
 */
export function enterReflectionIfTriggered(state: TeachingState): TeachingState {
  if (!shouldEnterReflection(state)) {
    return state;
  }

  const now = new Date().toISOString();
  return {
    ...state,
    currentSubphase: TeachingSubphase.PRACTICE_REFLECTION,
    nextSuggestedActions: calculateNextActions(TeachingPhase.PRACTICE_LOOP, TeachingSubphase.PRACTICE_REFLECTION),
    updatedAt: now,
  };
}

/**
 * 训练评分达标时降低症候严重度
 *
 * @param state - 当前教学状态
 * @param syndromeId - 训练对应的症候 ID
 * @param score - 训练评分（1-10）
 * @returns 更新后的状态片段
 */
export function downgradeSyndromeSeverity(
  state: TeachingState,
  syndromeId: string,
  score: number,
): Pick<TeachingState, 'activeProblems'> {
  if (score < 7) return { activeProblems: state.activeProblems };

  const SEVERITY_DOWNGRADE: Record<string, string> = {
    L3: 'L2',
    L2: 'L1',
  };

  const updated = state.activeProblems.map((p) => {
    if (p.id !== syndromeId) return p;
    const downgraded = SEVERITY_DOWNGRADE[p.severity];
    if (!downgraded) return p;
    return {
      ...p,
      severity: downgraded as typeof p.severity,
      status: 'improving' as const,
    };
  });

  return { activeProblems: updated };
}
