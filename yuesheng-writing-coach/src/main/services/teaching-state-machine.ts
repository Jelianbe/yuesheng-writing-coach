/**
 * 教学状态机核心逻辑
 * 负责：教学阶段流转、子阶段推进、状态验证
 *
 * 教学阶段流转：
 *   P0_INIT → P1_WORLD → P2_PRACTICE_LOOP → P4_REVIEW
 *                             ↑↓
 *                    (可反复在诊断和训练间切换)
 */

import { TeachingPhase, TeachingSubphase, ActionId } from '../../shared/constants';
import { severityToNumber } from '../../shared/severity-utils';
import { getActionsForSubphase } from '../../shared/mappings';
import { TeachingState } from './teaching-state.types';
import type { FocusArea, FocusAreaValue } from '../../renderer/shared/types';

/**
 * 聚焦方向对应的世界观子阶段序列
 * character 模式跳过部分子阶段，只走确定主角
 */
const FOCUS_AREA_WORLD_SUBPHASES: Record<FocusAreaValue, string[]> = {
  worldbuilding: [
    TeachingSubphase.WORLD_NATURAL_LAW,
    TeachingSubphase.WORLD_PROTAGONIST,
    TeachingSubphase.WORLD_SOCIAL_STRUCT,
    TeachingSubphase.WORLD_FIRST_SCENE,
    TeachingSubphase.WORLD_DAILY_DETAIL,
  ],
  character: [
    TeachingSubphase.WORLD_PROTAGONIST,
  ],
  general: [
    TeachingSubphase.WORLD_NATURAL_LAW,
    TeachingSubphase.WORLD_PROTAGONIST,
    TeachingSubphase.WORLD_SOCIAL_STRUCT,
    TeachingSubphase.WORLD_FIRST_SCENE,
    TeachingSubphase.WORLD_DAILY_DETAIL,
  ],
};

/**
 * 过渡邀请话术已从硬编码迁移到外部配置
 * @see resources/config/transition-prompts.json
 * @see transition-prompt-loader.ts
 */
export { getTransitionPrompt } from './transition-prompt-loader';

/** 阶段名称映射 */
const PHASE_NAMES: Record<string, string> = {
  [TeachingPhase.INIT]: '初次见面',
  [TeachingPhase.ENGAGE]: '投入建立',
  [TeachingPhase.WORLD]: '世界观搭建',
  [TeachingPhase.PRACTICE_LOOP]: '诊断与训练',
  [TeachingPhase.REVIEW]: '复盘总结',
};

/** 子阶段名称映射 */
const SUBPHASE_NAMES: Record<string, string> = {
  [TeachingSubphase.ENGAGE_CONFIRM]: '确认投入',
  [TeachingSubphase.WORLD_NATURAL_LAW]: '自然法则',
  [TeachingSubphase.WORLD_PROTAGONIST]: '确定主角',
  [TeachingSubphase.WORLD_SOCIAL_STRUCT]: '社会结构',
  [TeachingSubphase.WORLD_FIRST_SCENE]: '缩小到第一个场景',
  [TeachingSubphase.WORLD_DAILY_DETAIL]: '日常细节',
  [TeachingSubphase.PRACTICE_IDENTIFY]: '识别问题',
  [TeachingSubphase.PRACTICE_REFLECTION]: '反思引导',
  [TeachingSubphase.PRACTICE_TEACHING]: '教学建议',
  [TeachingSubphase.PRACTICE_ASSIGN]: '布置任务',
  [TeachingSubphase.PRACTICE_REVIEW]: '评估练习',
  [TeachingSubphase.REVIEW_SUMMARY]: '总结复盘',
};

/** 每个阶段的子阶段序列 */
const PHASE_SUBPHASES: Record<string, string[]> = {
  [TeachingPhase.INIT]: [],
  [TeachingPhase.ENGAGE]: [
    TeachingSubphase.ENGAGE_CONFIRM,
  ],
  [TeachingPhase.WORLD]: [
    TeachingSubphase.WORLD_NATURAL_LAW,
    TeachingSubphase.WORLD_PROTAGONIST,
    TeachingSubphase.WORLD_SOCIAL_STRUCT,
    TeachingSubphase.WORLD_FIRST_SCENE,
    TeachingSubphase.WORLD_DAILY_DETAIL,
  ],
  [TeachingPhase.PRACTICE_LOOP]: [
    TeachingSubphase.PRACTICE_IDENTIFY,
    TeachingSubphase.PRACTICE_REFLECTION,
    TeachingSubphase.PRACTICE_TEACHING,
    TeachingSubphase.PRACTICE_ASSIGN,
    TeachingSubphase.PRACTICE_REVIEW,
  ],
  [TeachingPhase.REVIEW]: [TeachingSubphase.REVIEW_SUMMARY],
};

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
 * 根据阶段和子阶段计算建议动作
 *
 * 使用统一映射中心，而非硬编码
 */
