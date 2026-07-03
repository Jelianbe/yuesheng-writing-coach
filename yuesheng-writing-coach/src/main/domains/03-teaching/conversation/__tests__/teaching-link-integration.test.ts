/**
 * 教学链路集成测试 — Sprint 22 F-3 + Sprint 23 G-1 更新
 *
 * 覆盖完整事件流:
 * 1. 诊断发现症候 → phase_transition 事件 → TeachingStateService.confirmPhase
 * 2. 用户消息含训练意图 + 诊断有症候 → training_triggered 事件 → setActiveTraining (G-1 替换)
 * 3. 无训练意图时不触发 setActiveTraining
 * 4. 事件去重:5 秒内同 sessionId 不重复触发
 * 5. 完整教学链路串联 (phase_transition + training_triggered)
 * 6. setActiveTraining 写入 activeTrainingMeta 字段(G-1 新增)
 *
 * 策略:
 * - 实例化真实 ChatOrchestratorService + 真实 TeachingStateSubscriber
 * - TeachingStateService 用 fake(替代 SQLite store)
 * - 验证 subscriber.handle 接收事件后的 state 变化
 *
 * Sprint 23 G-1 改造:
 * - 训练触发 action 从 markTrainingIntent 改为 setActiveTraining
 * - 验证 lastUserConfirmation → activeTrainingMeta (业务元数据)
 *
 * DoD: ≥5 用例
 * 依据: dev-docs/tasks/sprint-22-plan.md §F-3 + dev-docs/tasks/sprint-23-plan.md §G-1
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import { ChatOrchestratorService } from '../../chat/chat-orchestrator.service';
import { TeachingStateSubscriber } from '../teaching-state-subscriber';
import type { ChatOrchestratorDeps } from '../../chat/chat-orchestrator.service';
import type { TeachingStateService } from '../../teaching-state.service';
import type { ActiveTrainingMeta } from '../../../../../shared/types/index';

function writeTempConfig(content: unknown): string {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'teaching-link-'));
  const file = path.join(dir, 'state-machine-event-mapping.json');
  fs.writeFileSync(file, JSON.stringify(content), 'utf-8');
  return file;
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

/** In-memory state 模拟 SQLite store */
function createFakeStateStore(): {
  store: Map<string, { lastUserConfirmation: string | null; currentPhase: string | null; activeTrainingMeta: ActiveTrainingMeta | null }>;
  getBySession: (sid: string) => { lastUserConfirmation: string | null; currentPhase: string | null; activeTrainingMeta: ActiveTrainingMeta | null } | null;
  update: (sid: string, patch: Partial<{ lastUserConfirmation: string | null; currentPhase: string | null; activeTrainingMeta: ActiveTrainingMeta | null }>) => void;
} {
  const store = new Map<string, { lastUserConfirmation: string | null; currentPhase: string | null; activeTrainingMeta: ActiveTrainingMeta | null }>();
  return {
    store,
    getBySession: (sid) => store.get(sid) ?? null,
    update: (sid, patch) => {
      const cur = store.get(sid) ?? { lastUserConfirmation: null, currentPhase: 'P1', activeTrainingMeta: null };
      store.set(sid, { ...cur, ...patch });
    },
  };
}

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

interface FakeTeachingStateService {
  service: TeachingStateService;
  calls: {
    setActiveTraining: Array<{ sessionId: string; syndromeId: string; techniqueId?: string; source: ActiveTrainingMeta['source'] }>;
    markTrainingIntent: Array<{ sessionId: string; syndromeId: string; techniqueId?: string }>;
    confirmPhase: Array<{ sessionId: string }>;
    recordProblem: Array<{ sessionId: string; syndromeId: string }>;
  };
  store: ReturnType<typeof createFakeStateStore>;
}

function createFakeTeachingStateService(): FakeTeachingStateService {
  const store = createFakeStateStore();
  const calls: FakeTeachingStateService['calls'] = {
    setActiveTraining: [],
    markTrainingIntent: [],
    confirmPhase: [],
    recordProblem: [],
  };
  const service = {
    // Sprint 23 G-1: setActiveTraining 替代 markTrainingIntent (training_triggered 路径)
    setActiveTraining: (
      sessionId: string,
      syndromeId: string,
      techniqueId: string | undefined,
      source: ActiveTrainingMeta['source'],
    ) => {
      calls.setActiveTraining.push({ sessionId, syndromeId, techniqueId, source });
      const meta: ActiveTrainingMeta = {
        syndromeId,
        techniqueId,
        triggeredAt: new Date().toISOString(),
        source,
      };
      store.update(sessionId, { activeTrainingMeta: meta });
    },
    // Sprint 21 D-2 保留: markTrainingIntent 仍服务于 intent:train 事件(语义不同)
    markTrainingIntent: (sessionId: string, syndromeId: string, techniqueId?: string) => {
      calls.markTrainingIntent.push({ sessionId, syndromeId, techniqueId });
      const stamp = new Date().toISOString();
      const confirmation = techniqueId
        ? `train:${syndromeId}:${techniqueId}:${stamp}`
        : `train:${syndromeId}:${stamp}`;
      store.update(sessionId, { lastUserConfirmation: confirmation });
    },
    recordProblem: (sessionId: string, syndromeId: string) => {
      calls.recordProblem.push({ sessionId, syndromeId });
    },
    confirmPhase: (sessionId: string) => {
      calls.confirmPhase.push({ sessionId });
      const cur = store.getBySession(sessionId) ?? { lastUserConfirmation: null, currentPhase: 'P1', activeTrainingMeta: null };
      store.update(sessionId, { currentPhase: 'P2' });
      return { oldState: cur, newState: store.getBySession(sessionId) };
    },
    getStore: () => store,
  } as unknown as TeachingStateService;
  return { service, calls, store };
}

