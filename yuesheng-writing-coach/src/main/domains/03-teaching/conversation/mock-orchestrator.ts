/**
 * MockConversationOrchestrator — A-1 骨架实现
 *
 * 目的:
 * - 提供可测试的事件流基线,不依赖真实 AI
 * - 让 A-2/A-3/A-4 在主进程未完全就绪时可对接
 * - 单测可预测:固定输入 → 固定事件序列
 *
 * 不在范围:不调用 ChatOrchestratorService(留给 A-2 桥接层)
 */

import type {
  ConversationOrchestrator,
  ConversationPhase,
  HandleTurnInput,
  OrchestratorEvent,
  PromptVersion,
  SkillRef,
} from './orchestrator.types';

const MOCK_PROMPT: PromptVersion = {
  version: 'v5.0.0-mock',
  changelog: 'A-1 骨架,固定响应,无 AI 调用',
};

const SKILL_MANIFEST: Record<ConversationPhase, SkillRef[]> = {
  trust_building: [
    { id: 'core-identity', estimatedTokens: 200, phases: ['trust_building'] },
  ],
  requirement: [
    { id: 'core-identity', estimatedTokens: 200, phases: ['requirement'] },
    { id: 'scenario-rules', estimatedTokens: 350, phases: ['requirement'] },
  ],
  diagnosis: [
    { id: 'core-identity', estimatedTokens: 200, phases: ['diagnosis'] },
    { id: 'teaching-strategy', estimatedTokens: 800, phases: ['diagnosis'] },
  ],
  training: [
    { id: 'core-identity', estimatedTokens: 200, phases: ['training'] },
    { id: 'validation-rules', estimatedTokens: 400, phases: ['training'] },
  ],
  reflection: [
    { id: 'core-identity', estimatedTokens: 200, phases: ['reflection'] },
    { id: 'feedback-cognition', estimatedTokens: 300, phases: ['reflection'] },
  ],
};

export class MockConversationOrchestrator implements ConversationOrchestrator {
  private stopRequested = false;

  /** 重置状态,供多轮测试使用 */
  reset(): void {
    this.stopRequested = false;
  }

  async *handleTurn(input: HandleTurnInput): AsyncIterable<OrchestratorEvent> {
    if (!input.sessionId) {
      yield { type: 'error', payload: { code: 'CONTEXT_MISSING', message: 'sessionId 必填', retryable: false } };
      return;
    }

    if (this.stopRequested) {
      yield { type: 'error', payload: { code: 'PHASE_INVALID', message: '已停止,创建新实例继续', retryable: false } };
      return;
    }

    // 阶段 0 (信任建立) 首次进入时发 phase_transition
    if (input.phase === 'trust_building') {
      yield {
        type: 'phase_transition',
        payload: { from: 'trust_building', to: 'requirement', reason: 'mock:trust_built' },
      };
    }

    // 模拟 token 流
    const tokens = ['我', '看到', '了', '你', '的', '消息', '。'];
    for (const t of tokens) {
      if (this.stopRequested) {
        yield { type: 'error', payload: { code: 'TIMEOUT', message: 'mock:stopped', retryable: false } };
        return;
      }
      yield { type: 'token', content: t };
    }

    // 模拟意图提取
    if (input.userMessage.includes('诊断') || input.userMessage.includes('分析')) {
      yield { type: 'intent', payload: { type: 'diagnose', syndromeHints: ['P003'] } };
      yield {
        type: 'diagnosis_extracted',
        payload: {
          syndromeId: 'P003',
          severity: 'L2',
          evidenceQuote: input.userMessage.slice(0, 50),
        },
      };
    } else if (input.userMessage.includes('训练')) {
      yield {
        type: 'intent',
        payload: { type: 'train', syndromeId: 'P003', techniqueId: 'T001' },
      };
      yield {
        type: 'training_triggered',
        payload: { sessionId: input.sessionId, syndromeId: 'P003', reason: 'user_request' },
      };
    } else {
      yield { type: 'intent', payload: { type: 'none' } };
    }

    yield { type: 'done' };
  }

  promptVersion(): PromptVersion {
    return MOCK_PROMPT;
  }

  skillManifest(phase: ConversationPhase): SkillRef[] {
    return SKILL_MANIFEST[phase] ?? [];
  }

  stopGeneration(): { stopped: boolean } {
    this.stopRequested = true;
    return { stopped: true };
  }
}
