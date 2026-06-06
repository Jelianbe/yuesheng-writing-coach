import { ipcMain } from 'electron';
import { IPC_CHANNELS } from '../../shared/constants';
import { SessionService } from '../services/session.service';
import { apiSuccess, apiError } from '../../renderer/shared/types';

let sessionService: SessionService;

export function setSessionService(svc: SessionService): void {
  sessionService = svc;
}

export function registerSessionHandlers(): void {
  ipcMain.handle(IPC_CHANNELS.SESSION_LIST, () => {
    try {
      const sessions = sessionService.listSessions();
      return apiSuccess(sessions.map(s => ({
        id: s.id,
        title: s.title,
        createdAt: s.created_at,
        updatedAt: s.updated_at,
        lastMessage: sessionService.getLastMessage(s.id)?.content.slice(0, 50) || undefined,
        messages: [],
      })));
    } catch (error) {
      console.error('[SessionHandler] SESSION_LIST Error:', error);
      return apiError(String(error));
    }
  });

  ipcMain.handle(IPC_CHANNELS.SESSION_CREATE, () => {
    try {
      const s = sessionService.createSession();
      return apiSuccess({ id: s.id, title: s.title, createdAt: s.created_at, updatedAt: s.updated_at, messages: [] });
    } catch (error) {
      console.error('[SessionHandler] SESSION_CREATE Error:', error);
      return apiError(String(error));
    }
  });

  ipcMain.handle(IPC_CHANNELS.SESSION_DELETE, (_event, args: { sessionId: string }) => {
    try {
      sessionService.deleteSession(args.sessionId);
      return apiSuccess(void 0);
    } catch (error) {
      console.error('[SessionHandler] SESSION_DELETE Error:', error);
      return apiError(String(error));
    }
  });

  ipcMain.handle(IPC_CHANNELS.SESSION_RENAME, (_event, args: { sessionId: string; title: string }) => {
    try {
      sessionService.renameSession(args.sessionId, args.title);
      return apiSuccess(void 0);
    } catch (error) {
      console.error('[SessionHandler] SESSION_RENAME Error:', error);
      return apiError(String(error));
    }
  });

  ipcMain.handle(IPC_CHANNELS.SESSION_GET_MESSAGES, (_event, args: { sessionId: string }) => {
    try {
      return apiSuccess(sessionService.getMessages(args.sessionId));
    } catch (error) {
      console.error('[SessionHandler] SESSION_GET_MESSAGES Error:', error);
      return apiError(String(error));
    }
  });
}
