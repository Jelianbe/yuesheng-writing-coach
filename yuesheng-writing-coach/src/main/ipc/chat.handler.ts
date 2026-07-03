/**
 * 聊天 IPC 处理器（薄委托层）
 *
 * 职责：
 *   - 参数校验（validatePayload）
 *   - 委托给 ChatOrchestratorService 执行业务逻辑
 *
 * 所有编排逻辑已迁移至 ChatOrchestratorService。
 */

import type { AttitudeLevel } from '../../shared/types/index';
import { IPC_CHANNELS } from '../../shared/constants';
import { validatePayload } from './utils/validate-payload';
import { createHandler } from './utils/create-handler';
import type { ChatOrchestratorService } from '../domains/03-teaching/chat/chat-orchestrator.service';
// Sprint 20 A-4
import { ChatHandleTurnBridge } from '../domains/03-teaching/conversation/chat-handle-turn.bridge';
import type { HandleTurnInput, ConversationPhase } from '../domains/03-teaching/conversation/orchestrator.types';

let orchestrator: ChatOrchestratorService | null = null;
let handleTurnBridge: ChatHandleTurnBridge | null = null;

export function initChatHandlers(orchestratorService: ChatOrchestratorService): void {
  orchestrator = orchestratorService;
  // A-4: 初始化订阅式入口桥接
  handleTurnBridge = new ChatHandleTurnBridge();
}

// ============ 主 Handler ============

export function registerChatHandlers(): void {
  if (!orchestrator) throw new Error('ChatHandler orchestrator not injected');

  // CHAT_SEND: 发送消息
  createHandler(IPC_CHANNELS.CHAT_SEND, async (_event, args) => {
    const validation = validatePayload<{
      message: string;
      sessionId: string;
      history?: { role: string; content: string }[];
      attitudeLevel?: AttitudeLevel;
      studentContext?: string;
    }>(args, {
      required: ['message'],
      types: { message: 'string', sessionId: 'string' },
    });
    if (!validation.valid) {
      throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    }

    const result = await orchestrator!.sendMessage(validation.data);
    return { messageId: result.messageId };
  });

  // CHAT_STOP: 中断当前流式响应
  createHandler(IPC_CHANNELS.CHAT_STOP, () => {
    // A-4: 同时停止订阅式入口的活跃流
    handleTurnBridge?.stopAll();
    return orchestrator!.stopGeneration();
  });

  // CHAT_HANDLE_TURN: Sprint 20 A-4 — 编排器订阅式入口
  createHandler(IPC_CHANNELS.CHAT_HANDLE_TURN, async (event, args) => {
    if (!handleTurnBridge) throw new Error('ChatHandleTurnBridge not initialized');
    const validation = validatePayload<{
      userMessage: string;
      sessionId: string;
      phase?: ConversationPhase;
      attitudeLevel?: AttitudeLevel;
      history?: Array<{ role: 'user' | 'assistant'; content: string }>;
      studentContext?: string;
      activeProblemId?: string;
      activeTrainingSessionId?: string;
    }>(args, {
      required: ['userMessage', 'sessionId'],
      types: { userMessage: 'string', sessionId: 'string' },
    });
    if (!validation.valid) {
      throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    }

    const data = validation.data;
    const input: HandleTurnInput = {
      userMessage: data.userMessage,
      sessionId: data.sessionId,
      phase: data.phase ?? 'trust_building',
      attitudeLevel: data.attitudeLevel,
      history: data.history,
      studentContext: data.studentContext,
      activeProblemId: data.activeProblemId,
      activeTrainingSessionId: data.activeTrainingSessionId,
    };

    const { streamId } = await handleTurnBridge.startTurn(event.sender, input);
    return { streamId };
  });

  // ONBOARDING_ANALYZE: 引导分析
  createHandler(IPC_CHANNELS.ONBOARDING_ANALYZE, async (_event, args) => {
    const validation = validatePayload<{ text: string }>(args, {
      required: ['text'],
      types: { text: 'string' },
    });
    if (!validation.valid) {
      throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    }
    const text = validation.data.text?.trim() ?? '';
    return orchestrator!.handleOnboardingAnalyze(text);
  });
}

export function refreshApiProxy(): void {
  orchestrator?.updateApiProxyConfig();
}

export { markDiagnosisPushed, wasDiagnosisPushed } from './utils/diagnosis-dedup';
