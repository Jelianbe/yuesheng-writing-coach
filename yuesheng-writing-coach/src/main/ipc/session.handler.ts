import { IPC_CHANNELS } from '../../shared/constants';
import { SessionService } from '../shared/services/session.service';
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

  createHandler(IPC_CHANNELS.SESSION_LIST, () => {
    const sessions = deps!.sessionService.listSessions();
    return sessions.map(s => ({
      id: s.id,
      title: s.title,
      createdAt: s.created_at,
      updatedAt: s.updated_at,
      lastMessage: deps!.sessionService.getLastMessage(s.id)?.content.slice(0, 50) || undefined,
      messages: [],
    }));
  });

  // session:isNewUser — 判断是否为新用户（无任何会话）
  createHandler(IPC_CHANNELS.SESSION_IS_NEW_USER, () => {
    const sessions = deps!.sessionService.listSessions();
    return sessions.length === 0;
  });

  createHandler(IPC_CHANNELS.SESSION_CREATE, () => {
    const s = deps!.sessionService.createSession();
    return { id: s.id, title: s.title, createdAt: s.created_at, updatedAt: s.updated_at, messages: [] };
  });

  createHandler(IPC_CHANNELS.SESSION_DELETE, (_event, args) => {
    const validation = validatePayload<{ sessionId: string }>(args, { required: ['sessionId'], types: { sessionId: 'string' } });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    deps!.sessionService.deleteSession(validation.data.sessionId);
  });

  createHandler(IPC_CHANNELS.SESSION_RENAME, (_event, args) => {
    const validation = validatePayload<{ sessionId: string; title: string }>(args, { required: ['sessionId', 'title'], types: { sessionId: 'string', title: 'string' } });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    deps!.sessionService.renameSession(validation.data.sessionId, validation.data.title);
  });

  createHandler(IPC_CHANNELS.SESSION_GET_MESSAGES, (_event, args) => {
    const validation = validatePayload<{ sessionId: string }>(args, { required: ['sessionId'], types: { sessionId: 'string' } });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    return deps!.sessionService.getMessages(validation.data.sessionId);
  });

  // session:getMessagesPaged — 分页加载消息（V2-019）
  createHandler(IPC_CHANNELS.SESSION_GET_MESSAGES_PAGED, (_event, args) => {
    const validation = validatePayload<{ sessionId: string; offset: number; limit: number }>(args, {
      required: ['sessionId'],
      types: { sessionId: 'string', offset: 'number', limit: 'number' },
      ranges: { offset: { min: 0 }, limit: { min: 1, max: 200 } },
    });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    return deps!.sessionService.getMessagesPaged(validation.data.sessionId, validation.data.offset, validation.data.limit);
  });

  // session:listWithMeta — 含 title/preview 的会话列表（V2 SOLO）
  createHandler(IPC_CHANNELS.SESSION_LIST_WITH_META, (_event, args: { limit?: number; offset?: number }) => {
    const sessions = deps!.sessionService.listSessions();
    let result = sessions.map(s => {
      const lastMsg = deps!.sessionService.getLastMessage(s.id);
      return {
        id: s.id,
        title: s.title,
        preview: lastMsg ? lastMsg.content.slice(0, 80) : '',
        createdAt: s.created_at,
        updatedAt: s.updated_at,
      };
    });
    // 分页
    const offset = args.offset ?? 0;
    const limit = args.limit ?? result.length;
    result = result.slice(offset, offset + limit);
    return result;
  });

  // session:updateTitle
  createHandler(IPC_CHANNELS.SESSION_UPDATE_TITLE, (_event, args) => {
    const validation = validatePayload<{ id: string; title: string }>(args, { required: ['id', 'title'], types: { id: 'string', title: 'string' } });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    deps!.sessionService.renameSession(validation.data.id, validation.data.title);
  });

  // session:searchMessages — 跨会话搜索消息（全局搜索面板）
  createHandler(IPC_CHANNELS.SESSION_SEARCH_MESSAGES, (_event, args) => {
    const validation = validatePayload<{ query: string }>(args, { required: ['query'], types: { query: 'string' } });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    return deps!.sessionService.searchMessages(validation.data.query);
  });
}
