/**
 * ChatOrchestratorService G-2 单测 — Sprint 23
 *
 * 覆盖 IntentRouter 升级后的主路径:
 * 1. IntentRouter.route() 返回 'train' → emit training_triggered
 * 2. IntentRouter.route() 返回其他 intent → 不 emit
 * 3. IntentRouter.route() 抛错 → 降级 TRAINING_INTENT_PATTERN 正则
 * 4. IntentRouter 显式注入优先于内部懒加载
 * 5. IntentRouter 返回 'train' 但消息正则不命中 → 仍 emit(IntentRouter 主路径胜出)
 * 6. IntentRouter 降级到正则:IntentRouter 抛错 + 正则命中 → emit
 *
 * 策略:显式注入 mock IntentRouter,控制 route() 返回值覆盖各种路径。
 *
 * DoD: ≥4 单测
 * 依据: dev-docs/tasks/sprint-23-plan.md §G-2
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { ChatOrchestratorService } from '../chat-orchestrator.service';
import type { OrchestratorEvent } from '../../conversation/orchestrator.types';
import type { ChatOrchestratorDeps } from '../chat-orchestrator.service';
import type { IntentRouter } from '../intent-router';
import type { RouteResult } from '../intent-router.types';

function createMockIntentRouter(behavior: {
  intent?: RouteResult['intent'];
  throw?: Error;
}): IntentRouter {
  return {
    route: vi.fn().mockImplementation(async (_msg: string): Promise<RouteResult> => {
      if (behavior.throw) {
        throw behavior.throw;
      }
      return {
        intent: behavior.intent ?? 'general_chat',
        confidence: behavior.intent === 'general_chat' ? 1.0 : 0.95,
        source: 'keyword',
      };
    }),
    updateLLMProvider: vi.fn(),
  } as unknown as IntentRouter;
}

function createMockDeps(intentRouter?: IntentRouter): ChatOrchestratorDeps {
  return {
    configService: { getConfig: () => ({ attitudeLevel: 'yuesheng' }) } as unknown as ChatOrchestratorDeps['configService'],
    sessionService: {} as ChatOrchestratorDeps['sessionService'],
    messageRouter: {} as ChatOrchestratorDeps['messageRouter'],
    diagnosisDomain: {} as ChatOrchestratorDeps['diagnosisDomain'],
    promptDomain: {} as ChatOrchestratorDeps['promptDomain'],
    studentDomain: {} as ChatOrchestratorDeps['studentDomain'],
    teachingDomain: {
      checkMessage: () => {},
      getEffectiveAttitude: () => 'yuesheng',
    } as unknown as ChatOrchestratorDeps['teachingDomain'],
    mainWindow: null,
    db: {} as ChatOrchestratorDeps['db'],
    diagnosisOrchestrator: {
      extractSyndromeIds: () => [],
      analyze: async () => ({ analysis: null, isNarrative: true }),
    } as unknown as ChatOrchestratorDeps['diagnosisOrchestrator'],
    teachingContext: {
      prepare: () => ({ finalPrompt: '', isReflectionGate: false }),
    } as unknown as ChatOrchestratorDeps['teachingContext'],
    streamHandler: {
      handleStream: async () => ({ success: true, messageId: 'm1' }),
      handleStreamWithTools: async () => ({ success: true, messageId: 'm1' }),
      stopStream: () => {},
    } as unknown as ChatOrchestratorDeps['streamHandler'],
    intentRouter,
  };
}

describe('ChatOrchestratorService training_triggered emit (Sprint 23 G-2 IntentRouter 主路径)', () => {
  beforeEach(() => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});
  });

  it('IntentRouter.route 返回 train → emit training_triggered', async () => {
    const intentRouter = createMockIntentRouter({ intent: 'train' });
    const svc = new ChatOrchestratorService(createMockDeps(intentRouter));

    const events: OrchestratorEvent[] = [];
    svc.onOrchestratorEvent((e) => {
      if (e.type === 'training_triggered') events.push(e);
    });

    const emit = (svc as unknown as {
      emitTrainingTriggeredIfNeeded: (
        sid: string,
        msg: string,
        a: { syndromeRef?: string[] },
      ) => Promise<void>;
    }).emitTrainingTriggeredIfNeeded.bind(svc);

    // "我想练环境描写" 命中 IntentRouter keyword('练习/训练/试试' 等)
    await emit('session-g2-1', '我想练环境描写', { syndromeRef: ['P003'] });

    expect(intentRouter.route).toHaveBeenCalledWith('我想练环境描写');
    expect(events.length).toBe(1);
    expect(events[0].type).toBe('training_triggered');
  });

  it('IntentRouter.route 返回其他 intent(learn/review) → 不 emit', async () => {
    const intentRouter = createMockIntentRouter({ intent: 'learn' });
    const svc = new ChatOrchestratorService(createMockDeps(intentRouter));

    let callCount = 0;
    svc.onOrchestratorEvent((e) => {
      if (e.type === 'training_triggered') callCount++;
    });

    const emit = (svc as unknown as {
      emitTrainingTriggeredIfNeeded: (
        sid: string,
        msg: string,
        a: { syndromeRef?: string[] },
      ) => Promise<void>;
    }).emitTrainingTriggeredIfNeeded.bind(svc);

    await emit('session-g2-2', '怎么写好人物对话', { syndromeRef: ['P003'] });

    expect(intentRouter.route).toHaveBeenCalled();
    expect(callCount).toBe(0);
  });

  it('IntentRouter.route 抛错 → 降级 TRAINING_INTENT_PATTERN 正则命中 → emit', async () => {
    const intentRouter = createMockIntentRouter({ throw: new Error('LLM timeout') });
    const svc = new ChatOrchestratorService(createMockDeps(intentRouter));

    const events: OrchestratorEvent[] = [];
    svc.onOrchestratorEvent((e) => {
      if (e.type === 'training_triggered') events.push(e);
    });

    const emit = (svc as unknown as {
      emitTrainingTriggeredIfNeeded: (
        sid: string,
        msg: string,
      a: { syndromeRef?: string[] },
      ) => Promise<void>;
    }).emitTrainingTriggeredIfNeeded.bind(svc);

    // "帮我训练" 命中正则(降级路径生效)
    await emit('session-g2-3', '帮我训练', { syndromeRef: ['P003'] });

    expect(intentRouter.route).toHaveBeenCalled();
    expect(events.length).toBe(1);
  });

  it('IntentRouter.route 抛错 + 正则不命中 → 不 emit', async () => {
    const intentRouter = createMockIntentRouter({ throw: new Error('LLM fail') });
    const svc = new ChatOrchestratorService(createMockDeps(intentRouter));

    let callCount = 0;
    svc.onOrchestratorEvent((e) => {
      if (e.type === 'training_triggered') callCount++;
    });

    const emit = (svc as unknown as {
      emitTrainingTriggeredIfNeeded: (
        sid: string,
        msg: string,
        a: { syndromeRef?: string[] },
      ) => Promise<void>;
    }).emitTrainingTriggeredIfNeeded.bind(svc);

    await emit('session-g2-4', '今天写了一段', { syndromeRef: ['P003'] });

    expect(intentRouter.route).toHaveBeenCalled();
    expect(callCount).toBe(0);
  });

  it('IntentRouter 显式注入优先于内部懒加载(deps.intentRouter 存在时不创建 internal)', async () => {
    const intentRouter = createMockIntentRouter({ intent: 'train' });
    const svc = new ChatOrchestratorService(createMockDeps(intentRouter));

    // 验证 getIntentRouter 返回 deps.intentRouter(不是 internalIntentRouter)
    const router = (svc as unknown as {
      getIntentRouter: () => IntentRouter | null;
    }).getIntentRouter();
    expect(router).toBe(intentRouter);
  });

  it('IntentRouter.route 返回 train,正则不命中 → 仍 emit(IntentRouter 主路径胜出)', async () => {
    // "我想练环境描写" 含"练"但不含 TRAINING_INTENT_PATTERN 的任何 keyword
    // 验证 IntentRouter 升级后,正则降级仅在 IntentRouter 失败时触发
    const intentRouter = createMockIntentRouter({ intent: 'train' });
    const svc = new ChatOrchestratorService(createMockDeps(intentRouter));

    const events: OrchestratorEvent[] = [];
    svc.onOrchestratorEvent((e) => {
      if (e.type === 'training_triggered') events.push(e);
    });

    const emit = (svc as unknown as {
      emitTrainingTriggeredIfNeeded: (
        sid: string,
        msg: string,
        a: { syndromeRef?: string[] },
      ) => Promise<void>;
    }).emitTrainingTriggeredIfNeeded.bind(svc);

    await emit('session-g2-5', '给我练练对话', { syndromeRef: ['P003'] });

    expect(events.length).toBe(1);
  });
});
