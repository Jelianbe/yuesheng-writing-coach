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
  /**
   * Sprint 23 G-1: 主进程侧 ActiveTraining 业务元数据
   * 记录 session 进入 ActiveTraining 状态的元数据,实际 ActiveTrainingSession
   * 完整状态机仍在 renderer 侧维护(renderer/stores/training.store.ts)。
   * 主进程侧仅承担"哪个 session 进入了训练态 + 关联症候"业务元数据,供审计/查询用。
   * 完整状态机迁移推到 S24。
   */
  activeTrainingMeta?: ActiveTrainingMeta | null;
}

/**
 * Sprint 23 G-1: ActiveTraining 业务元数据
 * 轻量级 JSON 字段,记录训练触发的关键元数据
 */
export interface ActiveTrainingMeta {
  /** 触发的症候 ID */
  syndromeId: string;
  /** 关联技法 ID(可选) */
  techniqueId?: string;
  /** 触发时间 ISO 格式 */
  triggeredAt: string;
  /** 触发来源(对齐 TrainingTriggeredEvent.reason) */
  source: 'training_triggered' | 'user_request' | 'diagnosis_result' | 'prescription';
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

// ======================== 教学策略路由（T-032） ========================

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
  attitude?: 'doubao' | 'yuesheng' | 'sensei' | 'direct';
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
  /** S7: 症候教学动作映射（来自 syndrome-action-map.json） */
  actionMapping?: {
    /** 触发信号描述 */
    triggerSignal: string;
    /** 触发模板（含占位符） */
    triggerTemplate: string;
    /** 教练引导问题 */
    coachingQuestion: string;
  };
  /** S7: 关联能力节点信息 */
  abilityNode?: {
    id: string;
    name: string;
    focus: string;
  };
}

// ======================== 会话进度（RWR-P0-2 新增） ========================

/** 单个问题的教学状态(spec §9.1 + TASK-DETAILS RWR-P0-2 融合) */
export type ProgressIssueStatus = 'identified' | 'teaching' | 'mastered' | 'relapsed';

/** 教学进度展示状态(右侧栏状态指示器,spec §9.1) */
export type DisplayStatus = 'idle' | 'diagnosing' | 'teaching' | 'reflecting' | 'completed';

/** 单个问题的进度明细 */
export interface ProgressIssue {
  /** 症候 ID(与 diagnosis 的 SyndromeId 对齐) */
  syndromeId: string;
  /** 当前状态 */
  status: ProgressIssueStatus;
  /** 人类可读简短描述(UI 展示用) */
  label: string;
}

/**
 * 会话进度(0/N 显性反馈)
 *
 * 设计依据:TASK-DETAILS RWR-P0-2 DoD + spec §9.1 融合
 * - 分子 resolvedIssues:只增不减(spec §4.2 "问题解决跳一次")
 * - 分母 totalIssues:只增不减(spec §4.2 "分母只增不减")
 * - phaseGroup:分阶段分组(spec §4.2 "第一批 3/3 ✓ → 第二批 0/4")
 * - issues[]:各问题明细状态(spec §9.1,复发分析输入源)
 *
 * 持久化:progress.store 的 persist middleware 写入 localStorage
 * 真源:教学状态机(teaching-state.store)的诊断结果
 */
export interface SessionProgress {
  /** 所属会话 ID */
  sessionId: string;
  /** 当前聚焦的问题 ID(教学状态机当前处理对象) */
  currentIssue?: string;
  /** 当前会话累计识别的症候总数(分母,只增不减) */
  totalIssues: number;
  /** 已掌握/精通的问题数(分子) */
  resolvedIssues: number;
  /** 当前教学阶段(如 'P2_PRACTICE_LOOP') */
  stage: string;
  /** 阶段分组标识(spec §4.2 分阶段展示,如 'batch-1' / 'batch-2') */
  phaseGroup?: string;
  /** 各问题明细(含 status 追踪) */
  issues: ProgressIssue[];
  /** 当前系统展示状态(右侧栏状态指示器) */
  displayStatus: DisplayStatus;
  /** 最后更新时间(ISO 8601) */
  updatedAt: string;
}

// ======================== 教学决策记录层(RWR-P1-6 / B-2) ========================
// 依据 spec §8.2:教学策略选择的不透明链路需要可回溯
// 阶段:Phase 1 = "写不读"(spec §8.3),只积累数据,Phase 4+ 回流优化 Router
// 约束:
//   - R-021 隐性诊断:本模块是系统内部字段,前端 UI 永不渲染
//   - R-014 配置外置:strategyChosen 枚举在此处定义,不在代码中散落 string

/** 教学策略枚举(spec §8.2 写死的 5 种) */
export type TeachingStrategyType =
  | 'GUIDE'
  | 'DIRECT_TEACHING'
  | 'GUIDE_DISCOVERY'
  | 'REFLECTION'
  | 'READING';

/** 决策时学生状态快照(spec §8.2 studentState) */
export interface TeachingDecisionStudentState {
  /** 信心水平 */
  confidence: 'high' | 'neutral' | 'low';
  /** 历史复发次数 */
  relapseCount: number;
  /** 当前教学阶段(从 TeachingState.currentPhase + currentSubphase 派生) */
  currentStage: string;
  /** 用户态度档位(从 config.attitudeLevel 派生) */
  attitudeLevel: 'gentle' | 'balanced' | 'direct';
}

/** 单条教学决策记录(spec §8.2) */
export interface TeachingDecisionLog {
  /** 决策唯一 ID(PK) */
  decisionId: string;
  /** 所属会话 */
  sessionId: string;
  /** 针对的症候(关联 DiagnosisEntry.syndromes[].id) */
  syndromeId: string;
  /** 选择的策略类型 */
  strategyChosen: TeachingStrategyType;
  /** 选择原因(模板或自然语言) */
  reason: string;
  /** 决策时的学生状态快照 */
  studentState: TeachingDecisionStudentState;
  /** 决策时间(unix epoch ms) */
  decidedAt: number;
}

// ======================== 画像增强(RWR-P1-7 / C-1) ========================
// 依据 spec §4.4:teachingHistory[] + attitudePreference 跨 session 持久化
// 约束:
//   - R-021 隐性诊断:teaching_history 系统内部字段,前端 UI 永不渲染
//   - R-014 配置外置:attitude 枚举在此处定义,与 DisputeTracker 保持一致

/** 用户态度档位(跨 session 持久化用,与 DisputeTrackerService.AttitudeLevel 对齐) */
export type AttitudePreferenceLevel = 'doubao' | 'yuesheng' | 'sensei';

/** 教学回合结果(用于 teachingHistory 记录) */
export type TeachingOutcome = 'success' | 'partial' | 'frustrated' | 'unknown';

/** 单条教学历史记录(spec §4.4) */
export interface TeachingHistoryEntry {
  /** 教学动作标识 */
  action: string;
  /** 关联症候 ID(无症候时为空字符串) */
  syndromeId: string;
  /** 回合结果 */
  outcome: TeachingOutcome;
  /** 发生时间(unix epoch ms) */
  timestamp: number;
}
