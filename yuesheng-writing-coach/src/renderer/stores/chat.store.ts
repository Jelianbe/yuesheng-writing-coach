import { create } from 'zustand';
import { IPC_CHANNELS } from '../shared/constants';
import type { ChatMessage } from '../shared/types';
import { useConfigStore } from './config.store';
import { useSessionStore } from './session.store';
import { useStudentContextStore } from './student-context.store';
import { getInvoke } from '../utils/ipc';

interface ChatState {
  messages: ChatMessage[];
  currentSessionId: string;
  isLoading: boolean;
  error: string | null;

  // P-04: 新用户引导状态
  onboardingActive: boolean;
  onboardingStep: 0 | 1 | 2 | 3;

  addMessage: (msg: ChatMessage) => void;
  appendToLastAssistant: (chunk: string) => void;
  finalizeLastMessage: () => void;
  setLoading: (loading: boolean) => void;
  setError: (error: string | null) => void;
  sendMessage: (text: string) => Promise<void>;
  getHistory: () => { role: string; content: string }[];
  clearMessages: () => void;
  setMessages: (messages: ChatMessage[]) => void;

  // P0-1: chat:stop — 中断流式响应
  streamAborted: boolean;
  abortStream: () => void;

  // P-04: 新用户引导 actions
  /** P-04 新增 actions */
  resumeOnboarding: () => void;
  startOnboarding: () => void;
  completeOnboarding: () => void;
  skipOnboarding: () => void;
  setOnboardingStep: (step: 0 | 1 | 2 | 3) => void;
}

function generateId(): string {
  return `msg_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
}

/** P-04: localStorage key for onboarding state */
const ONBOARDING_STORAGE_KEY = 'yuesheng_onboarding';

/**
 * P-04: 从 localStorage 恢复引导状态
 * 返回 { step, baseline } 或 null
 */
function loadOnboardingState(): { step: number } | null {
  try {
    const raw = localStorage.getItem(ONBOARDING_STORAGE_KEY);
    if (raw) return JSON.parse(raw);
  } catch { /* ignore */ }
  return null;
}

/**
 * P-04: 保存引导状态到 localStorage
 */
function saveOnboardingState(step: number): void {
  try {
    localStorage.setItem(ONBOARDING_STORAGE_KEY, JSON.stringify({ step }));
  } catch { /* ignore */ }
}

/**
 * P-04: 清除引导状态
 */
function clearOnboardingState(): void {
  try { localStorage.removeItem(ONBOARDING_STORAGE_KEY); } catch { /* ignore */ }
}

// ===== 常量 =====

/** 滑动窗口最大 Token 预算（约 8000 tokens，中文约 4 字符/token）*/
const MAX_HISTORY_TOKENS = 8000;
/** 每条消息的固定开销（角色标签 + 元数据）*/
const MSG_OVERHEAD_TOKENS = 8;

/** 估算字符串的 Token 数（中文约 4 字符/token，英文约 1 字符/token）*/
function estimateTokens(text: string): number {
  let chineseChars = 0;
  let asciiChars = 0;
  for (const ch of text) {
    if (ch >= '\u4e00' && ch <= '\u9fff') chineseChars++;
    else if (ch !== '\n' && ch !== '\r') asciiChars++;
  }
  return Math.ceil(chineseChars / 4) + Math.ceil(asciiChars / 3) + MSG_OVERHEAD_TOKENS;
}

/** 在滑动窗口内保留最近的消息，确保总 Token 不超过预算 */
function buildSlidingWindow(messages: Array<{ role: string; content: string }>): Array<{ role: string; content: string }> {
  let totalTokens = 0;
  const result: Array<{ role: string; content: string }> = [];
  // 从最新消息开始遍历，向旧消息方向累积
  for (let i = messages.length - 1; i >= 0; i--) {
    const tokens = estimateTokens(messages[i].content);
    if (totalTokens + tokens > MAX_HISTORY_TOKENS) break;
    totalTokens += tokens;
    result.unshift(messages[i]);
  }
  return result;
}

export const useChatStore = create<ChatState>((set, get) => ({
  messages: [],
  currentSessionId: `session_${Date.now()}`,
  isLoading: false,
  error: null,
  onboardingActive: false,
  onboardingStep: 0,
  streamAborted: false,

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
  abortStream: () => set({ streamAborted: true, isLoading: false }),

  getHistory: () => {
    const msgs = get().messages.filter((m) => m.role === 'user' || m.role === 'assistant');
    return buildSlidingWindow(msgs.map((m) => ({ role: m.role, content: m.content })));
  },

  clearMessages: () => set({ messages: [], error: null }),

  setMessages: (messages: ChatMessage[]) => set({ messages }),

  // P-04: 新用户引导
  resumeOnboarding: () => {
    const saved = loadOnboardingState();
    if (saved && saved.step >= 1 && saved.step <= 3) {
      set({ onboardingActive: true, onboardingStep: saved.step as 0 | 1 | 2 | 3 });
    }
  },
  startOnboarding: () => {
    // 先尝试恢复已保存的引导状态
    const saved = loadOnboardingState();
    if (saved && saved.step >= 1 && saved.step <= 3) {
      set({ onboardingActive: true, onboardingStep: saved.step as 0 | 1 | 2 | 3 });
    } else {
      set({ onboardingActive: true, onboardingStep: 1 });
      saveOnboardingState(1);
    }
  },
  completeOnboarding: () => {
    set({ onboardingActive: false, onboardingStep: 0 });
    clearOnboardingState();
  },
  skipOnboarding: () => {
    set({ onboardingActive: false, onboardingStep: 0 });
    clearOnboardingState();
  },
  setOnboardingStep: (step) => {
    set({ onboardingStep: step });
    saveOnboardingState(step);
  },

  /** 发送消息 */
  sendMessage: async (text: string) => {
    const { isLoading } = get();
    const currentSessionId = useSessionStore.getState().currentSessionId || '';
    if (isLoading || !text.trim()) return;

    const allMessages = get().messages.filter((m) => m.role === 'user' || m.role === 'assistant');
    const history = buildSlidingWindow(allMessages.map((m) => ({ role: m.role, content: m.content })));

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
