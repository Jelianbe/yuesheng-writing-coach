/**
 * ActiveTraining 集成测试 — Sprint 24 A-2
 *
 * 端到端事件流:
 * ChatOrchestratorService.emitTrainingTriggeredIfNeeded
 *   → emit training_triggered
 *   → TeachingStateSubscriber.handle
 *   → setActiveTraining (G-1 轻量元数据) + startActiveTraining (A-2 完整状态机)
 *   → ActiveTrainingService.start → ActiveTrainingStore → SQLite
 *
 * 覆盖:
 * 1. 完整事件链 → active_training 表真的有数据
 * 2. state machine 转换: start → advanceStep → evaluate → complete
 * 3. 状态机边界: complete 后 advanceStep 拒绝
 * 4. 完整事件链 → abort 状态写入
 * 5. 5 秒去重: 同 session 重复 trigger 不会创建多行
 *
 * DoD: ≥5 用例
 * 依据: dev-docs/tasks/sprint-24-plan.md §A-2
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import Database from 'better-sqlite3';
import { ChatOrchestratorService } from '../../chat/chat-orchestrator.service';
import { TeachingStateSubscriber } from '../teaching-state-subscriber';
import { ActiveTrainingStore } from '../../state/active-training.store';
import { ActiveTrainingService } from '../../state/active-training.service';
import type { ChatOrchestratorDeps } from '../../chat/chat-orchestrator.service';
import type { TeachingStateService } from '../../teaching-state.service';

function writeTempConfig(content: unknown): string {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'at-integration-'));
  const file = path.join(dir, 'state-machine-event-mapping.json');
  fs.writeFileSync(file, JSON.stringify(content), 'utf-8');
  return file;
}

const a2Config = {
  version: '1.1',
  subscribers: [
    { eventType: 'intent:train', action: 'markTrainingIntent', enabled: true },
    { eventType: 'diagnosis_extracted', action: 'recordProblem', enabled: true },
    { eventType: 'phase_transition', action: 'confirmPhase', enabled: true },
    { eventType: 'training_triggered', action: 'setActiveTraining', enabled: true },
    { eventType: 'training_triggered', action: 'startActiveTraining', enabled: true },
  ],
};

function createTestDb(): Database.Database {
  const db = new Database(':memory:');
  // 同时建立 teaching_state 和 active_training 两张表的 schema
  db.exec(`
    CREATE TABLE sessions (
      id TEXT PRIMARY KEY,
      title TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
    CREATE TABLE teaching_state (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id TEXT NOT NULL UNIQUE,
      current_phase TEXT,
      current_subphase TEXT,
      completed_actions TEXT,
      completed_tasks TEXT,
      active_problems TEXT,
      next_suggested_actions TEXT,
      current_task_id TEXT,
      diagnosis_summary TEXT,
      last_user_confirmation TEXT,
      focus_area TEXT,
      transition_offered INTEGER,
      locked_syndromes TEXT,
      active_training_meta TEXT,
      updated_at TEXT NOT NULL
    );
    CREATE TABLE active_training (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id TEXT NOT NULL,
      challenge_id TEXT NOT NULL,
      challenge_name TEXT,
      mode TEXT,
      current_step_index INTEGER NOT NULL DEFAULT 0,
      steps_json TEXT NOT NULL DEFAULT '[]',
      user_draft TEXT NOT NULL DEFAULT '',
      flow_type TEXT,
      training_flow_json TEXT,
      record_id TEXT,
      syndrome_id TEXT,
      original_quote TEXT,
      constraint_text TEXT,
      submission_result_json TEXT,
      step_responses_json TEXT NOT NULL DEFAULT '[]',
      status TEXT NOT NULL DEFAULT 'in_progress',
      started_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      completed_at TEXT,
      FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
    );
    CREATE UNIQUE INDEX idx_active_training_active_session
      ON active_training(session_id)
      WHERE status = 'in_progress';
  `);
  // 插入测试 session
  for (let i = 1; i <= 5; i++) {
    db.prepare(
      `INSERT INTO sessions (id, title, created_at, updated_at) VALUES (?, ?, ?, ?)`,
    ).run(`sess-int-${i}`, `test ${i}`, '2026-07-03T10:00:00Z', '2026-07-03T10:00:00Z');
  }
  return db;
}

function createMockDeps(db: Database.Database): ChatOrchestratorDeps {
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
    db,
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

function createFakeTeachingStateService(): TeachingStateService {
  // 真实 G-1 setActiveTraining 行为(写入 teaching_state.active_training_meta)
  // 集成测试用 fake 避免依赖完整的 TeachingStateStore
  return {
    setActiveTraining: (..._args: unknown[]) => {
      // mock: 实际集成时可在此处写 teaching_state
    },
  } as unknown as TeachingStateService;
}

describe('ActiveTraining 集成 (Sprint 24 A-2)', () => {
  beforeEach(() => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    vi.spyOn(console, 'info').mockImplementation(() => {});
  });

  it('端到端: training_triggered 事件 → active_training 表真的写入', async () => {
    const configPath = writeTempConfig(a2Config);
    const db = createTestDb();
    const store = new ActiveTrainingStore(db);
    const activeTrainingService = new ActiveTrainingService(store);
    const tsService = createFakeTeachingStateService();
    const subscriber = new TeachingStateSubscriber(tsService, configPath, activeTrainingService);
    const svc = new ChatOrchestratorService(createMockDeps(db));
    svc.onOrchestratorEvent((e, sid) => subscriber.handle(e, sid));

    await (svc as unknown as {
      emitTrainingTriggeredIfNeeded: (
        sid: string,
        msg: string,
        a: { syndromeRef?: string[] },
      ) => Promise<void>;
    }).emitTrainingTriggeredIfNeeded('sess-int-1', '帮我训练', { syndromeRef: ['P003'] });

    // 验证 SQLite 真的写入了
    const read = activeTrainingService.getActive('sess-int-1');
    expect(read).not.toBeNull();
    expect(read?.sessionId).toBe('sess-int-1');
    expect(read?.syndromeId).toBe('P003');
    expect(read?.status).toBe('in_progress');
    expect(read?.steps.length).toBeGreaterThan(0);
  });

  it('状态机端到端: start → advanceStep → evaluate → complete 全流程', async () => {
    const configPath = writeTempConfig(a2Config);
    const db = createTestDb();
    const store = new ActiveTrainingStore(db);
    const activeTrainingService = new ActiveTrainingService(store);
    const tsService = createFakeTeachingStateService();
    const subscriber = new TeachingStateSubscriber(tsService, configPath, activeTrainingService);
    const svc = new ChatOrchestratorService(createMockDeps(db));
    svc.onOrchestratorEvent((e, sid) => subscriber.handle(e, sid));

    await (svc as unknown as {
      emitTrainingTriggeredIfNeeded: (
        sid: string,
        msg: string,
        a: { syndromeRef?: string[] },
      ) => Promise<void>;
    }).emitTrainingTriggeredIfNeeded('sess-int-2', '帮我训练', { syndromeRef: ['P003'] });

    // 状态机转换
    const advanced = activeTrainingService.advanceStep('sess-int-2', { stepIndex: 1 });
    expect(advanced?.currentStepIndex).toBe(1);

    const evaluated = activeTrainingService.evaluate('sess-int-2', {
      passed: true,
      feedback: '改写得不错',
      score: 8,
    });
    expect(evaluated?.submissionResult?.passed).toBe(true);

    const completed = activeTrainingService.complete('sess-int-2', 'rec-001');
    expect(completed?.status).toBe('completed');
    expect(completed?.recordId).toBe('rec-001');
    expect(completed?.completedAt).not.toBeNull();
  });

  it('状态机边界: complete 后 advanceStep 拒绝', async () => {
    const configPath = writeTempConfig(a2Config);
    const db = createTestDb();
    const store = new ActiveTrainingStore(db);
    const activeTrainingService = new ActiveTrainingService(store);
    const tsService = createFakeTeachingStateService();
    const subscriber = new TeachingStateSubscriber(tsService, configPath, activeTrainingService);
    const svc = new ChatOrchestratorService(createMockDeps(db));
    svc.onOrchestratorEvent((e, sid) => subscriber.handle(e, sid));

    await (svc as unknown as {
      emitTrainingTriggeredIfNeeded: (
        sid: string,
        msg: string,
        a: { syndromeRef?: string[] },
      ) => Promise<void>;
    }).emitTrainingTriggeredIfNeeded('sess-int-3', '帮我训练', { syndromeRef: ['P003'] });
    activeTrainingService.complete('sess-int-3', 'rec-001');

    const advanced = activeTrainingService.advanceStep('sess-int-3', { stepIndex: 1 });
    expect(advanced).toBeNull();
  });

  it('端到端: 训练触发 → abort 状态写入', async () => {
    const configPath = writeTempConfig(a2Config);
    const db = createTestDb();
    const store = new ActiveTrainingStore(db);
    const activeTrainingService = new ActiveTrainingService(store);
    const tsService = createFakeTeachingStateService();
    const subscriber = new TeachingStateSubscriber(tsService, configPath, activeTrainingService);
    const svc = new ChatOrchestratorService(createMockDeps(db));
    svc.onOrchestratorEvent((e, sid) => subscriber.handle(e, sid));

    await (svc as unknown as {
      emitTrainingTriggeredIfNeeded: (
        sid: string,
        msg: string,
        a: { syndromeRef?: string[] },
      ) => Promise<void>;
    }).emitTrainingTriggeredIfNeeded('sess-int-4', '帮我训练', { syndromeRef: ['P003'] });

    const aborted = activeTrainingService.abort('sess-int-4');
    expect(aborted?.status).toBe('aborted');
    expect(aborted?.completedAt).not.toBeNull();
  });

  it('端到端: 5 秒去重 — 同 session 重复 trigger 不会创建多行 in_progress', async () => {
    const configPath = writeTempConfig(a2Config);
    const db = createTestDb();
    const store = new ActiveTrainingStore(db);
    const activeTrainingService = new ActiveTrainingService(store);
    const tsService = createFakeTeachingStateService();
    const subscriber = new TeachingStateSubscriber(tsService, configPath, activeTrainingService);
    const svc = new ChatOrchestratorService(createMockDeps(db));
    svc.onOrchestratorEvent((e, sid) => subscriber.handle(e, sid));

    const emit = (svc as unknown as {
      emitTrainingTriggeredIfNeeded: (
        sid: string,
        msg: string,
        a: { syndromeRef?: string[] },
      ) => Promise<void>;
    }).emitTrainingTriggeredIfNeeded.bind(svc);

    await emit('sess-int-5', '帮我训练', { syndromeRef: ['P001'] });
    await emit('sess-int-5', '练一下', { syndromeRef: ['P001'] });
    await emit('sess-int-5', '试试', { syndromeRef: ['P001'] });

    // 5 秒去重 → 只有第一次真正创建了行,后续两次 emitTrainingTriggeredIfNeeded
    // 不会调用 subscriber.handle(因为 5 秒窗口跳过)
    const active = activeTrainingService.getActive('sess-int-5');
    expect(active).not.toBeNull();

    // 验证只有一行
    const allRows = db
      .prepare('SELECT * FROM active_training WHERE session_id = ?')
      .all('sess-int-5') as Array<{ status: string }>;
    const inProgressRows = allRows.filter((r) => r.status === 'in_progress');
    expect(inProgressRows).toHaveLength(1);
  });
});
