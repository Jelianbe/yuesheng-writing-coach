/**
 * ActiveTraining IPC 契约 — Sprint 24 A-3
 *
 * 定义 ActiveTraining 状态机 IPC 边界的请求/响应类型。
 * 主进程侧 ActiveTrainingService 接收这些请求,操作 SQLite active_training 表。
 *
 * 依据: dev-docs/tasks/sprint-24-plan.md §A-3, §A-4
 */

import type { ApiResponse } from './base';
import type { ActiveTrainingStatus, TrainingStep, TrainingFlow } from '../types/index';

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
export const ActiveTrainingApi = {
  updateDraft: {
    channel: 'activeTraining:updateDraft',
    response: {} as ApiResponse<ActiveTrainingUpdateDraftResponse>,
  },
  get: {
    channel: 'activeTraining:get',
    response: {} as ApiResponse<ActiveTrainingGetResponse | null>,
  },
  /** Sprint 24 A-4: 状态变更推送事件(主进程 → renderer) */
  updated: {
    channel: 'activeTraining:updated',
    event: {} as ActiveTrainingUpdatedEvent,
  },
} as const;

