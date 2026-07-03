/**
 * 教学链路集成测试 — Sprint 22 F-3
 *
 * 覆盖完整事件流:
 * 1. 诊断发现症候 → phase_transition 事件 → TeachingStateService.confirmPhase
 * 2. 用户消息含训练意图 + 诊断有症候 → training_triggered 事件 → markTrainingIntent
 * 3. 无训练意图时不触发 training_triggered
 * 4. 事件去重:5 秒内同 sessionId 不重复触发
 *
 * 策略:
 * - 实例化真实 ChatOrchestratorService + 真实 TeachingStateSubscriber
 * - TeachingStateService 用 in-memory fake(替代 SQLite store)
 * - 验证 subscriber.handle 接收事件后的 state 变化
 *
 * 设计决策:
 * - 改用集成测试而非 Playwright E2E(R-010 最小化 + R-027 教训)
 * - 原因:playwright.config.ts 用 npm run dev:vite,无法验证主进程 IPC 链路
 * - 真正的 Electron E2E 框架推到 S23(与主进程侧 ActiveTraining 状态机一起)
 * - 当前 F-3 聚焦:验证 emit → subscriber → service 完整链路
 *
 * DoD: ≥4 用例
 * 依据: dev-docs/tasks/sprint-22-plan.md §F-3
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import { ChatOrchestratorService } from '../../chat/chat-orchestrator.service';
import { TeachingStateSubscriber } from '../teaching-state-subscriber';
import type { ChatOrchestratorDeps } from '../../chat/chat-orchestrator.service';
import type { TeachingStateService } from '../../teaching-state.service';

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

/** In-memory state 模拟 SQLite store,支持 lastUserConfirmation 读写 */
function createFakeStateStore(): {
  store: Map<string, { lastUserConfirmation: string | null; currentPhase: string | null }>;
  getBySession: (sid: string) => { lastUserConfirmation: string | null; currentPhase: string | null } | null;
  update: (sid: string, patch: Partial<{ lastUserConfirmation: string | null; currentPhase: string | null }>) => void;
} {
  const store = new Map<string, { lastUserConfirmation: string | null; currentPhase: string | null }>();
  return {
    store,
    getBySession: (sid) => store.get(sid) ?? null,
    update: (sid, patch) => {
      const cur = store.get(sid) ?? { lastUserConfirmation: null, currentPhase: 'P1' };
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
    markTrainingIntent: Array<{ sessionId: string; syndromeId: string; techniqueId?: string }>;
    confirmPhase: Array<{ sessionId: string }>;
    recordProblem: Array<{ sessionId: string; syndromeId: string }>;
  };
  store: ReturnType<typeof createFakeStateStore>;
}

function createFakeTeachingStateService(): FakeTeachingStateService {
  const store = createFakeStateStore();
  const calls: FakeTeachingStateService['calls'] = {
    markTrainingIntent: [],
    confirmPhase: [],
    recordProblem: [],
  };
  const service = {
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
      // 真实实现会推进 phase,这里也模拟一下
      const cur = store.getBySession(sessionId) ?? { lastUserConfirmation: null, currentPhase: 'P1' };
      store.update(sessionId, { currentPhase: 'P2' });
      return { oldState: cur, newState: store.getBySession(sessionId) };
    },
    getStore: () => store,
  } as unknown as TeachingStateService;
  return { service, calls, store };
}

