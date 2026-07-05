/**
 * TeachingStateSubscriber D-2 单测 — Sprint 21 D-2
 *
 * 验证:
 * 1. config 加载(默认路径 + 自定义路径)
 * 2. config 解析失败 → fallback 空 mapping,不崩
 * 3. intent:train → markTrainingIntent 触发(且 A-3 兼容 getContext)
 * 4. diagnosis_extracted → recordProblem 触发
 * 5. disabled action → 跳过(不调 service)
 * 6. 未知 eventType → 跳过
 * 7. service 抛错 → 异常隔离,不影响主流程
 * 8. A-3 兼容:既有 lastTrainEvent 记录仍工作
 * 9. eventTypeOf 正确解析 intent:* 复合形式
 * 10. phase_transition / training_triggered 暂 disabled 但 switch case 兜底
 *
 * DoD: ≥5 单测
 * 依据: dev-docs/tasks/sprint-21-plan.md §D-2
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import { TeachingStateSubscriber } from '../teaching-state-subscriber';
import type { OrchestratorEvent } from '../orchestrator.types';
import type { TeachingStateService } from '../../teaching-state.service';

// ─── 辅助:写入临时 config JSON ───
function writeTempConfig(content: unknown): string {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tss-config-'));
  const file = path.join(dir, 'state-machine-event-mapping.json');
  fs.writeFileSync(file, JSON.stringify(content), 'utf-8');
  return file;
}

// ─── 辅助:构造 fake TeachingStateService(只关心被调用的方法) ───
interface FakeTeachingStateCalls {
  markTrainingIntent: Array<{ sessionId: string; syndromeId: string; techniqueId?: string }>;
  recordProblem: Array<{ sessionId: string; syndromeId: string; severity: string | null; evidence: string }>;
  getContext: Array<{ sessionId: string }>;
  confirmPhase: Array<{ sessionId: string }>;
}

const createFakeService = (overrides: Partial<{
  markTrainingIntent: () => void;
  recordProblem: () => void;
  getContext: () => void;
  confirmPhase: () => void;
}> = {}): { service: TeachingStateService; calls: FakeTeachingStateCalls } => {
  const calls: FakeTeachingStateCalls = {
    markTrainingIntent: [],
    recordProblem: [],
    getContext: [],
    confirmPhase: [],
  };
  const service = {
    markTrainingIntent: (sessionId: string, syndromeId: string, techniqueId?: string) => {
      calls.markTrainingIntent.push({ sessionId, syndromeId, techniqueId });
      overrides.markTrainingIntent?.();
    },
    recordProblem: (sessionId: string, syndromeId: string, severity: 'L1' | 'L2' | 'L3' | null, evidence: string) => {
      calls.recordProblem.push({ sessionId, syndromeId, severity, evidence });
      overrides.recordProblem?.();
    },
    getContext: (sessionId: string) => {
      calls.getContext.push({ sessionId });
      overrides.getContext?.();
      return { currentPhase: 'P1', currentSubphase: null, activeProblems: [] };
    },
    confirmPhase: (sessionId: string) => {
      calls.confirmPhase.push({ sessionId });
      overrides.confirmPhase?.();
      return { oldState: {} as never, newState: {} as never };
    },
  } as unknown as TeachingStateService;
  return { service, calls };
};

const baseConfig = {
  version: '1.0',
  subscribers: [
    { eventType: 'intent:train', action: 'markTrainingIntent', enabled: true },
    { eventType: 'diagnosis_extracted', action: 'recordProblem', enabled: true },
    { eventType: 'phase_transition', action: 'confirmPhase', enabled: false },
    { eventType: 'training_triggered', action: 'setActiveTraining', enabled: false },
  ],
};

describe('TeachingStateSubscriber (Sprint 21 D-2)', () => {
  beforeEach(() => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});
  });

  it('加载自定义 config + 解析为 SubscriberMapping[]', () => {
    const configPath = writeTempConfig(baseConfig);
    const { service } = createFakeService();
    const subscriber = new TeachingStateSubscriber(service, configPath);

    const mapping = subscriber.getMapping();
    expect(mapping).toHaveLength(4);
    expect(mapping[0]).toEqual({ eventType: 'intent:train', action: 'markTrainingIntent', enabled: true });
    expect(mapping[2].enabled).toBe(false);
  });

  it('config 文件不存在 → fallback 空 mapping,handle 不崩', () => {
    const { service, calls } = createFakeService();
    const subscriber = new TeachingStateSubscriber(service, '/non/existent/path.json');

    expect(subscriber.getMapping()).toEqual([]);
    // 任意事件都不应触发任何 service 调用
    subscriber.handle(
      { type: 'intent', payload: { type: 'train', syndromeId: 'P001' } },
      'sess-fallback',
    );
    expect(calls.markTrainingIntent).toHaveLength(0);
  });

  it('intent:train → markTrainingIntent 触发 + A-3 兼容 getContext', () => {
    const configPath = writeTempConfig(baseConfig);
    const { service, calls } = createFakeService();
    const subscriber = new TeachingStateSubscriber(service, configPath);

    subscriber.handle(
      { type: 'intent', payload: { type: 'train', syndromeId: 'P003', techniqueId: 'TQ-005' } },
      'sess-train-1',
    );

    expect(calls.markTrainingIntent).toEqual([
      { sessionId: 'sess-train-1', syndromeId: 'P003', techniqueId: 'TQ-005' },
    ]);
    expect(calls.getContext).toHaveLength(1);
    // A-3 兼容:lastTrainEvent 仍记录
    const last = subscriber.getLastTrainEvent();
    expect(last?.syndromeId).toBe('P003');
    expect(last?.techniqueId).toBe('TQ-005');
  });

  it('diagnosis_extracted → recordProblem 触发(severity 透传)', () => {
    const configPath = writeTempConfig(baseConfig);
    const { service, calls } = createFakeService();
    const subscriber = new TeachingStateSubscriber(service, configPath);

    subscriber.handle(
      {
        type: 'diagnosis_extracted',
        payload: {
          syndromeId: 'P002',
          severity: 'L2',
          evidenceQuote: '"世界观单薄"',
        },
      },
      'sess-diag-1',
    );

    expect(calls.recordProblem).toEqual([
      { sessionId: 'sess-diag-1', syndromeId: 'P002', severity: 'L2', evidence: '"世界观单薄"' },
    ]);
    const last = subscriber.getLastDiagnosisRecord();
    expect(last?.syndromeId).toBe('P002');
  });

  it('diagnosis_extracted severity=null → recordProblem 仍被调用(null 透传)', () => {
    const configPath = writeTempConfig(baseConfig);
    const { service, calls } = createFakeService();
    const subscriber = new TeachingStateSubscriber(service, configPath);

    subscriber.handle(
      {
        type: 'diagnosis_extracted',
        payload: { syndromeId: 'P005', severity: null, evidenceQuote: 'text' },
      },
      'sess-null',
    );

    expect(calls.recordProblem).toHaveLength(1);
    expect(calls.recordProblem[0].severity).toBeNull();
  });

  it('disabled action 跳过:phase_transition → 不调 confirmPhase', () => {
    const configPath = writeTempConfig(baseConfig);
    const { service, calls } = createFakeService();
    const subscriber = new TeachingStateSubscriber(service, configPath);

    subscriber.handle(
      {
        type: 'phase_transition',
        payload: { from: 'trust_building', to: 'requirement', reason: 'test' },
      },
      'sess-disabled',
    );

    expect(calls.confirmPhase).toHaveLength(0);
  });

  it('未知 eventType 跳过:token / done 不触发任何 action', () => {
    const configPath = writeTempConfig(baseConfig);
    const { service, calls } = createFakeService();
    const subscriber = new TeachingStateSubscriber(service, configPath);

    const events: OrchestratorEvent[] = [
      { type: 'token', content: 'hi' },
      { type: 'done' },
      { type: 'error', payload: { code: 'API_ERROR', message: 'x', retryable: false } },
      { type: 'intent', payload: { type: 'none' } }, // intent:none 不在 mapping
    ];
    for (const ev of events) subscriber.handle(ev, 'sess-unknown');

    expect(calls.markTrainingIntent).toHaveLength(0);
    expect(calls.recordProblem).toHaveLength(0);
    expect(calls.getContext).toHaveLength(0);
  });

  it('service 抛错 → 异常隔离,不影响主流程 + 不冒泡到 handle', () => {
    const configPath = writeTempConfig(baseConfig);
    const { service } = createFakeService({
      markTrainingIntent: () => {
        throw new Error('db down');
      },
    });
    const subscriber = new TeachingStateSubscriber(service, configPath);

    expect(() => {
      subscriber.handle(
        { type: 'intent', payload: { type: 'train', syndromeId: 'P001' } },
        'sess-err',
      );
    }).not.toThrow();

    // A-3 兼容:即使 markTrainingIntent 抛错,lastTrainEvent 仍记录(在抛错前)
    const last = subscriber.getLastTrainEvent();
    expect(last?.syndromeId).toBe('P001');
  });

  it('recordProblem 抛错 → 异常隔离', () => {
    const configPath = writeTempConfig(baseConfig);
    const { service } = createFakeService({
      recordProblem: () => {
        throw new Error('store lock');
      },
    });
    const subscriber = new TeachingStateSubscriber(service, configPath);

    expect(() => {
      subscriber.handle(
        {
          type: 'diagnosis_extracted',
          payload: { syndromeId: 'P001', severity: 'L1', evidenceQuote: 'q' },
        },
        'sess-err-2',
      );
    }).not.toThrow();

    // lastDiagnosisRecord 仍记录(在抛错前)
    const last = subscriber.getLastDiagnosisRecord();
    expect(last?.syndromeId).toBe('P001');
  });

  it('config 解析为非法 JSON → fallback 空 mapping', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tss-bad-'));
    const file = path.join(dir, 'state-machine-event-mapping.json');
    fs.writeFileSync(file, '{ invalid json', 'utf-8');

    const { service } = createFakeService();
    const subscriber = new TeachingStateSubscriber(service, file);

    expect(subscriber.getMapping()).toEqual([]);
  });

  it('config 无 subscribers 字段 → fallback 空 mapping', () => {
    const configPath = writeTempConfig({ version: '1.0' });
    const { service } = createFakeService();
    const subscriber = new TeachingStateSubscriber(service, configPath);

    expect(subscriber.getMapping()).toEqual([]);
  });

  it('多次 intent:train 事件 → lastTrainEvent 只保留最近一次', () => {
    const configPath = writeTempConfig(baseConfig);
    const { service, calls } = createFakeService();
    const subscriber = new TeachingStateSubscriber(service, configPath);

    subscriber.handle({ type: 'intent', payload: { type: 'train', syndromeId: 'P001' } }, 'sess-A');
    subscriber.handle({ type: 'intent', payload: { type: 'train', syndromeId: 'P002' } }, 'sess-B');
    subscriber.handle({ type: 'intent', payload: { type: 'train', syndromeId: 'P003' } }, 'sess-C');

    const last = subscriber.getLastTrainEvent();
    expect(last?.sessionId).toBe('sess-C');
    expect(last?.syndromeId).toBe('P003');
    expect(calls.markTrainingIntent).toHaveLength(3);
  });

  it('intensity 多次触发 recordProblem → 累加(由 service 实现,subscriber 透明转发)', () => {
    const configPath = writeTempConfig(baseConfig);
    const { service, calls } = createFakeService();
    const subscriber = new TeachingStateSubscriber(service, configPath);

    subscriber.handle(
      { type: 'diagnosis_extracted', payload: { syndromeId: 'P001', severity: 'L1', evidenceQuote: 'q1' } },
      'sess-loop',
    );
    subscriber.handle(
      { type: 'diagnosis_extracted', payload: { syndromeId: 'P001', severity: 'L2', evidenceQuote: 'q2' } },
      'sess-loop',
    );

    expect(calls.recordProblem).toHaveLength(2);
    expect(calls.recordProblem[0].severity).toBe('L1');
    expect(calls.recordProblem[1].severity).toBe('L2');
  });
});
