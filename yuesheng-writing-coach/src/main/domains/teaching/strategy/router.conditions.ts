/**
 * 教学策略路由 — 条件匹配引擎
 * 负责：教育理论规则的条件匹配、工具函数
 */

import type { RouterInput } from '../../../../renderer/shared/types';
import type { EducationTheoryFragment, RouterConfigs, SyndromeTypeMapConfig } from './router.types';
import { LAYER1_THEORY_RULE_IDS } from './router.constants';

/**
 * 检查教育理论规则的条件是否匹配输入的简化引擎
 */
export function matchesCondition(condition: Record<string, unknown>, input: RouterInput, configs: RouterConfigs): boolean {
  for (const [key, value] of Object.entries(condition)) {
    switch (key) {
      case 'userLevel':
        if (value !== input.userLevel) return false;
        break;
      case 'syndromeType': {
        const inputType = getDominantSyndromeType(input.activeSyndromes.map((s) => s.id), configs.syndromeTypeMap);
        if (value !== inputType) return false;
        break;
      }
      case 'activeSyndromeCount': {
        const count = input.activeSyndromes.length;
        const cond = String(value);
        if (cond.startsWith('>=')) {
          if (count < parseInt(cond.slice(2), 10)) return false;
        } else if (cond.startsWith('<=')) {
          if (count > parseInt(cond.slice(2), 10)) return false;
        } else if (cond.startsWith('>')) {
          if (count <= parseInt(cond.slice(1), 10)) return false;
        } else if (cond.startsWith('<')) {
          if (count >= parseInt(cond.slice(1), 10)) return false;
        } else if (count !== parseInt(cond, 10)) return false;
        break;
      }
      case 'sameSyndromeCount':
        if (typeof value === 'number' && input.topSyndromeCount < value) return false;
        break;
      case 'syndromeSeverity': {
        const hasSeverity = input.activeSyndromes.some(
          (s) => severityToLabel(s.severity) === value,
        );
        if (!hasSeverity) return false;
        break;
      }
      case 'activeSyndromes': {
        if (Array.isArray(value)) {
          const ids = input.activeSyndromes.map((s) => s.id);
          const matchCount = (value as string[]).filter((v) => ids.includes(v)).length;
          if (matchCount === 0) return false;
        }
        break;
      }
      case 'trainingScore': {
        const completed = input.trainingHistory.filter((t) => t.completed);
        if (completed.length === 0) return false;
        const avgScore = completed.reduce((sum, t) => sum + t.score, 0) / completed.length;
        const cond = String(value);
        if (cond.startsWith('>=')) {
          if (avgScore < parseFloat(cond.slice(2))) return false;
        } else if (cond.startsWith('<=')) {
          if (avgScore > parseFloat(cond.slice(2))) return false;
        } else {
          if (avgScore < parseFloat(cond)) return false;
        }
        break;
      }
      case 'sameSyndromeRepeated': {
        const repeated = input.topSyndromeCount >= 2;
        if (value === true && !repeated) return false;
        if (value === false && repeated) return false;
        break;
      }
      case 'trainingMotivation': {
        if (value !== input.trainingMotivation) return false;
        break;
      }
      case 'trainingSkipRate': {
        const rate = input.trainingSkipRate ?? 0;
        const cond = String(value);
        if (cond.startsWith('>')) {
          if (rate <= parseFloat(cond.slice(1))) return false;
        } else if (cond.startsWith('>=')) {
          if (rate < parseFloat(cond.slice(2))) return false;
        } else if (cond.startsWith('<')) {
          if (rate >= parseFloat(cond.slice(1))) return false;
        } else if (cond.startsWith('<=')) {
          if (rate > parseFloat(cond.slice(2))) return false;
        }
        break;
      }
      case 'conflict': {
        const ids = input.activeSyndromes.map((s) => s.id);
        const hasConflict = ids.length >= 2;
        if (value === true && !hasConflict) return false;
        if (value === false && hasConflict) return false;
        break;
      }
      case 'syndromePriority': {
        const highPriority = ['P006', 'P004'];
        const hasPriority = input.activeSyndromes.some((s) => highPriority.includes(s.id));
        if (value === 'reading_experience_impact' && !hasPriority) return false;
        break;
      }
      default:
        break;
    }
  }
  return true;
}

/** 数字严重度转 L1/L2/L3 标签 */
export function severityToLabel(sev: number): string {
  if (sev >= 3) return 'L3';
  if (sev >= 2) return 'L2';
  return 'L1';
}

/** 获取应优先处理的症候 ID 列表（来自 R-015） */
export function getPrioritySyndromeIds(): string[] {
  return ['P006', 'P004'];
}

/** 查找指定 ID 的教育理论规则 */
export function findTheoryRule(ruleId: string, fragments: EducationTheoryFragment[]): EducationTheoryFragment | undefined {
  return fragments.find((r) => r.id === ruleId);
}

/** 收集与特定症候相关的教育理论依据 */
export function collectTheoryRefForSyndrome(
  _syndromeId: string,
  input: RouterInput,
  configs: RouterConfigs,
): string[] {
  const refs: string[] = [];
  const rules = configs.educationTheoryFragments;
  for (const rule of rules) {
    if (LAYER1_THEORY_RULE_IDS.includes(rule.id)) {
      if (matchesCondition(rule.condition, input, configs)) {
        refs.push(`${rule.id}: ${rule.rationale}`);
      }
    }
  }
  return refs;
}

/** 获取占主导的症候类型 */
export function getDominantSyndromeType(
  syndromeIds: string[],
  typeMap: SyndromeTypeMapConfig,
): string | null {
  const typeCounts = new Map<string, number>();

  for (const [typeName, typeInfo] of Object.entries(typeMap.types)) {
    const matchCount = syndromeIds.filter((id) => typeInfo.syndromes.includes(id)).length;
    if (matchCount > 0) {
      typeCounts.set(typeName, matchCount);
    }
  }

  if (typeCounts.size === 0) return null;

  let dominant: string | null = null;
  let maxCount = 0;
  for (const [typeName, count] of typeCounts) {
    if (count > maxCount) {
      dominant = typeName;
      maxCount = count;
    }
  }
  return dominant;
}

/** 计算训练平均分映射 */
export function computeAvgTrainingScores(
  history: Array<{ syndromeId: string; score: number }>,
): Map<string, number> {
  const scoreMap = new Map<string, { total: number; count: number }>();
  for (const h of history) {
    const entry = scoreMap.get(h.syndromeId) ?? { total: 0, count: 0 };
    entry.total += h.score;
    entry.count += 1;
    scoreMap.set(h.syndromeId, entry);
  }
  const avgMap = new Map<string, number>();
  for (const [id, data] of scoreMap.entries()) {
    avgMap.set(id, data.total / data.count);
  }
  return avgMap;
}
