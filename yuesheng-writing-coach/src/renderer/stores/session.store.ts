/**
 * session.store.ts — 聊天会话管理（主会话，非面板会话）
 *
 * ⚠️ 本文件 catch 块中的 console.error / console.warn 仅用于开发调试，
 *    生产环境应通过构建工具（如 terser drop_console）自动移除。
 *
 * 职责：
 * - 管理聊天会话列表（创建/切换/删除）
 * - 通过 IPC 与主进程 SessionService 交互
 * - 提供 currentSessionId 给 chat.store 使用
 */

import { create } from 'zustand';
import { IPC_CHANNELS } from '../shared/constants';
import { typedInvoke } from '../services/ipc-client';
import type { ChatMessage } from '../shared/types';
import type {
  SessionListWithMetaResponse,
  SessionCreateResponse,
  SessionGetMessagesResponse,
  SessionCreateRequest,
  SessionGetMessagesRequest,
  SessionDeleteRequest,
  SessionRenameRequest,
} from '../../shared/api-contracts/session.contract';

/** 聊天会话 */
export interface ChatSession {
  id: string;
  title: string;
  createdAt: number;
  updatedAt: number;
  messageCount?: number;
  lastMessageAt?: number;
  messages?: unknown[];
}

interface SessionState {
  /** 所有聊天会话 */
  sessions: ChatSession[];
  /** 当前激活的会话 ID */
  currentSessionId: string | null;
}

interface SessionActions {
  /** 从后端加载会话列表(带 messageCount/lastMessageAt) */
  loadSessions: () => Promise<void>;
  /** 创建新会话 */
  createSession: (title?: string) => Promise<ChatSession | null>;
  /** 切换当前会话 */
  switchSession: (id: string) => void;
  /** 加载指定会话的消息列表 */
  loadMessages: (sessionId: string) => Promise<ChatMessage[]>;
  /** 删除会话 */
  deleteSession: (id: string) => Promise<void>;
  /** 重命名会话 */
  renameSession: (id: string, title: string) => Promise<void>;
}

const toChatSession = (s: { id: string; title: string; createdAt: number; updatedAt: number; messageCount?: number; lastMessageAt?: number }): ChatSession => ({
  id: s.id,
  title: s.title,
  createdAt: s.createdAt,
  updatedAt: s.updatedAt,
  messageCount: s.messageCount,
  lastMessageAt: s.lastMessageAt,
});

export const useSessionStore = create<SessionState & SessionActions>((set, get) => ({
  // State
  sessions: [],
  currentSessionId: null,

  // Actions
  loadSessions: async () => {
    try {
      const res = await typedInvoke<Record<string, never>, SessionListWithMetaResponse>(
        IPC_CHANNELS.SESSION_LIST_WITH_META,
        {},
      );
      if (res.success && res.data) {
        const list = res.data.sessions.map(toChatSession);
        set({ sessions: list });
        if (list.length > 0 && !get().currentSessionId) {
          set({ currentSessionId: list[0].id });
        }
      }
    } catch (err) {
      console.error('[session.store] loadSessions failed:', err);
    }
  },

  createSession: async (title?: string) => {
    try {
      const res = await typedInvoke<SessionCreateRequest, SessionCreateResponse>(
        IPC_CHANNELS.SESSION_CREATE,
        title ? { title } : {},
      );
      if (res.success && res.data) {
        const session = toChatSession(res.data.session);
        set((state) => ({
          sessions: [...state.sessions, session],
          currentSessionId: session.id,
        }));
        return session;
      }
      return null;
    } catch (err) {
      console.error('[session.store] createSession failed:', err);
      return null;
    }
  },

  switchSession: (id) => set({ currentSessionId: id }),

  loadMessages: async (sessionId) => {
    try {
      const res = await typedInvoke<SessionGetMessagesRequest, SessionGetMessagesResponse>(
        IPC_CHANNELS.SESSION_GET_MESSAGES,
        { sessionId },
      );
      if (res.success && res.data) {
        return res.data.messages as unknown as ChatMessage[];
      }
      return [];
    } catch (err) {
      console.error('[session.store] loadMessages failed:', err);
      return [];
    }
  },

  deleteSession: async (id) => {
    try {
      const payload: SessionDeleteRequest = { sessionId: id };
      await typedInvoke<SessionDeleteRequest, { success: true }>(
        IPC_CHANNELS.SESSION_DELETE,
        payload,
      );
      set((state) => ({
        sessions: state.sessions.filter(s => s.id !== id),
        currentSessionId: state.currentSessionId === id ? null : state.currentSessionId,
      }));
    } catch (err) {
      console.error('[session.store] deleteSession failed:', err);
    }
  },

  renameSession: async (id, title) => {
    try {
      const payload: SessionRenameRequest = { sessionId: id, title };
      await typedInvoke<SessionRenameRequest, { success: true }>(
        IPC_CHANNELS.SESSION_RENAME,
        payload,
      );
      set((state) => ({
        sessions: state.sessions.map(s => s.id === id ? { ...s, title } : s),
      }));
    } catch (err) {
      console.error('[session.store] renameSession failed:', err);
    }
  },
}));
