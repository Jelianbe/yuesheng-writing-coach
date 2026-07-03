/**
 * 会话管理服务 — Sprint 20 B-3 降级(D-DEBT-34)
 *
 * 降级策略:调用失败时 console.error + 返回 fallback,不再 throw。
 * isNewUser 已是降级模式(返回 false),其余 8 处统一对齐。
 *
 * 注意:8 处强错误降级后,签名可能与原 try/catch 调用方不兼容。
 * 当前审计显示 renderer 端仅 isNewUser 被 useAppController 调用,
 * 其余方法为内部 API 暴露,本降级属于"防御性基线"提前完成。
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
  /** 获取会话列表 — 失败时返回 [] */
  async list(): Promise<SessionInfo[]> {
    const result = await typedInvoke<Record<string, never>, SessionListResponse>(
      SessionApi.list.channel,
      {},
    );
    if (!result.success) {
      console.error('[session] list failed:', result.error);
      return [];
    }
    return result.data.sessions;
  },

  /** 创建新会话 — 失败时返回 null */
  async create(title?: string): Promise<SessionInfo | null> {
    const result = await typedInvoke<{ title?: string }, SessionCreateResponse>(
      SessionApi.create.channel,
      { title },
    );
    if (!result.success) {
      console.error('[session] create failed:', result.error);
      return null;
    }
    return result.data.session;
  },

  /** 删除会话 — 失败时返回 false */
  async delete(sessionId: string): Promise<boolean> {
    const result = await typedInvoke<{ sessionId: string }, void>(
      SessionApi.delete.channel,
      { sessionId },
    );
    if (!result.success) {
      console.error('[session] delete failed:', result.error);
      return false;
    }
    return true;
  },

  /** 重命名会话 — 失败时返回 false */
  async rename(sessionId: string, title: string): Promise<boolean> {
    const result = await typedInvoke<{ sessionId: string; title: string }, void>(
      SessionApi.rename.channel,
      { sessionId, title },
    );
    if (!result.success) {
      console.error('[session] rename failed:', result.error);
      return false;
    }
    return true;
  },

  /** 分页加载消息 — 失败时返回空页(降级,载荷含消息内容) */
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
      console.error('[session] getMessagesPaged failed:', result.error);
      return { messages: [], hasMore: false };
    }
    return result.data;
  },

  /** 获取会话列表(含元数据) — 失败时返回 [] */
  async listWithMeta(): Promise<SessionListWithMetaResponse['sessions']> {
    const result = await typedInvoke<Record<string, never>, SessionListWithMetaResponse>(
      SessionApi.listWithMeta.channel,
      {},
    );
    if (!result.success) {
      console.error('[session] listWithMeta failed:', result.error);
      return [];
    }
    return result.data.sessions;
  },

  /** 更新会话标题 — 失败时返回 false */
  async updateTitle(sessionId: string, title: string): Promise<boolean> {
    const result = await typedInvoke<{ sessionId: string; title: string }, SessionUpdateTitleResponse>(
      SessionApi.updateTitle.channel,
      { sessionId, title },
    );
    if (!result.success) {
      console.error('[session] updateTitle failed:', result.error);
      return false;
    }
    return true;
  },

  /** 搜索消息 — 失败时返回 [] */
  async searchMessages(sessionId: string, query: string): Promise<SessionMessage[]> {
    const result = await typedInvoke<
      { sessionId: string; query: string },
      SessionSearchMessagesResponse
    >(SessionApi.searchMessages.channel, { sessionId, query });
    if (!result.success) {
      console.error('[session] searchMessages failed:', result.error);
      return [];
    }
    return result.data.messages;
  },

  /** 检测是否为新用户 — 已降级 */
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
