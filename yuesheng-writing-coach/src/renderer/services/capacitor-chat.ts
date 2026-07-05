/**
 * Capacitor 聊天模块 — Sprint 31
 *
 * 在 Android/Capacitor 端使用 LlmClient 直接调用 LLM API，
 * 通过内存事件总线模拟 Electron IPC 的事件推送（onStreamData/onStreamEnd）。
 *
 * 外部不直接使用本模块 — chat.service.ts 在 Capacitor 端自动路由到此处。
 *
 * 依据: dev-docs/tasks/sprint-31-plan.md §阶段 2
 */

import { LlmClient } from '../../shared/llm/llm-client';
import type { ChatSendRequest, ChatSendResponse } from '../../shared/api-contracts/chat.contract';
import type { ApiConfig } from '../../shared/types/types-config';
import { loadConfig } from './capacitor-config';

// ============================================================
// 内存事件总线 — 替代 Capacitor 端的 IPC 事件推送
// ============================================================

type EventHandler = (data: unknown) => void;
const eventListeners = new Map<string, Set<EventHandler>>();

function on(event: string, handler: EventHandler): () => void {
  if (!eventListeners.has(event)) eventListeners.set(event, new Set());
  const handlers = eventListeners.get(event);
  if (handlers) handlers.add(handler);
  return () => {
    const current = eventListeners.get(event);
    current?.delete(handler);
  };
}

function emit(event: string, data: unknown): void {
  const handlers = eventListeners.get(event);
  if (handlers) handlers.forEach((h) => h(data));
}

const EVENTS = {
  STREAM_DATA: 'capacitor:chat:stream:data',
  STREAM_END: 'capacitor:chat:stream:end',
} as const;

// ============================================================
// 会话级缓存 — 避免每次请求都重读 localStorage
// ============================================================

let _config: ApiConfig | null = null;

async function getConfig(): Promise<ApiConfig> {
  if (!_config) _config = await loadConfig();
  return _config;
}

// ============================================================
// 公开 API
// ============================================================

/**
 * Capacitor 端发送消息 — 直调 LLM API
 * - 流式响应通过事件总线推送
 * - sendStreamData 用于外部（chat.service.ts）注册
 */
export async function capacitorSendMessage(
  params: ChatSendRequest,
): Promise<ChatSendResponse | null> {
  try {
    const config = await getConfig();
    if (!config.apiKey) {
      console.error('[capacitor-chat] API Key 未配置');
      return null;
    }

    const client = new LlmClient({
      apiKey: config.apiKey,
      baseUrl: config.baseUrl,
      modelName: config.modelName,
      temperature: config.temperature,
      maxTokens: config.maxTokens,
    });

    const messages: Array<{ role: 'user' | 'assistant' | 'system'; content: string }> = [];

    // 如果有历史，加入历史消息
    if (params.history && params.history.length > 0) {
      messages.push(...params.history);
    }

    // 加入当前消息
    messages.push({ role: 'user', content: params.message });

    // 流式调用
    const sessionId = params.sessionId;
    let fullContent = '';

    try {
      const streamIterator = client.chatStream(messages);

      for await (const chunk of streamIterator) {
        fullContent += chunk.content;
        emit(EVENTS.STREAM_DATA, { sessionId, chunk: chunk.content });
      }

      emit(EVENTS.STREAM_END, {
        sessionId,
        fullResponse: fullContent,
        messageId: `android-${Date.now()}`,
      });
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : String(err);
      console.error('[capacitor-chat] 流式调用失败:', errorMsg);

      // 回退到非流式
      try {
        const result = await client.chat(messages);
        fullContent = result.content;

        // 以块的形式模拟流
        const chunkSize = 20;
        for (let i = 0; i < fullContent.length; i += chunkSize) {
          const chunk = fullContent.slice(i, i + chunkSize);
          emit(EVENTS.STREAM_DATA, { sessionId, chunk });
        }

        emit(EVENTS.STREAM_END, {
          sessionId,
          fullResponse: fullContent,
          messageId: `android-${Date.now()}`,
        });
      } catch (fallbackErr) {
        const fbMsg = fallbackErr instanceof Error ? fallbackErr.message : String(fallbackErr);
        console.error('[capacitor-chat] 非流式回退也失败:', fbMsg);
        emit(EVENTS.STREAM_END, {
          sessionId,
          fullResponse: '',
          messageId: `android-${Date.now()}-error`,
          error: fbMsg,
          aborted: false,
        });
        return null;
      }
    }

    return { acknowledged: true, messageId: `android-${Date.now()}` };
  } catch (err) {
    console.error('[capacitor-chat] send 失败:', err);
    return null;
  }
}

/**
 * 注册流数据监听 — 替代 IPC typedOn
 */
export function capacitorOnStreamData(
  handler: (data: { sessionId: string; chunk: string }) => void,
): () => void {
  return on(EVENTS.STREAM_DATA, handler as EventHandler);
}

/**
 * 注册流结束监听 — 替代 IPC typedOn
 */
export function capacitorOnStreamEnd(
  handler: (data: {
    sessionId: string;
    fullResponse: string;
    messageId: string;
    error?: string;
    aborted?: boolean;
  }) => void,
): () => void {
  return on(EVENTS.STREAM_END, handler as EventHandler);
}

/**
 * 清除配置缓存（测试用）
 */
export function resetConfigCache(): void {
  _config = null;
}
