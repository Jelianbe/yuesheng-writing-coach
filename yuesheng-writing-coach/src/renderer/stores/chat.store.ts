import { create } from 'zustand';
import { IPC_CHANNELS } from '../shared/constants';
import type { ChatMessage, AttitudeLevel } from '../shared/types';
import { useConfigStore } from './config.store';
import { useSessionStore } from './session.store';
import { useStudentContextStore } from './student-context.store';
import { getInvoke } from '../utils/ipc';

interface ChatState {
  messages: ChatMessage[];
  currentSessionId: string;
  isLoading: boolean;
  error: string | null;

  addMessage: (msg: ChatMessage) => void;
  appendToLastAssistant: (chunk: string) => void;
  finalizeLastMessage: () => void;
  setLoading: (loading: boolean) => void;
  setError: (error: string | null) => void;
  sendMessage: (text: string) => Promise<void>;
  getHistory: () => { role: string; content: string }[];
  clearMessages: () => void;
  setMessages: (messages: ChatMessage[]) => void;
}

function generateId(): string {
  return `msg_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
}

export const useChatStore = create<ChatState>((set, get) => ({
  messages: [],
  currentSessionId: `session_${Date.now()}`,
  isLoading: false,
  error: null,

  addMessage: (msg: ChatMessage) => {
    set((state) => ({ messages: [...state.messages, msg] }));
  },

  appendToLastAssistant: (chunk: string) => {
    set((state) => {
      const msgs = [...state.messages];
      for (let i = msgs.length - 1; i >= 0; i--) {
        if (msgs[i].role === 'assistant') {
          msgs[i] = { ...msgs[i], content: msgs[i].content + chunk };
          break;
        }
      }
      return { messages: msgs };
    });
  },

  finalizeLastMessage: () => {
    // placeholder for future post-processing
  },

  setLoading: (loading: boolean) => set({ isLoading: loading }),
  setError: (error: string | null) => set({ error }),

  getHistory: () => {
    return get().messages
      .filter((m) => m.role === 'user' || m.role === 'assistant')
      .slice(-20)
      .map((m) => ({ role: m.role, content: m.content }));
  },

  clearMessages: () => set({ messages: [], error: null }),

  setMessages: (messages: ChatMessage[]) => set({ messages }),

  /** 发送消息 */
  sendMessage: async (text: string) => {
    const { isLoading } = get();
    const currentSessionId = useSessionStore.getState().currentSessionId || '';
    if (isLoading || !text.trim()) return;

    const history = get().messages
      .filter((m) => m.role === 'user' || m.role === 'assistant')
      .slice(-20)
      .map((m) => ({ role: m.role, content: m.content }));

    const userMsg: ChatMessage = {
      id: generateId(),
      role: 'user',
      content: text.trim(),
      timestamp: Date.now(),
    };

    const assistantMsg: ChatMessage = {
      id: generateId(),
      role: 'assistant',
      content: '',
      timestamp: Date.now(),
    };

    set((state) => ({
      messages: [...state.messages, userMsg, assistantMsg],
      isLoading: true,
      error: null,
    }));

    try {
      const invoke = getInvoke();
      const attitudeLevel = useConfigStore.getState().attitudeLevel;
      const studentContext = useStudentContextStore.getState().toJSON();

      const result = await invoke(IPC_CHANNELS.CHAT_SEND, {
        message: text.trim(),
        sessionId: currentSessionId,
        history,
        attitudeLevel,
        studentContext,
      }) as { success: boolean; error?: string };

      if (!result.success) {
        set((state) => {
          const msgs = state.messages.filter((m) => m.id !== assistantMsg.id);
          return { messages: msgs, isLoading: false, error: result.error || '发送失败' };
        });
      }
    } catch (error) {
      set((state) => {
        const msgs = state.messages.filter((m) => m.id !== assistantMsg.id);
        return {
          messages: msgs,
          isLoading: false,
          error: error instanceof Error ? error.message : '发送失败',
        };
      });
    }
  },
}));
