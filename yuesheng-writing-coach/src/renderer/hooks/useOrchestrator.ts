/**
 * useOrchestrator — Sprint 20 A-4
 *
 * 渲染进程侧编排器订阅 Hook:
 * - send(input): 触发 chat:handleTurn invoke,返回 streamId
 * - subscribe(handler): 订阅 chat:event 事件流(全局唯一订阅,handler 内按 streamId 过滤)
 * - streaming: 是否在流式过程中
 *
 * 与 A-1/A-2/A-3 协作:
 * - 取代 ChatPage 直接调 chat:send
 * - 不再让 renderer 持有 raw stream
 * - 事件分发到 UI(MessageBubble)和外部状态机
 */

import { useCallback, useEffect, useRef, useState } from 'react';
import { typedOn } from '../services/ipc-client';
import { serviceBridge } from '../services/service-bridge';
import { IPC_CHANNELS } from '../../shared/constants';
import type {
  ChatHandleTurnRequest,
} from '../../shared/api-contracts/chat.contract';

// IPC 边界用 unknown(避免 shared 跨域引用 main/domains,符合 R-020)
// 这里仅声明 renderer 关心的 phase 枚举,完整类型定义在 main 域
export type ConversationPhase =
  | 'trust_building'
  | 'requirement'
  | 'diagnosis'
  | 'training'
  | 'reflection';

// OrchestratorEvent 标准化结构(与 main/domains/.../orchestrator.types 保持一致)
// 单一类型来源在 main 域;renderer 端通过 unknown + 守卫函数 narrow
export interface OrchestratorEvent {
  type: 'token' | 'intent' | 'phase_transition' | 'training_triggered' | 'diagnosis_extracted' | 'done' | 'error';
  payload?: unknown;
  content?: string;
}

export interface OrchestratorSendInput {
  userMessage: string;
  sessionId: string;
  phase?: ConversationPhase;
  attitudeLevel?: string;
  history?: Array<{ role: 'user' | 'assistant'; content: string }>;
  studentContext?: string;
  activeProblemId?: string;
  activeTrainingSessionId?: string;
}

export interface OrchestratorEventEnvelope {
  streamId: string;
  sessionId: string;
  event: OrchestratorEvent;
}

export type OrchestratorEventHandler = (envelope: OrchestratorEventEnvelope) => void;

// 轻量类型守卫(避免跨域引用 main/domains)
export const isTokenEvent = (e: OrchestratorEvent): e is OrchestratorEvent & { type: 'token'; content: string } =>
  e.type === 'token' && typeof e.content === 'string';

export const isErrorEvent = (e: OrchestratorEvent): e is OrchestratorEvent & { type: 'error'; payload: { code: string; message: string; retryable: boolean } } =>
  e.type === 'error' && typeof e.payload === 'object' && e.payload !== null;

export const isDoneEvent = (e: OrchestratorEvent): e is OrchestratorEvent & { type: 'done' } =>
  e.type === 'done';

/**
 * 单例订阅:避免每个 ChatPage 实例重复订阅 chat:event
 * (Electron renderer 端 on() 重复订阅会收到多份)
 */
const eventHandlers: Set<OrchestratorEventHandler> = new Set();
let globalUnsub: (() => void) | null = null;

function ensureGlobalSubscription(): () => void {
  if (globalUnsub) return globalUnsub;
  globalUnsub = typedOn<unknown>(IPC_CHANNELS.CHAT_EVENT, (raw) => {
    const envelope = raw as OrchestratorEventEnvelope;
    if (!envelope || typeof envelope !== 'object') return;
    for (const handler of eventHandlers) {
      try {
        handler(envelope);
      } catch (e) {
        console.warn('[useOrchestrator] handler failed:', e);
      }
    }
  });
  return globalUnsub;
}

export function useOrchestrator() {
  const [streaming, setStreaming] = useState(false);
  const streamIdRef = useRef<string | null>(null);
  const localHandlersRef = useRef<Set<OrchestratorEventHandler>>(new Set());

  // 组件卸载时清理本地 handler(全局订阅保留)
  useEffect(() => {
    const localHandlers = localHandlersRef.current;
    for (const h of localHandlers) eventHandlers.add(h);
    ensureGlobalSubscription();
    return () => {
      for (const h of localHandlers) eventHandlers.delete(h);
    };
  }, []);

  const subscribe = useCallback((handler: OrchestratorEventHandler): (() => void) => {
    const localHandlers = localHandlersRef.current;
    localHandlers.add(handler);
    eventHandlers.add(handler);
    ensureGlobalSubscription();
    return () => {
      localHandlers.delete(handler);
      eventHandlers.delete(handler);
    };
  }, []);

  const send = useCallback(async (input: OrchestratorSendInput): Promise<{ streamId: string } | null> => {
    const req: ChatHandleTurnRequest = {
      userMessage: input.userMessage,
      sessionId: input.sessionId,
      phase: input.phase,
      attitudeLevel: input.attitudeLevel,
      history: input.history,
      studentContext: input.studentContext,
      activeProblemId: input.activeProblemId,
      activeTrainingSessionId: input.activeTrainingSessionId,
    };
    // Sprint 26 阶段 3.6: 改走 service-bridge 单端点
    const data = await serviceBridge.invoke<ChatHandleTurnRequest, { streamId: string }>(
      'chat:handleTurn',
      req,
    );
    if (!data) {
      console.warn('[useOrchestrator] handleTurn failed');
      return null;
    }
    streamIdRef.current = data.streamId;
    setStreaming(true);
    return data;
  }, []);

  const finishStream = useCallback(() => {
    streamIdRef.current = null;
    setStreaming(false);
  }, []);

  return { send, subscribe, streaming, streamId: streamIdRef.current, finishStream };
}
