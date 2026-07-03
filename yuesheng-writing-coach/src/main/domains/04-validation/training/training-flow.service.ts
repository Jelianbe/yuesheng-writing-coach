/**
 * training-flow.service.ts — 训练流服务(主进程)
 *
 * 职责：实现五步通用训练流——解说技法 → 例证展示 → 确认理解 → 主动尝试 → 修改反馈。
 *
 * 设计哲学：
 * - 通用化：不逐个技法写练法，而是按大类（开篇/角色/语言/结构等）生成五步流程
 * - 可扩展：新技法只需加入对应分类，自动获得五步训练流
 * - 零硬编码(R-014)：所有配置走 flow-mapping.loader + technique-library.loader
 *
 * 五步流：
 * 1. 解说技法 → 向用户解说该技法是什么、为什么有效
 * 2. 例证展示 → 从技法库或用户原文中展示范例
 * 3. 确认理解 → 用户用自己的话复述或回答问题
 * 4. 主动尝试 → 在约束下应用技法改写/创作
 * 5. 修改反馈 → AI 评估 + 用户修订
 *
 * 重构记录(S25 BL-01):
 * - 删除 CATEGORY_CONFIGS/DEFAULT_CONFIG/inferEffect/estimateMinutes 4 处硬编码
 * - 走 flow-mapping.loader(categoryTemplates/FLOW_TEMPLATES/effect)
 * - 走 technique-library.loader(findTechnique) 替代直接 import JSON
 * - 行为零变更(11 个单测断言全部对齐)
 */

import type { TrainingFlow, TrainingFlowStep, TrainingFlowStepId } from '../../../../shared/types/index';
import {
  FLOW_CATEGORIES,
  FLOW_TEMPLATES,
  getCategoryTemplate,
  getFlowCategory,
  getFlowTemplate,
} from './flow-mapping.loader';
import { findTechnique } from './technique-library.loader';

// ==============================
// 内部方法
// ==============================

/**
 * 生成步骤指令文本(占位符 {var} 替换)
 */
function fillTemplate(template: string, variables: Record<string, string>): string {
  let result = template;
  for (const [key, value] of Object.entries(variables)) {
    result = result.replace(`{${key}}`, value);
  }
  return result;
}

/**
 * 根据技法所属分类和难度估算每步耗时
 *
 * 基础耗时来自 FLOW_TEMPLATES[stepId].estimatedMinutes(配置外置),
 * 难度系数:hard=1.5 / medium=1.2 / 其他=1
 */
function estimateMinutes(stepId: TrainingFlowStepId, difficulty: string): number {
  const base = getFlowTemplate(stepId).estimatedMinutes;
  const factor = difficulty === 'hard' ? 1.5 : difficulty === 'medium' ? 1.2 : 1;
  return Math.round(base * factor);
}

// ==============================
// 公开 API
// ==============================

/**
 * 生成五步通用训练流
 *
 * @param params.syndromeId - 症候 ID
 * @param params.techniqueName - 技法名称或 ID
 * @param params.userLevel - 用户难度等级(1-3,对应 easy/medium/hard)
 * @param params.syndromeDescription - 症候描述(可选)
 * @param params.challengeConstraint - 挑战约束(可选)
 * @returns 完整训练流
 */
export function generateTrainingFlow(params: {
  syndromeId: string;
  techniqueName: string;
  userLevel: number;
  syndromeDescription?: string;
  challengeConstraint?: string;
}): TrainingFlow {
  const { syndromeId, techniqueName, userLevel: _userLevel, syndromeDescription, challengeConstraint } = params;

  const technique = findTechnique(techniqueName);
  const categoryKey = technique?.category ?? '_default';
  const config = getFlowCategory(categoryKey);
  const template = getCategoryTemplate(categoryKey);
  const description = technique?.description ?? techniqueName;
  const example = technique?.example ?? '';
  const exercise = technique?.exercise ?? '应用所学技法进行写作练习。';
  const difficulty = technique?.difficulty ?? 'beginner';
  const effect = config.effect;

  // 约束条件
  const constraint = challengeConstraint ?? exercise;

  const variables = {
    techniqueName,
    description,
    example,
    effect,
    constraint,
  };

  // 生成五步(模板来自 JSON,运行时填变量)
  const steps: TrainingFlowStep[] = [
    {
      stepId: 1,
      name: FLOW_TEMPLATES[1].name,
      instruction: fillTemplate(template.explainTemplate, variables),
      userAction: FLOW_TEMPLATES[1].userAction,
      estimatedMinutes: estimateMinutes(1, difficulty),
      coachingHint: `技法 ${techniqueName} 属于 ${categoryKey} 分类,${description}`,
    },
    {
      stepId: 2,
      name: FLOW_TEMPLATES[2].name,
      instruction: fillTemplate(template.exampleTemplate, variables),
      userAction: FLOW_TEMPLATES[2].userAction,
      estimatedMinutes: estimateMinutes(2, difficulty),
    },
    {
      stepId: 3,
      name: FLOW_TEMPLATES[3].name,
      instruction: fillTemplate(template.verifyQuestion, variables),
      userAction: FLOW_TEMPLATES[3].userAction,
      estimatedMinutes: estimateMinutes(3, difficulty),
    },
    {
      stepId: 4,
      name: FLOW_TEMPLATES[4].name,
      instruction: fillTemplate(template.practiceTemplate, variables),
      userAction: FLOW_TEMPLATES[4].userAction,
      estimatedMinutes: estimateMinutes(4, difficulty),
    },
    {
      stepId: 5,
      name: FLOW_TEMPLATES[5].name,
      instruction: fillTemplate(template.revisionGuide, variables),
      userAction: FLOW_TEMPLATES[5].userAction,
      estimatedMinutes: estimateMinutes(5, difficulty),
      coachingHint: `症候:${syndromeId}${syndromeDescription ? ` — ${syndromeDescription}` : ''}`,
    },
  ];

  return {
    syndromeId,
    techniqueName,
    category: config.abilityCategory,
    steps,
    estimatedTotalMinutes: steps.reduce((sum, s) => sum + s.estimatedMinutes, 0),
  };
}

/**
 * 获取所有支持的分类(从 JSON 配置读取,key 列表)
 */
export function getSupportedCategories(): string[] {
  return Object.keys(FLOW_CATEGORIES);
}
