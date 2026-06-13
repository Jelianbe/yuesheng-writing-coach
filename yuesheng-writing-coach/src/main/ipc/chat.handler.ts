/**
 * 聊天 IPC 处理器（薄委托层）
 *
 * 职责：
 *   - 参数校验（validatePayload）
 *   - 委托给 ChatOrchestratorService 执行业务逻辑
 *
 * 所有编排逻辑已迁移至 ChatOrchestratorService。
 */

import type { AttitudeLevel } from '../../renderer/shared/types';
import { IPC_CHANNELS } from '../../shared/constants';
import { validatePayload } from './utils/validate-payload';
import { createHandler } from './utils/create-handler';
import { ChatOrchestratorService } from '../services/chat-orchestrator.service';

let orchestrator: ChatOrchestratorService | null = null;

export function initChatHandlers(orchestratorService: ChatOrchestratorService): void {
  orchestrator = orchestratorService;
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
    return orchestrator!.stopGeneration();
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
