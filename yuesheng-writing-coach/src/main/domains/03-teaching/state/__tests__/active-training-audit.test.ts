/**
 * ActiveTraining 审计日志测试 — Sprint 25 C-2
 *
 * 覆盖:
 * 1. start 自动创建 'start' 审计
 * 2. advanceStep 自动创建 'advance' 审计
 * 3. evaluate 自动创建 'evaluate' 审计
 * 4. complete 自动创建 'complete' 审计
 * 5. abort 自动创建 'abort' 审计
 * 6. getAuditLogs 按时间倒序返回
 * 7. getRecentTransitions 按 session 查询
 * 8. getRecentTransitions 支持 limit 参数
 * 9. 审计日志包含 from_state / to_state
 * 10. 审计日志 context_json 包含上下文
 *
 * DoD: ≥8 用例(实际 10)
 * 依据: dev-docs/tasks/sprint-25-plan.md §C-2
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import Database from 'better-sqlite3';
import type { Database as DatabaseType } from 'better-sqlite3';
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
  ).run('sess-audit-1', 'test', '2026-07-05T10:00:00Z', '2026-07-05T10:00:00Z');
  db.prepare(
    `INSERT INTO sessions (id, title, created_at, updated_at) VALUES (?, ?, ?, ?)`,
  ).run('sess-audit-2', 'test', '2026-07-05T10:00:00Z', '2026-07-05T10:00:00Z');
  return db;
}

const TEST_STEPS: TrainingStep[] = [
  { id: 's1', title: '解说', description: '解说', status: 'active' },
  { id: 's2', title: '练习', description: '练习', status: 'pending' },
];

describe('ActiveTrainingService audit log (Sprint 25 C-2)', () => {
  let service: ActiveTrainingService;
  let db: DatabaseType;

  beforeEach(() => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    vi.spyOn(console, 'error').mockImplementation(() => {});
    db = createTestDb();
    const store = new ActiveTrainingStore(db);
    service = new ActiveTrainingService(store);
  });

  function startTraining(sessionId: string): number {
    const active = service.start({
      sessionId,
      challengeId: 'CH-1',
      syndromeId: 'SYN-1',
      steps: TEST_STEPS,
      source: 'training_triggered',
    });
    if (!active) throw new Error(`start failed for ${sessionId}`);
    return active.id;
  }

  it('start 自动创建 start 审计', () => {
    const activeId = startTraining('sess-audit-1');

    const logs = service.getAuditLogs(activeId);
    expect(logs).toHaveLength(1);
    expect(logs[0].trigger).toBe('start');
    expect(logs[0].fromState).toBeNull();
    expect(logs[0].toState).toBe('in_progress');
  });

  it('advanceStep 自动创建 advance 审计', () => {
    const activeId = startTraining('sess-audit-1');
    service.advanceStep('sess-audit-1', { stepIndex: 1 });

    const logs = service.getAuditLogs(activeId);
    expect(logs).toHaveLength(2); // start + advance
    expect(logs[0].trigger).toBe('advance');
    expect(logs[0].fromState).toBe('in_progress');
    expect(logs[0].toState).toBe('in_progress');
  });

  it('evaluate 自动创建 evaluate 审计', () => {
    const activeId = startTraining('sess-audit-1');
    service.evaluate('sess-audit-1', { passed: true, feedback: 'good' });

    const logs = service.getAuditLogs(activeId);
    expect(logs).toHaveLength(2); // start + evaluate
    expect(logs[0].trigger).toBe('evaluate');
    expect(logs[0].contextJson).toContain('"passed":true');
  });

  it('complete 自动创建 complete 审计', () => {
    const activeId = startTraining('sess-audit-1');
    service.complete('sess-audit-1', 'rec-123');

    const logs = service.getAuditLogs(activeId);
    expect(logs).toHaveLength(2); // start + complete
    expect(logs[0].trigger).toBe('complete');
    expect(logs[0].fromState).toBe('in_progress');
    expect(logs[0].toState).toBe('completed');
  });

  it('abort 自动创建 abort 审计', () => {
    const activeId = startTraining('sess-audit-1');
    service.abort('sess-audit-1');

    const logs = service.getAuditLogs(activeId);
    expect(logs).toHaveLength(2); // start + abort
    expect(logs[0].trigger).toBe('abort');
    expect(logs[0].fromState).toBe('in_progress');
    expect(logs[0].toState).toBe('aborted');
  });

  it('getAuditLogs 按时间倒序返回', () => {
    const activeId = startTraining('sess-audit-1');
    service.advanceStep('sess-audit-1', { stepIndex: 1 });
    service.evaluate('sess-audit-1', { passed: true, feedback: 'ok' });

    const logs = service.getAuditLogs(activeId);
    expect(logs).toHaveLength(3);
    // 倒序: evaluate → advance → start
    expect(logs[0].trigger).toBe('evaluate');
    expect(logs[1].trigger).toBe('advance');
    expect(logs[2].trigger).toBe('start');
  });

  it('getRecentTransitions 按 session 查询', () => {
    startTraining('sess-audit-1');
    service.advanceStep('sess-audit-1', { stepIndex: 1 });

    const logs = service.getRecentTransitions('sess-audit-1');
    expect(logs.length).toBeGreaterThanOrEqual(2);
    expect(logs[0].trigger).toBe('advance');
  });

  it('getRecentTransitions 支持 limit 参数', () => {
    startTraining('sess-audit-1');
    service.advanceStep('sess-audit-1', { stepIndex: 1 });
    service.evaluate('sess-audit-1', { passed: true, feedback: 'ok' });

    const logs = service.getRecentTransitions('sess-audit-1', 2);
    expect(logs).toHaveLength(2);
  });

  it('不同的 session 审计日志隔离', () => {
    const id1 = startTraining('sess-audit-1');
    const id2 = startTraining('sess-audit-2');
    service.advanceStep('sess-audit-1', { stepIndex: 1 });

    expect(service.getAuditLogs(id1)).toHaveLength(2); // start + advance
    expect(service.getAuditLogs(id2)).toHaveLength(1); // start only
  });

  it('active_training 删除时级联删除审计日志', () => {
    const activeId = startTraining('sess-audit-1');
    service.advanceStep('sess-audit-1', { stepIndex: 1 });
    expect(service.getAuditLogs(activeId)).toHaveLength(2);

    db.prepare('DELETE FROM active_training WHERE session_id = ?').run('sess-audit-1');
    expect(service.getAuditLogs(activeId)).toHaveLength(0);
  });
});
