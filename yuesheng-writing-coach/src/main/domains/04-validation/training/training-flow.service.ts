/**
 * 训练流服务（TrainingFlowService）
 *
 * 职责：实现五步通用训练流——解说技法 → 例证展示 → 确认理解 → 主动尝试 → 修改反馈。
 *
 * 设计哲学：
 * - 通用化：不逐个技法写练法，而是按大类（开篇/角色/语言/结构等）生成五步流程
 * - 可扩展：新技法只需加入对应分类，自动获得五步训练流
 * - 无硬编码：所有指令文本基于技法数据和分类动态生成
 *
 * 五步流：
 * 1. 解说技法 → 向用户解说该技法是什么、为什么有效
 * 2. 例证展示 → 从技法库或用户原文中展示范例
 * 3. 确认理解 → 用户用自己的话复述或回答问题
 * 4. 主动尝试 → 在约束下应用技法改写/创作
 * 5. 修改反馈 → AI 评估 + 用户修订
 */

import type { TrainingFlow, TrainingFlowStep, TrainingFlowStepId } from '../../../../shared/types/index';
import techniqueLibrary from '../../../../../resources/config/technique-library.json';

// ==============================
// 内部类型
// ==============================

interface TechniqueEntry {
  id: string;
  name: string;
  source: string;
  difficulty: string;
  category: string;
  discoverable?: boolean;
  applicableSyndromes: string[];
  description: string;
  example?: string;
  exercise?: string;
  coreId?: string;
  coreName?: string;
  difficultyOrder?: number;
}

interface TechniqueCategoryConfig {
  /** 分类名 */
  name: string;
  /** 分类对应的能力大类 */
  abilityCategory: string;
  /** 步骤 1 的解说模板 */
  explainTemplate: string;
  /** 步骤 2 的例证模板 */
  exampleTemplate: string;
  /** 步骤 3 的理解确认问题模板 */
  verifyQuestion: string;
  /** 步骤 4 的练习模板 */
  practiceTemplate: string;
  /** 步骤 5 的修改指导 */
  revisionGuide: string;
}

// ==============================
// 分类配置
// ==============================

const CATEGORY_CONFIGS: Record<string, TechniqueCategoryConfig> = {
  '开篇': {
    name: '开篇技法',
    abilityCategory: '叙事能力',
    explainTemplate: '「{techniqueName}」是一种{description}。它的核心价值在于让读者在第一瞬间被抓住，愿意继续读下去。',
    exampleTemplate: '看看这个例子：「{example}」。注意它是怎么在极短的篇幅内制造{effect}的。你能感受到什么？',
    verifyQuestion: '用你自己的话描述「{techniqueName}」的核心要点。如果让你给一个没听过的人讲解，你会怎么说？',
    practiceTemplate: '现在轮到你尝试了。找到你作品中开篇的一段，应用「{techniqueName}」来改写。{constraint}',
    revisionGuide: '对照练习目标检查你的改写：是否抓住了核心要点？是否偏离了原文的意思？根据反馈进行修订。',
  },
  '人物': {
    name: '人物技法',
    abilityCategory: '角色能力',
    explainTemplate: '「{techniqueName}」是一种{description}。好的角色塑造让读者感受到角色是"活人"而非叙事工具。',
    exampleTemplate: '看这个例子：「{example}」。注意作者是怎么通过{effect}来塑造角色的立体感的。',
    verifyQuestion: '你觉得「{techniqueName}」最关键的要点是什么？在你的写作中，你觉得哪个方面最需要这个技巧？',
    practiceTemplate: '选择你作品中的一个角色，用「{techniqueName}」来加深ta的立体感。{constraint}',
    revisionGuide: '检查你的改写：角色是否有了更多层次？ta的行为是否更有说服力？根据反馈进行调整。',
  },
  '节奏': {
    name: '节奏技法',
    abilityCategory: '叙事能力',
    explainTemplate: '「{techniqueName}」是一种{description}。叙事节奏决定了读者阅读时的情绪起伏和沉浸感。',
    exampleTemplate: '看这个例子：「{example}」。注意作者是怎么通过{effect}来控制节奏的。',
    verifyQuestion: '在你看来，「{techniqueName}」适用于什么样的场景？它和普通的写法区别在哪里？',
    practiceTemplate: '在你作品中选择一处节奏需要调整的地方，用「{techniqueName}」来改进。{constraint}',
    revisionGuide: '对比原文和改写：节奏感是否改善了？信息密度是否更合理？根据反馈修订。',
  },
  '语言': {
    name: '语言技法',
    abilityCategory: '语言能力',
    explainTemplate: '「{techniqueName}」是一种{description}。精准的语言是写作的基石，它让读者"看见"而非"知道"。',
    exampleTemplate: '看这个例子：「{example}」。注意{effect}是怎么通过具体的词语选择来达成的。',
    verifyQuestion: '你觉得「{techniqueName}」的核心要点是什么？你能不能举一个你读过的作品中类似的例子？',
    practiceTemplate: '在你作品中找出一段可以用「{techniqueName}」改进的文字，尝试改写。{constraint}',
    revisionGuide: '检查你的用词：是否更精准了？是否删掉了多余的字？根据反馈进一步打磨。',
  },
  '结构': {
    name: '结构技法',
    abilityCategory: '叙事能力',
    explainTemplate: '「{techniqueName}」是一种{description}。好的结构让故事整体有条理，不松散、不跑题。',
    exampleTemplate: '看这个例子：「{example}」。注意作者是怎么通过{effect}来组织信息、引导读者注意力的。',
    verifyQuestion: '「{techniqueName}」的核心思路是什么？它解决了什么样的结构问题？',
    practiceTemplate: '在你作品中选一段结构需要优化之处，用「{techniqueName}」来重新组织。{constraint}',
    revisionGuide: '对比原文：结构是否更清晰了？信息是否更有序了？根据反馈调整。',
  },
};

