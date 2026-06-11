import { ipcMain } from 'electron';
import { IPC_CHANNELS } from '../../shared/constants';
import { SessionService } from '../services/session.service';
import { apiSuccess, apiError } from '../../renderer/shared/types';
import { validatePayload } from './utils/validate-payload';

export interface SessionHandlerDeps {
  sessionService: SessionService;
}

let deps: SessionHandlerDeps | null = null;

export function initSessionHandlers(d: SessionHandlerDeps): void {
  deps = d;
}

export function registerSessionHandlers(): void {
  if (!deps) throw new Error('SessionHandler deps not injected');

  ipcMain.handle(IPC_CHANNELS.SESSION_LIST, () => {
    try {
      const sessions = deps!.sessionService.listSessions();
      return apiSuccess(sessions.map(s => ({
        id: s.id,
        title: s.title,
        createdAt: s.created_at,
        updatedAt: s.updated_at,
        lastMessage: deps!.sessionService.getLastMessage(s.id)?.content.slice(0, 50) || undefined,
        messages: [],
      })));
    } catch (error) {
      console.error('[SessionHandler] SESSION_LIST Error:', error);
      return apiError(String(error));
    }
  });

  // session:isNewUser — 判断是否为新用户（无任何会话）
  ipcMain.handle(IPC_CHANNELS.SESSION_IS_NEW_USER, () => {
    try {
      const sessions = deps!.sessionService.listSessions();
      return apiSuccess(sessions.length === 0);
    } catch (error) {
      console.error('[SessionHandler] SESSION_IS_NEW_USER Error:', error);
      return apiError(String(error));
    }
  });

  ipcMain.handle(IPC_CHANNELS.SESSION_CREATE, () => {
    try {
      const s = deps!.sessionService.createSession();
      return apiSuccess({ id: s.id, title: s.title, createdAt: s.created_at, updatedAt: s.updated_at, messages: [] });
    } catch (error) {
      console.error('[SessionHandler] SESSION_CREATE Error:', error);
      return apiError(String(error));
    }
  });

  ipcMain.handle(IPC_CHANNELS.SESSION_DELETE, (_event, args) => {
    const validation = validatePayload<{ sessionId: string }>(args, { required: ['sessionId'], types: { sessionId: 'string' } });
    if (!validation.valid) return apiError(`INVALID_PAYLOAD: ${validation.error.message}`);
    try {
      deps!.sessionService.deleteSession(validation.data.sessionId);
      return apiSuccess(void 0);
    } catch (error) {
      console.error('[SessionHandler] SESSION_DELETE Error:', error);
      return apiError(String(error));
    }
  });

  ipcMain.handle(IPC_CHANNELS.SESSION_RENAME, (_event, args) => {
    const validation = validatePayload<{ sessionId: string; title: string }>(args, { required: ['sessionId', 'title'], types: { sessionId: 'string', title: 'string' } });
    if (!validation.valid) return apiError(`INVALID_PAYLOAD: ${validation.error.message}`);
    try {
      deps!.sessionService.renameSession(validation.data.sessionId, validation.data.title);
      return apiSuccess(void 0);
    } catch (error) {
      console.error('[SessionHandler] SESSION_RENAME Error:', error);
      return apiError(String(error));
    }
  });

  ipcMain.handle(IPC_CHANNELS.SESSION_GET_MESSAGES, (_event, args) => {
    const validation = validatePayload<{ sessionId: string }>(args, { required: ['sessionId'], types: { sessionId: 'string' } });
    if (!validation.valid) return apiError(`INVALID_PAYLOAD: ${validation.error.message}`);
    try {
      return apiSuccess(deps!.sessionService.getMessages(validation.data.sessionId));
    } catch (error) {
      console.error('[SessionHandler] SESSION_GET_MESSAGES Error:', error);
      return apiError(String(error));
    }
  });

  // session:getMessagesPaged — 分页加载消息（V2-019）
  ipcMain.handle(IPC_CHANNELS.SESSION_GET_MESSAGES_PAGED, (_event, args) => {
    const validation = validatePayload<{ sessionId: string; offset: number; limit: number }>(args, {
      required: ['sessionId'],
      types: { sessionId: 'string', offset: 'number', limit: 'number' },
      ranges: { offset: { min: 0 }, limit: { min: 1, max: 200 } },
    });
    if (!validation.valid) return apiError(`INVALID_PAYLOAD: ${validation.error.message}`);
    try {
      return apiSuccess(deps!.sessionService.getMessagesPaged(validation.data.sessionId, validation.data.offset, validation.data.limit));
    } catch (error) {
      console.error('[SessionHandler] SESSION_GET_MESSAGES_PAGED Error:', error);
      return apiError(String(error));
    }
  });

  // session:listWithMeta — 含 title/preview 的会话列表（V2 SOLO）
  ipcMain.handle(IPC_CHANNELS.SESSION_LIST_WITH_META, (_event, args: { limit?: number; offset?: number }) => {
    try {
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
      return apiSuccess(result);
    } catch (error) {
      console.error('[SessionHandler] SESSION_LIST_WITH_META Error:', error);
      return apiError(String(error));
    }
  });

  // session:updateTitle
  ipcMain.handle(IPC_CHANNELS.SESSION_UPDATE_TITLE, (_event, args) => {
    const validation = validatePayload<{ id: string; title: string }>(args, { required: ['id', 'title'], types: { id: 'string', title: 'string' } });
    if (!validation.valid) return apiError(`INVALID_PAYLOAD: ${validation.error.message}`);
    try {
      deps!.sessionService.renameSession(validation.data.id, validation.data.title);
      return apiSuccess(void 0);
    } catch (error) {
      console.error('[SessionHandler] SESSION_UPDATE_TITLE Error:', error);
      return apiError(String(error));
    }
  });

  // session:searchMessages — 跨会话搜索消息（全局搜索面板）
  ipcMain.handle(IPC_CHANNELS.SESSION_SEARCH_MESSAGES, (_event, args) => {
    const validation = validatePayload<{ query: string }>(args, { required: ['query'], types: { query: 'string' } });
    if (!validation.valid) return apiError(`INVALID_PAYLOAD: ${validation.error.message}`);
    try {
      const groups = deps!.sessionService.searchMessages(validation.data.query);
      return apiSuccess(groups);
    } catch (error) {
      console.error('[SessionHandler] SESSION_SEARCH_MESSAGES Error:', error);
      return apiError(String(error));
    }
  });
}
