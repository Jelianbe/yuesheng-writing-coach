/**
 * 聊天编排服务
 *
 * 封装所有 chat 域 IPC 通信。
 * 替代 chat.store.ts sendMessage 中的 5 处跨 store getState()。
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
  /** 发送消息 */
  async send(params: ChatSendRequest): Promise<ChatSendResponse | null> {
    const result = await typedInvoke<ChatSendRequest, ChatSendResponse>(
      ChatApi.send.channel,
      params,
    );
    if (!result.success) {
      throw new Error(result.error);
    }
    return result.data;
  },

  /** 停止流式响应 */
  async stop(): Promise<{ stopped: boolean }> {
    const result = await typedInvoke<{ sessionId: string }, { stopped: boolean }>(
      ChatApi.stop.channel,
      { sessionId: '' },
    );
    if (!result.success) {
      throw new Error(result.error);
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
