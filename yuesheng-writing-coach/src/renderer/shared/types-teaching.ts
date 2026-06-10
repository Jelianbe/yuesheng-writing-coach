// 教学状态与策略类型
import type { SyndromeId, SeverityLevel, ActionId } from './types-diagnosis';

/** 教学阶段（运行时常量见 constants.js → TeachingPhase） */
export type TeachingPhase = string;

/** 教学子阶段（运行时常量见 constants.js → TeachingSubphase） */
export type TeachingSubphase = string;

/** 活跃病症状态 */
export type ProblemStatus = 'active' | 'improving' | 'resolved';

/** 活跃病症记录 */
export interface ActiveProblem {
  /** 病症 ID */
  id: SyndromeId;
  /** 病症名称 */
  name: string;
  /** 严重度 */
  severity: SeverityLevel;
  /** 用户原文证据片段 */
  evidence: string[];
  /** 信号分（可选，用于排序） */
  score?: number;
  /** 首次检测时间 */
  firstDetected: string;
  /** 当前状态 */
  status: ProblemStatus;
  /** P-06: 连续检测次数（跨轮次一致性追踪） */
  detectionCount: number;
  /** P-06: 已消失轮次数（0 = 当前轮仍存在，>0 = 已消失 n 轮） */
  missedCount: number;
  /** 建议教学动作 */
  suggestedActions: ActionId[];
}

/** AI 状态更新建议 */
export interface AIStateSuggestion {
  /** 建议标记完成的动作 */
  completeAction?: ActionId;
  /** 建议新增的问题 */
  newProblem?: Omit<ActiveProblem, 'firstDetected' | 'status'>;
  /** 建议的下一步动作 */
  nextAction?: ActionId;
}

/** 聚焦方向值 */
export type FocusAreaValue = 'worldbuilding' | 'character' | 'general';

/** 聚焦方向（含未选择状态） */
export type FocusArea = FocusAreaValue | null;

/** 教学状态（数据库存储格式） */
export interface TeachingState {
  /** 所属会话 ID */
  sessionId: string;
  /** 当前大阶段 */
  currentPhase: TeachingPhase;
  /** 当前子阶段 */
  currentSubphase: TeachingSubphase;
  /** 已完成的教学动作 ID 列表 */
  completedActions: ActionId[];
  /** 已完成的训练任务 ID 列表 */
  completedTasks: string[];
  /** 当前活跃的病症问题 */
  activeProblems: ActiveProblem[];
  /** 建议的下一步动作 */
  nextSuggestedActions: ActionId[];
  /** 当前建议的任务 ID */
  currentTaskId: string | null;
  /** 诊断历史摘要（最近 3 轮简洁文本） */
  diagnosisSummary: string;
  /** 用户最后确认时间 */
  lastUserConfirmation: string | null;
  /** 当前聚焦方向 */
  focusArea: FocusArea;
  /** 是否已提供过过渡邀请（防止重复） */
  transitionOffered: boolean;
  /** 状态最后更新时间 */
  updatedAt: string;
  /** 锁定的症候 ID 列表（诊断后锁定，跨轮次保持，直到 resolved） */
  lockedSyndromes: string[];
}

/** 教学状态更新请求 */
export interface TeachingStateUpdateRequest {
  /** 要更新的字段（部分更新） */
  updates: Partial<Omit<TeachingState, 'sessionId' | 'updatedAt'>>;
}

/** 教学进度展示数据（前端用） */
export interface TeachingProgressDisplay {
  /** 当前阶段名称 */
  phaseName: string;
  /** 当前子阶段名称 */
  subphaseName: string;
  /** 阶段进度（0-1） */
  phaseProgress: number;
  /** 已完成动作列表（含名称） */
  completedActions: { id: ActionId; name: string }[];
  /** 建议下一步动作列表（含名称） */
  nextActions: { id: ActionId; name: string }[];
  /** 活跃问题列表 */
  activeProblems: ActiveProblem[];
}

// ======================== 教学策略路由（T-033） ========================

/** 教学模式 */
export type TeachingMode = 'scaffolding' | 'guiding' | 'challenging';

/** 教学策略类型 */
export type TeachingStrategy = 'case-driven' | 'analysis-driven' | 'reflection-driven';

