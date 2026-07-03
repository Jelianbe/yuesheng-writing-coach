/**
 * TeachingStateSubscriber F-2 → G-1 单测 — Sprint 22 F-2 / Sprint 23 G-1
 *
 * Sprint 22 F-2: training_triggered enabled 后行为(承接 D-2 disabled 状态)
 *   - 当时实现: markTrainingIntent + console.info (占位,S23+ 接入)
 * Sprint 23 G-1: 真实主进程侧 ActiveTraining 业务元数据
 *   - 替换为: setActiveTraining
 *   - 不再调用 markTrainingIntent
 *   - 不再有 console.info 占位标注
 *
 * 覆盖:
 * 1. training_triggered → setActiveTraining 透传 syndromeId/techniqueId/source
 * 2. setActiveTraining 替代 markTrainingIntent(原占位不再调用)
 * 3. payload 字段(syndromeId/techniqueId/reason)完整透传
 * 4. 与 phase_transition 同时触发不互相干扰
 *
 * DoD: ≥3 单测
 * 依据: dev-docs/tasks/sprint-22-plan.md §F-2 + dev-docs/tasks/sprint-23-plan.md §G-1
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import { TeachingStateSubscriber } from '../teaching-state-subscriber';
import type { TeachingStateService } from '../../teaching-state.service';
import type { ActiveTrainingMeta } from '../../../../../shared/types/index';

function writeTempConfig(content: unknown): string {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tss-f2-'));
  const file = path.join(dir, 'state-machine-event-mapping.json');
  fs.writeFileSync(file, JSON.stringify(content), 'utf-8');
  return file;
}

interface FakeCalls {
  setActiveTraining: Array<{
    sessionId: string;
    syndromeId: string;
    techniqueId?: string;
    source: ActiveTrainingMeta['source'];
  }>;
  markTrainingIntent: Array<{ sessionId: string; syndromeId: string; techniqueId?: string }>;
  confirmPhase: Array<{ sessionId: string }>;
  recordProblem: Array<{ sessionId: string; syndromeId: string }>;
}

const f2Config = {
  version: '1.0',
  subscribers: [
    { eventType: 'intent:train', action: 'markTrainingIntent', enabled: true },
    { eventType: 'diagnosis_extracted', action: 'recordProblem', enabled: true },
    { eventType: 'phase_transition', action: 'confirmPhase', enabled: true },
    { eventType: 'training_triggered', action: 'setActiveTraining', enabled: true },
  ],
};

const createFakeService = (): { service: TeachingStateService; calls: FakeCalls } => {
  const calls: FakeCalls = {
    setActiveTraining: [],
    markTrainingIntent: [],
    confirmPhase: [],
    recordProblem: [],
  };
  const service = {
    // Sprint 23 G-1: 新增 setActiveTraining 替代 Sprint 22 F-2 占位
    setActiveTraining: (
      sessionId: string,
      syndromeId: string,
      techniqueId: string | undefined,
      source: ActiveTrainingMeta['source'],
    ) => {
      calls.setActiveTraining.push({ sessionId, syndromeId, techniqueId, source });
    },
    // Sprint 21 D-2 保留: markTrainingIntent 仍服务于 intent:train 事件(语义不同)
    markTrainingIntent: (sessionId: string, syndromeId: string, techniqueId?: string) => {
      calls.markTrainingIntent.push({ sessionId, syndromeId, techniqueId });
    },
    recordProblem: (sessionId: string, syndromeId: string) => {
      calls.recordProblem.push({ sessionId, syndromeId });
    },
    getContext: () => ({ currentPhase: 'P2', currentSubphase: null, activeProblems: [] }),
    confirmPhase: (sessionId: string) => {
      calls.confirmPhase.push({ sessionId });
      return { oldState: {} as never, newState: {} as never };
    },
  } as unknown as TeachingStateService;
  return { service, calls };
};

describe('TeachingStateSubscriber training_triggered (Sprint 22 F-2 → Sprint 23 G-1)', () => {
  beforeEach(() => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    vi.spyOn(console, 'info').mockImplementation(() => {});
  });

  it('training_triggered → setActiveTraining 透传 syndromeId/techniqueId/source (G-1)', () => {
    const configPath = writeTempConfig(f2Config);
    const { service, calls } = createFakeService();
    const subscriber = new TeachingStateSubscriber(service, configPath);

    subscriber.handle(
      {
        type: 'training_triggered',
        payload: {
          sessionId: 'sess-f2-1',
          syndromeId: 'P003',
          techniqueId: 'TQ-007',
          reason: 'user_request',
        },
      },
      'sess-f2-1',
    );

    expect(calls.setActiveTraining).toEqual([
      { sessionId: 'sess-f2-1', syndromeId: 'P003', techniqueId: 'TQ-007', source: 'user_request' },
    ]);
  });

  it('training_triggered → setActiveTraining 不再调用 markTrainingIntent (G-1 替换占位)', () => {
    const configPath = writeTempConfig(f2Config);
    const { service, calls } = createFakeService();
    const subscriber = new TeachingStateSubscriber(service, configPath);

    subscriber.handle(
      {
        type: 'training_triggered',
        payload: {
          sessionId: 'sess-f2-2',
          syndromeId: 'P005',
          reason: 'diagnosis_result',
        },
      },
      'sess-f2-2',
    );

    // G-1: setActiveTraining 被调用
    expect(calls.setActiveTraining).toHaveLength(1);
    expect(calls.setActiveTraining[0]).toEqual({
      sessionId: 'sess-f2-2',
      syndromeId: 'P005',
      techniqueId: undefined,
      source: 'diagnosis_result',
    });
    // G-1: 原 Sprint 22 F-2 占位的 markTrainingIntent 不再被调用
    expect(calls.markTrainingIntent).toHaveLength(0);
  });

  it('training_triggered → 移除 F-2 占位 console.info (G-1 真实实现不再需要占位标注)', () => {
    const configPath = writeTempConfig(f2Config);
    const infoSpy = vi.mocked(console.info);
    infoSpy.mockClear();
    const { service } = createFakeService();
    const subscriber = new TeachingStateSubscriber(service, configPath);

    subscriber.handle(
      {
        type: 'training_triggered',
        payload: {
          sessionId: 'sess-f2-3',
          syndromeId: 'P005',
          reason: 'diagnosis_result',
        },
      },
      'sess-f2-3',
    );

    // G-1: 真实 setActiveTraining 替代了 F-2 占位 console.info
    // 不再输出 "S23+ 接入主进程" 占位标注
    const trainingTriggeredInfoCalls = infoSpy.mock.calls.filter((call) => {
      const msg = call[0];
      return typeof msg === 'string' && msg.includes('training_triggered received');
    });
    expect(trainingTriggeredInfoCalls).toHaveLength(0);
  });

  it('training_triggered → techniqueId 缺省 → setActiveTraining source 透传', () => {
    const configPath = writeTempConfig(f2Config);
    const { service, calls } = createFakeService();
    const subscriber = new TeachingStateSubscriber(service, configPath);

    subscriber.handle(
      {
        type: 'training_triggered',
        payload: {
          sessionId: 'sess-f2-3b',
          syndromeId: 'P001',
          reason: 'user_request',
        },
      },
      'sess-f2-3b',
    );

    expect(calls.setActiveTraining).toHaveLength(1);
    expect(calls.setActiveTraining[0].techniqueId).toBeUndefined();
    expect(calls.setActiveTraining[0].source).toBe('user_request');
  });

  it('phase_transition + training_triggered 互不干扰', () => {
    const configPath = writeTempConfig(f2Config);
    const { service, calls } = createFakeService();
    const subscriber = new TeachingStateSubscriber(service, configPath);

    subscriber.handle(
      {
        type: 'phase_transition',
        payload: { from: 'requirement', to: 'diagnosis', reason: 'symptoms_detected:2' },
      },
      'sess-f2-4',
    );
    subscriber.handle(
      {
        type: 'training_triggered',
        payload: { sessionId: 'sess-f2-4', syndromeId: 'P003', reason: 'user_request' },
      },
      'sess-f2-4',
    );

    expect(calls.confirmPhase).toEqual([{ sessionId: 'sess-f2-4' }]);
    expect(calls.setActiveTraining).toEqual([
      { sessionId: 'sess-f2-4', syndromeId: 'P003', techniqueId: undefined, source: 'user_request' },
    ]);
  });
});
