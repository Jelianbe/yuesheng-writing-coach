/**
 * 会话管理服务 — Sprint 32 (移除 serviceBridge/dual-track)
 *
 * 双轨迁移:
 * - Electron 端: 直接 typedInvoke → main handler
 * - Android 端: import shared SessionService + CapacitorSqliteAdapter
 *
 * 依据: dev-docs/tasks/sprint-32-plan.md
 */
import { invoke } from './_invoke';
import { isCapacitor } from './_platform';
import type {
  SessionInfo,
  SessionMessage,
} from '../../shared/api-contracts/session.contract';
import { createStorageAdapter } from '../../shared/storage';
import { SessionService as DirectSessionService } from '../../shared/services/session.service';

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
    if (isCapacitor()) {
      const direct = await getDirectService();
      if (!direct) return [];
      try { return (await direct.listSessions()).map(toSessionInfo); }
      catch (err) { console.error('[session] list failed (direct):', err); return []; }
    }
    return (await invoke<SessionInfo[]>('session:list', {})) ?? [];
  },

  /** 创建新会话 — 失败时返回 null */
  async create(title?: string): Promise<SessionInfo | null> {
    if (isCapacitor()) {
      const direct = await getDirectService();
      if (!direct) return null;
      try {
        const row = await direct.createSession();
        if (title) { await direct.renameSession(row.id, title); row.title = title; }
        return toSessionInfo(row);
      } catch (err) { console.error('[session] create failed (direct):', err); return null; }
    }
    return invoke<SessionInfo>('session:create', { title }) ?? null;
  },

  /** 删除会话 — 失败时返回 false */
  async delete(sessionId: string): Promise<boolean> {
    if (isCapacitor()) {
      const direct = await getDirectService();
      if (!direct) return false;
      try { await direct.deleteSession(sessionId); return true; }
      catch (err) { console.error('[session] delete failed (direct):', err); return false; }
    }
    const result = await invoke<{ success: true }>('session:delete', { sessionId });
    return result !== null;
  },

  /** 重命名会话 — 失败时返回 false */
  async rename(sessionId: string, title: string): Promise<boolean> {
    if (isCapacitor()) {
      const direct = await getDirectService();
      if (!direct) return false;
      try { await direct.renameSession(sessionId, title); return true; }
      catch (err) { console.error('[session] rename failed (direct):', err); return false; }
    }
    const result = await invoke<{ success: true }>('session:rename', { sessionId, title });
    return result !== null;
  },

  /** 加载会话所有消息 — 失败时返回 [] */
  async getMessages(sessionId: string): Promise<SessionMessage[]> {
    if (isCapacitor()) {
      const direct = await getDirectService();
      if (!direct) return [];
      try {
        const rows = await direct.getMessages(sessionId);
        return rows.map((m) => ({ id: m.id, sessionId: m.session_id, role: m.role as SessionMessage['role'], content: m.content, createdAt: m.timestamp }));
      } catch (err) { console.error('[session] getMessages failed (direct):', err); return []; }
    }
    return (await invoke<SessionMessage[]>('session:getMessages', { sessionId })) ?? [];
  },

  /** 分页加载消息 — 失败时返回空页 */
  async getMessagesPaged(
    sessionId: string,
    offset: number,
    limit: number,
  ): Promise<{ messages: SessionMessage[]; hasMore: boolean }> {
    if (isCapacitor()) {
      const direct = await getDirectService();
      if (!direct) return { messages: [], hasMore: false };
      try {
        const result = await direct.getMessagesPaged(sessionId, offset, limit);
        return {
          messages: result.messages.map((m) => ({ id: m.id, sessionId: m.session_id, role: m.role as SessionMessage['role'], content: m.content, createdAt: m.timestamp })),
          hasMore: result.hasMore,
        };
      } catch (err) { console.error('[session] getMessagesPaged failed (direct):', err); return { messages: [], hasMore: false }; }
    }
    return (await invoke<{ messages: SessionMessage[]; hasMore: boolean }>('session:getMessagesPaged', { sessionId, offset, limit })) ?? { messages: [], hasMore: false };
  },

  /** 获取会话列表(含元数据) — 失败时返回 [] */
  async listWithMeta(): Promise<Array<SessionInfo & { messageCount: number; lastMessageAt: number }>> {
    if (isCapacitor()) {
      const direct = await getDirectService();
      if (!direct) return [];
      try {
        const rows = await direct.listSessions();
        return rows.map((r) => ({ ...toSessionInfo(r), messageCount: 0, lastMessageAt: Date.parse(r.updated_at) }));
      } catch (err) { console.error('[session] listWithMeta failed (direct):', err); return []; }
    }
    return (await invoke<Array<SessionInfo & { messageCount: number; lastMessageAt: number }>>('session:listWithMeta', {})) ?? [];
  },

  /** 更新会话标题 — 失败时返回 false */
  async updateTitle(sessionId: string, title: string): Promise<boolean> {
    return this.rename(sessionId, title);
  },

  /** 搜索消息 — 失败时返回 [] */
  async searchMessages(sessionId: string, query: string): Promise<SessionMessage[]> {
    if (isCapacitor()) {
      const direct = await getDirectService();
      if (!direct) return [];
      try {
        const results = await direct.searchMessages(query);
        return results
          .filter((r) => r.sessionId === sessionId || !sessionId)
          .flatMap((r) => r.messages)
          .map((m) => ({ id: m.id, sessionId: m.session_id, role: m.role as SessionMessage['role'], content: m.content, createdAt: m.timestamp }));
      } catch (err) { console.error('[session] searchMessages failed (direct):', err); return []; }
    }
    return (await invoke<SessionMessage[]>('session:searchMessages', { sessionId, query })) ?? [];
  },

  /** 检测是否为新用户 — 失败时返回 false */
  async isNewUser(): Promise<boolean> {
    if (isCapacitor()) {
      const direct = await getDirectService();
      if (!direct) return false;
      try { return (await direct.listSessions()).length === 0; }
      catch (err) { console.error('[session] isNewUser failed (direct):', err); return false; }
    }
    return (await invoke<boolean>('session:isNewUser', {})) ?? false;
  },
};