function calculateNextActions(
  _phase: string,
  subphase: string,
): ActionId[] {
  return getActionsForSubphase(subphase) as ActionId[];
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

// ===== 状态锁定机制 =====

/**
 * 症候锁定：诊断后锁定到 TeachingState，跨轮次保持
 *
 * 锁定语义：
 * 1. 首次诊断发现的症候自动锁定
 * 2. 锁定后的症候不会因后续诊断未检测到而被清除
 * 3. 只有状态变为 resolved 时才解锁
 *
 * @param state - 当前教学状态
 * @param newSyndromeIds - 新诊断发现的症候 ID 列表
 * @returns 更新后的状态片段
 */
export function lockSyndromes(
  state: TeachingState,
  newSyndromeIds: string[],
): Pick<TeachingState, 'lockedSyndromes'> {
  const locked = new Set(state.lockedSyndromes ?? []);
  for (const id of newSyndromeIds) {
    locked.add(id);
  }
  return { lockedSyndromes: Array.from(locked) };
}

/**
 * 自动更新症候状态（基于重新诊断的严重度比较）
 *
 * 规则：
 * - 新严重度 < 旧严重度 → status = improving
 * - 新严重度 = 旧严重度 → status 不变（保持锁定）
 * - 新严重度 > 旧严重度 → status = active（复发）
 * - P-06: 重新检测到的症候 → detectionCount++，missedCount=0
 * - P-06: 本轮未检测到的症候 → missedCount++（检测不连续）
 *
 * @param state - 当前教学状态
 * @param newDiagnosisSyndromes - 新诊断的症候列表
 * @returns 更新后的 activeProblems
 */
export function updateSyndromeStatus(
  state: TeachingState,
  newDiagnosisSyndromes: Array<{ id: string; name: string; severity: 'L1' | 'L2' | 'L3'; evidence: string[]; suggestedActions: string[] }>,
): Pick<TeachingState, 'activeProblems'> {
  const now = new Date().toISOString();
  const newIds = new Set(newDiagnosisSyndromes.map((s) => s.id));

  // Step 1: 更新已有症候 —— 重新检测到的 increment detectionCount，未检测到的 increment missedCount
  const updated = state.activeProblems.map((existing) => {
    if (newIds.has(existing.id)) {
      const newSyndrome = newDiagnosisSyndromes.find((s) => s.id === existing.id)!;
      const newSev = severityToNumber(newSyndrome.severity);
      const oldSev = severityToNumber(existing.severity);

      return {
        ...existing,
        severity: newSyndrome.severity,
        evidence: newSyndrome.evidence,
        suggestedActions: newSyndrome.suggestedActions as typeof existing.suggestedActions,
        status:
          newSev < oldSev
            ? 'improving'
            : newSev > oldSev
              ? 'active'
              : existing.status,
        detectionCount: existing.detectionCount + 1,
        missedCount: 0,
      };
    } else {
      // 本轮未检测到 —— 检测不连续
      return {
        ...existing,
        missedCount: existing.missedCount + 1,
      };
    }
  });

  // Step 2: 新增本次首次检测到的症候
  const existingIds = new Set(state.activeProblems.map((p) => p.id));
  for (const newSyndrome of newDiagnosisSyndromes) {
    if (!existingIds.has(newSyndrome.id)) {
      updated.push({
        id: newSyndrome.id as TeachingState['activeProblems'][number]['id'],
        name: newSyndrome.name,
        severity: newSyndrome.severity,
        evidence: newSyndrome.evidence,
        firstDetected: now,
        status: 'active',
        suggestedActions: newSyndrome.suggestedActions as TeachingState['activeProblems'][number]['suggestedActions'],
        detectionCount: 1,
        missedCount: 0,
      });
    }
  }

  return { activeProblems: updated };
}

/**
 * 自动锁定连续检测到的一致性症候（P-06）
 *
 * 规则：当某个症的 detectionCount >= 2 时，自动将其加入 lockedSyndromes。
 * 这解决了"症候偶发出现→消失→再出现"场景下的锁定不一致问题。
 * 只有经过至少 2 轮检测确认的症候才会被锁定。
 *
 * @param state - 当前教学状态
 * @returns 更新后的 lockedSyndromes
 */
export function autoLockConsistentSyndromes(
  state: TeachingState,
): Pick<TeachingState, 'lockedSyndromes'> {
  const locked = new Set(state.lockedSyndromes ?? []);

  for (const problem of state.activeProblems) {
    if (problem.detectionCount >= 2 && !locked.has(problem.id)) {
      locked.add(problem.id);
    }
  }

  return { lockedSyndromes: Array.from(locked) };
}

/**
 * 解锁已解决的症候
 *
 * 将 activeProblems 中 status = 'resolved' 的症候从 lockedSyndromes 中移除
 *
 * @param state - 当前教学状态
 * @returns 更新后的状态片段
 */
export function unlockResolvedSyndromes(state: TeachingState): Pick<TeachingState, 'lockedSyndromes' | 'activeProblems'> {
  const resolvedIds = new Set(
    state.activeProblems
      .filter((p) => p.status === 'resolved')
      .map((p) => p.id),
  );

  const newLocked = (state.lockedSyndromes ?? []).filter(
    (id) => !resolvedIds.has(id),
  );

  // 清理已 resolved 的症候（保留 improving 和 active）
  const newActiveProblems = state.activeProblems.filter(
    (p) => p.status !== 'resolved',
  );

  return {
    lockedSyndromes: newLocked,
    activeProblems: newActiveProblems,
  };
}

/**
 * 判断是否所有锁定的症候都已解决
 *
 * @param state - 当前教学状态
 * @returns true = 所有锁定症候已解决，可以进入 P4_REVIEW
 */
export function areAllSyndromesResolved(state: TeachingState): boolean {
  const locked = state.lockedSyndromes ?? [];
  if (locked.length === 0) return false; // 没有锁定症候，不能判断

  const unresolved = state.activeProblems.filter(
    (p) => locked.includes(p.id) && p.status !== 'resolved',
  );

  return unresolved.length === 0;
}

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
 * 当反思门控触发时，将当前子阶段设为 PRACTICE_REFLECTION
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
 * 规则：当训练评分 >= 7 时，将该症候的严重度降低一级（L3→L2, L2→L1）。
 * L1 不再降低（已是最低）。
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
