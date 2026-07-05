/**
 * 会话管理 — Sprint 26 阶段 3.5 方案 4a bridge 注册
 *
 * 原 IPC handler 已废弃,改为 registerMethod 走单端点 bridge:invoke。
 * 调用方:`serviceBridge.invoke('session:list' | 'session:isNewUser' | 'session:create' | ...)`
 *
 * 注: 3.4 评估标记 session 8 个直调为删除候选(纯直调),先迁 bridge 作为过渡收口,
 *     后续批次 4 统一删除。SESSION_LIST_WITH_META 因有列表+消息组装,短期保留。
 */

import type { SessionService } from '../../shared/services/session.service';
import { validatePayload } from './utils/validate-payload';
import { registerMethod } from '../core/service-bridge';

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

  registerMethod('session:list', async (_args) => {
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

  registerMethod('session:isNewUser', async (_args) => {
    const sessions = await d.sessionService.listSessions();
    return sessions.length === 0;
  });

  registerMethod('session:create', async (_args) => {
    const s = await d.sessionService.createSession();
    return { id: s.id, title: s.title, createdAt: s.created_at, updatedAt: s.updated_at, messages: [] };
  });

  registerMethod('session:delete', async (args) => {
    const validation = validatePayload<{ sessionId: string }>(args, { required: ['sessionId'], types: { sessionId: 'string' } });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    await d.sessionService.deleteSession(validation.data.sessionId);
  });

  registerMethod('session:rename', async (args) => {
    const validation = validatePayload<{ sessionId: string; title: string }>(args, { required: ['sessionId', 'title'], types: { sessionId: 'string', title: 'string' } });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    await d.sessionService.renameSession(validation.data.sessionId, validation.data.title);
  });

  registerMethod('session:getMessages', async (args) => {
    const validation = validatePayload<{ sessionId: string }>(args, { required: ['sessionId'], types: { sessionId: 'string' } });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    return d.sessionService.getMessages(validation.data.sessionId);
  });

  registerMethod('session:getMessagesPaged', async (args) => {
    const validation = validatePayload<{ sessionId: string; offset: number; limit: number }>(args, {
      required: ['sessionId'],
      types: { sessionId: 'string', offset: 'number', limit: 'number' },
      ranges: { offset: { min: 0 }, limit: { min: 1, max: 200 } },
    });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    return d.sessionService.getMessagesPaged(validation.data.sessionId, validation.data.offset, validation.data.limit);
  });

  registerMethod('session:listWithMeta', async (args) => {
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
    const { limit, offset } = (args ?? {}) as { limit?: number; offset?: number };
    const o = offset ?? 0;
    const l = limit ?? result.length;
    result = result.slice(o, o + l);
    return result;
  });

  registerMethod('session:updateTitle', async (args) => {
    const validation = validatePayload<{ id: string; title: string }>(args, { required: ['id', 'title'], types: { id: 'string', title: 'string' } });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    await d.sessionService.renameSession(validation.data.id, validation.data.title);
  });

  registerMethod('session:searchMessages', async (args) => {
    const validation = validatePayload<{ query: string }>(args, { required: ['query'], types: { query: 'string' } });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    return d.sessionService.searchMessages(validation.data.query);
  });
}
