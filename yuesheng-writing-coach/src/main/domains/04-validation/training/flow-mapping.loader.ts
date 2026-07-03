/**
 * flow-mapping.loader.ts — 训练流配置加载器(main 端)
 *
 * 职责:从 resources/config/training-flow-mapping.json 读取分类、分类模板与五步流模板,
 *      供 TrainingFlowService 在生成 TrainingFlow 时使用。
 *      符合 R-014(配置外置):新增分类只需追加 JSON,无需改代码。
 *
 * 缓存:模块级单例,process lifetime 内只读一次。
 *
 * 跨端约定:与 src/renderer/flow/training.flow.ts 共享同一 JSON 文件,
 *          任何字段变更需同步两端。
 *          共享仅 JSON 路径(不共享 TS 模块,遵循 R-020 循环依赖零容忍)。
 *
 * 版本:1.1.0 (S25 BL-01 扩展 categoryTemplates)
 */

import trainingFlowMapping from '../../../../../resources/config/training-flow-mapping.json';

export interface FlowCategoryConfig {
  key: string;
  abilityCategory: string;
  displayName: string;
  effect: string;
}

export interface FlowCategoryTemplate {
  explainTemplate: string;
  exampleTemplate: string;
  verifyQuestion: string;
  practiceTemplate: string;
  revisionGuide: string;
}

export interface FlowTemplate {
  stepId: 1 | 2 | 3 | 4 | 5;
  name: string;
  template: string;
  userAction: string;
  estimatedMinutes: number;
}

export interface TrainingFlowMapping {
  version: string;
  categories: FlowCategoryConfig[];
  categoryTemplates: Record<string, FlowCategoryTemplate>;
  flowTemplates: FlowTemplate[];
}

const mapping = trainingFlowMapping as unknown as TrainingFlowMapping;

if (!mapping.categories || !mapping.categoryTemplates || !mapping.flowTemplates) {
  throw new Error(
    '[flow-mapping.loader] training-flow-mapping.json 缺少 categories / categoryTemplates / flowTemplates 字段',
  );
}

if (mapping.flowTemplates.length !== 5) {
  throw new Error(
    `[flow-mapping.loader] flowTemplates 必须为 5 条,当前 ${mapping.flowTemplates.length} 条`,
  );
}

for (const t of mapping.flowTemplates) {
  if (![1, 2, 3, 4, 5].includes(t.stepId)) {
    throw new Error(
      `[flow-mapping.loader] flowTemplates stepId 必须 1-5,实际 ${t.stepId}`,
    );
  }
  if (!t.name || !t.template || !t.userAction) {
    throw new Error(
      `[flow-mapping.loader] flowTemplates step ${t.stepId} 缺少 name/template/userAction`,
    );
  }
}

for (const [key, tpl] of Object.entries(mapping.categoryTemplates)) {
  if (!tpl.explainTemplate || !tpl.exampleTemplate || !tpl.verifyQuestion ||
      !tpl.practiceTemplate || !tpl.revisionGuide) {
    throw new Error(
      `[flow-mapping.loader] categoryTemplates[${key}] 缺少 5 步模板字段`,
    );
  }
}

/** 分类索引(key → 配置) */
export const FLOW_CATEGORIES: Record<string, FlowCategoryConfig> = (() => {
  const idx: Record<string, FlowCategoryConfig> = {};
  for (const c of mapping.categories) {
    idx[c.key] = c;
  }
  return idx;
})();

/** 默认分类(_default) */
export const FLOW_DEFAULT_CATEGORY: FlowCategoryConfig =
  FLOW_CATEGORIES['_default'] ?? mapping.categories[mapping.categories.length - 1];

/** 分类模板索引(key → 5 步模板) */
export const FLOW_CATEGORY_TEMPLATES: Record<string, FlowCategoryTemplate> = mapping.categoryTemplates;

/** 默认分类模板(_default) */
export const FLOW_DEFAULT_CATEGORY_TEMPLATE: FlowCategoryTemplate =
  FLOW_CATEGORY_TEMPLATES['_default'] ?? Object.values(FLOW_CATEGORY_TEMPLATES).pop()!;

/** 五步模板(按 stepId 排序) */
export const FLOW_TEMPLATES: Record<1 | 2 | 3 | 4 | 5, FlowTemplate> = (() => {
  const idx = {} as Record<1 | 2 | 3 | 4 | 5, FlowTemplate>;
  for (const t of mapping.flowTemplates) {
    idx[t.stepId] = t;
  }
  return idx;
})();

/** 取分类,找不到时回退默认 */
export function getFlowCategory(categoryKey: string): FlowCategoryConfig {
  return FLOW_CATEGORIES[categoryKey] ?? FLOW_DEFAULT_CATEGORY;
}

/** 取分类 5 步模板,找不到时回退默认 */
export function getCategoryTemplate(categoryKey: string): FlowCategoryTemplate {
  return FLOW_CATEGORY_TEMPLATES[categoryKey] ?? FLOW_DEFAULT_CATEGORY_TEMPLATE;
}

/** 取五步模板(按 stepId) */
export function getFlowTemplate(stepId: 1 | 2 | 3 | 4 | 5): FlowTemplate {
  return FLOW_TEMPLATES[stepId];
}

/** 取配置版本号 */
export function getMappingVersion(): string {
  return mapping.version ?? 'unknown';
}
