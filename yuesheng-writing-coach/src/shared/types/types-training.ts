// 训练工坊类型
import type { SeverityLevel, SyndromeType } from './types-diagnosis';

// ======================== 训练相关类型（T-021） ========================

/** 中心面板模式 */
export type CenterMode = 'chat' | 'training' | 'retro';

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
  /** 技法说明 */
  description: string;
  /** 技法来源 */
  source: string;
  /** 核心技法 ID（如 suspense-engine） */
  coreId?: string;
  /** 核心技法名称（如 悬念驱动） */
  coreName?: string;
  /** 分类（如 开篇、节奏、人物） */
  category?: string;
  /** 难度（beginner / intermediate / advanced） */
  difficulty?: string;
  /** 难度排序（1/2/3） */
  difficultyOrder?: number;
}

/** 训练记录 */
export interface TrainingRecord {
  /** 记录 ID */
  id: string;
  /** 任务 ID */
  taskId?: string;
  /** 会话 ID */
  sessionId: string;
  /** 挑战 ID */
  challengeId: string;
  /** 挑战名称 */
  challengeName: string;
  /** 状态 */
  status: 'assigned' | 'in_progress' | 'completed' | 'skipped';
  /** 分数（0-10，仅 completed） */
  score?: number;
  /** 任务类型 */
  taskType?: string;
  /** 有效率（0-1） */
  effectiveness?: number;
  /** 分配时间 */
  assignedAt: string;
  /** 完成时间 */
  completedAt?: string;
}

/** 评估结果 */
export interface EvaluationResult {
  /** 评分（0-10） */
  score: number;
  /** 评语 */
  feedback: string;
  /** 是否改善 */
  improved: boolean;
  /** 下一步建议 */
  nextStep: string;
}

// ======================== C-01a: 训练库类型 ========================

/** 训练库条目 */
export interface TrainingTask {
  /** 训练条目 ID（如 TRAIN-P001-001） */
  id: string;
  /** 对应症候 ID */
  syndromeId: string;
  /** 症候名称 */
  syndromeName: string;
  /** 任务标题 */
  title: string;
  /** 难度等级 */
  difficulty: 'easy' | 'medium' | 'hard';
  /** 交互模式 */
  mode: string;
  /** 层级（structural/surface） */
  tier: string;
  /** 约束条件 */
  constraint: string;
  /** 预期结果 */
  expectedOutcome: string;
  /** 关联技法 ID 列表 */
  techniques: string[];
}

/** 训练库分类 */
export interface TrainingCategory {
  /** 分类 ID */
  id: string;
  /** 分类名称 */
  name: string;
  /** 分类描述 */
  description: string;
  /** 包含的症候 ID 列表 */
  syndromeIds: string[];
}
