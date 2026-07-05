/**
 * ActiveTraining IPC 契约 — Sprint 24 A-3
 *
 * 定义 ActiveTraining 状态机 IPC 边界的请求/响应类型。
 * 主进程侧 ActiveTrainingService 接收这些请求,操作 SQLite active_training 表。
 *
 * 依据: dev-docs/tasks/sprint-24-plan.md §A-3, §A-4
 */

import type { ApiResponse } from './base';
import type {
  ActiveTrainingStatus,
  StepResponse,
  TrainingStep,
  TrainingFlow,
} from '../types/index';

/** 草稿更新请求 */
export interface ActiveTrainingUpdateDraftRequest {
  sessionId: string;
  content: string;
}

/** 草稿更新响应 */
export interface ActiveTrainingUpdateDraftResponse {
  success: boolean;
  /** 草稿长度(字符数) */
  length: number;
  /** 持久化时间戳(ISO 8601) */
  persistedAt: string;
  /** 当前训练状态(可能因 race condition 改变) */
  status: ActiveTrainingStatus | null;
}

/** 获取活跃训练请求 */
export interface ActiveTrainingGetRequest {
  sessionId: string;
}

/** 获取活跃训练响应(主进程侧 ActiveTraining 领域对象) */
export interface ActiveTrainingGetResponse {
  sessionId: string;
  challengeId: string;
  challengeName: string | null;
  mode: string | null;
  currentStepIndex: number;
  steps: TrainingStep[];
  userDraft: string;
  flowType: 'flow5' | 'legacy' | null;
  trainingFlow: TrainingFlow | null;
  recordId: string | null;
  syndromeId: string | null;
  originalQuote: string | null;
  constraint: string | null;
  submissionResult: unknown | null;
  /** Sprint 25 BL-01 C-4: 5 步分步提交回答 */
  stepResponses: StepResponse[];
  status: ActiveTrainingStatus;
  startedAt: string;
  updatedAt: string;
  completedAt: string | null;
}

// ===== Sprint 24 A-4: 状态推送事件 =====

/** 状态变更类型(与主进程 ActiveTrainingService.ActiveTrainingStateChangeType 保持一致) */
export type ActiveTrainingStateChangeType =
  | 'start'
  | 'updateDraft'
  | 'advanceStep'
  | 'submitStep'
  | 'evaluate'
  | 'complete'
  | 'abort';

/**
 * 状态推送事件载荷(主进程 → renderer)
 * - 主进程在每次成功状态机操作后推送
 * - renderer 应根据 sessionId 过滤,只处理当前 session
 * - state 为最新完整 ActiveTraining 快照(行读取后领域对象)
 */
export interface ActiveTrainingUpdatedEvent {
  type: ActiveTrainingStateChangeType;
  sessionId: string;
  state: ActiveTrainingGetResponse;
}

/** IPC 频道 + 包装响应 */

// ===== Sprint 25 BL-01 C-4: 5 步分步提交契约 =====

/** 5 步分步提交请求 */
export interface ActiveTrainingSubmitStepRequest {
  sessionId: string;
  stepId: 1 | 2 | 3 | 4 | 5;
  content: string;
}

/** 5 步分步提交响应 */
export interface ActiveTrainingSubmitStepResponse {
  success: boolean;
  /** 已累计 stepResponses 数量(1-5) */
  submittedCount: number;
  /** 本次提交时间戳(ISO 8601) */
  submittedAt: string;
  /** 当前训练状态(可能因 race condition 改变) */
  status: ActiveTrainingStatus | null;
}

// ===== Sprint 25 C-1: 草稿快照版本历史 =====

/** 草稿快照触发原因 */
export type DraftSnapshotTrigger = 'advance' | 'evaluate' | 'complete' | 'abort' | 'restore';

/** 草稿快照 */
export interface DraftSnapshot {
  id: number;
  activeTrainingId: number;
  stepIndex: number;
  content: string;
  trigger: DraftSnapshotTrigger;
  snapshotAt: string;
  restoredFromId: number | null;
}

/** 获取草稿快照请求 */
export interface ActiveTrainingGetDraftSnapshotsRequest {
  activeTrainingId: number;
}

/** 获取草稿快照响应 */
export interface ActiveTrainingGetDraftSnapshotsResponse {
  snapshots: DraftSnapshot[];
}

/** 回退草稿快照请求 */
export interface ActiveTrainingRestoreDraftSnapshotRequest {
  activeTrainingId: number;
  snapshotId: number;
}

/** 回退草稿快照响应 */
export interface ActiveTrainingRestoreDraftSnapshotResponse {
  success: boolean;
  restoredSnapshot: DraftSnapshot | null;
}

// ===== Sprint 25 C-2: 审计日志 =====

/** 审计日志触发原因 */
export type AuditLogTrigger =
  | 'start'
  | 'advance'
  | 'evaluate'
  | 'complete'
  | 'abort'
  | 'restore'
  | 'updateDraft'
  | 'submitStep';

/** 审计日志条目 */
export interface AuditLog {
  id: number;
  activeTrainingId: number;
  trigger: AuditLogTrigger;
  fromState: string | null;
  toState: string;
  actor: 'main' | 'renderer';
  contextJson: string | null;
  occurredAt: string;
}

/** 获取审计日志请求 */
export interface ActiveTrainingGetAuditLogsRequest {
  activeTrainingId: number;
}

/** 获取审计日志响应 */
export interface ActiveTrainingGetAuditLogsResponse {
  auditLogs: AuditLog[];
}

/** 获取最近状态转换请求 */
export interface ActiveTrainingGetRecentTransitionsRequest {
  sessionId: string;
  limit?: number;
}

/** 获取最近状态转换响应 */
export interface ActiveTrainingGetRecentTransitionsResponse {
  auditLogs: AuditLog[];
}

export const ActiveTrainingApi = {
  updateDraft: {
    channel: 'activeTraining:updateDraft',
    response: {} as ApiResponse<ActiveTrainingUpdateDraftResponse>,
  },
  get: {
    channel: 'activeTraining:get',
    response: {} as ApiResponse<ActiveTrainingGetResponse | null>,
  },
  /** Sprint 25 BL-01 C-4: 5 步分步提交 */
  submitStep: {
    channel: 'activeTraining:submitStep',
    response: {} as ApiResponse<ActiveTrainingSubmitStepResponse>,
  },
  /** Sprint 25 C-1: 获取草稿快照 */
  getDraftSnapshots: {
    channel: 'activeTraining:getDraftSnapshots',
    response: {} as ApiResponse<ActiveTrainingGetDraftSnapshotsResponse>,
  },
  /** Sprint 25 C-1: 回退草稿快照 */
  restoreDraftSnapshot: {
    channel: 'activeTraining:restoreDraftSnapshot',
    response: {} as ApiResponse<ActiveTrainingRestoreDraftSnapshotResponse>,
  },
  /** Sprint 25 C-2: 获取审计日志 */
  getAuditLogs: {
    channel: 'activeTraining:getAuditLogs',
    response: {} as ApiResponse<ActiveTrainingGetAuditLogsResponse>,
  },
  /** Sprint 25 C-2: 获取最近状态转换 */
  getRecentTransitions: {
    channel: 'activeTraining:getRecentTransitions',
    response: {} as ApiResponse<ActiveTrainingGetRecentTransitionsResponse>,
  },
  /** Sprint 24 A-4: 状态变更推送事件(主进程 → renderer) */
  updated: {
    channel: 'activeTraining:updated',
    event: {} as ActiveTrainingUpdatedEvent,
  },
} as const;

