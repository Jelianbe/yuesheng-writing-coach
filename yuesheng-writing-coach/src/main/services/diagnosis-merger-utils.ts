/**
 * 诊断合并工具函数
 * 负责：将诊断结果合并到教学状态的纯函数逻辑
 * 解耦：提取为独立模块，避免 diagnosis.handler 和 diagnosis-merger 之间的循环依赖
 */

import { DiagnosisEntry, TeachingState, ActiveProblem, SyndromeId } from '../../renderer/shared/types';
import { severityToNumber } from '../../shared/severity-utils';
export { severityToNumber };

/**
 * 将诊断结果合并到 TeachingState（纯函数，不依赖 store）
 *
 * @param state 当前教学状态
 * @param diagnosis 新诊断结果
 * @returns 更新后的状态片段
 */
export function mergeSyndromesIntoState(
  state: TeachingState,
  diagnosis: DiagnosisEntry,
): Partial<TeachingState> {
  const now = new Date().toISOString();
  const existingProblems = state.activeProblems;

  const mergedProblems: ActiveProblem[] = [...existingProblems];

  for (const syndrome of diagnosis.syndromes) {
    const existingIndex = mergedProblems.findIndex((p) => p.id === syndrome.id);

    if (existingIndex >= 0) {
      mergedProblems[existingIndex] = {
        ...mergedProblems[existingIndex],
        severity: syndrome.severity,
        evidence: syndrome.evidence,
        score: syndrome.score,
        suggestedActions: syndrome.suggestedActions,
        status: severityToNumber(syndrome.severity) < severityToNumber(mergedProblems[existingIndex].severity)
          ? 'improving'
          : mergedProblems[existingIndex].status,
      };
    } else {
      mergedProblems.push({
        id: syndrome.id as SyndromeId,
        name: syndrome.name,
        severity: syndrome.severity,
        evidence: syndrome.evidence,
        score: syndrome.score,
        firstDetected: now,
        status: 'active',
        suggestedActions: syndrome.suggestedActions,
      });
    }
  }

  return {
    activeProblems: mergedProblems,
    nextSuggestedActions: [
      ...new Set([
        ...state.nextSuggestedActions,
        ...diagnosis.suggestedActions,
      ]),
    ],
    diagnosisSummary: appendToSummary(state.diagnosisSummary, diagnosis),
    // 新诊断的症候自动锁定
    lockedSyndromes: [
      ...new Set([
        ...(state.lockedSyndromes ?? []),
        ...diagnosis.syndromes.map((s) => s.id),
      ]),
    ],
  };
}

/**
 * 追加诊断摘要
 */
function appendToSummary(current: string, diagnosis: DiagnosisEntry): string {
  const syndromeNames = diagnosis.syndromes
    .map((s) => `${s.id}(${s.name})`)
    .join(', ');
  const entry = `[${new Date().toISOString().slice(0, 10)}] 识别: ${syndromeNames}`;

  const rounds = current ? current.split('\n---\n') : [];
  rounds.push(entry);

  // 保留最近 3 轮
  if (rounds.length > 3) {
    return rounds.slice(-3).join('\n---\n');
  }

  return rounds.join('\n---\n');
}
