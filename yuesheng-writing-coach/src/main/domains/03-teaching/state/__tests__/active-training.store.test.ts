/**
 * ActiveTrainingStore 单测 — Sprint 24 A-1
 *
 * 覆盖:
 * 1. create 正常路径
 * 2. create 同 session 已存在 in_progress → 先 abort 再创建
 * 3. getBySession 读回数据(JSON 反序列化正确)
 * 4. getActiveBySession 只返回 in_progress
 * 5. update 部分字段
 * 6. update userDraft(草稿持久化核心)
 * 7. update status → completed + completedAt
 * 8. delete 成功
 * 9. listActive 全局查询
 * 10. findBySyndrome 症候查询
 * 11. 异常隔离: DB 错误返回 null/[](不抛出)
 * 12. 状态字面量非法时回退 in_progress(防御性)
 *
 * DoD: ≥8 用例(实际给 12)
 * 依据: dev-docs/tasks/sprint-24-plan.md §A-1
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import Database from 'better-sqlite3';
import { ActiveTrainingStore } from '../active-training.store';
import type { TrainingStep } from '../active-training.types';

function createTestDb(): Database.Database {
  const db = new Database(':memory:');
  // 应用 026 migration(active_training 表)
  // 同步应用 sessions 表(外键依赖)
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

    CREATE INDEX idx_active_training_status ON active_training(status);
    CREATE INDEX idx_active_training_syndrome ON active_training(syndrome_id);
    CREATE UNIQUE INDEX idx_active_training_active_session
      ON active_training(session_id)
      WHERE status = 'in_progress';
  `);
  // 插入测试 session
  db.prepare(
    `INSERT INTO sessions (id, title, created_at, updated_at) VALUES (?, ?, ?, ?)`,
  ).run('sess-a1-1', 'test session 1', '2026-07-03T10:00:00Z', '2026-07-03T10:00:00Z');
  db.prepare(
    `INSERT INTO sessions (id, title, created_at, updated_at) VALUES (?, ?, ?, ?)`,
  ).run('sess-a1-2', 'test session 2', '2026-07-03T10:00:00Z', '2026-07-03T10:00:00Z');
  return db;
}

const sampleSteps: TrainingStep[] = [
  { id: 's1', title: '理解', description: '理解挑战', status: 'active' },
  { id: 's2', title: '尝试', description: '尝试改写', status: 'pending' },
  { id: 's3', title: '确认', description: '确认完成', status: 'pending' },
];

describe('ActiveTrainingStore (Sprint 24 A-1)', () => {
  let store: ActiveTrainingStore;
  let db: Database.Database;

  beforeEach(() => {
    db = createTestDb();
    store = new ActiveTrainingStore(db);
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    vi.spyOn(console, 'error').mockImplementation(() => {});
  });

  it('create: 正常路径 → 写入并返回完整 ActiveTraining', () => {
    const result = store.create({
      sessionId: 'sess-a1-1',
      challengeId: 'CH-001',
      challengeName: '环境描写',
      mode: 'rewrite',
      steps: sampleSteps,
      syndromeId: 'P003',
      source: 'training_triggered',
    });

    expect(result).not.toBeNull();
    expect(result?.sessionId).toBe('sess-a1-1');
    expect(result?.challengeId).toBe('CH-001');
    expect(result?.challengeName).toBe('环境描写');
    expect(result?.mode).toBe('rewrite');
    expect(result?.currentStepIndex).toBe(0);
    expect(result?.steps).toHaveLength(3);
    expect(result?.userDraft).toBe('');
    expect(result?.status).toBe('in_progress');
    expect(result?.syndromeId).toBe('P003');
    expect(result?.completedAt).toBeNull();
    expect(result?.startedAt).toMatch(/^\d{4}-\d{2}-\d{2}T/);
  });

  it('create: 同 session 已有 in_progress → 先 abort 旧训练再创建新行', () => {
    const first = store.create({
      sessionId: 'sess-a1-1',
      challengeId: 'CH-001',
      steps: sampleSteps,
      source: 'training_triggered',
    });
    expect(first?.status).toBe('in_progress');

    // 第二次 create 同 session
    const second = store.create({
      sessionId: 'sess-a1-1',
      challengeId: 'CH-002',
      steps: sampleSteps,
      source: 'user_request',
    });
    expect(second?.status).toBe('in_progress');
    expect(second?.challengeId).toBe('CH-002');

    // 第一次创建的应该被 abort
    const firstAfter = store.getBySession('sess-a1-1');
    // 最新 getBySession 返回最新行(CH-002),不是被 abort 的 CH-001
    expect(firstAfter?.challengeId).toBe('CH-002');

    // 找一下所有同 session 的行(CH-001 应该是 aborted)
    const allRows = db.prepare('SELECT * FROM active_training WHERE session_id = ?').all('sess-a1-1') as Array<{ challenge_id: string; status: string }>;
    const abortedRow = allRows.find((r) => r.challenge_id === 'CH-001');
    expect(abortedRow?.status).toBe('aborted');
  });

  it('getBySession: 读回数据 + JSON 反序列化正确', () => {
    store.create({
      sessionId: 'sess-a1-1',
      challengeId: 'CH-001',
      steps: sampleSteps,
      trainingFlow: {
        syndromeId: 'P003',
        techniqueName: '环境描写',
        category: 'surface',
        steps: [],
        estimatedTotalMinutes: 30,
      },
      source: 'training_triggered',
    });

    const read = store.getBySession('sess-a1-1');
    expect(read).not.toBeNull();
    expect(read?.steps).toEqual(sampleSteps);
    expect(read?.trainingFlow?.syndromeId).toBe('P003');
    expect(read?.trainingFlow?.techniqueName).toBe('环境描写');
  });

  it('getActiveBySession: 只返回 in_progress', () => {
    store.create({
      sessionId: 'sess-a1-1',
      challengeId: 'CH-001',
      steps: sampleSteps,
      source: 'training_triggered',
    });

    // 状态为 in_progress 时返回
    expect(store.getActiveBySession('sess-a1-1')?.status).toBe('in_progress');

    // 标记为 completed 后,getActiveBySession 返回 null
    store.update('sess-a1-1', { status: 'completed', completedAt: new Date().toISOString() });
    expect(store.getActiveBySession('sess-a1-1')).toBeNull();

    // getBySession 仍能返回(供审计)
    expect(store.getBySession('sess-a1-1')?.status).toBe('completed');
  });

  it('update: 部分字段更新(currentStepIndex + steps)', () => {
    store.create({
      sessionId: 'sess-a1-1',
      challengeId: 'CH-001',
      steps: sampleSteps,
      source: 'training_triggered',
    });

    const newSteps: TrainingStep[] = [
      { id: 's1', title: '理解', description: '理解挑战', status: 'completed' },
      { id: 's2', title: '尝试', description: '尝试改写', status: 'active' },
      { id: 's3', title: '确认', description: '确认完成', status: 'pending' },
    ];

    const updated = store.update('sess-a1-1', { currentStepIndex: 1, steps: newSteps });
    expect(updated?.currentStepIndex).toBe(1);
    expect(updated?.steps[0]?.status).toBe('completed');
    expect(updated?.steps[1]?.status).toBe('active');
  });

  it('update: userDraft 草稿持久化核心', () => {
    store.create({
      sessionId: 'sess-a1-1',
      challengeId: 'CH-001',
      steps: sampleSteps,
      source: 'training_triggered',
    });

    const draft = '用户写的训练草稿: 雪覆盖了屋顶, 整个世界安静了下来...';
    const updated = store.update('sess-a1-1', { userDraft: draft });
    expect(updated?.userDraft).toBe(draft);

    // 验证持久化(从 DB 直接读)
    const reloaded = store.getBySession('sess-a1-1');
    expect(reloaded?.userDraft).toBe(draft);
  });

  it('update: status → completed + completedAt 写入', () => {
    store.create({
      sessionId: 'sess-a1-1',
      challengeId: 'CH-001',
      steps: sampleSteps,
      source: 'training_triggered',
    });

    const completedAt = '2026-07-03T15:30:00Z';
    const updated = store.update('sess-a1-1', {
      status: 'completed',
      completedAt,
      recordId: 'rec-001',
    });
    expect(updated?.status).toBe('completed');
    expect(updated?.completedAt).toBe(completedAt);
    expect(updated?.recordId).toBe('rec-001');
  });

  it('delete: 硬删除(供特殊场景)', () => {
    store.create({
      sessionId: 'sess-a1-1',
      challengeId: 'CH-001',
      steps: sampleSteps,
      source: 'training_triggered',
    });

    const deleted = store.delete('sess-a1-1');
    expect(deleted).toBe(true);
    expect(store.getBySession('sess-a1-1')).toBeNull();
  });

  it('listActive: 全局查询进行中训练', () => {
    store.create({
      sessionId: 'sess-a1-1',
      challengeId: 'CH-001',
      steps: sampleSteps,
      source: 'training_triggered',
    });
    store.create({
      sessionId: 'sess-a1-2',
      challengeId: 'CH-002',
      steps: sampleSteps,
      source: 'training_triggered',
    });
    // 标记 sess-a1-2 为 completed
    store.update('sess-a1-2', { status: 'completed', completedAt: new Date().toISOString() });

    const active = store.listActive();
    expect(active).toHaveLength(1);
    expect(active[0]?.sessionId).toBe('sess-a1-1');
    expect(active[0]?.status).toBe('in_progress');
  });

  it('findBySyndrome: 按症候查询(诊断联动)', () => {
    store.create({
      sessionId: 'sess-a1-1',
      challengeId: 'CH-001',
      steps: sampleSteps,
      syndromeId: 'P003',
      source: 'training_triggered',
    });
    store.create({
      sessionId: 'sess-a1-2',
      challengeId: 'CH-002',
      steps: sampleSteps,
      syndromeId: 'P005',
      source: 'training_triggered',
    });

    const p003 = store.findBySyndrome('P003');
    expect(p003).toHaveLength(1);
    expect(p003[0]?.sessionId).toBe('sess-a1-1');

    const p005 = store.findBySyndrome('P005');
    expect(p005).toHaveLength(1);
    expect(p005[0]?.sessionId).toBe('sess-a1-2');
  });

  it('异常隔离: DB 错误返回 null/[] 不抛出', () => {
    // 构造一个会抛错的 DB(关闭后访问)
    db.close();
    // 关闭后再调用应该被 try/catch 捕获,返回 null/[]
    expect(() => store.getBySession('sess-a1-1')).not.toThrow();
    expect(store.getBySession('sess-a1-1')).toBeNull();
    expect(store.listActive()).toEqual([]);
    expect(store.findBySyndrome('P003')).toEqual([]);
  });

  it('防御性: 状态字面量非法时回退 in_progress', () => {
    // 创建一个,然后手动把 status 改成非法值
    store.create({
      sessionId: 'sess-a1-1',
      challengeId: 'CH-001',
      steps: sampleSteps,
      source: 'training_triggered',
    });
    // 直接用 SQL 改 status 为非法字面量
    db.prepare('UPDATE active_training SET status = ? WHERE session_id = ?').run(
      'invalid_status',
      'sess-a1-1',
    );

    const read = store.getBySession('sess-a1-1');
    expect(read?.status).toBe('in_progress');
  });
});
