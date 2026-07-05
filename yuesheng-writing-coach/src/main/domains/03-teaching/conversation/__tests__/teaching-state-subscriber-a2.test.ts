/**
 * TeachingStateSubscriber A-2 单测 — Sprint 24 A-2
 *
 * 覆盖 subscriber.handleStartActiveTraining:
 * 1. training_triggered 事件 → 调 ActiveTrainingService.start
 * 2. start() 输入透传 sessionId/syndromeId/source
 * 3. challengeId 从 training-library.json 查 syndromeId 匹配条目
 * 4. 步骤组装: 3 步通用流(理解/尝试/确认)
 * 5. 异常隔离: ActiveTrainingService 未注入时不抛错(静默跳过)
 * 6. 异常隔离: start() 抛错时不中断事件流
 * 7. 与 setActiveTraining 共存: 同一个 training_triggered 事件两个 action 都触发
 *
 * DoD: ≥5 用例
 * 依据: dev-docs/tasks/sprint-24-plan.md §A-2
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import Database from 'better-sqlite3';
import { TeachingStateSubscriber } from '../teaching-state-subscriber';
import type { TeachingStateService } from '../../teaching-state.service';
import { ActiveTrainingStore } from '../../state/active-training.store';
import { ActiveTrainingService } from '../../state/active-training.service';
import type { TrainingTriggeredEvent, OrchestratorEvent } from '../orchestrator.types';
import type { ActiveTrainingMeta } from '../../../../../shared/types/index';

function writeTempConfig(content: unknown): string {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tss-a2-'));
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
  db.exec(`
    CREATE TABLE sessions (
      id TEXT PRIMARY KEY,
      title TEXT,
      created_at TEXT NOT NULL,
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
  db.prepare(
    `INSERT INTO sessions (id, title, created_at, updated_at) VALUES (?, ?, ?, ?)`,
  ).run('sess-a2-1', 'test', '2026-07-03T10:00:00Z', '2026-07-03T10:00:00Z');
  return db;
}

function makeTrainingTriggeredEvent(
  sessionId: string,
  syndromeId: string,
  techniqueId?: string,
  reason: TrainingTriggeredEvent['reason'] = 'user_request',
): OrchestratorEvent {
  return {
    type: 'training_triggered',
    payload: {
      sessionId,
      syndromeId,
      techniqueId,
      reason,
    },
  };
}

interface FakeTeachingStateService {
  service: TeachingStateService;
  calls: {
    setActiveTraining: Array<{ sessionId: string; syndromeId: string; source: ActiveTrainingMeta['source'] }>;
  };
}

function createFakeTeachingStateService(): FakeTeachingStateService {
  const calls: FakeTeachingStateService['calls'] = { setActiveTraining: [] };
  const service = {
    setActiveTraining: (
      sessionId: string,
      syndromeId: string,
      _techniqueId: string | undefined,
      source: ActiveTrainingMeta['source'],
    ) => {
      calls.setActiveTraining.push({ sessionId, syndromeId, source });
    },
  } as unknown as TeachingStateService;
  return { service, calls };
}

describe('TeachingStateSubscriber A-2 startActiveTraining (Sprint 24 A-2)', () => {
  beforeEach(() => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    vi.spyOn(console, 'error').mockImplementation(() => {});
  });

  it('startActiveTraining: training_triggered → ActiveTrainingService.start 写入 active_training', () => {
    const configPath = writeTempConfig(a2Config);
    const db = createTestDb();
    const store = new ActiveTrainingStore(db);
    const activeTrainingService = new ActiveTrainingService(store);
    const { service: tsService } = createFakeTeachingStateService();
    const subscriber = new TeachingStateSubscriber(tsService, configPath, activeTrainingService);

    const event = makeTrainingTriggeredEvent('sess-a2-1', 'P003');
    subscriber.handle(event, 'sess-a2-1');

    // 验证 SQLite 真的写入了
    const read = activeTrainingService.getActive('sess-a2-1');
    expect(read).not.toBeNull();
    expect(read?.sessionId).toBe('sess-a2-1');
    expect(read?.syndromeId).toBe('P003');
    expect(read?.status).toBe('in_progress');
    expect(read?.currentStepIndex).toBe(0);
  });

  it('startActiveTraining: steps 3 步通用流 + 正确 challengeId', () => {
    const configPath = writeTempConfig(a2Config);
    const db = createTestDb();
    const store = new ActiveTrainingStore(db);
    const activeTrainingService = new ActiveTrainingService(store);
    const { service: tsService } = createFakeTeachingStateService();
    const subscriber = new TeachingStateSubscriber(tsService, configPath, activeTrainingService);

    subscriber.handle(
      makeTrainingTriggeredEvent('sess-a2-1', 'P999'), // 不存在的症候
      'sess-a2-1',
    );

    const read = activeTrainingService.getActive('sess-a2-1');
    expect(read?.steps).toHaveLength(3);
    expect(read?.steps[0]?.title).toBe('理解挑战');
    expect(read?.steps[1]?.title).toBe('尝试改写');
    expect(read?.steps[2]?.title).toBe('确认完成');
    expect(read?.challengeId).toBe('generic-P999'); // 降级路径
  });

  it('startActiveTraining: 异常隔离 — ActiveTrainingService 未注入时静默跳过', () => {
    const configPath = writeTempConfig(a2Config);
    const { service: tsService } = createFakeTeachingStateService();
    // 不传 activeTrainingService
    const subscriber = new TeachingStateSubscriber(tsService, configPath);

    const event = makeTrainingTriggeredEvent('sess-a2-1', 'P003');
    expect(() => subscriber.handle(event, 'sess-a2-1')).not.toThrow();
  });

  it('startActiveTraining: 异常隔离 — start() 抛错时不中断事件流', () => {
    const configPath = writeTempConfig(a2Config);
    const { service: tsService } = createFakeTeachingStateService();

    // mock 一个抛错的 activeTrainingService
    const throwingService = {
      start: () => {
        throw new Error('SQLite error');
      },
    } as unknown as ActiveTrainingService;
    const subscriber = new TeachingStateSubscriber(tsService, configPath, throwingService);

    const event = makeTrainingTriggeredEvent('sess-a2-1', 'P003');
    expect(() => subscriber.handle(event, 'sess-a2-1')).not.toThrow();
  });

  it('startActiveTraining: 与 setActiveTraining 共存 — 同一事件两个 action 都触发', () => {
    const configPath = writeTempConfig(a2Config);
    const db = createTestDb();
    const store = new ActiveTrainingStore(db);
    const activeTrainingService = new ActiveTrainingService(store);
    const { service: tsService, calls } = createFakeTeachingStateService();
    const subscriber = new TeachingStateSubscriber(tsService, configPath, activeTrainingService);

    const event = makeTrainingTriggeredEvent('sess-a2-1', 'P003', undefined, 'user_request');
    subscriber.handle(event, 'sess-a2-1');

    // setActiveTraining 写入教学状态元数据
    expect(calls.setActiveTraining).toHaveLength(1);
    expect(calls.setActiveTraining[0]).toEqual({
      sessionId: 'sess-a2-1',
      syndromeId: 'P003',
      source: 'user_request',
    });

    // startActiveTraining 写入 active_training 表
    const read = activeTrainingService.getActive('sess-a2-1');
    expect(read).not.toBeNull();
  });

  it('startActiveTraining: getLastStartActiveTrainingCall 测试 getter', () => {
    const configPath = writeTempConfig(a2Config);
    const db = createTestDb();
    const store = new ActiveTrainingStore(db);
    const activeTrainingService = new ActiveTrainingService(store);
    const { service: tsService } = createFakeTeachingStateService();
    const subscriber = new TeachingStateSubscriber(tsService, configPath, activeTrainingService);

    expect(subscriber.getLastStartActiveTrainingCall()).toBeNull();

    subscriber.handle(
      makeTrainingTriggeredEvent('sess-a2-1', 'P003', 'TECH-001', 'diagnosis_result'),
      'sess-a2-1',
    );

    const call = subscriber.getLastStartActiveTrainingCall();
    expect(call).not.toBeNull();
    expect(call?.sessionId).toBe('sess-a2-1');
    expect(call?.syndromeId).toBe('P003');
    expect(call?.techniqueId).toBe('TECH-001');
    expect(call?.source).toBe('diagnosis_result');
  });

  it('startActiveTraining: diagnosis_result reason 透传', () => {
    const configPath = writeTempConfig(a2Config);
    const db = createTestDb();
    const store = new ActiveTrainingStore(db);
    const activeTrainingService = new ActiveTrainingService(store);
    const { service: tsService } = createFakeTeachingStateService();
    const subscriber = new TeachingStateSubscriber(tsService, configPath, activeTrainingService);

    subscriber.handle(
      makeTrainingTriggeredEvent('sess-a2-1', 'P003', undefined, 'diagnosis_result'),
      'sess-a2-1',
    );

    const read = activeTrainingService.getActive('sess-a2-1');
    expect(read).not.toBeNull();
  });
});
