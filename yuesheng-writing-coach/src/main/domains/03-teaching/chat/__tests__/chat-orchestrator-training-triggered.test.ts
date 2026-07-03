/**
 * ChatOrchestratorService F-2 单测 — Sprint 22
 *
 * Sprint 23 G-2 更新:IntentRouter 升级后,本测试验证"IntentRouter 不可用 → 降级正则"路径
 * - 不注入 IntentRouter → 内部懒加载失败(ApiProxy 在测试 mock 中) → 降级 TRAINING_INTENT_PATTERN
 * - emitTrainingTriggeredIfNeeded 改为 async,所有调用点需 await
 *
 * 覆盖:
 * 1. 训练意图关键词 + 诊断有症候 → emit training_triggered(降级路径)
 * 2. 无症候时不 emit
 * 3. 无训练意图关键词时不 emit
 * 4. 5 秒内重复 emit 被去重
 * 5. 不同 sessionId 互不干扰
 * 6. payload.syndromeId 取第一个症候
 *
 * 策略:实例化 ChatOrchestratorService 注入最小 deps,IntentRouter 故意不注入,
 * 验证降级路径行为与 Sprint 22 F-2 一致(向后兼容)。
 *
 * DoD: ≥3 单测(实际给 6 个)
 * 依据: dev-docs/tasks/sprint-22-plan.md §F-2 + dev-docs/tasks/sprint-23-plan.md §G-2
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { ChatOrchestratorService } from '../chat-orchestrator.service';
import type { OrchestratorEvent } from '../../conversation/orchestrator.types';
import type { ChatOrchestratorDeps } from '../chat-orchestrator.service';

function createMockDeps(): ChatOrchestratorDeps {
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
  };
}

describe('ChatOrchestratorService training_triggered emit (Sprint 22 F-2 fallback path, Sprint 23 G-2 IntentRouter 降级验证)', () => {
  let svc: ChatOrchestratorService;
  let mockDeps: ChatOrchestratorDeps;

  beforeEach(() => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    mockDeps = createMockDeps();
    svc = new ChatOrchestratorService(mockDeps);
  });

  it('训练意图关键词 + 有症候 → emit training_triggered (IntentRouter 不可用 → 降级正则)', async () => {
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

    await emit('session-A', '帮我训练这个', { syndromeRef: ['P001', 'P002'] });

    expect(events.length).toBe(1);
    expect(events[0].type).toBe('training_triggered');
    if (events[0].type === 'training_triggered') {
      expect(events[0].payload.syndromeId).toBe('P001');
      expect(events[0].payload.reason).toBe('user_request');
      expect(events[0].payload.techniqueId).toBeUndefined();
      expect(events[0].payload.sessionId).toBe('session-A');
    }
  });

  it('无症候时不 emit(防御性)', async () => {
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

    await emit('session-A', '帮我训练', { syndromeRef: [] });
    expect(callCount).toBe(0);

    await emit('session-A', '帮我训练', {});
    expect(callCount).toBe(0);
  });

  it('无训练意图时不 emit (IntentRouter + 正则都未命中)', async () => {
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

    // 描述症状但不主动要求训练
    await emit('session-A', '我觉得这一段节奏有点乱', { syndromeRef: ['P003'] });
    expect(callCount).toBe(0);

    // 完全中性的句子:既不命中 IntentRouter keyword("练习/训练/试试"等),也不命中正则
    await emit('session-A', '今天写了三千字', { syndromeRef: ['P003'] });
    expect(callCount).toBe(0);

    // 注:IntentRouter keyword 含"练习"独立词,所以"练习题"会触发 train 意图,
    // 这是 G-2 升级后的设计变化(从"严格正则"升级为"keyword + LLM 兜底")
  });

  it('5 秒内重复 emit 被去重', async () => {
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

    await emit('session-A', '帮我训练', { syndromeRef: ['P001'] });
    await emit('session-A', '练一下', { syndromeRef: ['P001'] });
    await emit('session-A', '开始训练', { syndromeRef: ['P001'] });
    expect(callCount).toBe(1);
  });

  it('5 秒后允许重新 emit', async () => {
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

    await emit('session-A', '帮我训练', { syndromeRef: ['P001'] });
    expect(callCount).toBe(1);

    vi.useFakeTimers();
    vi.advanceTimersByTime(6000);
    await emit('session-A', '帮我训练', { syndromeRef: ['P001'] });
    expect(callCount).toBe(2);
    vi.useRealTimers();
  });

  it('不同 sessionId 互不干扰(独立去重)', async () => {
    let aCount = 0;
    let bCount = 0;
    svc.onOrchestratorEvent((e, sid) => {
      if (e.type !== 'training_triggered') return;
      if (sid === 'session-A') aCount++;
      if (sid === 'session-B') bCount++;
    });

    const emit = (svc as unknown as {
      emitTrainingTriggeredIfNeeded: (
        sid: string,
        msg: string,
        a: { syndromeRef?: string[] },
      ) => Promise<void>;
    }).emitTrainingTriggeredIfNeeded.bind(svc);

    await emit('session-A', '帮我训练', { syndromeRef: ['P001'] });
    await emit('session-B', '帮我训练', { syndromeRef: ['P002'] });
    await emit('session-A', '帮我训练', { syndromeRef: ['P001'] });
    await emit('session-B', '帮我训练', { syndromeRef: ['P002'] });

    expect(aCount).toBe(1);
    expect(bCount).toBe(1);
  });

  it('payload.syndromeId 取 syndromeRef 第一个', async () => {
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

    await emit('session-A', '开始训练', { syndromeRef: ['P005', 'P003', 'P001'] });

    expect(events.length).toBe(1);
    if (events[0].type === 'training_triggered') {
      expect(events[0].payload.syndromeId).toBe('P005');
    }
  });
});
