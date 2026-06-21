import type { ApiResponse } from './base';

// ─── 请求类型 ───

/** empty — 列出所有作品 */
export type ManuscriptListRequest = Record<string, never>;

export interface ManuscriptGetRequest {
  manuscriptId: string;
}

export interface ManuscriptCreateRequest {
  title: string;
  content?: string;
  genre?: string;
}

export interface ManuscriptUpdateRequest {
  manuscriptId: string;
  title?: string;
  content?: string;
  genre?: string;
}

export interface ManuscriptDeleteRequest {
  manuscriptId: string;
}

export interface ChapterListRequest {
  manuscriptId: string;
}

export interface ChapterGetRequest {
  chapterId: string;
}

export interface ChapterCreateRequest {
  manuscriptId: string;
  title: string;
  content?: string;
}

export interface ChapterDeleteRequest {
  chapterId: string;
}

export interface ChapterUpdateContentRequest {
  chapterId: string;
  content: string;
}

// ─── 响应类型 ───

export interface ManuscriptInfo {
  id: string;
  title: string;
  genre?: string;
  createdAt: number;
  updatedAt: number;
}

export interface ChapterInfo {
  id: string;
  manuscriptId: string;
  title: string;
  content: string;
  createdAt: number;
  updatedAt: number;
}

export interface ManuscriptListResponse {
  manuscripts: ManuscriptInfo[];
}

export interface ManuscriptGetResponse {
  manuscript: ManuscriptInfo;
}

export interface ManuscriptCreateResponse {
  manuscript: ManuscriptInfo;
}

export interface ChapterListResponse {
  chapters: ChapterInfo[];
}

export interface ChapterGetResponse {
  chapter: ChapterInfo;
}

export interface ChapterCreateResponse {
  chapter: ChapterInfo;
}

export interface ChapterUpdateContentResponse {
  success: true;
}

// ─── API 接口定义 ───

export const ManuscriptApi = {
  list: {
    channel: 'manuscript:list' as const,
    request: {} as ManuscriptListRequest,
    response: {} as ApiResponse<ManuscriptListResponse>,
  },

  get: {
    channel: 'manuscript:get' as const,
    request: {} as ManuscriptGetRequest,
    response: {} as ApiResponse<ManuscriptGetResponse>,
  },

  create: {
    channel: 'manuscript:create' as const,
    request: {} as ManuscriptCreateRequest,
    response: {} as ApiResponse<ManuscriptCreateResponse>,
  },

  update: {
    channel: 'manuscript:update' as const,
    request: {} as ManuscriptUpdateRequest,
    response: {} as ApiResponse<ManuscriptCreateResponse>,
  },

  delete: {
    channel: 'manuscript:delete' as const,
    request: {} as ManuscriptDeleteRequest,
    response: {} as ApiResponse<{ success: true }>,
  },
} as const;

export const ChapterApi = {
  list: {
    channel: 'chapter:list' as const,
    request: {} as ChapterListRequest,
    response: {} as ApiResponse<ChapterListResponse>,
  },

  get: {
    channel: 'chapter:get' as const,
    request: {} as ChapterGetRequest,
    response: {} as ApiResponse<ChapterGetResponse>,
  },

  create: {
    channel: 'chapter:create' as const,
    request: {} as ChapterCreateRequest,
    response: {} as ApiResponse<ChapterCreateResponse>,
  },

  delete: {
    channel: 'chapter:delete' as const,
    request: {} as ChapterDeleteRequest,
    response: {} as ApiResponse<{ success: true }>,
  },

  updateContent: {
    channel: 'chapter:updateContent' as const,
    request: {} as ChapterUpdateContentRequest,
    response: {} as ApiResponse<ChapterUpdateContentResponse>,
  },
} as const;

export type ManuscriptInvokeChannels =
  | typeof ManuscriptApi.list.channel
  | typeof ManuscriptApi.get.channel
  | typeof ManuscriptApi.create.channel
  | typeof ManuscriptApi.update.channel
  | typeof ManuscriptApi.delete.channel;

export type ChapterInvokeChannels =
  | typeof ChapterApi.list.channel
  | typeof ChapterApi.get.channel
  | typeof ChapterApi.create.channel
  | typeof ChapterApi.delete.channel
  | typeof ChapterApi.updateContent.channel;