/** 第一层：聚焦症候决策 */
export interface FocusDecision {
  /** 本次聚焦的症候 ID */
  targetSyndrome: string;
  /** 症候中文名 */
  targetSyndromeName: string;
  /** 为什么选这个 */
  rationale: string;
  /** 教育理论依据 */
  theoryReference: string[];
  /** 备选症候（非本次但不忽略） */
  alternativeSyndromes: string[];
}

/** 第二层：教学模式决策 */
export interface ModeDecision {
  /** 教学模式 */
  teachingMode: TeachingMode;
  /** 教学策略 */
  strategy: TeachingStrategy;
  /** 症候类型（expressive_deficit / structural_disorder / motivation_deficit） */
  syndromeType: string;
  /** 推荐入口（来自 syndrome-type-map） */
  recommendedEntry: string;
  /** 教育理论依据 */
  theoryReference: string[];
}

export interface ParameterDecision {
  /** 当前学习路径阶段 ID */
  phaseId: string;
  /** 核心技法模式列表 */
  corePatterns: string[];
  /** 步骤序列 */
  stepSequence: Array<{
    stepId: string;
    stepName: string;
    coachingTemplateRef: string;
    toneProfile: string;
  }>;
  /** 匹配的教练话术模板 ID（T-036 新增） */
  matchedTemplateId?: string;
  /** 练习类型 */
  practiceType: string;
}

/**
 * Persona 配置（PE-001 结构化，替换 attitude 硬编码）
 *
 * 定义 AI 教练的人格化特征，包括语气、挑战强度、知识范围等。
 */
export interface PersonaConfig {
  id: 'doubao' | 'yuesheng' | 'direct';
  label: string;
  tone: string;
  challengeSize: 'micro' | 'medium' | 'full';
  knowledgeScope: string;
  responseStyle: string;
}

/** Persona 预设映射 */
export const PERSONA_PRESETS: Record<string, PersonaConfig> = {
  doubao: {
    id: 'doubao',
    label: '温柔陪伴型',
    tone: 'encouraging',
    challengeSize: 'micro',
    knowledgeScope: 'base',
    responseStyle: '先肯定再引导，多用提问少用判断',
  },
  yuesheng: {
    id: 'yuesheng',
    label: '老编辑型',
    tone: 'direct',
    challengeSize: 'full',
    knowledgeScope: 'full',
    responseStyle: '直击要害，给直接反馈，不绕弯',
  },
  direct: {
    id: 'direct',
    label: '挑战型',
    tone: 'challenging',
    challengeSize: 'medium',
    knowledgeScope: 'core',
    responseStyle: '持续施压，不满足于表面的答案',
  },
};

/** Router 输入 */
export interface RouterInput {
  /** 用户 ID */
  userId: string;
  /** 用户水平 */
  userLevel: 'beginner' | 'intermediate' | 'advanced';
  /** 认知风格（来自学生模型） */
  cognitiveStyle?: string;
  /** 挫折指数（0-1） */
  frustrationIndex: number;
  /** 最频繁症候出现次数 */
  topSyndromeCount: number;
  /** 活跃症候列表 */
  activeSyndromes: Array<{
    id: string;
    severity: number;
    name: string;
  }>;
  /** 训练历史 */
  trainingHistory: Array<{
    syndromeId: string;
    score: number;
    completed: boolean;
  }>;
  /** 当前教学阶段（来自状态机） */
  currentPhase?: string;
  /** 用户态度档位 */
  attitude?: 'doubao' | 'yuesheng' | 'direct';
  /** Persona 配置（PE-001，若提供则优先使用） */
  persona?: PersonaConfig;
  /** 训练动机水平（用于 R-007 规则匹配） */
  trainingMotivation?: 'low' | 'normal' | 'high';
  /** 训练跳过率 0-1（用于 R-007 规则匹配） */
  trainingSkipRate?: number;
  /** 各症候出现次数映射（用于 R-009/R-010/R-014 规则匹配） */
  syndromeCountMap?: Record<string, number>;
  /** 处理中的教育规则 ID 列表（外部注入，用于条件匹配） */
  activeRuleIds?: string[];
}

/** Router 输出 */
export interface RouterOutput {
  /** 聚焦症候决策 */
  targetSyndrome: FocusDecision;
  /** 教学模式决策 */
  teachingMode: ModeDecision;
  /** 参数细化决策 */
  parameters: ParameterDecision;
  /** 向后兼容字段 */
  compatibleWithLegacy: {
    mode: TeachingMode;
    tone: string;
    format?: string;
  };
}
