/**
 * ActiveTrainingService 状态变更订阅测试 — Sprint 24 A-4
 *
 * 覆盖:
 * 1. start() 触发 'start' 状态变更事件
 * 2. advanceStep() 触发 'advanceStep' 事件
 * 3. updateDraft() 触发 'updateDraft' 事件
 * 4. evaluate() 触发 'evaluate' 事件
 * 5. complete() 触发 'complete' 事件
 * 6. abort() 触发 'abort' 事件
 * 7. 多次订阅: 同一事件触发所有订阅者
 * 8. 取消订阅: unsubscribe 阻止后续事件
 * 9. 异常隔离: 订阅者抛错不影响其他订阅者
 * 10. 失败操作不触发事件(start 校验失败时)
 *
 * DoD: ≥6 用例
 * 依据: dev-docs/tasks/sprint-24-plan.md §A-4
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import Database from 'better-sqlite3';
import { ActiveTrainingStore } from '../active-training.store';
import { ActiveTrainingService } from '../active-training.service';
import type { TrainingStep } from '../active-training.types';

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

    CREATE TABLE active_training_drafts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      active_training_id INTEGER NOT NULL,
      step_index INTEGER NOT NULL,
      content TEXT NOT NULL,
      trigger TEXT NOT NULL,
      snapshot_at TEXT NOT NULL,
      restored_from_id INTEGER,
      FOREIGN KEY (active_training_id) REFERENCES active_training(id) ON DELETE CASCADE
    );
    CREATE INDEX idx_atd_at_id ON active_training_drafts(active_training_id, step_index);

    CREATE TABLE active_training_audit_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      active_training_id INTEGER NOT NULL,
      trigger TEXT NOT NULL,
      from_state TEXT,
      to_state TEXT NOT NULL,
      actor TEXT NOT NULL DEFAULT 'main',
      context_json TEXT,
      occurred_at TEXT NOT NULL,
      FOREIGN KEY (active_training_id) REFERENCES active_training(id) ON DELETE CASCADE
    );
    CREATE INDEX idx_atal_at_id ON active_training_audit_log(active_training_id, occurred_at);
  `);
  db.prepare(
    `INSERT INTO sessions (id, title, created_at, updated_at) VALUES (?, ?, ?, ?)`,
  ).run('sess-a4-1', 'test', '2026-07-03T10:00:00Z', '2026-07-03T10:00:00Z');
  return db;
}

const TEST_STEPS: TrainingStep[] = [
  { id: 's1', title: '解说', description: '解说', status: 'active' },
  { id: 's2', title: '练习', description: '练习', status: 'pending' },
];

describe('ActiveTrainingService onStateChange (Sprint 24 A-4)', () => {
  let service: ActiveTrainingService;

  beforeEach(() => {
    const db = createTestDb();
    const store = new ActiveTrainingStore(db);
    service = new ActiveTrainingService(store);
  });

  it('start() 触发 type="start" 状态变更事件', () => {
    const listener = vi.fn();
    service.onStateChange(listener);

    const created = service.start({
      sessionId: 'sess-a4-1',
      challengeId: 'CH-1',
      syndromeId: 'P001',
      steps: TEST_STEPS,
      source: 'training_triggered',
    });

    expect(created).not.toBeNull();
    expect(listener).toHaveBeenCalledTimes(1);
    expect(listener).toHaveBeenCalledWith({
      type: 'start',
      sessionId: 'sess-a4-1',
      state: expect.objectContaining({ challengeId: 'CH-1', status: 'in_progress' }),
    });
  });

  it('advanceStep() 触发 type="advanceStep" 事件', () => {
    service.start({
      sessionId: 'sess-a4-1',
      challengeId: 'CH-1',
      syndromeId: 'P001',
      steps: TEST_STEPS,
      source: 'training_triggered',
    });

    const listener = vi.fn();
    service.onStateChange(listener);

    const advanced = service.advanceStep('sess-a4-1', { stepIndex: 1 });
    expect(advanced).not.toBeNull();
    expect(listener).toHaveBeenCalledWith({
      type: 'advanceStep',
      sessionId: 'sess-a4-1',
      state: expect.objectContaining({ currentStepIndex: 1 }),
    });
  });

  it('updateDraft() 触发 type="updateDraft" 事件', () => {
    service.start({
      sessionId: 'sess-a4-1',
      challengeId: 'CH-1',
      syndromeId: 'P001',
      steps: TEST_STEPS,
      source: 'training_triggered',
    });

    const listener = vi.fn();
    service.onStateChange(listener);

    const updated = service.updateDraft('sess-a4-1', '用户草稿');
    expect(updated).not.toBeNull();
    expect(listener).toHaveBeenCalledWith({
      type: 'updateDraft',
      sessionId: 'sess-a4-1',
      state: expect.objectContaining({ userDraft: '用户草稿' }),
    });
  });

  it('evaluate() 触发 type="evaluate" 事件', () => {
    service.start({
      sessionId: 'sess-a4-1',
      challengeId: 'CH-1',
      syndromeId: 'P001',
      steps: TEST_STEPS,
      source: 'training_triggered',
    });

    const listener = vi.fn();
    service.onStateChange(listener);

    const evaluated = service.evaluate('sess-a4-1', { passed: true, feedback: 'good', score: 8 });
    expect(evaluated).not.toBeNull();
    expect(listener).toHaveBeenCalledWith({
      type: 'evaluate',
      sessionId: 'sess-a4-1',
      state: expect.objectContaining({
        submissionResult: expect.objectContaining({ passed: true, score: 8 }),
      }),
    });
  });

  it('complete() 触发 type="complete" 事件', () => {
    service.start({
      sessionId: 'sess-a4-1',
      challengeId: 'CH-1',
      syndromeId: 'P001',
      steps: TEST_STEPS,
      source: 'training_triggered',
    });

    const listener = vi.fn();
    service.onStateChange(listener);

    const completed = service.complete('sess-a4-1', 'rec-1');
    expect(completed).not.toBeNull();
    expect(listener).toHaveBeenCalledWith({
      type: 'complete',
      sessionId: 'sess-a4-1',
      state: expect.objectContaining({ status: 'completed', recordId: 'rec-1' }),
    });
  });

  it('abort() 触发 type="abort" 事件', () => {
    service.start({
      sessionId: 'sess-a4-1',
      challengeId: 'CH-1',
      syndromeId: 'P001',
      steps: TEST_STEPS,
      source: 'training_triggered',
    });

    const listener = vi.fn();
    service.onStateChange(listener);

    const aborted = service.abort('sess-a4-1');
    expect(aborted).not.toBeNull();
    expect(listener).toHaveBeenCalledWith({
      type: 'abort',
      sessionId: 'sess-a4-1',
      state: expect.objectContaining({ status: 'aborted' }),
    });
  });

  it('多次订阅同一事件: 所有订阅者都被触发', () => {
    const l1 = vi.fn();
    const l2 = vi.fn();
    service.onStateChange(l1);
    service.onStateChange(l2);

    service.start({
      sessionId: 'sess-a4-1',
      challengeId: 'CH-1',
      syndromeId: 'P001',
      steps: TEST_STEPS,
      source: 'training_triggered',
    });

    expect(l1).toHaveBeenCalledTimes(1);
    expect(l2).toHaveBeenCalledTimes(1);
  });

  it('unsubscribe 阻止后续事件', () => {
    const listener = vi.fn();
    const off = service.onStateChange(listener);

    service.start({
      sessionId: 'sess-a4-1',
      challengeId: 'CH-1',
      syndromeId: 'P001',
      steps: TEST_STEPS,
      source: 'training_triggered',
    });
    expect(listener).toHaveBeenCalledTimes(1);

    off();

    service.updateDraft('sess-a4-1', 'new');
    expect(listener).toHaveBeenCalledTimes(1); // 仍为 1
  });

  it('异常隔离: 订阅者抛错不影响其他订阅者', () => {
    const l1 = vi.fn(() => {
      throw new Error('boom');
    });
    const l2 = vi.fn();
    const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => {});

    service.onStateChange(l1);
    service.onStateChange(l2);

    service.start({
      sessionId: 'sess-a4-1',
      challengeId: 'CH-1',
      syndromeId: 'P001',
      steps: TEST_STEPS,
      source: 'training_triggered',
    });

    expect(l1).toHaveBeenCalledTimes(1);
    expect(l2).toHaveBeenCalledTimes(1); // 仍被调用
    expect(consoleSpy).toHaveBeenCalled();

    consoleSpy.mockRestore();
  });

  it('失败操作不触发事件: start 校验失败时 listener 不被调用', () => {
    const listener = vi.fn();
    service.onStateChange(listener);

    // 缺 syndromeId → validateStartInput 失败
    service.start({
      sessionId: 'sess-a4-1',
      challengeId: 'CH-1',
      syndromeId: '', // 空
      steps: TEST_STEPS,
      source: 'training_triggered',
    });

    expect(listener).not.toHaveBeenCalled();
  });

  it('removeAllStateChangeListeners 一次性清理所有订阅', () => {
    const l1 = vi.fn();
    const l2 = vi.fn();
    service.onStateChange(l1);
    service.onStateChange(l2);
    service.removeAllStateChangeListeners();

    service.start({
      sessionId: 'sess-a4-1',
      challengeId: 'CH-1',
      syndromeId: 'P001',
      steps: TEST_STEPS,
      source: 'training_triggered',
    });

    expect(l1).not.toHaveBeenCalled();
    expect(l2).not.toHaveBeenCalled();
  });
});
