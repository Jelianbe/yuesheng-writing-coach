import type { ApiResponse } from './base';

// ─── 请求类型 ───

export interface SessionListRequest {
  /** empty — 无参数 */
}

export interface SessionCreateRequest {
  title?: string;
}

export interface SessionDeleteRequest {
  sessionId: string;
}

export interface SessionRenameRequest {
  sessionId: string;
  title: string;
}

export interface SessionGetMessagesRequest {
  sessionId: string;
}

export interface SessionGetMessagesPagedRequest {
  sessionId: string;
  limit: number;
  offset: number;
}

export interface SessionListWithMetaRequest {
  /** empty — 无参数 */
}

export interface SessionUpdateTitleRequest {
  sessionId: string;
  title: string;
}

export interface SessionSearchMessagesRequest {
  sessionId: string;
  query: string;
  limit?: number;
}

export interface SessionIsNewUserRequest {
  /** empty — 无参数 */
}

// ─── 响应类型 ───

export interface SessionInfo {
  id: string;
  title: string;
  createdAt: number;
  updatedAt: number;
  messageCount?: number;
}

export interface SessionMessage {
  id: string;
  sessionId: string;
  role: 'user' | 'assistant' | 'system';
  content: string;
  createdAt: number;
}

export interface SessionListResponse {
  sessions: SessionInfo[];
}

export interface SessionCreateResponse {
  session: SessionInfo;
}

export interface SessionGetMessagesResponse {
  messages: SessionMessage[];
}

export interface SessionGetMessagesPagedResponse {
  messages: SessionMessage[];
  total: number;
  hasMore: boolean;
}

export interface SessionListWithMetaResponse {
  sessions: Array<SessionInfo & { messageCount: number; lastMessageAt: number }>;
}

export interface SessionUpdateTitleResponse {
  success: true;
}

export interface SessionSearchMessagesResponse {
  messages: SessionMessage[];
  total: number;
}

export interface SessionIsNewUserResponse {
  isNewUser: boolean;
}

// ─── API 接口定义 ───

export const SessionApi = {
  list: {
    channel: 'session:list' as const,
    request: {} as SessionListRequest,
    response: {} as ApiResponse<SessionListResponse>,
  },

  create: {
    channel: 'session:create' as const,
    request: {} as SessionCreateRequest,
    response: {} as ApiResponse<SessionCreateResponse>,
  },

  delete: {
    channel: 'session:delete' as const,
    request: {} as SessionDeleteRequest,
    response: {} as ApiResponse<{ success: true }>,
  },

  rename: {
    channel: 'session:rename' as const,
    request: {} as SessionRenameRequest,
    response: {} as ApiResponse<{ success: true }>,
  },

  getMessages: {
    channel: 'session:getMessages' as const,
    request: {} as SessionGetMessagesRequest,
    response: {} as ApiResponse<SessionGetMessagesResponse>,
  },

  getMessagesPaged: {
    channel: 'session:getMessagesPaged' as const,
    request: {} as SessionGetMessagesPagedRequest,
    response: {} as ApiResponse<SessionGetMessagesPagedResponse>,
  },

  listWithMeta: {
    channel: 'session:listWithMeta' as const,
    request: {} as SessionListWithMetaRequest,
    response: {} as ApiResponse<SessionListWithMetaResponse>,
  },

  updateTitle: {
    channel: 'session:updateTitle' as const,
    request: {} as SessionUpdateTitleRequest,
    response: {} as ApiResponse<SessionUpdateTitleResponse>,
  },

  searchMessages: {
    channel: 'session:searchMessages' as const,
    request: {} as SessionSearchMessagesRequest,
    response: {} as ApiResponse<SessionSearchMessagesResponse>,
  },

  isNewUser: {
    channel: 'session:isNewUser' as const,
    request: {} as SessionIsNewUserRequest,
    response: {} as ApiResponse<SessionIsNewUserResponse>,
  },
} as const;

export type SessionInvokeChannels =
  | typeof SessionApi.list.channel
  | typeof SessionApi.create.channel
  | typeof SessionApi.delete.channel
  | typeof SessionApi.rename.channel
  | typeof SessionApi.getMessages.channel
  | typeof SessionApi.getMessagesPaged.channel
  | typeof SessionApi.listWithMeta.channel
  | typeof SessionApi.updateTitle.channel
  | typeof SessionApi.searchMessages.channel
  | typeof SessionApi.isNewUser.channel;
