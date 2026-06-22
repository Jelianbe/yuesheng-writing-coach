import type { ApiEndpoint, ApiResponse } from './base';
import type { DevelopmentStageInfo, StageProgress } from '../types/index';

// ─── 重导出领域类型 — index.ts 统一从此处导出，避免直接穿透到 types/index ───
export type { DevelopmentStageInfo, StageProgress };

// ─── 数据类型 ───

/** 学习阶段 ID 列表请求(无入参) */
export interface PrescriptionGetAllStagesRequest {
  // empty
}

/** 按 ID 获取学习阶段 */
export interface PrescriptionGetStageByIdRequest {
  stageId: string;
}

/** 按会话获取阶段进度 */
export interface PrescriptionGetStageProgressRequest {
  sessionId: string;
}

export interface PrescriptionGetStageProgressResponse {
  /** 当前阶段 ID */
  currentStageId: string | null;
  /** 阶段进度详情 */
  progress: StageProgress;
  /** 全部可用阶段（按 order 排序） */
  allStages: DevelopmentStageInfo[];
}

// ─── API 定义 ───

/**
 * Prescription 阶段 API 契约
 *
 * 阶段（stage）是学习者跨越的长期里程碑，由多个相关症候的掌握度共同决定。
 * 调用方: renderer/stores/training.actions.ts、workspaces/StageProgressWorkspace
 */
export const PrescriptionApi = {
  getAllStages: 'prescription:getAllStages',
  getStageById: 'prescription:getStageById',
  getStageProgress: 'prescription:getStageProgress',
} as const;

export type PrescriptionApiChannel = typeof PrescriptionApi[keyof typeof PrescriptionApi];

/** invoke 通道（主进程调用） */
export type PrescriptionInvokeChannels = PrescriptionApiChannel;

/** event 通道（预留,当前不推送任何事件） */
export type PrescriptionEventChannels = never;

// ─── 端点类型映射 ───

export type PrescriptionEndpoints = {
  [PrescriptionApi.getAllStages]: ApiEndpoint<PrescriptionGetAllStagesRequest, ApiResponse<DevelopmentStageInfo[]>>;
  [PrescriptionApi.getStageById]: ApiEndpoint<PrescriptionGetStageByIdRequest, ApiResponse<DevelopmentStageInfo | null>>;
  [PrescriptionApi.getStageProgress]: ApiEndpoint<PrescriptionGetStageProgressRequest, ApiResponse<PrescriptionGetStageProgressResponse>>;
};
