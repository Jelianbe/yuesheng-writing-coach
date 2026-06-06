import { create } from 'zustand';
import { IPC_CHANNELS } from '../shared/constants';
import type { Session, MessageRow, ApiResponse } from '../shared/types';
import { getInvoke } from '../utils/ipc';

interface SessionState {
  sessions: Session[];
  currentSessionId: string | null;
  currentMessages: MessageRow[];
  isLoading: boolean;
  loadSessions: () => Promise<void>;
  createSession: () => Promise<Session | null>;
  deleteSession: (sessionId: string) => Promise<void>;
  renameSession: (sessionId: string, title: string) => Promise<void>;
  switchSession: (sessionId: string) => Promise<void>;
  setCurrentSessionId: (id: string | null) => void;
}

export const useSessionStore = create<SessionState>((set, get) => ({
  sessions: [],
  currentSessionId: null,
  currentMessages: [],
  isLoading: false,

  loadSessions: async () => {
    const invoke = getInvoke();
    const result = await invoke(IPC_CHANNELS.SESSION_LIST) as ApiResponse<Session[]>;
    if (result.success) set({ sessions: result.data ?? [] });
  },

  createSession: async () => {
    const invoke = getInvoke();
    const result = await invoke(IPC_CHANNELS.SESSION_CREATE) as ApiResponse<Session>;
    if (!result.success || !result.data) return null;
    const session = result.data;
    const { sessions } = get();
    set({ sessions: [session, ...sessions], currentSessionId: session.id, currentMessages: [] });
    return session;
  },

  deleteSession: async (sessionId: string) => {
    const invoke = getInvoke();
    await invoke(IPC_CHANNELS.SESSION_DELETE, { sessionId });
    const { sessions, currentSessionId } = get();
    const filtered = sessions.filter(s => s.id !== sessionId);
    if (currentSessionId === sessionId) {
      const next = filtered[0] || null;
      set({ sessions: filtered, currentSessionId: next ? next.id : null, currentMessages: [] });
      if (next) get().switchSession(next.id);
    } else {
      set({ sessions: filtered });
    }
  },

  renameSession: async (sessionId: string, title: string) => {
    const invoke = getInvoke();
    await invoke(IPC_CHANNELS.SESSION_RENAME, { sessionId, title });
    const { sessions } = get();
    set({
      sessions: sessions.map(s => s.id === sessionId ? { ...s, title } : s),
    });
  },

  switchSession: async (sessionId: string) => {
    const invoke = getInvoke();
    set({ isLoading: true });
    const result = await invoke(IPC_CHANNELS.SESSION_GET_MESSAGES, { sessionId }) as ApiResponse<MessageRow[]>;
    set({ currentSessionId: sessionId, currentMessages: result.data ?? [], isLoading: false });
  },

  setCurrentSessionId: (id: string | null) => set({ currentSessionId: id }),
}));