describe('教学链路集成 (Sprint 22 F-3 + Sprint 23 G-1 更新)', () => {
  beforeEach(() => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    vi.spyOn(console, 'info').mockImplementation(() => {});
  });

  it('完整链路 1:诊断发现症候 → phase_transition → confirmPhase', () => {
    const configPath = writeTempConfig(f2Config);
    const mockDeps = createMockDeps();
    const svc = new ChatOrchestratorService(mockDeps);
    const { service, calls, store } = createFakeTeachingStateService();
    store.update('sess-link-1', { lastUserConfirmation: null, currentPhase: 'P1', activeTrainingMeta: null });
    const subscriber = new TeachingStateSubscriber(service, configPath);
    svc.onOrchestratorEvent((e, sid) => subscriber.handle(e, sid));

    (svc as unknown as {
      emitPhaseTransitionIfNeeded: (sid: string, a: { syndromeRef?: string[] }) => void;
    }).emitPhaseTransitionIfNeeded('sess-link-1', { syndromeRef: ['P003', 'P005'] });

    expect(calls.confirmPhase).toHaveLength(1);
    expect(calls.confirmPhase[0].sessionId).toBe('sess-link-1');
    expect(store.getBySession('sess-link-1')?.currentPhase).toBe('P2');
  });

  it('完整链路 2:训练意图消息 → training_triggered → setActiveTraining → activeTrainingMeta 写入 (G-1)', async () => {
    const configPath = writeTempConfig(f2Config);
    const mockDeps = createMockDeps();
    const svc = new ChatOrchestratorService(mockDeps);
    const { service, calls, store } = createFakeTeachingStateService();
    store.update('sess-link-2', { lastUserConfirmation: null, currentPhase: 'P1', activeTrainingMeta: null });
    const subscriber = new TeachingStateSubscriber(service, configPath);
    svc.onOrchestratorEvent((e, sid) => subscriber.handle(e, sid));

    await (svc as unknown as {
      emitTrainingTriggeredIfNeeded: (
        sid: string,
        msg: string,
        a: { syndromeRef?: string[] },
      ) => Promise<void>;
    }).emitTrainingTriggeredIfNeeded('sess-link-2', '帮我训练这个', { syndromeRef: ['P003'] });

    // G-1: setActiveTraining 被调用,markTrainingIntent 不被调用
    expect(calls.setActiveTraining).toHaveLength(1);
    expect(calls.setActiveTraining[0]).toEqual({
      sessionId: 'sess-link-2',
      syndromeId: 'P003',
      techniqueId: undefined,
      source: 'user_request',
    });
    expect(calls.markTrainingIntent).toHaveLength(0);

    // G-1: 验证 activeTrainingMeta 字段写入
    const meta = store.getBySession('sess-link-2')?.activeTrainingMeta;
    expect(meta).not.toBeNull();
    expect(meta?.syndromeId).toBe('P003');
    expect(meta?.source).toBe('user_request');
    expect(meta?.triggeredAt).toMatch(/^\d{4}-\d{2}-\d{2}T/);
  });

  it('完整链路 3:无训练意图时不触发 setActiveTraining', async () => {
    const configPath = writeTempConfig(f2Config);
    const mockDeps = createMockDeps();
    const svc = new ChatOrchestratorService(mockDeps);
    const { service, calls, store } = createFakeTeachingStateService();
    store.update('sess-link-3', { lastUserConfirmation: null, currentPhase: 'P1', activeTrainingMeta: null });
    const subscriber = new TeachingStateSubscriber(service, configPath);
    svc.onOrchestratorEvent((e, sid) => subscriber.handle(e, sid));

    await (svc as unknown as {
      emitTrainingTriggeredIfNeeded: (
        sid: string,
        msg: string,
        a: { syndromeRef?: string[] },
      ) => Promise<void>;
    }).emitTrainingTriggeredIfNeeded('sess-link-3', '我觉得节奏有点乱', { syndromeRef: ['P003'] });

    expect(calls.setActiveTraining).toHaveLength(0);
    expect(store.getBySession('sess-link-3')?.activeTrainingMeta).toBeNull();
  });

  it('完整链路 4:训练触发 5 秒去重 + 不同 session 互不干扰', async () => {
    const configPath = writeTempConfig(f2Config);
    const mockDeps = createMockDeps();
    const svc = new ChatOrchestratorService(mockDeps);
    const { service, calls, store } = createFakeTeachingStateService();
    store.update('sess-link-4a', { lastUserConfirmation: null, currentPhase: 'P1', activeTrainingMeta: null });
    store.update('sess-link-4b', { lastUserConfirmation: null, currentPhase: 'P1', activeTrainingMeta: null });
    const subscriber = new TeachingStateSubscriber(service, configPath);
    svc.onOrchestratorEvent((e, sid) => subscriber.handle(e, sid));

    const emit = (svc as unknown as {
      emitTrainingTriggeredIfNeeded: (
        sid: string,
        msg: string,
        a: { syndromeRef?: string[] },
      ) => Promise<void>;
    }).emitTrainingTriggeredIfNeeded.bind(svc);

    await emit('sess-link-4a', '帮我训练', { syndromeRef: ['P001'] });
    await emit('sess-link-4a', '练一下', { syndromeRef: ['P001'] });
    await emit('sess-link-4b', '帮我训练', { syndromeRef: ['P002'] });

    expect(calls.setActiveTraining).toHaveLength(2);
    expect(calls.setActiveTraining[0].sessionId).toBe('sess-link-4a');
    expect(calls.setActiveTraining[1].sessionId).toBe('sess-link-4b');
  });

  it('完整链路 5:phase_transition + training_triggered 串联,完整教学链路', async () => {
    const configPath = writeTempConfig(f2Config);
    const mockDeps = createMockDeps();
    const svc = new ChatOrchestratorService(mockDeps);
    const { service, calls, store } = createFakeTeachingStateService();
    store.update('sess-link-5', { lastUserConfirmation: null, currentPhase: 'P1', activeTrainingMeta: null });
    const subscriber = new TeachingStateSubscriber(service, configPath);
    svc.onOrchestratorEvent((e, sid) => subscriber.handle(e, sid));

    const emitPhase = (svc as unknown as {
      emitPhaseTransitionIfNeeded: (sid: string, a: { syndromeRef?: string[] }) => void;
    }).emitPhaseTransitionIfNeeded.bind(svc);
    const emitTrain = (svc as unknown as {
      emitTrainingTriggeredIfNeeded: (
        sid: string,
        msg: string,
        a: { syndromeRef?: string[] },
      ) => Promise<void>;
    }).emitTrainingTriggeredIfNeeded.bind(svc);

    emitPhase('sess-link-5', { syndromeRef: ['P003'] });
    await emitTrain('sess-link-5', '帮我训练这个', { syndromeRef: ['P003'] });

    expect(calls.confirmPhase).toHaveLength(1);
    expect(calls.setActiveTraining).toHaveLength(1);
    const state = store.getBySession('sess-link-5');
    expect(state?.currentPhase).toBe('P2');
    expect(state?.activeTrainingMeta?.syndromeId).toBe('P003');
  });

  it('Sprint 23 G-1 新增:diagnosis_result reason → activeTrainingMeta.source 透传', () => {
    // 验证 TrainingTriggeredEvent.reason(diagnosis_result / user_request / prescription)完整透传
    const configPath = writeTempConfig(f2Config);
    const mockDeps = createMockDeps();
    const svc = new ChatOrchestratorService(mockDeps);
    const { service, calls, store } = createFakeTeachingStateService();
    store.update('sess-link-6', { lastUserConfirmation: null, currentPhase: 'P1', activeTrainingMeta: null });
    const subscriber = new TeachingStateSubscriber(service, configPath);
    svc.onOrchestratorEvent((e, sid) => subscriber.handle(e, sid));

    // 直接 emit 完整 reason (绕过 emitTrainingTriggeredIfNeeded,模拟其他触发路径)
    (svc as unknown as {
      emitOrchestratorEvent: (e: unknown, sid: string) => void;
    }).emitOrchestratorEvent({
      type: 'training_triggered',
      payload: {
        sessionId: 'sess-link-6',
        syndromeId: 'P005',
        techniqueId: 'TQ-007',
        reason: 'diagnosis_result',
      },
    }, 'sess-link-6');

    expect(calls.setActiveTraining).toHaveLength(1);
    expect(calls.setActiveTraining[0].source).toBe('diagnosis_result');
    expect(store.getBySession('sess-link-6')?.activeTrainingMeta?.source).toBe('diagnosis_result');
  });
});
