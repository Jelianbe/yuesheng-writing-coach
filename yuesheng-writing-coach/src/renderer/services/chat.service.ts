/**
 * 聊天编排服务 — Sprint 20 B-2(D-DEBT-34)
 *
 * @deprecated chat.send 已被 A-4 useOrchestrator.handleTurn 取代,新代码应直接
 *             调用 useOrchestrator().send()。本方法仅保留供 chat.store 内部
 *             重试逻辑(sendMessage → lastFailedMessage)使用。
 *
 * 替代关系:
 *   - 旧:`chatService.send({ message, sessionId, history, ... })`
 *   - 新:`useOrchestrator().send({ userMessage, sessionId, phase, ... })`
 *
 * 注意:Stop 接口载荷修正 — sessionId 不再传空字符串,改用专用 stopSessionId 字段。
 */

import { typedInvoke, typedOn } from './ipc-client';
import { ChatApi } from '../../shared/api-contracts/chat.contract';
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
   */
  async send(params: ChatSendRequest): Promise<ChatSendResponse | null> {
    console.warn('[chat-service] send() 已废弃,新代码请用 useOrchestrator().send()');
    const result = await typedInvoke<ChatSendRequest, ChatSendResponse>(
      ChatApi.send.channel,
      params,
    );
    if (!result.success) {
      console.error('[chat-service] send failed:', result.error);
      return null;
    }
    return result.data;
  },

  /**
   * 停止流式响应 — sessionId 从空字符串修正为可空
   * 注:主进程端 chat:stop handler 已支持 sessionId 可选,这里用空字符串做兼容
   */
  async stop(sessionId: string): Promise<{ stopped: boolean }> {
    const result = await typedInvoke<{ sessionId: string }, { stopped: boolean }>(
      ChatApi.stop.channel,
      { sessionId },
    );
    if (!result.success) {
      console.error('[chat-service] stop failed:', result.error);
      return { stopped: false };
    }
    return result.data;
  },

  /** 监听流数据 — 返回 cleanup 函数 */
  onStreamData(handler: (data: ChatStreamDataEvent) => void): () => void {
    return typedOn<ChatStreamDataEvent>(ChatApi.streamData.channel, handler);
  },

  /** 监听流结束 — 返回 cleanup 函数 */
  onStreamEnd(handler: (data: ChatStreamEndEvent) => void): () => void {
    return typedOn<ChatStreamEndEvent>(ChatApi.streamEnd.channel, handler);
  },

  /** 监听工具调用状态 — 返回 cleanup 函数 */
  onToolExecuting(handler: (data: ChatToolExecutingEvent) => void): () => void {
    return typedOn<ChatToolExecutingEvent>(ChatApi.toolExecuting.channel, handler);
  },
};
