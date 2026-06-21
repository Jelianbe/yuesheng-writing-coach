import type { ApiEndpoint, ApiResponse } from './base';

// ─── 数据类型 ───

/**
 * 项目信息(数据库行 → API 投影)
 *
 * 设计依据:RWR-P0-4 DoD
 * - id / name / description / settingTree / settingTreeType
 * - createdAt / updatedAt (INTEGER unixepoch → number)
 */
export interface ProjectInfo {
  id: string;
  name: string;
  description: string | null;
  /** JSON 字符串,存储项目设置树(小说设定/人物/情节大纲等) */
  settingTree: string | null;
  settingTreeType: string;
  createdAt: number;
  updatedAt: number;
}

// ─── 请求类型 ───

/** empty — 列出所有项目(按 updatedAt DESC) */
export type ProjectListRequest = Record<string, never>;

export interface ProjectGetRequest {
  projectId: string;
}

export interface ProjectCreateRequest {
  name: string;
  description?: string;
  /** 可选:导入已有 settingTree(JSON 字符串) */
  settingTree?: string;
  settingTreeType?: string;
}

export interface ProjectUpdateRequest {
  projectId: string;
  name?: string;
  description?: string;
  settingTree?: string;
  settingTreeType?: string;
}

export interface ProjectDeleteRequest {
  projectId: string;
}

// ─── 响应类型 ───

export type ProjectListResponse = ProjectInfo[];
export type ProjectGetResponse = ProjectInfo;
export type ProjectCreateResponse = ProjectInfo;
export type ProjectUpdateResponse = ProjectInfo;
export type ProjectDeleteResponse = void;

// ─── IPC 通道元类型 ───

export type ProjectInvokeChannels =
  | 'project:list'
  | 'project:get'
  | 'project:create'
  | 'project:update'
  | 'project:delete';

// ─── API 端点元数据 ───

export const ProjectApi = {
  list: {
    channel: 'project:list',
    request: {} as ProjectListRequest,
    response: {} as ApiResponse<ProjectListResponse>,
  },
  get: {
    channel: 'project:get',
    request: {} as ProjectGetRequest,
    response: {} as ApiResponse<ProjectGetResponse>,
  },
  create: {
    channel: 'project:create',
    request: {} as ProjectCreateRequest,
    response: {} as ApiResponse<ProjectCreateResponse>,
  },
  update: {
    channel: 'project:update',
    request: {} as ProjectUpdateRequest,
    response: {} as ApiResponse<ProjectUpdateResponse>,
  },
  delete: {
    channel: 'project:delete',
    request: {} as ProjectDeleteRequest,
    response: {} as ApiResponse<ProjectDeleteResponse>,
  },
} as const satisfies Record<string, ApiEndpoint<unknown, unknown>>;