describe('教学链路集成 (Sprint 22 F-3)', () => {
  beforeEach(() => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    vi.spyOn(console, 'info').mockImplementation(() => {});
  });

  it('完整链路 1:诊断发现症候 → phase_transition → confirmPhase', () => {
    // Arrange
    const configPath = writeTempConfig(f2Config);
    const mockDeps = createMockDeps();
    const svc = new ChatOrchestratorService(mockDeps);
    const { service, calls, store } = createFakeTeachingStateService();
    // 预置 session state
    store.update('sess-link-1', { lastUserConfirmation: null, currentPhase: 'P1' });
    const subscriber = new TeachingStateSubscriber(service, configPath);
    svc.onOrchestratorEvent((e, sid) => subscriber.handle(e, sid));

    // Act: 模拟 ChatOrchestrator 诊断完成 emit phase_transition
    (svc as unknown as {
      emitPhaseTransitionIfNeeded: (sid: string, a: { syndromeRef?: string[] }) => void;
    }).emitPhaseTransitionIfNeeded('sess-link-1', { syndromeRef: ['P003', 'P005'] });

    // Assert
    expect(calls.confirmPhase).toHaveLength(1);
    expect(calls.confirmPhase[0].sessionId).toBe('sess-link-1');
    // 状态机写入
    expect(store.getBySession('sess-link-1')?.currentPhase).toBe('P2');
  });

  it('完整链路 2:训练意图消息 → training_triggered → markTrainingIntent → lastUserConfirmation 格式正确', () => {
    // Arrange
    const configPath = writeTempConfig(f2Config);
    const mockDeps = createMockDeps();
    const svc = new ChatOrchestratorService(mockDeps);
    const { service, calls, store } = createFakeTeachingStateService();
    store.update('sess-link-2', { lastUserConfirmation: null, currentPhase: 'P1' });
    const subscriber = new TeachingStateSubscriber(service, configPath);
    svc.onOrchestratorEvent((e, sid) => subscriber.handle(e, sid));

    // Act: 用户消息含训练意图 + 诊断有症候
    (svc as unknown as {
      emitTrainingTriggeredIfNeeded: (
        sid: string,
        msg: string,
        a: { syndromeRef?: string[] },
      ) => void;
    }).emitTrainingTriggeredIfNeeded('sess-link-2', '帮我训练这个', { syndromeRef: ['P003'] });

    // Assert
    expect(calls.markTrainingIntent).toHaveLength(1);
    expect(calls.markTrainingIntent[0]).toEqual({
      sessionId: 'sess-link-2',
      syndromeId: 'P003',
      techniqueId: undefined,
    });
    // 验证 lastUserConfirmation 格式: train:P003:timestamp
    const lastConfirm = store.getBySession('sess-link-2')?.lastUserConfirmation;
    expect(lastConfirm).toMatch(/^train:P003:\d{4}-\d{2}-\d{2}T/);
  });

  it('完整链路 3:无训练意图时不触发 markTrainingIntent', () => {
    // Arrange
    const configPath = writeTempConfig(f2Config);
    const mockDeps = createMockDeps();
    const svc = new ChatOrchestratorService(mockDeps);
    const { service, calls, store } = createFakeTeachingStateService();
    store.update('sess-link-3', { lastUserConfirmation: null, currentPhase: 'P1' });
    const subscriber = new TeachingStateSubscriber(service, configPath);
    svc.onOrchestratorEvent((e, sid) => subscriber.handle(e, sid));

    // Act: 用户只描述症状,不提训练
    (svc as unknown as {
      emitTrainingTriggeredIfNeeded: (
        sid: string,
        msg: string,
        a: { syndromeRef?: string[] },
      ) => void;
    }).emitTrainingTriggeredIfNeeded('sess-link-3', '我觉得节奏有点乱', { syndromeRef: ['P003'] });

    // Assert
    expect(calls.markTrainingIntent).toHaveLength(0);
    expect(store.getBySession('sess-link-3')?.lastUserConfirmation).toBeNull();
  });

  it('完整链路 4:训练触发 5 秒去重 + 不同 session 互不干扰', () => {
    // Arrange
    const configPath = writeTempConfig(f2Config);
    const mockDeps = createMockDeps();
    const svc = new ChatOrchestratorService(mockDeps);
    const { service, calls, store } = createFakeTeachingStateService();
    store.update('sess-link-4a', { lastUserConfirmation: null, currentPhase: 'P1' });
    store.update('sess-link-4b', { lastUserConfirmation: null, currentPhase: 'P1' });
    const subscriber = new TeachingStateSubscriber(service, configPath);
    svc.onOrchestratorEvent((e, sid) => subscriber.handle(e, sid));

    const emit = (svc as unknown as {
      emitTrainingTriggeredIfNeeded: (
        sid: string,
        msg: string,
        a: { syndromeRef?: string[] },
      ) => void;
    }).emitTrainingTriggeredIfNeeded.bind(svc);

    // Act
    emit('sess-link-4a', '帮我训练', { syndromeRef: ['P001'] });
    emit('sess-link-4a', '练一下', { syndromeRef: ['P001'] }); // 去重
    emit('sess-link-4b', '帮我训练', { syndromeRef: ['P002'] }); // 不同 session,独立触发

    // Assert
    expect(calls.markTrainingIntent).toHaveLength(2);
    expect(calls.markTrainingIntent[0].sessionId).toBe('sess-link-4a');
    expect(calls.markTrainingIntent[1].sessionId).toBe('sess-link-4b');
  });

  it('完整链路 5:phase_transition + training_triggered 串联,完整教学链路', () => {
    // Arrange
    const configPath = writeTempConfig(f2Config);
    const mockDeps = createMockDeps();
    const svc = new ChatOrchestratorService(mockDeps);
    const { service, calls, store } = createFakeTeachingStateService();
    store.update('sess-link-5', { lastUserConfirmation: null, currentPhase: 'P1' });
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
      ) => void;
    }).emitTrainingTriggeredIfNeeded.bind(svc);

    // Act: 完整教学链路 诊断 → phase推进 → 用户要求训练
    emitPhase('sess-link-5', { syndromeRef: ['P003'] });
    emitTrain('sess-link-5', '帮我训练这个', { syndromeRef: ['P003'] });

    // Assert
    expect(calls.confirmPhase).toHaveLength(1);
    expect(calls.markTrainingIntent).toHaveLength(1);
    // 状态机最终态
    const state = store.getBySession('sess-link-5');
    expect(state?.currentPhase).toBe('P2');
    expect(state?.lastUserConfirmation).toMatch(/^train:P003:/);
  });
});
