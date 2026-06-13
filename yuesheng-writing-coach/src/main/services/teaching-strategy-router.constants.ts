/**
 * 教学策略路由 — 常量映射
 */

import type { TeachingStrategy, TeachingMode } from '../../renderer/shared/types';

/** syndrome-type-map.json 的 recommendedEntry → TeachingStrategy 映射 */
export const ENTRY_TO_STRATEGY: Record<string, TeachingStrategy> = {
  '先案例再模仿': 'case-driven',
  '先反思再练习': 'reflection-driven',
  '先提问激发再案例': 'analysis-driven',
};

/** 教育学理论规则分段：Layer 1 适用规则 (R-011 ~ R-015) */
export const LAYER1_THEORY_RULE_IDS = ['R-011', 'R-012', 'R-013', 'R-014', 'R-015'];

/** 教育学理论规则分段：Layer 2 适用规则 (R-001 ~ R-006) */
export const LAYER2_THEORY_RULE_IDS = ['R-001', 'R-002', 'R-003', 'R-004', 'R-005', 'R-006'];

/** user-type-map 中的 mode → TeachingMode 映射（含降级） */
export const USER_TYPE_MODE_TO_TEACHING_MODE: Record<string, TeachingMode> = {
  scaffolding: 'scaffolding',
  guiding: 'guiding',
  challenging: 'challenging',
  reflective: 'guiding', // reflective 降级为 guiding
};

/** 症候类型 → 练习类型映射 */
export const SYNDROME_TYPE_TO_PRACTICE: Record<string, string> = {
  expressive_deficit: 'imitation',
  structural_disorder: 'reflection',
  motivation_deficit: 'analysis',
};

/** 教学模式 → 练习类型映射（兜底） */
export const MODE_TO_PRACTICE: Record<string, string> = {
  scaffolding: 'guided_practice',
  guiding: 'semi_independent',
  challenging: 'independent',
};
