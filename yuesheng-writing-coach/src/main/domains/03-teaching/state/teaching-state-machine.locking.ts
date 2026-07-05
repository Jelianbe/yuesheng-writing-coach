/**
 * 教学状态机 — 锁定机制
 * 负责：症候锁定/更新/解锁/一致性判断
 */

import { severityToNumber } from '../../../../shared/severity-utils';
import type { TeachingState } from './teaching-state.types';

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

  // Step 1: 更新已有症候
  const updated = state.activeProblems.map((existing) => {
    if (newIds.has(existing.id)) {
      const newSyndrome = newDiagnosisSyndromes.find((s) => s.id === existing.id);
      if (!newSyndrome) return existing;
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

  // 清理已 resolved 的症候
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
