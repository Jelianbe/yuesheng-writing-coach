/**
 * ActiveTraining 草稿快照测试 — Sprint 25 C-1
 *
 * 覆盖:
 * 1. advanceStep 自动创建 'advance' 快照
 * 2. evaluate 自动创建 'evaluate' 快照
 * 3. complete 自动创建 'complete' 快照
 * 4. abort 自动创建 'abort' 快照
 * 5. getDraftSnapshots 按时间倒序返回
 * 6. restoreDraftSnapshot 回退 userDraft 并生成 'restore' 快照
 * 7. 回退到非本训练快照被拒绝
 * 8. 回退不存在快照返回 null
 * 9. 50K 字符上限:超长草稿截断并 warn
 * 10. 快照表随 active_training 级联删除
 * 11. start / updateDraft 不触发快照
 *
 * DoD: ≥8 用例(实际 11)
 * 依据: #42 / dev-docs/tasks/sprint-25-plan.md §C-1
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import Database from 'better-sqlite3';
import type { Database as DatabaseType } from 'better-sqlite3';
import { ActiveTrainingStore } from '../active-training.store';
import { ActiveTrainingService } from '../active-training.service';
import type { TrainingStep, ActiveTraining } from '../active-training.types';

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
  ).run('sess-draft-1', 'test', '2026-07-05T10:00:00Z', '2026-07-05T10:00:00Z');
  db.prepare(
    `INSERT INTO sessions (id, title, created_at, updated_at) VALUES (?, ?, ?, ?)`,
  ).run('sess-draft-2', 'test', '2026-07-05T10:00:00Z', '2026-07-05T10:00:00Z');
  return db;
}

const TEST_STEPS: TrainingStep[] = [
  { id: 's1', title: '解说', description: '解说', status: 'active' },
  { id: 's2', title: '练习', description: '练习', status: 'pending' },
];

describe('ActiveTrainingService draft snapshots (Sprint 25 C-1)', () => {
  let service: ActiveTrainingService;
  let db: DatabaseType;

  beforeEach(() => {
    db = createTestDb();
    const store = new ActiveTrainingStore(db);
    service = new ActiveTrainingService(store);
  });

  function startTraining(sessionId: string): ActiveTraining {
    const active = service.start({
      sessionId,
      challengeId: 'CH-1',
      syndromeId: 'SYN-1',
      steps: TEST_STEPS,
      source: 'training_triggered',
    });
    if (!active) throw new Error(`start failed for ${sessionId}`);
    return active;
  }

  it('advanceStep 自动创建 advance 快照', () => {
    const active = startTraining('sess-draft-1');
    service.updateDraft('sess-draft-1', 'step0 draft');
    service.advanceStep('sess-draft-1', { stepIndex: 1 });

    const snapshots = service.getDraftSnapshots(active.id);
    expect(snapshots).toHaveLength(1);
    expect(snapshots[0].trigger).toBe('advance');
    expect(snapshots[0].stepIndex).toBe(0);
    expect(snapshots[0].content).toBe('step0 draft');
  });

  it('evaluate 自动创建 evaluate 快照', () => {
    const active = startTraining('sess-draft-1');
    service.updateDraft('sess-draft-1', 'before evaluate');
    service.evaluate('sess-draft-1', { passed: true, feedback: 'good' });

    const snapshots = service.getDraftSnapshots(active.id);
    expect(snapshots).toHaveLength(1);
    expect(snapshots[0].trigger).toBe('evaluate');
    expect(snapshots[0].content).toBe('before evaluate');
  });

  it('complete 自动创建 complete 快照', () => {
    const active = startTraining('sess-draft-1');
    service.updateDraft('sess-draft-1', 'final draft');
    service.complete('sess-draft-1', 'record-123');

    const snapshots = service.getDraftSnapshots(active.id);
    expect(snapshots).toHaveLength(1);
    expect(snapshots[0].trigger).toBe('complete');
    expect(snapshots[0].content).toBe('final draft');
  });

  it('abort 自动创建 abort 快照', () => {
    const active = startTraining('sess-draft-1');
    service.updateDraft('sess-draft-1', 'aborted draft');
    service.abort('sess-draft-1');

    const snapshots = service.getDraftSnapshots(active.id);
    expect(snapshots).toHaveLength(1);
    expect(snapshots[0].trigger).toBe('abort');
    expect(snapshots[0].content).toBe('aborted draft');
  });

  it('getDraftSnapshots 按时间倒序返回', () => {
    const active = startTraining('sess-draft-1');
    expect(service.updateDraft('sess-draft-1', 'draft1')).not.toBeNull();
    expect(service.advanceStep('sess-draft-1', { stepIndex: 1 })).not.toBeNull();
    expect(service.updateDraft('sess-draft-1', 'draft2')).not.toBeNull();
    expect(service.advanceStep('sess-draft-1', { stepIndex: 2 })).not.toBeNull();

    const snapshots = service.getDraftSnapshots(active.id);
    expect(snapshots).toHaveLength(2);
    expect(snapshots[0].stepIndex).toBe(1);
    expect(snapshots[1].stepIndex).toBe(0);
  });

  it('restoreDraftSnapshot 回退 userDraft 并生成 restore 快照', () => {
    const active = startTraining('sess-draft-1');
    service.updateDraft('sess-draft-1', 'old version');
    service.advanceStep('sess-draft-1', { stepIndex: 1 });
    service.updateDraft('sess-draft-1', 'new version');

    const snapshots = service.getDraftSnapshots(active.id);
    const target = snapshots.find((s) => s.content === 'old version');
    if (!target) throw new Error('target snapshot not found');

    const restored = service.restoreDraftSnapshot(active.id, target.id);
    expect(restored).not.toBeNull();
    expect(restored?.trigger).toBe('restore');
    expect(restored?.restoredFromId).toBe(target.id);

    const current = service.getActive('sess-draft-1');
    expect(current?.userDraft).toBe('old version');
  });

  it('回退到不属于本训练的快照被拒绝', () => {
    const active1 = startTraining('sess-draft-1');
    const active2 = startTraining('sess-draft-2');
    service.updateDraft('sess-draft-2', 'training2 draft');
    service.advanceStep('sess-draft-2', { stepIndex: 1 });

    const otherSnapshot = service.getDraftSnapshots(active2.id)[0];
    const result = service.restoreDraftSnapshot(active1.id, otherSnapshot.id);
    expect(result).toBeNull();
  });

  it('回退不存在的快照返回 null', () => {
    const active = startTraining('sess-draft-1');
    const result = service.restoreDraftSnapshot(active.id, 999);
    expect(result).toBeNull();
  });

  it('50K 字符上限:超长草稿截断并 warn', () => {
    const active = startTraining('sess-draft-1');
    const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const longDraft = 'a'.repeat(60000);

    service.updateDraft('sess-draft-1', longDraft);
    service.advanceStep('sess-draft-1', { stepIndex: 1 });

    const snapshots = service.getDraftSnapshots(active.id);
    expect(snapshots[0].content.length).toBe(50000);
    expect(warnSpy).toHaveBeenCalledWith(
      expect.stringContaining('draft exceeds 50000 chars'),
    );
    warnSpy.mockRestore();
  });

  it('start / updateDraft 不触发快照', () => {
    const active = startTraining('sess-draft-1');
    service.updateDraft('sess-draft-1', 'just typing');

    const snapshots = service.getDraftSnapshots(active.id);
    expect(snapshots).toHaveLength(0);
  });

  it('active_training 删除时级联删除快照', () => {
    const active = startTraining('sess-draft-1');
    service.updateDraft('sess-draft-1', 'draft');
    service.advanceStep('sess-draft-1', { stepIndex: 1 });
    expect(service.getDraftSnapshots(active.id)).toHaveLength(1);

    db.prepare('DELETE FROM active_training WHERE session_id = ?').run('sess-draft-1');
    expect(service.getDraftSnapshots(active.id)).toHaveLength(0);
  });
});
