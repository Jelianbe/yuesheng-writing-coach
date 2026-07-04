/**
 * 会话管理服务 — Sprint 26 跨端版
 *
 * 双轨实现(R-010 最小化):
 * - Electron 端: 走 typedInvoke → main 进程 → better-sqlite3(保留旧 IPC 路径)
 * - Android/Capacitor 端: 直接 import 新 SessionService + CapacitorSqliteAdapter
 *
 * 平台检测: 通过 `window.Capacitor` 区分(由 @capacitor/core 注入)
 *
 * 依据: dev-docs/tasks/sprint-26-android-pivot.md §1.2 / D-074
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
  SessionSearchMessagesResponse,
  SessionIsNewUserResponse,
} from '../../shared/api-contracts/session.contract';
import { createStorageAdapter } from '../../shared/storage';
import { SessionService as DirectSessionService } from '../../shared/services/session.service';

/** Platform detection — Capacitor 在 WebView 中注入 `window.Capacitor` */
const isCapacitor = (): boolean => {
  if (typeof window === 'undefined') return false;
  return !!(window as unknown as { Capacitor?: unknown }).Capacitor;
};

/** Android 端: 延迟初始化 adapter + direct service */
let _directService: DirectSessionService | null = null;

async function getDirectService(): Promise<DirectSessionService | null> {
  if (!isCapacitor()) return null;
  if (_directService) return _directService;

  const adapter = createStorageAdapter({ type: 'capacitor-sqlite', dbName: 'yuesheng.db', version: 1 });
  await adapter.initialize();
  _directService = new DirectSessionService(adapter);
  return _directService;
}

/** 把 SessionRow 转成 SessionInfo(created_at ISO string → createdAt number) */
function toSessionInfo(row: { id: string; title: string; created_at: string; updated_at: string }): SessionInfo {
  return {
    id: row.id,
    title: row.title,
    createdAt: Date.parse(row.created_at),
    updatedAt: Date.parse(row.updated_at),
  };
}

export const sessionService = {
  /** 获取会话列表 — 失败时返回 [] */
  async list(): Promise<SessionInfo[]> {
    const direct = await getDirectService();
    if (direct) {
      try {
        const rows = await direct.listSessions();
        return rows.map(toSessionInfo);
      } catch (err) {
        console.error('[session] list failed (direct):', err);
        return [];
      }
    }

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
    const direct = await getDirectService();
    if (direct) {
      try {
        const row = await direct.createSession();
        // 标题覆盖(若传入)
        if (title) {
          await direct.renameSession(row.id, title);
          row.title = title;
        }
        return toSessionInfo(row);
      } catch (err) {
        console.error('[session] create failed (direct):', err);
        return null;
      }
    }

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
    const direct = await getDirectService();
    if (direct) {
      try {
        await direct.deleteSession(sessionId);
        return true;
      } catch (err) {
        console.error('[session] delete failed (direct):', err);
        return false;
      }
    }

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
    const direct = await getDirectService();
    if (direct) {
      try {
        await direct.renameSession(sessionId, title);
        return true;
      } catch (err) {
        console.error('[session] rename failed (direct):', err);
        return false;
      }
    }

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

  /** 分页加载消息 — 失败时返回空页 */
  async getMessagesPaged(
    sessionId: string,
    offset: number,
    limit: number,
  ): Promise<{ messages: SessionMessage[]; hasMore: boolean }> {
    const direct = await getDirectService();
    if (direct) {
      try {
        const result = await direct.getMessagesPaged(sessionId, offset, limit);
        return {
          messages: result.messages.map((m) => ({
            id: m.id,
            sessionId: m.session_id,
            role: m.role,
            content: m.content,
            createdAt: m.timestamp,
          })),
          hasMore: result.hasMore,
        };
      } catch (err) {
        console.error('[session] getMessagesPaged failed (direct):', err);
        return { messages: [], hasMore: false };
      }
    }

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
    const direct = await getDirectService();
    if (direct) {
      try {
        const rows = await direct.listSessions();
        return rows.map((r) => {
          const info = toSessionInfo(r);
          return { ...info, messageCount: 0, lastMessageAt: info.updatedAt };
        });
      } catch (err) {
        console.error('[session] listWithMeta failed (direct):', err);
        return [];
      }
    }

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
    return this.rename(sessionId, title);
  },

  /** 搜索消息 — 失败时返回 [] */
  async searchMessages(sessionId: string, query: string): Promise<SessionMessage[]> {
    const direct = await getDirectService();
    if (direct) {
      try {
        const results = await direct.searchMessages(query);
        // 跨会话搜索: 展平所有 session 的 messages
        return results
          .filter((r) => r.sessionId === sessionId || !sessionId)
          .flatMap((r) => r.messages)
          .map((m) => ({
            id: m.id,
            sessionId: m.session_id,
            role: m.role,
            content: m.content,
            createdAt: m.timestamp,
          }));
      } catch (err) {
        console.error('[session] searchMessages failed (direct):', err);
        return [];
      }
    }

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
    const direct = await getDirectService();
    if (direct) {
      try {
        const sessions = await direct.listSessions();
        return sessions.length === 0;
      } catch (err) {
        console.error('[session] isNewUser failed (direct):', err);
        return false;
      }
    }

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
