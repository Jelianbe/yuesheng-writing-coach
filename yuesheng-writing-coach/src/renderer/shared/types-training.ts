// 训练工坊类型
import type { SeverityLevel, SyndromeType } from './types-diagnosis';

// ======================== 训练相关类型（T-021） ========================

/** 中心面板模式 */
export type CenterMode = 'chat' | 'training';

/** 训练步骤 */
export interface TrainingStep {
  /** 步骤 ID */
  id: string;
  /** 步骤标题 */
  title: string;
  /** 步骤描述 */
  description: string;
  /** 步骤状态 */
  status: 'completed' | 'active' | 'pending';
}

/** 活跃训练会话 */
export interface ActiveTrainingSession {
  /** 挑战 ID */
  challengeId: string;
  /** 挑战名称 */
  challengeName: string;
  /** 挑战描述（训练任务说明） */
  challengeDescription: string;
  /** 交互模式（对应 challenge-templates.json 的 mode） */
  mode: string;
  /** 步骤列表 */
  steps: TrainingStep[];
  /** 当前步骤索引（0-based） */
  currentStepIndex: number;
  /** 原始文本引用 */
  originalQuote: string;
  /** 约束条件 */
  constraint: string;
  /** 用户草稿 */
  userDraft: string;
  /** 训练记录 ID（用于提交 complete） */
  recordId?: string;
  /** 对应的症候 ID */
  syndromeId?: string;
  /** 目标症候（SF-002 长期目标展示） */
  targetSyndrome?: string;
  /** 核心技法模式（SF-002 中期目标展示） */
  corePatterns?: string;
  /** 长期目标改善进度（0-100） */
  longTermProgress?: number;
  /** AI 评估结果（用于 complete 提交） */
  submissionResult?: { passed: boolean; feedback: string };
}

/** 错误卡片（训练工坊区块一） */
export interface ErrorCard {
  /** 症候 ID */
  syndromeId: string;
  /** 症候名称 */
  syndromeName: string;
  /** 严重度 */
  severity: SeverityLevel;
  /** 诊断次数 */
  diagnosisCount: number;
  /** 最近引用（原文片段） */
  lastQuote: string;
  /** 最后诊断时间 */
  lastDiagnosedAt: string;
  /** 匹配的挑战模板 ID */
  matchedChallengeId?: string;
}

/** 训练推荐 */
export interface TrainingRecommendation {
  /** 挑战 ID */
  challengeId: string;
  /** 挑战名称 */
  challengeName: string;
  /** 挑战描述 */
  description: string;
  /** 对应症候 ID */
  syndromeId: string;
  /** 症候名称 */
  syndromeName?: string;
  /** 症候类型（V6.0新增） */
  syndromeType?: SyndromeType | null;
  /** 严重度 */
  severity: SeverityLevel;
  /** 层级（structural/surface） */
  tier: string;
  /** 约束条件 */
  constraint: string;
  /** 预期结果 */
  expectedOutcome: string;
  /** 模式 */
  mode: string;
  /** 匹配的技法列表 */
  techniques?: TechniqueInfo[];
  /** T-TRAIN-001: 结构化任务字段 */
  scenario?: string;
  wordCount?: number;
  forbiddenWords?: string[];
  evaluationCriteria?: string[];
}

/** 技法信息（来自 technique-library.json） */
export interface TechniqueInfo {
  /** 技法 ID */
  id: string;
  /** 技法名称 */
  name: string;
  /** 来源（小说名/公开资源） */
  source: string;
  /** 来源作者 */
  sourceAuthor?: string;
  /** 来源类型（V6.0新增：public_teaching=公开教学资源） */
  sourceType?: string;
  /** 难度 */
  difficulty: string;
  /** 分类 */
  category: string;
  /** 适用症候 */
  applicableSyndromes?: string[];
  /** 核心一句话（V6.0新增，TE系列专用） */
  coreIdea?: string;
  /** 简述 */
  description: string;
  /** 教学逻辑（V6.0新增，TE系列的核心附加值——原作者是怎么教的） */
  teachingLogic?: string;
  /** 原文示例 */
  example: string;
  /** 练习建议 */
  exercise?: string;
  /** 核心模式标识（V6.0新增） */
  coreId?: string;
  /** 核心模式名称（V6.0新增） */
  coreName?: string;
  /** 难度顺序：1=beginner, 2=intermediate, 3=advanced（V6.0新增） */
  difficultyOrder?: number;
  /** 适用范围：通用/奇幻玄幻/推理悬疑等（V6.0新增） */
  genreScope?: string | string[];
}

/** 训练记录（数据库行格式） */
export interface TrainingRecord {
  /** 记录 ID */
  id: string;
  /** 会话 ID */
  sessionId: string;
  /** 挑战 ID（challengeId） */
  taskId: string;
  /** 症候 ID */
  syndromeId: string;
  /** 训练类型（writing/reading/reflection/technique） */
  taskType?: 'writing' | 'reading' | 'reflection' | 'technique';
  /** 用户响应 */
  userResponse: string;
  /** 状态（assigned/in_progress/completed/skipped） */
  status: string;
  /** 有效性评分（0-1） */
  effectiveness: number;
  /** AI 评估反馈 */
  aiFeedback: string;
  /** 分配时间 */
  assignedAt: string;
  /** 完成时间 */
  completedAt?: string;
  /** Evaluator Agent 评分（1-10） */
  score?: number | null;
}

/** 评估结果（Evaluator Agent 输出） */
export interface EvaluationResult {
  /** 评分 1-10 */
  score: number;
  /** 文字反馈 */
  feedback: string;
  /** 是否相比原文有改善 */
  improved: boolean;
  /** 下一步建议 */
  nextStep: string;
}
