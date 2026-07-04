import { IPC_CHANNELS } from '../../shared/constants';
// Sprint 26 阶段 2:切到 shared/services/session.service.ts(异步 + StorageAdapter)
// 旧 src/main/shared/services/session.service.ts(sync) 已标 @deprecated
import type { SessionService } from '../../shared/services/session.service';
import { validatePayload } from './utils/validate-payload';
import { createHandler } from './utils/create-handler';

export interface SessionHandlerDeps {
  sessionService: SessionService;
}

let deps: SessionHandlerDeps | null = null;

export function initSessionHandlers(d: SessionHandlerDeps): void {
  deps = d;
}

export function registerSessionHandlers(): void {
  if (!deps) throw new Error('SessionHandler deps not injected');
  const d = deps;

  createHandler(IPC_CHANNELS.SESSION_LIST, async () => {
    const sessions = await d.sessionService.listSessions();
    return Promise.all(sessions.map(async s => {
      const last = await d.sessionService.getLastMessage(s.id);
      return {
        id: s.id,
        title: s.title,
        createdAt: s.created_at,
        updatedAt: s.updated_at,
        lastMessage: last?.content.slice(0, 50) || undefined,
        messages: [],
      };
    }));
  });

  // session:isNewUser — 判断是否为新用户（无任何会话）
  createHandler(IPC_CHANNELS.SESSION_IS_NEW_USER, async () => {
    const sessions = await d.sessionService.listSessions();
    return sessions.length === 0;
  });

  createHandler(IPC_CHANNELS.SESSION_CREATE, async () => {
    const s = await d.sessionService.createSession();
    return { id: s.id, title: s.title, createdAt: s.created_at, updatedAt: s.updated_at, messages: [] };
  });

  createHandler(IPC_CHANNELS.SESSION_DELETE, async (_event, args) => {
    const validation = validatePayload<{ sessionId: string }>(args, { required: ['sessionId'], types: { sessionId: 'string' } });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    await d.sessionService.deleteSession(validation.data.sessionId);
  });

  createHandler(IPC_CHANNELS.SESSION_RENAME, async (_event, args) => {
    const validation = validatePayload<{ sessionId: string; title: string }>(args, { required: ['sessionId', 'title'], types: { sessionId: 'string', title: 'string' } });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    await d.sessionService.renameSession(validation.data.sessionId, validation.data.title);
  });

  createHandler(IPC_CHANNELS.SESSION_GET_MESSAGES, async (_event, args) => {
    const validation = validatePayload<{ sessionId: string }>(args, { required: ['sessionId'], types: { sessionId: 'string' } });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    return d.sessionService.getMessages(validation.data.sessionId);
  });

  // session:getMessagesPaged — 分页加载消息（V2-019）
  createHandler(IPC_CHANNELS.SESSION_GET_MESSAGES_PAGED, async (_event, args) => {
    const validation = validatePayload<{ sessionId: string; offset: number; limit: number }>(args, {
      required: ['sessionId'],
      types: { sessionId: 'string', offset: 'number', limit: 'number' },
      ranges: { offset: { min: 0 }, limit: { min: 1, max: 200 } },
    });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    return d.sessionService.getMessagesPaged(validation.data.sessionId, validation.data.offset, validation.data.limit);
  });

  // session:listWithMeta — 含 title/preview 的会话列表（V2 SOLO）
  createHandler(IPC_CHANNELS.SESSION_LIST_WITH_META, async (_event, args: { limit?: number; offset?: number }) => {
    const sessions = await d.sessionService.listSessions();
    let result = await Promise.all(sessions.map(async s => {
      const lastMsg = await d.sessionService.getLastMessage(s.id);
      return {
        id: s.id,
        title: s.title,
        preview: lastMsg ? lastMsg.content.slice(0, 80) : '',
        createdAt: s.created_at,
        updatedAt: s.updated_at,
      };
    }));
    // 分页
    const offset = args.offset ?? 0;
    const limit = args.limit ?? result.length;
    result = result.slice(offset, offset + limit);
    return result;
  });

  // session:updateTitle
  createHandler(IPC_CHANNELS.SESSION_UPDATE_TITLE, async (_event, args) => {
    const validation = validatePayload<{ id: string; title: string }>(args, { required: ['id', 'title'], types: { id: 'string', title: 'string' } });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    await d.sessionService.renameSession(validation.data.id, validation.data.title);
  });

  // session:searchMessages — 跨会话搜索消息（全局搜索面板）
  createHandler(IPC_CHANNELS.SESSION_SEARCH_MESSAGES, async (_event, args) => {
    const validation = validatePayload<{ query: string }>(args, { required: ['query'], types: { query: 'string' } });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    return d.sessionService.searchMessages(validation.data.query);
  });
}
