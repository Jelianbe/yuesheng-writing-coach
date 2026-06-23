/**
 * training.flow.ts — 训练流配置加载器
 *
 * 职责：从 resources/config/training-flow-mapping.json 读取分类与五步流模板，
 *       供 TrainingFlowService 在生成 TrainingFlow 时使用。
 *       符合 R-014（配置外置）：新增分类只需追加 JSON。
 *
 * 缓存：模块级单例，process lifetime 内只读一次。
 */

import trainingFlowMapping from '../../../resources/config/training-flow-mapping.json';

export interface FlowCategoryConfig {
  key: string;
  abilityCategory: string;
  displayName: string;
  effect: string;
}

export interface FlowTemplate {
  stepId: 1 | 2 | 3 | 4 | 5;
  name: string;
  template: string;
  userAction: string;
  estimatedMinutes: number;
}

export interface TrainingFlowMapping {
  categories: FlowCategoryConfig[];
  flowTemplates: FlowTemplate[];
}

const mapping = trainingFlowMapping as unknown as TrainingFlowMapping;

if (!mapping.categories || !mapping.flowTemplates) {
  throw new Error(
    '[training.flow] training-flow-mapping.json 缺少 categories / flowTemplates 字段',
  );
}

if (mapping.flowTemplates.length !== 5) {
  throw new Error(
    `[training.flow] flowTemplates 必须为 5 条，当前 ${mapping.flowTemplates.length} 条`,
  );
}

/** 分类索引（key → 配置） */
export const FLOW_CATEGORIES: Record<string, FlowCategoryConfig> = (() => {
  const idx: Record<string, FlowCategoryConfig> = {};
  for (const c of mapping.categories) {
    idx[c.key] = c;
  }
  return idx;
})();

/** 默认分类（_default） */
export const FLOW_DEFAULT_CATEGORY: FlowCategoryConfig =
  FLOW_CATEGORIES['_default'] ?? mapping.categories[mapping.categories.length - 1];

/** 五步模板（按 stepId 排序） */
export const FLOW_TEMPLATES: Record<1 | 2 | 3 | 4 | 5, FlowTemplate> = (() => {
  const idx = {} as Record<1 | 2 | 3 | 4 | 5, FlowTemplate>;
  for (const t of mapping.flowTemplates) {
    idx[t.stepId] = t;
  }
  return idx;
})();

/** 取分类，找不到时回退默认 */
export function getFlowCategory(categoryKey: string): FlowCategoryConfig {
  return FLOW_CATEGORIES[categoryKey] ?? FLOW_DEFAULT_CATEGORY;
}
