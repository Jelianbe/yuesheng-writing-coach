/* eslint-disable @typescript-eslint/no-non-null-assertion */
/**
 * TeachingStateSubscriber + ChatOrchestratorService 事件订阅测试
 *
 * Sprint 20 A-3 试点 — 验证"事件 → 状态机方法"链路
 * DoD: 至少 1 个状态机分支走事件驱动
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { TeachingStateSubscriber } from '../teaching-state-subscriber';
import type { OrchestratorEvent } from '../orchestrator.types';
import type { TeachingStateService } from '../../teaching-state.service';

describe('TeachingStateSubscriber (Sprint 20 A-3 试点)', () => {
  let mockTeachingState: { getContext: ReturnType<typeof vi.fn> };
  let subscriber: TeachingStateSubscriber;
  let getContextCalls: Array<{ sessionId: string }>;

  beforeEach(() => {
    getContextCalls = [];
    mockTeachingState = {
      getContext: vi.fn((sessionId: string) => {
        getContextCalls.push({ sessionId });
        return { currentPhase: 'P0_INIT', currentSubphase: null, activeProblems: [] };
      }),
    };
    subscriber = new TeachingStateSubscriber(
      mockTeachingState as unknown as TeachingStateService,
    );
  });

  it('收到 intent:train 事件 → 记录 + 调用 teachingStateService.getContext', () => {
    const event: OrchestratorEvent = {
      type: 'intent',
      payload: { type: 'train', syndromeId: 'P003', techniqueId: 'T001' },
    };
    subscriber.handle(event, 'sess-1');

    const record = subscriber.getLastTrainEvent();
    expect(record).not.toBeNull();
    expect(record!.sessionId).toBe('sess-1');
    expect(record!.syndromeId).toBe('P003');
    expect(record!.techniqueId).toBe('T001');
    expect(getContextCalls).toHaveLength(1);
    expect(getContextCalls[0].sessionId).toBe('sess-1');
  });

  it('收到非 train 事件 → 不记录 + 不调用', () => {
    const event: OrchestratorEvent = {
      type: 'intent',
      payload: { type: 'none' },
    };
    subscriber.handle(event, 'sess-2');

    expect(subscriber.getLastTrainEvent()).toBeNull();
    expect(getContextCalls).toHaveLength(0);
  });

  it('收到非 intent 事件(phase_transition / token)→ 完全忽略', () => {
    const events: OrchestratorEvent[] = [
      { type: 'token', content: 'hi' },
      { type: 'phase_transition', payload: { from: 'trust_building', to: 'requirement', reason: 'test' } },
      { type: 'done' },
    ];
    for (const ev of events) {
      subscriber.handle(ev, 'sess-3');
    }
    expect(subscriber.getLastTrainEvent()).toBeNull();
    expect(getContextCalls).toHaveLength(0);
  });

  it('多次 train 事件 → 只保留最近一次记录', () => {
    subscriber.handle({ type: 'intent', payload: { type: 'train', syndromeId: 'P001' } }, 'sess-A');
    subscriber.handle({ type: 'intent', payload: { type: 'train', syndromeId: 'P002' } }, 'sess-B');
    subscriber.handle({ type: 'intent', payload: { type: 'train', syndromeId: 'P003' } }, 'sess-C');

    const record = subscriber.getLastTrainEvent();
    expect(record!.sessionId).toBe('sess-C');
    expect(record!.syndromeId).toBe('P003');
    expect(getContextCalls).toHaveLength(3);
  });

  it('teachingStateService.getContext 抛错 → 不影响记录(异常隔离)', () => {
    const errorService = {
      getContext: vi.fn(() => {
        throw new Error('mock db error');
      }),
    };
    const errorSubscriber = new TeachingStateSubscriber(
      errorService as unknown as TeachingStateService,
    );

    // 不应 throw
    expect(() => {
      errorSubscriber.handle(
        { type: 'intent', payload: { type: 'train', syndromeId: 'P001' } },
        'sess-err',
      );
    }).not.toThrow();

    // 记录仍然保留
    const record = errorSubscriber.getLastTrainEvent();
    expect(record).not.toBeNull();
    expect(record!.syndromeId).toBe('P001');
  });
});
