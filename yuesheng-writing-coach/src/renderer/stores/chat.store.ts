import { create } from 'zustand';
import type { ChatMessage } from '../shared/types';
import { chatService } from '../services/chat.service';
import { getUserFacingErrorMessage, isRetryable } from '../../shared/error-codes';

export interface SendMessageDeps {
  /** 当前会话 ID（由 appController/ChatView 传入） */
  sessionId: string;
  /** AI 态度档位（由 appController/ChatView 传入） */
  attitudeLevel: string;
  /** 学生上下文 JSON（由 appController/ChatView 传入） */
  studentContext: string;
}

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
  sendMessage: (text: string, deps: SendMessageDeps) => Promise<void>;
  getHistory: () => { role: string; content: string }[];
  clearMessages: () => void;
  setMessages: (messages: ChatMessage[]) => void;

  // P0-1: chat:stop — 中断流式响应
  streamAborted: boolean;
  abortStream: () => void;

  // Q-02: 重试机制
  /** 上次发送失败的消息文本 */
  lastFailedMessage: string | null;
  /** 是否可重试（根据错误类型判断） */
  retryable: boolean;
  /** 重试上次失败的消息 */
  retryLastMessage: (deps: SendMessageDeps) => Promise<void>;

  // P-04: 新用户引导 actions
  /** P-04 新增 actions */
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

/** Q-02: 消息发送超时(毫秒) */
const MESSAGE_TIMEOUT_MS = 120_000;

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
  lastFailedMessage: null,
  retryable: false,

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

  /** Q-02: 重试上次失败的消息 */
  retryLastMessage: async (deps: SendMessageDeps) => {
    const { lastFailedMessage } = get();
    if (!lastFailedMessage) return;
    // 清除错误并重新发送
    set({ error: null, lastFailedMessage: null, retryable: false });
    await get().sendMessage(lastFailedMessage, deps);
  },

  /** 发送消息 */
  sendMessage: async (text: string, deps: SendMessageDeps) => {
    const { isLoading } = get();
    if (isLoading || !text.trim()) return;

    const { sessionId, attitudeLevel, studentContext } = deps;

    // 同步会话 ID（确保后续 refreshFromDiagnosis 能找到对应诊断历史）
    if (sessionId !== get().currentSessionId) {
      set({ currentSessionId: sessionId });
    }

    const allMessages = get().messages.filter((m) => m.role === 'user' || m.role === 'assistant');
    const history = buildSlidingWindow(allMessages.map((m) => ({ role: m.role, content: m.content }))) as Array<{ role: 'user' | 'assistant'; content: string }>;

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
      lastFailedMessage: null,
      retryable: false,
    }));

    try {
      // Q-02: 超时保护 — 120 秒超时自动中断
      const timeoutPromise = new Promise<never>((_, reject) => {
        setTimeout(() => reject(new DOMException('timeout', 'AbortError')), MESSAGE_TIMEOUT_MS);
      });

      const result = await Promise.race([
        chatService.send({
          message: text.trim(),
          sessionId,
          history,
          attitudeLevel,
          studentContext,
        }),
        timeoutPromise,
      ]);

      if (!result) {
        set((state) => {
          const msgs = state.messages.filter((m) => m.id !== assistantMsg.id);
          return { messages: msgs, isLoading: false, error: getUserFacingErrorMessage('ERR_REQUEST_TIMEOUT'), lastFailedMessage: text, retryable: true };
        });
      }
    } catch (error) {
      // Q-02: 使用中文错误消息 + 保存失败消息供重试
      const errorMessage = getUserFacingErrorMessage(error);
      const canRetry = isRetryable(error);
      set((state) => {
        const msgs = state.messages.filter((m) => m.id !== assistantMsg.id);
        return {
          messages: msgs,
          isLoading: false,
          error: errorMessage,
          lastFailedMessage: text,
          retryable: canRetry,
        };
      });
    }
  },
}));
