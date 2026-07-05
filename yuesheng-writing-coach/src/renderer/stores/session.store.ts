/**
 * session.store.ts — 聊天会话管理（主会话，非面板会话）
 *
 * 职责：
 * - 管理聊天会话列表（创建/切换/删除）
 * - 通过双轨 service 与主进程/SessionService 交互 (Sprint 26 阶段 3.4 Z-1)
 * - 提供 currentSessionId 给 chat.store 使用
 *
 * 双轨说明: 全部调用走 renderer/services/session.service.ts,
 * 平台检测在 service 内部,store 无需关心。
 */

import { create } from 'zustand';
import { sessionService } from '../services/session.service';
import type { ChatMessage } from '../shared/types';
import type {
  SessionCreateRequest,
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
  /** 是否正在加载会话列表 */
  loading: boolean;
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
  /** 分页加载消息（Sprint 34） */
  loadMessagesPaged: (sessionId: string, offset: number, limit: number) => Promise<{ messages: ChatMessage[]; hasMore: boolean }>;
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
  loading: false,

  // Actions — 全部走 sessionService (双轨)
  loadSessions: async () => {
    set({ loading: true });
    const sessions = await sessionService.listWithMeta();
    if (sessions.length > 0) {
      const list = sessions.map(toChatSession);
      set({ sessions: list, loading: false });
      if (!get().currentSessionId) {
        set({ currentSessionId: list[0].id });
      }
    } else {
      set({ loading: false });
    }
  },

  createSession: async (title?: string) => {
    const session = await sessionService.create(title);
    if (session) {
      const chatSession = toChatSession(session);
      set((state) => ({
        sessions: [...state.sessions, chatSession],
        currentSessionId: chatSession.id,
      }));
      return chatSession;
    }
    return null;
  },

  switchSession: (id) => set({ currentSessionId: id }),

  loadMessages: async (sessionId) => {
    return sessionService.getMessages(sessionId) as unknown as Promise<ChatMessage[]>;
  },

  loadMessagesPaged: async (sessionId, offset, limit) => {
    const result = await sessionService.getMessagesPaged(sessionId, offset, limit);
    return {
      messages: result.messages as unknown as ChatMessage[],
      hasMore: result.hasMore,
    };
  },

  deleteSession: async (id) => {
    const success = await sessionService.delete(id);
    if (success) {
      set((state) => ({
        sessions: state.sessions.filter(s => s.id !== id),
        currentSessionId: state.currentSessionId === id ? null : state.currentSessionId,
      }));
    }
  },

  renameSession: async (id, title) => {
    const success = await sessionService.rename(id, title);
    if (success) {
      set((state) => ({
        sessions: state.sessions.map(s => s.id === id ? { ...s, title } : s),
      }));
    }
  },
}));

// 保留 unused warning 抑制(Sprint 26 阶段 3.4 Z-1 改造后)
void ({} as SessionCreateRequest);
