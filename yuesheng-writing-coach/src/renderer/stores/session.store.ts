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
import { getInvoke } from '../utils/ipc';
import type { ChatMessage } from '../shared/types';

/** 聊天会话 */
export interface ChatSession {
  id: string;
  title: string;
  createdAt: number;
  updatedAt: number;
  lastMessage?: string;
  messageCount?: number;
  messages?: unknown[];
}

interface SessionState {
  /** 所有聊天会话 */
  sessions: ChatSession[];
  /** 当前激活的会话 ID */
  currentSessionId: string | null;
}

interface SessionActions {
  /** 从后端加载会话列表 */
  loadSessions: () => Promise<void>;
  /** 创建新会话 */
  createSession: () => Promise<ChatSession | null>;
  /** 切换当前会话 */
  switchSession: (id: string) => void;
  /** 加载指定会话的消息列表 */
  loadMessages: (sessionId: string) => Promise<ChatMessage[]>;
  /** 删除会话 */
  deleteSession: (id: string) => Promise<void>;
  /** 重命名会话 */
  renameSession: (id: string, title: string) => Promise<void>;
}

export const useSessionStore = create<SessionState & SessionActions>((set, get) => ({
  // State
  sessions: [],
  currentSessionId: null,

  // Actions
  loadSessions: async () => {
    try {
      const invoke = getInvoke();
      const res = await invoke(IPC_CHANNELS.SESSION_LIST) as { success: boolean; data?: ChatSession[] };
      if (res.success && res.data) {
        set({ sessions: res.data });
        // 自动激活第一个会话
        if (res.data.length > 0 && !get().currentSessionId) {
          set({ currentSessionId: res.data[0].id });
        }
      }
    } catch (err) {
      console.error('[session.store] loadSessions failed:', err);
    }
  },

  createSession: async () => {
    try {
      const invoke = getInvoke();
      const res = await invoke(IPC_CHANNELS.SESSION_CREATE) as { success: boolean; data?: ChatSession };
      if (res.success && res.data) {
        set((state) => ({
          sessions: [...state.sessions, res.data!],
          currentSessionId: res.data!.id,
        }));
        return res.data;
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
      const invoke = getInvoke();
      const res = await invoke(IPC_CHANNELS.SESSION_GET_MESSAGES, { sessionId }) as { success: boolean; data?: ChatMessage[] };
      if (res.success && res.data) {
        return res.data;
      }
      return [];
    } catch (err) {
      console.error('[session.store] loadMessages failed:', err);
      return [];
    }
  },

  deleteSession: async (id) => {
    try {
      const invoke = getInvoke();
      await invoke(IPC_CHANNELS.SESSION_DELETE, { sessionId: id });
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
      const invoke = getInvoke();
      await invoke(IPC_CHANNELS.SESSION_RENAME, { sessionId: id, title });
      set((state) => ({
        sessions: state.sessions.map(s => s.id === id ? { ...s, title } : s),
      }));
    } catch (err) {
      console.error('[session.store] renameSession failed:', err);
    }
  },
}));
