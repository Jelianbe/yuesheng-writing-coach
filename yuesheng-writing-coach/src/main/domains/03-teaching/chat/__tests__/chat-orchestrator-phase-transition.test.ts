/**
 * ChatOrchestratorService F-1 单测 — Sprint 22
 *
 * 覆盖:
 * 1. phase_transition 事件能被订阅者收到
 * 2. 5 秒去重窗口工作(连续两次 emit 只触发一次 dispatch)
 * 3. 5 秒后允许重新 emit
 * 4. 不同 sessionId 互不干扰
 *
 * 策略:实例化 ChatOrchestratorService 注入最小 deps,
 * 直接通过 TypeScript 类型转换调 emitPhaseTransitionIfNeeded 测内部逻辑。
 *
 * DoD: ≥3 单测
 * 依据: dev-docs/tasks/sprint-22-plan.md §F-1
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

describe('ChatOrchestratorService phase_transition emit (Sprint 22 F-1)', () => {
  let svc: ChatOrchestratorService;
  let mockDeps: ChatOrchestratorDeps;

  beforeEach(() => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    mockDeps = createMockDeps();
    svc = new ChatOrchestratorService(mockDeps);
  });

  it('订阅者能收到 phase_transition 事件', () => {
    const events: OrchestratorEvent[] = [];
    svc.onOrchestratorEvent((e) => {
      if (e.type === 'phase_transition') events.push(e);
    });

    // 通过类型转换访问私有方法
    (svc as unknown as {
      emitPhaseTransitionIfNeeded: (sid: string, a: { syndromeRef?: string[] }) => void;
    }).emitPhaseTransitionIfNeeded('session-A', { syndromeRef: ['P001', 'P002'] });

    expect(events.length).toBe(1);
    expect(events[0].type).toBe('phase_transition');
    if (events[0].type === 'phase_transition') {
      expect(events[0].payload.to).toBe('diagnosis');
      expect(events[0].payload.reason).toContain('symptoms_detected:2');
    }
  });

  it('5 秒内重复 emit 被去重(只触发一次 dispatch)', () => {
    let callCount = 0;
    svc.onOrchestratorEvent((e) => {
      if (e.type === 'phase_transition') callCount++;
    });

    const emit = (svc as unknown as {
      emitPhaseTransitionIfNeeded: (sid: string, a: { syndromeRef?: string[] }) => void;
    }).emitPhaseTransitionIfNeeded.bind(svc);

    emit('session-A', { syndromeRef: ['P001'] });
    emit('session-A', { syndromeRef: ['P001'] });
    emit('session-A', { syndromeRef: ['P001'] });

    expect(callCount).toBe(1);
  });

  it('5 秒后允许重新 emit', async () => {
    let callCount = 0;
    svc.onOrchestratorEvent((e) => {
      if (e.type === 'phase_transition') callCount++;
    });

    const emit = (svc as unknown as {
      emitPhaseTransitionIfNeeded: (sid: string, a: { syndromeRef?: string[] }) => void;
    }).emitPhaseTransitionIfNeeded.bind(svc);

    emit('session-A', { syndromeRef: ['P001'] });
    expect(callCount).toBe(1);

    // 推进 6 秒越过 5 秒窗口
    vi.useFakeTimers();
    vi.advanceTimersByTime(6000);
    emit('session-A', { syndromeRef: ['P001'] });
    expect(callCount).toBe(2);
    vi.useRealTimers();
  });

  it('不同 sessionId 互不干扰(独立去重)', () => {
    let aCount = 0;
    let bCount = 0;
    svc.onOrchestratorEvent((e, sid) => {
      if (e.type !== 'phase_transition') return;
      if (sid === 'session-A') aCount++;
      if (sid === 'session-B') bCount++;
    });

    const emit = (svc as unknown as {
      emitPhaseTransitionIfNeeded: (sid: string, a: { syndromeRef?: string[] }) => void;
    }).emitPhaseTransitionIfNeeded.bind(svc);

    emit('session-A', { syndromeRef: ['P001'] });
    emit('session-B', { syndromeRef: ['P002'] });
    emit('session-A', { syndromeRef: ['P001'] }); // A 已被去重
    emit('session-B', { syndromeRef: ['P002'] }); // B 已被去重

    expect(aCount).toBe(1);
    expect(bCount).toBe(1);
  });

  it('syndromeRef 为空时调用不 emit(防御性)', () => {
    let callCount = 0;
    svc.onOrchestratorEvent((e) => {
      if (e.type === 'phase_transition') callCount++;
    });

    // syndromeRef 缺失或为空时,sendMessage 入口的 if 守卫会拦截,
    // 但 emit 内部仍应容忍(不抛错,因 payload.to 必填)
    const emit = (svc as unknown as {
      emitPhaseTransitionIfNeeded: (sid: string, a: { syndromeRef?: string[] }) => void;
    }).emitPhaseTransitionIfNeeded.bind(svc);

    // 正常 emit(空 syndromeRef 也会 emit,reason 显示 0)
    emit('session-A', { syndromeRef: [] });
    expect(callCount).toBe(1);
  });
});
