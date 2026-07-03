/**
 * TeachingStateSubscriber F-2 单测 — Sprint 22
 *
 * 覆盖 training_triggered enabled 后行为(承接 D-2 disabled 状态):
 * 1. training_triggered 事件触发 handleSetActiveTraining → markTrainingIntent + console.info
 * 2. console.info 标注 S23+ 接入主进程
 * 3. payload 字段全部透传
 * 4. 与 phase_transition 同时触发不互相干扰
 *
 * DoD: ≥3 单测
 * 依据: dev-docs/tasks/sprint-22-plan.md §F-2
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import { TeachingStateSubscriber } from '../teaching-state-subscriber';
import type { TeachingStateService } from '../../teaching-state.service';

function writeTempConfig(content: unknown): string {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tss-f2-'));
  const file = path.join(dir, 'state-machine-event-mapping.json');
  fs.writeFileSync(file, JSON.stringify(content), 'utf-8');
  return file;
}

interface FakeCalls {
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
    markTrainingIntent: [],
    confirmPhase: [],
    recordProblem: [],
  };
  const service = {
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

describe('TeachingStateSubscriber training_triggered enabled (Sprint 22 F-2)', () => {
  beforeEach(() => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    vi.spyOn(console, 'info').mockImplementation(() => {});
  });

  it('training_triggered → markTrainingIntent 透传 syndromeId/techniqueId', () => {
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

    expect(calls.markTrainingIntent).toEqual([
      { sessionId: 'sess-f2-1', syndromeId: 'P003', techniqueId: 'TQ-007' },
    ]);
  });

  it('training_triggered → console.info 标注 S23+ 接入主进程', () => {
    const configPath = writeTempConfig(f2Config);
    const infoSpy = vi.mocked(console.info);
    infoSpy.mockClear();
    const { service } = createFakeService();
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

    expect(infoSpy).toHaveBeenCalled();
    const message = infoSpy.mock.calls[0]?.[0] as string;
    expect(message).toContain('training_triggered received');
    expect(message).toContain('syndrome=P005');
    expect(message).toContain('reason=diagnosis_result');
    expect(message).toContain('S23+');
  });

  it('training_triggered → techniqueId 缺省 → console.info 显示 "none"', () => {
    const configPath = writeTempConfig(f2Config);
    const infoSpy = vi.mocked(console.info);
    infoSpy.mockClear();
    const { service, calls } = createFakeService();
    const subscriber = new TeachingStateSubscriber(service, configPath);

    subscriber.handle(
      {
        type: 'training_triggered',
        payload: {
          sessionId: 'sess-f2-3',
          syndromeId: 'P001',
          reason: 'user_request',
        },
      },
      'sess-f2-3',
    );

    expect(calls.markTrainingIntent).toHaveLength(1);
    expect(calls.markTrainingIntent[0].techniqueId).toBeUndefined();
    const message = infoSpy.mock.calls[0]?.[0] as string;
    expect(message).toContain('technique=none');
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
    expect(calls.markTrainingIntent).toEqual([{ sessionId: 'sess-f2-4', syndromeId: 'P003', techniqueId: undefined }]);
  });
});
