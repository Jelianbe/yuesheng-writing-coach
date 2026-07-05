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
 *
 * ─── Sprint 26 阶段 3.2 (双轨化决策) ───
 *
 * chat 业务(Orchestrator + AI 调用 + 流式 token)全部在主进程,shared 端无等价
 * 实现。因此本 service **不引入 runDualTrack**,而是:
 *   - 所有 5 个方法保持 IPC-only
 *   - Capacitor 端 isCapacitor() 早返回 noop + warn
 *   - 后续 orchestrator 双轨化时再统一迁移
 *
 * Capacitor 端已知 trade-off:
 *   - send 降级:重试链路不可用
 *   - onStreamData/End/Tool 降级:流式 UI 不更新
 *   - 等待 S27+ orchestrator 双轨化解决
 *
 * 依据: dev-docs/tasks/sprint-26-phase-3-plan.md §3.2 / D-074
 */

import { typedInvoke, typedOn } from './ipc-client';
import { isCapacitor } from './_dual-track';
import { ChatApi } from '../../shared/api-contracts/chat.contract';
import type {
  ChatSendRequest,
  ChatSendResponse,
  ChatStreamDataEvent,
  ChatStreamEndEvent,
  ChatToolExecutingEvent,
} from '../../shared/api-contracts/chat.contract';

/** Capacitor 端无 IPC 通道,统一降级标识 */
function capacitorNoopChat<T>(methodName: string): T | null {
  console.warn(`[chat-service] ${methodName}: not supported on Capacitor (chat 业务全在主进程), returning null`);
  return null;
}

export const chatService = {
  /**
   * @deprecated 已被 A-4 useOrchestrator.handleTurn 取代,保留仅为兼容
   *             chat.store.sendMessage 的重试链路。
   *
   * Capacitor 端:降级 noop(chat 业务全在主进程,shared 端无等价实现)。
   */
  async send(params: ChatSendRequest): Promise<ChatSendResponse | null> {
    if (isCapacitor()) return capacitorNoopChat('send');
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
   *
   * Capacitor 端:降级 noop。
   */
  async stop(sessionId: string): Promise<{ stopped: boolean }> {
    if (isCapacitor()) {
      console.warn('[chat-service] stop: not supported on Capacitor, returning { stopped: false }');
      return { stopped: false };
    }
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

  /**
   * 监听流数据 — 返回 cleanup 函数
   * Capacitor 端:降级 noop(无事件推送通道)。
   */
  onStreamData(handler: (data: ChatStreamDataEvent) => void): () => void {
    if (isCapacitor()) {
      console.warn('[chat-service] onStreamData: not supported on Capacitor');
      return () => {};
    }
    return typedOn<ChatStreamDataEvent>(ChatApi.streamData.channel, handler);
  },

  /**
   * 监听流结束 — 返回 cleanup 函数
   * Capacitor 端:降级 noop(无事件推送通道)。
   */
  onStreamEnd(handler: (data: ChatStreamEndEvent) => void): () => void {
    if (isCapacitor()) {
      console.warn('[chat-service] onStreamEnd: not supported on Capacitor');
      return () => {};
    }
    return typedOn<ChatStreamEndEvent>(ChatApi.streamEnd.channel, handler);
  },

  /**
   * 监听工具调用状态 — 返回 cleanup 函数
   * Capacitor 端:降级 noop(无事件推送通道)。
   */
  onToolExecuting(handler: (data: ChatToolExecutingEvent) => void): () => void {
    if (isCapacitor()) {
      console.warn('[chat-service] onToolExecuting: not supported on Capacitor');
      return () => {};
    }
    return typedOn<ChatToolExecutingEvent>(ChatApi.toolExecuting.channel, handler);
  },
};
