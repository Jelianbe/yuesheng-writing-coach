/**
 * 教学策略路由 — Layer 1：聚焦症候选择
 */

import type { RouterInput, FocusDecision } from '../../renderer/shared/types';
import type { RouterConfigs } from './teaching-strategy-router.types';
import { findTheoryRule, getPrioritySyndromeIds, computeAvgTrainingScores, collectTheoryRefForSyndrome } from './teaching-strategy-router.conditions';

/**
 * Layer 1：聚焦症候选择
 * 从活跃症候中选择最需要优先处理的一个
 */
export function selectFocusSyndrome(input: RouterInput, configs: RouterConfigs): FocusDecision {
  const active = input.activeSyndromes;
  if (active.length === 0) {
    return {
      targetSyndrome: '',
      targetSyndromeName: '',
      rationale: '无活跃症候，使用默认教学路径',
      theoryReference: [],
      alternativeSyndromes: [],
    };
  }

  if (active.length === 1) {
    return {
      targetSyndrome: active[0].id,
      targetSyndromeName: active[0].name,
      rationale: '唯一活跃症候，直接聚焦',
      theoryReference: collectTheoryRefForSyndrome(active[0].id, input, configs),
      alternativeSyndromes: [],
    };
  }

  // 多症候选择
  const theoryRef: string[] = [];

  // Step 1: 应用 R-015
  const r015 = findTheoryRule('R-015', configs.educationTheoryFragments);
  const prioritySyndromeIds = getPrioritySyndromeIds();
  const priorityMatch = active.find((s) => prioritySyndromeIds.includes(s.id));

  if (priorityMatch && r015) {
    theoryRef.push(`R-015: ${r015.rationale}`);
  }

  // Step 2: 检查训练评分
  const completedTraining = input.trainingHistory.filter((t) => t.completed);
  if (completedTraining.length > 0) {
    const avgScores = computeAvgTrainingScores(completedTraining);
    const scorable = active.filter((s) => avgScores.has(s.id));
    if (scorable.length > 0) {
      const lowest = scorable.reduce((a, b) =>
        (avgScores.get(a.id) ?? Infinity) <= (avgScores.get(b.id) ?? Infinity) ? a : b,
      );
      return {
        targetSyndrome: lowest.id,
        targetSyndromeName: lowest.name,
        rationale: `训练评分最低（${avgScores.get(lowest.id)?.toFixed(1)}/10），需要优先改进`,
        theoryReference: theoryRef,
        alternativeSyndromes: active.filter((s) => s.id !== lowest.id).map((s) => s.id),
      };
    }
  }

  // Step 3: 检查 syndromePriorityMap
  const priorityMap = configs.techniqueSelectionMatrix.syndromePriorityMap;
  for (const s of active) {
    if (priorityMap[s.id] && priorityMap[s.id].length > 0) {
      return {
        targetSyndrome: s.id,
        targetSyndromeName: s.name,
        rationale: `症候 ${s.id} 在技法矩阵中有优先映射关系`,
        theoryReference: theoryRef,
        alternativeSyndromes: active.filter((a) => a.id !== s.id).map((a) => a.id),
      };
    }
  }

  // Step 4: 选最高严重度
  const highest = active.reduce((a, b) =>
    (a.severity ?? 1) >= (b.severity ?? 1) ? a : b,
  );

  // Step 5: 应用 R-011
  if (active.length >= 2) {
    const r011 = findTheoryRule('R-011', configs.educationTheoryFragments);
    if (r011) {
      theoryRef.push(`R-011: ${r011.rationale}`);
    }
  }

  return {
    targetSyndrome: highest.id,
    targetSyndromeName: highest.name,
    rationale: `严重度最高的症候（severity=${highest.severity}）`,
    theoryReference: theoryRef,
    alternativeSyndromes: active.filter((s) => s.id !== highest.id).map((s) => s.id),
  };
}
