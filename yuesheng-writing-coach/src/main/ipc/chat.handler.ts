/**
 * 聊天 — Sprint 26 阶段 3.5 方案 4a bridge 注册
 *
 * 原 IPC handler 已废弃,改为 registerMethod 走单端点 bridge:invoke。
 * 调用方:`serviceBridge.invoke('chat:send' | 'chat:stop' | 'chat:handleTurn' | 'onboarding:analyze', ...)`
 *
 * 依赖: ChatOrchestratorService, ChatHandleTurnBridge
 *
 * 流式推送: handleTurnBridge.startTurnToWindow(mainWindow, input) 替代原
 *          event.sender (ChatHandleTurnBridge 已有 startTurnToWindow 封装)
 *
 * chat:event 事件推送 channel 保持不变(由 ChatHandleTurnBridge 内部用 webContents.send)
 */

import type { AttitudeLevel } from '../../shared/types/index';
import { validatePayload } from './utils/validate-payload';
import { registerMethod } from '../core/service-bridge';
import type { ChatOrchestratorService } from '../domains/03-teaching/chat/chat-orchestrator.service';
import { ChatHandleTurnBridge } from '../domains/03-teaching/conversation/chat-handle-turn.bridge';
import type { HandleTurnInput, ConversationPhase } from '../domains/03-teaching/conversation/orchestrator.types';
import type { BrowserWindow } from 'electron';

let orchestrator: ChatOrchestratorService | null = null;
let handleTurnBridge: ChatHandleTurnBridge | null = null;
let mainWindow: BrowserWindow | null = null;

export function initChatHandlers(
  orchestratorService: ChatOrchestratorService,
  win: BrowserWindow | null = null,
): void {
  orchestrator = orchestratorService;
  handleTurnBridge = new ChatHandleTurnBridge();
  mainWindow = win;
}

export function registerChatHandlers(): void {
  if (!orchestrator) throw new Error('ChatHandler orchestrator not injected');

  registerMethod('chat:send', async (args) => {
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

    const result = await (orchestrator as ChatOrchestratorService).sendMessage(validation.data);
    return { messageId: result.messageId };
  });

  registerMethod('chat:stop', async (_args) => {
    handleTurnBridge?.stopAll();
    return (orchestrator as ChatOrchestratorService).stopGeneration();
  });

  registerMethod('chat:handleTurn', async (args) => {
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

    const { streamId } = await handleTurnBridge.startTurnToWindow(mainWindow, input);
    return { streamId };
  });

  registerMethod('onboarding:analyze', async (args) => {
    const validation = validatePayload<{ text: string }>(args, {
      required: ['text'],
      types: { text: 'string' },
    });
    if (!validation.valid) {
      throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    }
    const text = validation.data.text?.trim() ?? '';
    return (orchestrator as ChatOrchestratorService).handleOnboardingAnalyze(text);
  });
}

export function refreshApiProxy(): void {
  orchestrator?.updateApiProxyConfig();
}

export { markDiagnosisPushed, wasDiagnosisPushed } from './utils/diagnosis-dedup';