const DEFAULT_CONFIG: TechniqueCategoryConfig = {
  name: '通用技法',
  abilityCategory: '综合能力',
  explainTemplate: '「{techniqueName}」是一种{description}。掌握它能帮助你在写作中更有效地表达。',
  exampleTemplate: '看这个例子：「{example}」。注意作者是怎么做到的。',
  verifyQuestion: '用你自己的话总结「{techniqueName}」的核心要点。',
  practiceTemplate: '尝试在你的作品中应用「{techniqueName}」。{constraint}',
  revisionGuide: '检查你的改写是否达到了目标。根据反馈修订。',
};

// ==============================
// 内部方法
// ==============================

const techniques = techniqueLibrary as unknown as TechniqueEntry[];

/**
 * 根据技法名查找技法详情
 */
function findTechnique(techniqueName: string): TechniqueEntry | undefined {
  return techniques.find(t => t.name === techniqueName || t.id === techniqueName);
}

/**
 * 获取分类配置（fallback 到默认配置）
 */
function getCategoryConfig(category: string): TechniqueCategoryConfig {
  return CATEGORY_CONFIGS[category] ?? DEFAULT_CONFIG;
}

/**
 * 生成步骤指令文本
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
 */
function estimateMinutes(stepId: TrainingFlowStepId, difficulty: string): number {
  const baseTimes: Record<TrainingFlowStepId, number> = { 1: 3, 2: 5, 3: 3, 4: 15, 5: 10 };
  const factor = difficulty === 'hard' ? 1.5 : difficulty === 'medium' ? 1.2 : 1;
  return Math.round(baseTimes[stepId] * factor);
}

/**
 * 根据分类和技法名推断效果描述（用于例证展示）
 */
function inferEffect(category: string): string {
  const effects: Record<string, string> = {
    '开篇': '吸引力和悬念',
    '人物': '人物的立体感和真实感',
    '节奏': '节奏的张弛变化',
    '语言': '语言的精准度和表现力',
    '结构': '结构的条理性和经济性',
  };
  return effects[category] ?? '表现效果';
}

// ==============================
// 公开 API
// ==============================

/**
 * 生成五步通用训练流
 *
 * @param params.syndromeId - 症候 ID
 * @param params.techniqueName - 技法名称或 ID
 * @param params.userLevel - 用户难度等级（1-3，对应 easy/medium/hard）
 * @param params.syndromeDescription - 症候描述（可选）
 * @param params.challengeConstraint - 挑战约束（可选）
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
  const category = technique?.category ?? '通用';
  const config = getCategoryConfig(category);
  const description = technique?.description ?? techniqueName;
  const example = technique?.example ?? '';
  const exercise = technique?.exercise ?? '应用所学技法进行写作练习。';
  const difficulty = technique?.difficulty ?? 'beginner';
  const effect = inferEffect(category);

  // 约束条件
  const constraint = challengeConstraint ?? exercise;

  const variables = {
    techniqueName,
    description,
    example,
    effect,
    constraint,
  };

  // 生成五步
  const steps: TrainingFlowStep[] = [
    {
      stepId: 1,
      name: '解说技法',
      instruction: fillTemplate(config.explainTemplate, variables),
      userAction: '阅读并理解技法说明。如有疑问可随时向教练提问。',
      estimatedMinutes: estimateMinutes(1, difficulty),
      coachingHint: `技法 ${techniqueName} 属于 ${category} 分类，${description}`,
    },
    {
      stepId: 2,
      name: '例证展示',
      instruction: fillTemplate(config.exampleTemplate, variables),
      userAction: '阅读示例，思考作者是怎么做到的。你也可以从自己读过的作品中找类似的例子。',
      estimatedMinutes: estimateMinutes(2, difficulty),
    },
    {
      stepId: 3,
      name: '确认理解',
      instruction: fillTemplate(config.verifyQuestion, variables),
      userAction: '用文字回答上面的问题。不求长篇大论，但要说到点子上。',
      estimatedMinutes: estimateMinutes(3, difficulty),
    },
    {
      stepId: 4,
      name: '主动尝试',
      instruction: fillTemplate(config.practiceTemplate, variables),
      userAction: '根据指令在你的作品上进行改写或创作。完成后再进入下一步。',
      estimatedMinutes: estimateMinutes(4, difficulty),
    },
    {
      stepId: 5,
      name: '修改反馈',
      instruction: fillTemplate(config.revisionGuide, variables),
      userAction: '接收 AI 评估反馈，根据建议修改你的稿子。可以反复迭代。',
      estimatedMinutes: estimateMinutes(5, difficulty),
      coachingHint: `症候：${syndromeId}${syndromeDescription ? ` — ${syndromeDescription}` : ''}`,
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
 * 获取所有支持的分类配置
 */
export function getSupportedCategories(): string[] {
  return Object.keys(CATEGORY_CONFIGS);
}
