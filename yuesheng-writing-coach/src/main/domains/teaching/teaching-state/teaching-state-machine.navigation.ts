/**
 * 教学状态机 — 导航函数
 * 负责：阶段/子阶段推进、进度计算、过渡判定
 *
 * S2_GUIDE 自动适配说明：
 * S2_GUIDE（PRACTICE_GUIDE）已插入 PHASE_SUBPHASES.PRACTICE_LOOP 序列的
 * IDENTIFY 与 REFLECTION 之间。导航函数使用 indexOf 动态计算当前索引，
 * 因此 getNextSubphase / calculatePhaseProgress / confirmPhaseComplete 等
 * 无需额外改动即可自动适配 S2_GUIDE 在序列中的位置。
 */

import { TeachingPhase, TeachingSubphase, ActionId } from '../../../../shared/constants';
import { getActionsForSubphase } from '../../../../shared/mappings';
import { TeachingState } from './teaching-state.types';
import type { FocusArea, FocusAreaValue } from '../../../../shared/types/index';
import {
  FOCUS_AREA_WORLD_SUBPHASES,
  PHASE_NAMES,
  SUBPHASE_NAMES,
  PHASE_SUBPHASES,
} from './teaching-state-machine.constants';

/**
 * 获取阶段名称
 */
export function getPhaseName(phase: string): string {
  return PHASE_NAMES[phase];
}

/**
 * 获取子阶段名称
 */
export function getSubphaseName(subphase: string): string {
  return SUBPHASE_NAMES[subphase];
}

/**
 * 根据当前阶段获取下一个阶段
 *
 * MVP 简化版：不自动离开 P2_PRACTICE_LOOP 循环
 * 除非用户明确说"我想复盘"或达到一定轮次
 */
export function getNextPhase(current: string): TeachingPhase {
  switch (current) {
    case TeachingPhase.INIT:
      return TeachingPhase.ENGAGE;
    case TeachingPhase.ENGAGE:
      return TeachingPhase.WORLD;
    case TeachingPhase.WORLD:
      return TeachingPhase.PRACTICE_LOOP;
    case TeachingPhase.PRACTICE_LOOP:
      // 不自动离开循环，除非用户主动要求复盘
      return TeachingPhase.PRACTICE_LOOP;
    case TeachingPhase.REVIEW:
      // 复盘后可回到 PRACTICE_LOOP 继续迭代
      return TeachingPhase.PRACTICE_LOOP;
    default:
      return TeachingPhase.PRACTICE_LOOP;
  }
}

/**
 * 获取阶段的第一个子阶段
 */
export function getFirstSubphaseOf(phase: string): TeachingSubphase {
  const subphases = PHASE_SUBPHASES[phase] ?? [];
  if (subphases.length === 0) {
    throw new Error(`Phase ${phase} has no subphases`);
  }
  return subphases[0] as TeachingSubphase;
}

/**
 * 获取当前子阶段的下一个子阶段
 * 支持根据 focusArea 过滤子阶段序列
 *
 * @returns 下一个子阶段，如果已到阶段末尾则返回 null
 */
export function getNextSubphase(
  phase: string,
  current: string,
  focusArea?: FocusArea,
): TeachingSubphase | null {
  const subphases =
    phase === TeachingPhase.WORLD && focusArea
      ? FOCUS_AREA_WORLD_SUBPHASES[focusArea as FocusAreaValue] ?? []
      : PHASE_SUBPHASES[phase] ?? [];
  const currentIndex = subphases.indexOf(current);

  if (currentIndex === -1) {
    console.warn(
      `[StateMachine] Subphase ${current} not found in phase ${phase}`,
    );
    return null;
  }

  const nextIndex = currentIndex + 1;
  if (nextIndex >= subphases.length) {
    return null; // 已到阶段末尾
  }

  return subphases[nextIndex] as TeachingSubphase;
}

/**
 * 计算阶段进度（0-1）
 */
export function calculatePhaseProgress(
  phase: string,
  subphase: string,
): number {
  const subphases = PHASE_SUBPHASES[phase] ?? [];
  if (subphases.length === 0) return 1;

  const currentIndex = subphases.indexOf(subphase);
  if (currentIndex === -1) return 0;

  return (currentIndex + 1) / subphases.length;
}

/**
 * 根据阶段和子阶段计算建议动作
 *
 * 使用统一映射中心，而非硬编码
 * S2_GUIDE 子阶段返回引导发现相关动作
 */
export function calculateNextActions(
  _phase: string,
  subphase: string,
): ActionId[] {
  // S2_GUIDE: 引导发现阶段，返回引导相关问题模板
  if (subphase === TeachingSubphase.PRACTICE_GUIDE) {
    return [ActionId.ConfidenceConfirm] as ActionId[];
  }
  return getActionsForSubphase(subphase) as ActionId[];
}

/**
 * 用户确认完成当前子阶段，推进状态
 *
 * @param state - 当前教学状态
 * @returns 更新后的教学状态
 */
export function confirmPhaseComplete(state: TeachingState): TeachingState {
  const now = new Date().toISOString();

  // 1. 将当前建议动作标记为已完成
  const updatedCompletedActions = [
    ...new Set([...state.completedActions, ...state.nextSuggestedActions]),
  ];

  // 2. 尝试推进子阶段
  const nextSubphase = getNextSubphase(
    state.currentPhase,
    state.currentSubphase,
    state.focusArea,
  );

  if (nextSubphase !== null) {
    // 子阶段还有后续，推进子阶段
    return {
      ...state,
      currentSubphase: nextSubphase,
      completedActions: updatedCompletedActions,
      nextSuggestedActions: calculateNextActions(state.currentPhase, nextSubphase),
      lastUserConfirmation: now,
      updatedAt: now,
    };
  }

  // 3. 子阶段已到末尾，尝试推进大阶段
  const nextPhase = getNextPhase(state.currentPhase);

  if (nextPhase !== state.currentPhase) {
    // 推进到大阶段
    const firstSubphase = getFirstSubphaseOf(nextPhase);
    return {
      ...state,
      currentPhase: nextPhase,
      currentSubphase: firstSubphase,
      completedActions: updatedCompletedActions,
      nextSuggestedActions: calculateNextActions(nextPhase, firstSubphase),
      lastUserConfirmation: now,
      updatedAt: now,
    };
  }

  // 4. 循环阶段（P2_PRACTICE_LOOP），回到第一个子阶段继续
  const firstSubphase = getFirstSubphaseOf(state.currentPhase);
  return {
    ...state,
    currentSubphase: firstSubphase,
    completedActions: updatedCompletedActions,
    nextSuggestedActions: calculateNextActions(state.currentPhase, firstSubphase),
    lastUserConfirmation: now,
    updatedAt: now,
  };
}

/**
 * 判断是否应提供过渡邀请
 * 同时满足：专精模式、未邀请过、已完成核心教学
 *
 * @param state - 当前教学状态
 * @returns 是否应提供过渡邀请
 */
export function shouldOfferTransition(state: TeachingState): boolean {
  // 仅专精模式触发
  if (!state.focusArea || state.focusArea === 'general') {
    return false;
  }
  // 已邀请过不再重复
  if (state.transitionOffered) {
    return false;
  }
  // worldbuilding: P1_WORLD 全部完成
  if (state.focusArea === 'worldbuilding') {
    return state.currentPhase === TeachingPhase.PRACTICE_LOOP;
  }
  // character: 进入 P2_PRACTICE_LOOP 即视为核心教学完成
  if (state.focusArea === 'character') {
    return state.currentPhase === TeachingPhase.PRACTICE_LOOP;
  }
  return false;
}
