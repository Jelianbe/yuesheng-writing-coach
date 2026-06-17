// 共享类型定义 — Barrel Re-export
// 按领域拆分后统一导出，保持向后兼容

// --- types-config: 配置与 API 基础类型 ---
export type { AttitudeLevel } from './types-config';
export type { ApiConfig } from './types-config';
export type { ApiResponse } from './types-config';
export { apiSuccess, apiError } from './types-config';
export type { ApiConfigValidation } from './types-config';
export type { ConnectionTestResult } from './types-config';

// --- types-diagnosis: 诊断域类型 ---
export type { SeverityLevel } from './types-diagnosis';
export type { SyndromeId } from './types-diagnosis';
export type { SyndromeType } from './types-diagnosis';
export type { ActionId } from './types-diagnosis';
export type { SyndromeSignal } from './types-diagnosis';
export type { SyndromeResult } from './types-diagnosis';
export type { RewriteEvaluation } from './types-diagnosis';
export type { TeachingProgress } from './types-diagnosis';
export type { DiagnosisEntry } from './types-diagnosis';
export type { EvidenceRecord } from './types-diagnosis';
export type { EvidenceChain } from './types-diagnosis';
export type { TechniqueRef } from './types-diagnosis';
export type { KeyPassage } from './types-diagnosis';
export type { DiagnosisAnalysis } from './types-diagnosis';

// --- types-chat: 聊天与会话 ---
export type { MessageRole } from './types-chat';
export type { ChatMessage } from './types-chat';
export type { Session } from './types-chat';
export type { ChatSendRequest } from './types-chat';
export type { StreamChunk } from './types-chat';
export type { StreamEnd } from './types-chat';
export type { MessageRow } from './types-chat';
export type { SessionMeta } from './types-chat';

// --- types-teaching: 教学状态与策略 ---
export type { TeachingPhase } from './types-teaching';
export type { TeachingSubphase } from './types-teaching';
export type { ProblemStatus } from './types-teaching';
export type { ActiveProblem } from './types-teaching';
export type { AIStateSuggestion } from './types-teaching';
export type { FocusAreaValue } from './types-teaching';
export type { FocusArea } from './types-teaching';
export type { TeachingState } from './types-teaching';
export type { TeachingStateUpdateRequest } from './types-teaching';
export type { TeachingProgressDisplay } from './types-teaching';
export type { TeachingMode } from './types-teaching';
export type { TeachingStrategy } from './types-teaching';
export type { FocusDecision } from './types-teaching';
export type { ModeDecision } from './types-teaching';
export type { ParameterDecision } from './types-teaching';
export type { PersonaConfig } from './types-teaching';
export { PERSONA_PRESETS } from './types-teaching';
export type { RouterInput } from './types-teaching';
export type { RouterOutput } from './types-teaching';
// RWR-P0-2: 会话进度
export type { ProgressIssueStatus, DisplayStatus } from './types-teaching';
export type { ProgressIssue } from './types-teaching';
export type { SessionProgress } from './types-teaching';

// --- types-training: 训练工坊 ---
export type { CenterMode } from './types-training';
export type { TrainingStep } from './types-training';
export type { ActiveTrainingSession } from './types-training';
export type { ErrorCard } from './types-training';
export type { TrainingRecommendation } from './types-training';
export type { TechniqueInfo } from './types-training';
export type { TrainingRecord } from './types-training';
export type { EvaluationResult } from './types-training';

// --- types-growth: 成长与能力画像 ---
export type { TeachingHistoryItem } from './types-growth';
export type { AbilityScore } from './types-growth';
export type { WeakPoint } from './types-growth';
export type { TrainingStats } from './types-growth';
export type { DiagnosisTrend } from './types-growth';
export type { AbilityProfile } from './types-growth';
export type { OnboardingBaseline } from './types-growth';
export type { TrajectoryPoint } from './types-growth';
export type { GrowthEvent } from './types-growth';
export type { GrowthChain } from './types-growth';
export type { VisualizationData } from './types-growth';

// --- types-manuscript: 作品与章节 ---
export type { Manuscript } from './types-manuscript';
export type { Chapter } from './types-manuscript';

// --- types-ipc: IPC 类型系统 ---
export type { IPCChannel } from './types-ipc';
export type { IPCRequestMap } from './types-ipc';
export type { IPCResponseMap } from './types-ipc';
export type { IPCEventMap } from './types-ipc';

// --- types-execution: 执行分析 ---
export type { ExecutionPattern } from './types-execution';
export type { ConsistencyGap } from './types-execution';
export type { IntentPhase } from './types-execution';
export type { AuthorStage } from './types-execution';

// --- types-prompt: Prompt / Role-Skill 类型 ---
export type { TeachingRole } from './types-prompt';
export type { RoleSkillConfig } from './types-prompt';
export type { RoleSchedule } from './types-prompt';
export type { RoleSchedulesConfig } from './types-prompt';
