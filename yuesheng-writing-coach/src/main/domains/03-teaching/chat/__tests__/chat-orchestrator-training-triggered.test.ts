/**
 * ChatOrchestratorService F-2 单测 — Sprint 22
 *
 * 覆盖:
 * 1. 训练意图关键词 + 诊断有症候 → emit training_triggered
 * 2. 无症候时不 emit
 * 3. 无训练意图关键词时不 emit
 * 4. 5 秒内重复 emit 被去重
 * 5. 不同 sessionId 互不干扰
 * 6. payload.syndromeId 取第一个症候
 *
 * 策略:实例化 ChatOrchestratorService 注入最小 deps,
 * 直接通过 TypeScript 类型转换调 emitTrainingTriggeredIfNeeded 测内部逻辑。
 *
 * DoD: ≥3 单测(实际给 6 个)
 * 依据: dev-docs/tasks/sprint-22-plan.md §F-2
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

describe('ChatOrchestratorService training_triggered emit (Sprint 22 F-2)', () => {
  let svc: ChatOrchestratorService;
  let mockDeps: ChatOrchestratorDeps;

  beforeEach(() => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    mockDeps = createMockDeps();
    svc = new ChatOrchestratorService(mockDeps);
  });

  it('训练意图关键词 + 有症候 → emit training_triggered', () => {
    const events: OrchestratorEvent[] = [];
    svc.onOrchestratorEvent((e) => {
      if (e.type === 'training_triggered') events.push(e);
    });

    const emit = (svc as unknown as {
      emitTrainingTriggeredIfNeeded: (
        sid: string,
        msg: string,
        a: { syndromeRef?: string[] },
      ) => void;
    }).emitTrainingTriggeredIfNeeded.bind(svc);

    emit('session-A', '帮我训练这个', { syndromeRef: ['P001', 'P002'] });

    expect(events.length).toBe(1);
    expect(events[0].type).toBe('training_triggered');
    if (events[0].type === 'training_triggered') {
      expect(events[0].payload.syndromeId).toBe('P001');
      expect(events[0].payload.reason).toBe('user_request');
      expect(events[0].payload.techniqueId).toBeUndefined();
      expect(events[0].payload.sessionId).toBe('session-A');
    }
  });

  it('无症候时不 emit(防御性)', () => {
    let callCount = 0;
    svc.onOrchestratorEvent((e) => {
      if (e.type === 'training_triggered') callCount++;
    });

    const emit = (svc as unknown as {
      emitTrainingTriggeredIfNeeded: (
        sid: string,
        msg: string,
        a: { syndromeRef?: string[] },
      ) => void;
    }).emitTrainingTriggeredIfNeeded.bind(svc);

    emit('session-A', '帮我训练', { syndromeRef: [] });
    expect(callCount).toBe(0);

    emit('session-A', '帮我训练', {});
    expect(callCount).toBe(0);
  });

  it('无训练意图关键词时不 emit', () => {
    let callCount = 0;
    svc.onOrchestratorEvent((e) => {
      if (e.type === 'training_triggered') callCount++;
    });

    const emit = (svc as unknown as {
      emitTrainingTriggeredIfNeeded: (
        sid: string,
        msg: string,
        a: { syndromeRef?: string[] },
      ) => void;
    }).emitTrainingTriggeredIfNeeded.bind(svc);

    // 描述症状但不主动要求训练
    emit('session-A', '我觉得这一段节奏有点乱', { syndromeRef: ['P003'] });
    expect(callCount).toBe(0);

    // 中性词"练习"被排除(避免误匹配"练习题")
    emit('session-A', '这里有练习题', { syndromeRef: ['P003'] });
    expect(callCount).toBe(0);
  });

  it('5 秒内重复 emit 被去重', () => {
    let callCount = 0;
    svc.onOrchestratorEvent((e) => {
      if (e.type === 'training_triggered') callCount++;
    });

    const emit = (svc as unknown as {
      emitTrainingTriggeredIfNeeded: (
        sid: string,
        msg: string,
        a: { syndromeRef?: string[] },
      ) => void;
    }).emitTrainingTriggeredIfNeeded.bind(svc);

    emit('session-A', '帮我训练', { syndromeRef: ['P001'] });
    emit('session-A', '练一下', { syndromeRef: ['P001'] });
    emit('session-A', '开始训练', { syndromeRef: ['P001'] });
    expect(callCount).toBe(1);
  });

  it('5 秒后允许重新 emit', () => {
    let callCount = 0;
    svc.onOrchestratorEvent((e) => {
      if (e.type === 'training_triggered') callCount++;
    });

    const emit = (svc as unknown as {
      emitTrainingTriggeredIfNeeded: (
        sid: string,
        msg: string,
        a: { syndromeRef?: string[] },
      ) => void;
    }).emitTrainingTriggeredIfNeeded.bind(svc);

    emit('session-A', '帮我训练', { syndromeRef: ['P001'] });
    expect(callCount).toBe(1);

    vi.useFakeTimers();
    vi.advanceTimersByTime(6000);
    emit('session-A', '帮我训练', { syndromeRef: ['P001'] });
    expect(callCount).toBe(2);
    vi.useRealTimers();
  });

  it('不同 sessionId 互不干扰(独立去重)', () => {
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
      ) => void;
    }).emitTrainingTriggeredIfNeeded.bind(svc);

    emit('session-A', '帮我训练', { syndromeRef: ['P001'] });
    emit('session-B', '帮我训练', { syndromeRef: ['P002'] });
    emit('session-A', '帮我训练', { syndromeRef: ['P001'] });
    emit('session-B', '帮我训练', { syndromeRef: ['P002'] });

    expect(aCount).toBe(1);
    expect(bCount).toBe(1);
  });

  it('payload.syndromeId 取 syndromeRef 第一个', () => {
    const events: OrchestratorEvent[] = [];
    svc.onOrchestratorEvent((e) => {
      if (e.type === 'training_triggered') events.push(e);
    });

    const emit = (svc as unknown as {
      emitTrainingTriggeredIfNeeded: (
        sid: string,
        msg: string,
        a: { syndromeRef?: string[] },
      ) => void;
    }).emitTrainingTriggeredIfNeeded.bind(svc);

    emit('session-A', '开始训练', { syndromeRef: ['P005', 'P003', 'P001'] });

    expect(events.length).toBe(1);
    if (events[0].type === 'training_triggered') {
      expect(events[0].payload.syndromeId).toBe('P005');
    }
  });
});
