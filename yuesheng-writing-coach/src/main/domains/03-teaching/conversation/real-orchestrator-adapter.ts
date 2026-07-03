/**
 * RealOrchestratorAdapter — Sprint 21 D-1
 *
 * 把真实 ChatOrchestratorService 包装为 ConversationOrchestrator 接口
 * 取代 Sprint 20 A-4 的 MockConversationOrchestrator(后者标 @legacy)
 *
 * 事件映射:
 * - sendMessage 的 token 流(streamHandler 通过 onToken 回调) → OrchestratorEvent.token
 * - sendMessage 末尾 emitOrchestratorEvent(intent:none 等) → OrchestratorEvent.intent
 * - sendMessage 成功 → OrchestratorEvent.done
 * - sendMessage 失败 → OrchestratorEvent.error
 *
 * 异常隔离:订阅 handler 抛错仅 warn,不中断事件流
 * 依据:dev-docs/tasks/sprint-21-plan.md §D-1
 */

import type {
  ConversationOrchestrator,
  ConversationPhase,
  HandleTurnInput,
  OrchestratorEvent,
  PromptVersion,
  SkillRef,
} from './orchestrator.types';
import type { ChatOrchestratorService } from '../chat/chat-orchestrator.service';
import type { SkillRegistry } from './skill-registry';

const FALLBACK_CONTRACT = {
  required_phases: ['trust_building', 'requirement', 'diagnosis', 'training', 'reflection'] as Array<'trust_building' | 'requirement' | 'diagnosis' | 'training' | 'reflection'>,
  required_skills: ['core-identity', 'scenario-rules', 'teaching-strategy', 'validation-rules', 'feedback-cognition'],
  required_techniques: ['TQ-001', 'TQ-002', 'TQ-003', 'TQ-004', 'TQ-005', 'TQ-006', 'TQ-007', 'TQ-008', 'TQ-009', 'TQ-010'],
  required_tools: ['chapter:get', 'chapter:list', 'training:recommend', 'session:list'],
  emits_events: ['chat:token', 'chat:intent', 'chat:phase_transition', 'chat:done', 'chat:error', 'diagnosis:extracted', 'training:triggered'],
};

export class RealOrchestratorAdapter implements ConversationOrchestrator {
  constructor(
    private readonly chatOrchestrator: ChatOrchestratorService,
    private readonly skillRegistry?: SkillRegistry,
  ) {}

  async *handleTurn(input: HandleTurnInput): AsyncIterable<OrchestratorEvent> {
    if (!input.sessionId) {
      yield {
        type: 'error',
        payload: { code: 'CONTEXT_MISSING', message: 'sessionId 必填', retryable: false },
      };
      return;
    }

    // 事件队列:用 push 模型替代 for-await 拉模型
    const queue: OrchestratorEvent[] = [];
    let resolveNext: (() => void) | null = null;
    let done = false;

    const enqueue = (event: OrchestratorEvent) => {
      queue.push(event);
      if (resolveNext) {
        const r = resolveNext;
        resolveNext = null;
        r();
      }
    };

    // 订阅 ChatOrchestratorService 的 orchestrator 事件
    const unsubscribe = this.chatOrchestrator.onOrchestratorEvent((event, sid) => {
      if (sid !== input.sessionId) return; // 过滤其他会话
      try {
        enqueue(event);
      } catch (e) {
        console.warn('[RealOrchestratorAdapter] enqueue failed:', e);
      }
    });

    // 触发真实 sendMessage(onToken 桥接 token 流)
    void this.chatOrchestrator
      .sendMessage({
        message: input.userMessage,
        sessionId: input.sessionId,
        history: input.history,
        attitudeLevel: input.attitudeLevel,
        studentContext: input.studentContext,
        onToken: (chunk: string) => {
          enqueue({ type: 'token', content: chunk });
        },
      })
      .then(() => {
        enqueue({ type: 'done' });
      })
      .catch((e: unknown) => {
        const err = e instanceof Error ? e : new Error(String(e));
        enqueue({
          type: 'error',
          payload: {
            code: 'API_ERROR',
            message: err.message,
            retryable: false,
          },
        });
      })
      .finally(() => {
        done = true;
        unsubscribe();
        if (resolveNext) {
          const r = resolveNext;
          resolveNext = null;
          r();
        }
      });

    // 消费事件队列
    try {
      while (true) {
        if (queue.length === 0) {
          if (done) return;
          await new Promise<void>(resolve => {
            resolveNext = resolve;
          });
          continue;
        }
        const event = queue.shift()!;
        yield event;
        if (event.type === 'done' || event.type === 'error') return;
      }
    } finally {
      // 确保清理:队列消费完或消费方中断,unsubscribe 已通过 .finally() 调用
      // 此处仅兜底(若 yield 抛出异常时 finally 还没跑)
      if (!done) {
        done = true;
        unsubscribe();
      }
    }
  }

  promptVersion(): PromptVersion {
    return {
      version: 'v5.0.1',
      rollbackTo: 'v5',
      changelog: 'Sprint 21 D-1:RealOrchestratorAdapter 接入真实 ChatOrchestratorService',
      contract: FALLBACK_CONTRACT,
    };
  }

  skillManifest(_phase: ConversationPhase, version?: string): SkillRef[] {
    if (!this.skillRegistry) return [];
    try {
      // Sprint 21 D-1:简化版,只做版本过滤,phase 过滤由 orchestrator 未来扩展
      const all = version ? this.skillRegistry.compatibleWith(version) : this.skillRegistry.getAll();
      return all.map(meta => ({
        id: meta.id,
        estimatedTokens: meta.estimatedTokens,
        phases: meta.phases,
        compatiblePromptVersions: meta.compatiblePromptVersions,
      }));
    } catch (e) {
      console.warn('[RealOrchestratorAdapter] getManifest failed:', e);
      return [];
    }
  }

  stopGeneration(): { stopped: boolean } {
    return this.chatOrchestrator.stopGeneration();
  }
}
