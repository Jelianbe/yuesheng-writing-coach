/**
 * 会话管理服务
 *
 * 封装所有 session 域 IPC 通信。
 */

import { typedInvoke } from './ipc-client';
import { SessionApi } from '../../shared/api-contracts/session.contract';
import type {
  SessionInfo,
  SessionMessage,
  SessionListResponse,
  SessionCreateResponse,
  SessionGetMessagesPagedResponse,
  SessionListWithMetaResponse,
  SessionUpdateTitleResponse,
  SessionSearchMessagesResponse,
  SessionIsNewUserResponse,
} from '../../shared/api-contracts/session.contract';

export const sessionService = {
  /** 获取会话列表 */
  async list(): Promise<SessionInfo[]> {
    const result = await typedInvoke<Record<string, never>, SessionListResponse>(
      SessionApi.list.channel,
      {},
    );
    if (!result.success) {
      throw new Error(result.error);
    }
    return result.data.sessions;
  },

  /** 创建新会话 */
  async create(title?: string): Promise<SessionInfo | null> {
    const result = await typedInvoke<{ title?: string }, SessionCreateResponse>(
      SessionApi.create.channel,
      { title },
    );
    if (!result.success) {
      throw new Error(result.error);
    }
    return result.data.session;
  },

  /** 删除会话 */
  async delete(sessionId: string): Promise<void> {
    const result = await typedInvoke<{ sessionId: string }, void>(
      SessionApi.delete.channel,
      { sessionId },
    );
    if (!result.success) {
      throw new Error(result.error);
    }
  },

  /** 重命名会话 */
  async rename(sessionId: string, title: string): Promise<void> {
    const result = await typedInvoke<{ sessionId: string; title: string }, void>(
      SessionApi.rename.channel,
      { sessionId, title },
    );
    if (!result.success) {
      throw new Error(result.error);
    }
  },

  /** 分页加载消息 */
  async getMessagesPaged(
    sessionId: string,
    offset: number,
    limit: number,
  ): Promise<{ messages: SessionMessage[]; hasMore: boolean }> {
    const result = await typedInvoke<
      { sessionId: string; offset: number; limit: number },
      SessionGetMessagesPagedResponse
    >(SessionApi.getMessagesPaged.channel, { sessionId, offset, limit });
    if (!result.success) {
      throw new Error(result.error);
    }
    return result.data;
  },

  /** 获取会话列表（含元数据） */
  async listWithMeta(): Promise<SessionListWithMetaResponse['sessions']> {
    const result = await typedInvoke<Record<string, never>, SessionListWithMetaResponse>(
      SessionApi.listWithMeta.channel,
      {},
    );
    if (!result.success) {
      throw new Error(result.error);
    }
    return result.data.sessions;
  },

  /** 更新会话标题 */
  async updateTitle(sessionId: string, title: string): Promise<void> {
    const result = await typedInvoke<{ sessionId: string; title: string }, SessionUpdateTitleResponse>(
      SessionApi.updateTitle.channel,
      { sessionId, title },
    );
    if (!result.success) {
      throw new Error(result.error);
    }
  },

  /** 搜索消息 */
  async searchMessages(sessionId: string, query: string): Promise<SessionMessage[]> {
    const result = await typedInvoke<
      { sessionId: string; query: string },
      SessionSearchMessagesResponse
    >(SessionApi.searchMessages.channel, { sessionId, query });
    if (!result.success) {
      throw new Error(result.error);
    }
    return result.data.messages;
  },

  /** 检测是否为新用户 */
  async isNewUser(): Promise<boolean> {
    const result = await typedInvoke<Record<string, never>, SessionIsNewUserResponse>(
      SessionApi.isNewUser.channel,
      {},
    );
    if (!result.success) {
      return false;
    }
    return result.data.isNewUser;
  },
};
