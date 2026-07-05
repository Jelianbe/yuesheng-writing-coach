/**
 * 训练计划 IPC 合约类型
 *
 * Sprint 38: 自定义训练计划功能
 */

/** 训练计划（列表项） */
export interface TrainingPlanDTO {
  id: string;
  name: string;
  description: string;
  createdAt: string;
  updatedAt: string;
  itemCount: number;
  completedCount: number;
}

/** 训练计划（含完整项列表） */
export interface TrainingPlanWithItemsDTO extends TrainingPlanDTO {
  items: TrainingPlanItemDTO[];
}

/** 训练计划项 */
export interface TrainingPlanItemDTO {
  id: string;
  planId: string;
  challengeId: string;
  techniqueName: string;
  syndromeId: string | null;
  sortOrder: number;
  status: 'pending' | 'in_progress' | 'completed';
  completedAt: string | null;
  createdAt: string;
}

/** 可用挑战（从 challenge-templates.json 提取，供用户选择添加到计划） */
export interface AvailableChallengeDTO {
  challengeId: string;
  techniqueName: string;
  syndromeId: string;
  description: string;
  constraint: string;
}

// ─── Request / Response ───

export interface PlanCreateRequest {
  name: string;
  description?: string;
}

export interface PlanCreateResponse {
  id: string;
}

export interface PlanAddItemRequest {
  planId: string;
  challengeId: string;
}

export interface PlanUpdateItemStatusRequest {
  itemId: string;
  status: 'pending' | 'in_progress' | 'completed';
}

export interface PlanReorderItemsRequest {
  planId: string;
  itemIds: string[]; // 新的顺序
}
