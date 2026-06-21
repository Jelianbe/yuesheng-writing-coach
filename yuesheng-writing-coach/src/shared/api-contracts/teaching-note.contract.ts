import type { ApiResponse } from './base';

// ─── 数据模型 ───

export interface TeachingNoteNode {
  id: string;
  /** 父节点 ID（root 节点为 null） */
  parentId: string | null;
  /** 节点标题 */
  label: string;
  /** 节点内容 */
  content: string;
  /** 创建时间戳 */
  createdAt: number;
  /** 子节点 */
  children: TeachingNoteNode[];
}

// ─── 请求类型 ───

export interface TeachingNoteRecordRequest {
  /** 关联会话 ID */
  sessionId: string;
  /** 节点标题 */
  label: string;
  /** 节点内容 */
  content: string;
  /** 父节点 ID（可选，不传则为 root 节点） */
  parentId?: string;
}

export interface TeachingNoteGetTreeRequest {
  /** 按会话筛选（可选，不传返回全部） */
  sessionId?: string;
}

export interface TeachingNoteDeleteRequest {
  id: string;
}

export interface TeachingNoteUpdateRequest {
  id: string;
  label?: string;
  content?: string;
}

// ─── 响应类型 ───

export interface TeachingNoteRecordResponse {
  id: string;
  createdAt: number;
}

export interface TeachingNoteGetTreeResponse {
  nodes: TeachingNoteNode[];
}

export interface TeachingNoteDeleteResponse {
  success: boolean;
}

export interface TeachingNoteUpdateResponse {
  success: boolean;
}

// ─── API 接口定义 ───

export const TeachingNoteApi = {
  record: {
    channel: 'teachingNote:record' as const,
    request: {} as TeachingNoteRecordRequest,
    response: {} as ApiResponse<TeachingNoteRecordResponse>,
  },
  getTree: {
    channel: 'teachingNote:getTree' as const,
    request: {} as TeachingNoteGetTreeRequest,
    response: {} as ApiResponse<TeachingNoteGetTreeResponse>,
  },
  delete: {
    channel: 'teachingNote:delete' as const,
    request: {} as TeachingNoteDeleteRequest,
    response: {} as ApiResponse<TeachingNoteDeleteResponse>,
  },
  update: {
    channel: 'teachingNote:update' as const,
    request: {} as TeachingNoteUpdateRequest,
    response: {} as ApiResponse<TeachingNoteUpdateResponse>,
  },
} as const;

export type TeachingNoteInvokeChannels =
  | typeof TeachingNoteApi.record.channel
  | typeof TeachingNoteApi.getTree.channel
  | typeof TeachingNoteApi.delete.channel
  | typeof TeachingNoteApi.update.channel;
