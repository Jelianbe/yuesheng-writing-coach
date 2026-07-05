/**
 * 聊天编排服务 — Sprint 32 (移除 serviceBridge/dual-track)
 *
 * @deprecated chat.send 已被 A-4 useOrchestrator.handleTurn 取代,新代码应直接
 *             调用 useOrchestrator().send()。本方法仅保留供 chat.store 内部
 *             重试逻辑(sendMessage → lastFailedMessage)使用。
 *
 * 替代关系:
 *   - 旧:`chatService.send({ message, sessionId, history, ... })`
 *   - 新:`useOrchestrator().send({ userMessage, sessionId, phase, ... })`
 *
 * ─── Sprint 31 (Capacitor 聊天激活) ───
 *
 * Capacitor 端不再 noop — 使用 LlmClient + 内存事件总线模拟流式体验:
 *   - send: 直调 LLM API（流式/非流式回退）
 *   - onStreamData/onStreamEnd: 通过内存事件总线推送
 *   - onToolExecuting: 保持 noop（Android 端无 Tool 调用）
 *
 * ─── Sprint 32 (移除 serviceBridge) ───
 *
 * Electron 端: serviceBridge.invoke → invoke() 包装器
 *
 * 依据: dev-docs/tasks/sprint-32-plan.md
 */

import { typedOn } from './ipc-client';
import { invoke } from './_invoke';
import { isCapacitor } from './_platform';
import {
  capacitorSendMessage,
  capacitorOnStreamData,
  capacitorOnStreamEnd,
} from './capacitor-chat';
import type {
  ChatSendRequest,
  ChatSendResponse,
  ChatStreamDataEvent,
  ChatStreamEndEvent,
  ChatToolExecutingEvent,
} from '../../shared/api-contracts/chat.contract';

export const chatService = {
  /**
   * @deprecated 已被 A-4 useOrchestrator.handleTurn 取代,保留仅为兼容
   *             chat.store.sendMessage 的重试链路。
   *
   * Capacitor 端:直调 LLM API + 内存事件总线推送流式事件。
   */
  async send(params: ChatSendRequest): Promise<ChatSendResponse | null> {
    if (isCapacitor()) {
      return capacitorSendMessage(params);
    }
    console.warn('[chat-service] send() 已废弃,新代码请用 useOrchestrator().send()');
    return invoke<ChatSendResponse>('chat:send', params as unknown as Record<string, unknown>);
  },

  /**
   * 停止流式响应
   * Capacitor 端:降级 noop（流式在 Capacitor 端通过本地 fetch 完成,无需 IPC stop）。
   */
  async stop(sessionId: string): Promise<{ stopped: boolean }> {
    if (isCapacitor()) {
      console.warn('[chat-service] stop: not supported on Capacitor, returning { stopped: false }');
      return { stopped: false };
    }
    const result = await invoke<{ stopped: boolean }>('chat:stop', { sessionId });
    return result ?? { stopped: false };
  },

  /**
   * 监听流数据 — 返回 cleanup 函数
   * Capacitor 端:通过内存事件总线推送（替代 IPC）。
   */
  onStreamData(handler: (data: ChatStreamDataEvent) => void): () => void {
    if (isCapacitor()) {
      return capacitorOnStreamData(handler);
    }
    return typedOn<ChatStreamDataEvent>('chat:stream:data', handler);
  },

  /**
   * 监听流结束 — 返回 cleanup 函数
   * Capacitor 端:通过内存事件总线推送（替代 IPC）。
   */
  onStreamEnd(handler: (data: ChatStreamEndEvent) => void): () => void {
    if (isCapacitor()) {
      return capacitorOnStreamEnd(handler);
    }
    return typedOn<ChatStreamEndEvent>('chat:stream:end', handler);
  },

  /**
   * 监听工具调用状态 — 返回 cleanup 函数
   * Capacitor 端:降级 noop（Android 端无 Tool 调用编排）。
   */
  onToolExecuting(handler: (data: ChatToolExecutingEvent) => void): () => void {
    if (isCapacitor()) {
      console.warn('[chat-service] onToolExecuting: not supported on Capacitor');
      return () => {};
    }
    return typedOn<ChatToolExecutingEvent>('chat:toolExecuting', handler);
  },
};
