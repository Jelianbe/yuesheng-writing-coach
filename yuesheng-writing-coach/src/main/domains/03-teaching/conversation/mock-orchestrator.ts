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
import type { PromptContract } from './prompt-contract';
import type { SkillRegistry } from './skill-registry';
import { createDefaultSkillRegistry } from './skill-registry';

const MOCK_CONTRACT: PromptContract = {
  required_phases: ['trust_building', 'requirement', 'diagnosis', 'training', 'reflection'],
  required_skills: ['core-identity', 'scenario-rules', 'teaching-strategy', 'validation-rules', 'feedback-cognition'],
  required_techniques: ['P001', 'P002', 'P003', 'P004', 'P005', 'P006', 'P007', 'P008', 'P009', 'P010'],
  required_tools: ['chapter:read', 'diagnosis:extract', 'training:start', 'session:saveMessage'],
  emits_events: ['chat:token', 'chat:intent', 'chat:phase_transition', 'chat:done', 'chat:error', 'diagnosis:extracted', 'training:triggered'],
};

const MOCK_PROMPT: PromptVersion = {
  version: 'v5.0.0-mock',
  changelog: 'A-1 骨架,固定响应,无 AI 调用',
  contract: MOCK_CONTRACT,
};

const SKILL_MANIFEST: Record<ConversationPhase, SkillRef[]> = {
  trust_building: [
    { id: 'core-identity', estimatedTokens: 200, phases: ['trust_building'], compatiblePromptVersions: ['v5.0.0', 'v5.0.0-mock'] },
  ],
  requirement: [
    { id: 'core-identity', estimatedTokens: 200, phases: ['requirement'], compatiblePromptVersions: ['v5.0.0', 'v5.0.0-mock'] },
    { id: 'scenario-rules', estimatedTokens: 350, phases: ['requirement'], compatiblePromptVersions: ['v5.0.0', 'v5.0.0-mock'] },
  ],
  diagnosis: [
    { id: 'core-identity', estimatedTokens: 200, phases: ['diagnosis'], compatiblePromptVersions: ['v5.0.0', 'v5.0.0-mock'] },
    { id: 'teaching-strategy', estimatedTokens: 800, phases: ['diagnosis'], compatiblePromptVersions: ['v5.0.0', 'v5.0.0-mock'] },
    { id: 'validation-rules', estimatedTokens: 400, phases: ['diagnosis'], compatiblePromptVersions: ['v5.0.0', 'v5.0.0-mock'] },
  ],
  training: [
    { id: 'core-identity', estimatedTokens: 200, phases: ['training'], compatiblePromptVersions: ['v5.0.0', 'v5.0.0-mock'] },
    { id: 'teaching-strategy', estimatedTokens: 800, phases: ['training'], compatiblePromptVersions: ['v5.0.0', 'v5.0.0-mock'] },
    { id: 'validation-rules', estimatedTokens: 400, phases: ['training'], compatiblePromptVersions: ['v5.0.0', 'v5.0.0-mock'] },
  ],
  reflection: [
    { id: 'core-identity', estimatedTokens: 200, phases: ['reflection'], compatiblePromptVersions: ['v5.0.0', 'v5.0.0-mock'] },
    { id: 'feedback-cognition', estimatedTokens: 300, phases: ['reflection'], compatiblePromptVersions: ['v5.0.0', 'v5.0.0-mock'] },
  ],
};

export class MockConversationOrchestrator implements ConversationOrchestrator {
  private stopRequested = false;
  private readonly registry: SkillRegistry;

  constructor(registry?: SkillRegistry) {
    this.registry = registry ?? createDefaultSkillRegistry(process.cwd());
  }

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

  skillManifest(phase: ConversationPhase, version?: string): SkillRef[] {
    const phaseSkills = SKILL_MANIFEST[phase] ?? [];
    if (!version) return phaseSkills;
    // 增量 1:版本过滤 — 用 SkillRegistry 检查每个 skill 是否与 version 兼容
    return phaseSkills.filter(s => {
      const meta = this.registry.getById(s.id);
      // 找不到元数据 → 保守放过(向后兼容)
      if (!meta) return true;
      // 元数据声明为空 → 视为不兼容(契约硬要求)
      if (meta.compatiblePromptVersions.length === 0) return false;
      return meta.compatiblePromptVersions.includes(version);
    });
  }

  stopGeneration(): { stopped: boolean } {
    this.stopRequested = true;
    return { stopped: true };
  }
}
