/**
 * ActiveTrainingService 单测 — Sprint 24 A-2
 *
 * 覆盖:
 * 1. start 正常路径
 * 2. start 校验: 空 steps / 缺字段拒绝
 * 3. start 业务规则: 同 session 已 in_progress → 先 abort 旧训练
 * 4. start 业务规则: 同 session 已 completed → 创建新行(保留历史)
 * 5. advanceStep 正常路径
 * 6. advanceStep 校验: stepIndex 越界 / 负数拒绝
 * 7. advanceStep 校验: 无 in_progress 时拒绝
 * 8. updateDraft 正常路径
 * 9. updateDraft 校验: 50K 字符阈值触发 warn
 * 10. updateDraft 异常隔离: 无 in_progress 时返回 null 不抛错
 * 11. evaluate 正常路径
 * 12. evaluate 校验: 无 in_progress 时拒绝
 * 13. complete 正常路径(InProgress → Completed)
 * 14. complete 校验: 无 in_progress 时拒绝
 * 15. complete 校验: 缺 recordId 拒绝
 * 16. abort 正常路径(InProgress → Aborted)
 * 17. abort 校验: 无 in_progress 时拒绝
 * 18. 状态机转换边界: Completed/Aborted 后调 advanceStep 拒绝
 * 19. getActive / getBySession / listActive / findBySyndrome 读正确
 * 20. 防御性: DB 错误异常隔离(不抛错)
 *
 * DoD: ≥10 用例(实际给 20+)
 * 依据: dev-docs/tasks/sprint-24-plan.md §A-2
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
  ).run('sess-svc-1', 'test', '2026-07-03T10:00:00Z', '2026-07-03T10:00:00Z');
  db.prepare(
    `INSERT INTO sessions (id, title, created_at, updated_at) VALUES (?, ?, ?, ?)`,
  ).run('sess-svc-2', 'test', '2026-07-03T10:00:00Z', '2026-07-03T10:00:00Z');
  return db;
}

const sampleSteps: TrainingStep[] = [
  { id: 's1', title: '理解', description: '理解挑战', status: 'active' },
  { id: 's2', title: '尝试', description: '尝试改写', status: 'pending' },
  { id: 's3', title: '确认', description: '确认完成', status: 'pending' },
];

describe('ActiveTrainingService (Sprint 24 A-2)', () => {
  let service: ActiveTrainingService;
  let store: ActiveTrainingStore;
  let db: Database.Database;

  beforeEach(() => {
    db = createTestDb();
    store = new ActiveTrainingStore(db);
    service = new ActiveTrainingService(store);
    vi.spyOn(console, 'warn').mockImplementation(() => {});
    vi.spyOn(console, 'error').mockImplementation(() => {});
  });

  // ─── start ───

  it('start: 正常路径 → 创建 in_progress 训练', () => {
    const result = service.start({
      sessionId: 'sess-svc-1',
      challengeId: 'CH-001',
      challengeName: '环境描写',
      steps: sampleSteps,
      syndromeId: 'P003',
      source: 'user_request',
    });

    expect(result).not.toBeNull();
    expect(result?.status).toBe('in_progress');
    expect(result?.currentStepIndex).toBe(0);
    expect(result?.steps).toHaveLength(3);
  });

  it('start: 校验失败 → 返回 null(空 steps)', () => {
    const result = service.start({
      sessionId: 'sess-svc-1',
      challengeId: 'CH-001',
      steps: [],
      syndromeId: 'P003',
      source: 'user_request',
    });
    expect(result).toBeNull();
  });

  it('start: 校验失败 → 返回 null(缺 syndromeId)', () => {
    const result = service.start({
      sessionId: 'sess-svc-1',
      challengeId: 'CH-001',
      steps: sampleSteps,
      // @ts-expect-error - 测试故意缺字段
      syndromeId: undefined,
      source: 'user_request',
    });
    expect(result).toBeNull();
  });

  it('start: 业务规则 — 同 session 已 in_progress → 先 abort 旧训练', () => {
    service.start({
      sessionId: 'sess-svc-1',
      challengeId: 'CH-001',
      steps: sampleSteps,
      syndromeId: 'P003',
      source: 'user_request',
    });

    const second = service.start({
      sessionId: 'sess-svc-1',
      challengeId: 'CH-002',
      steps: sampleSteps,
      syndromeId: 'P005',
      source: 'user_request',
    });
    expect(second?.challengeId).toBe('CH-002');
    expect(second?.status).toBe('in_progress');

    // 验证旧行被 abort
    const allRows = db
      .prepare('SELECT * FROM active_training WHERE session_id = ?')
      .all('sess-svc-1') as Array<{ challenge_id: string; status: string }>;
    const aborted = allRows.find((r) => r.challenge_id === 'CH-001');
    expect(aborted?.status).toBe('aborted');
  });

  it('start: 业务规则 — 同 session 已 completed → 创建新行(保留历史)', () => {
    service.start({
      sessionId: 'sess-svc-1',
      challengeId: 'CH-001',
      steps: sampleSteps,
      syndromeId: 'P003',
      source: 'user_request',
    });
    service.complete('sess-svc-1', 'rec-001');

    // 旧训练已 completed,新 start() 创建新行
    const newTraining = service.start({
      sessionId: 'sess-svc-1',
      challengeId: 'CH-002',
      steps: sampleSteps,
      syndromeId: 'P003',
      source: 'user_request',
    });
    expect(newTraining?.status).toBe('in_progress');
    expect(newTraining?.challengeId).toBe('CH-002');

    // 验证历史保留
    const allRows = db
      .prepare('SELECT * FROM active_training WHERE session_id = ?')
      .all('sess-svc-1') as Array<{ challenge_id: string; status: string }>;
    expect(allRows).toHaveLength(2);
    const completed = allRows.find((r) => r.challenge_id === 'CH-001');
    expect(completed?.status).toBe('completed');
  });

  // ─── advanceStep ───

  it('advanceStep: 正常路径 → 更新 currentStepIndex', () => {
    service.start({
      sessionId: 'sess-svc-1',
      challengeId: 'CH-001',
      steps: sampleSteps,
      syndromeId: 'P003',
      source: 'user_request',
    });

    const updated = service.advanceStep('sess-svc-1', { stepIndex: 1 });
    expect(updated?.currentStepIndex).toBe(1);
  });

  it('advanceStep: 同步更新 steps 状态', () => {
    service.start({
      sessionId: 'sess-svc-1',
      challengeId: 'CH-001',
      steps: sampleSteps,
      syndromeId: 'P003',
      source: 'user_request',
    });

    const newSteps: TrainingStep[] = [
      { id: 's1', title: '理解', description: '理解挑战', status: 'completed' },
      { id: 's2', title: '尝试', description: '尝试改写', status: 'active' },
      { id: 's3', title: '确认', description: '确认完成', status: 'pending' },
    ];

    const updated = service.advanceStep('sess-svc-1', {
      stepIndex: 1,
      steps: newSteps,
    });
    expect(updated?.steps[0]?.status).toBe('completed');
    expect(updated?.steps[1]?.status).toBe('active');
  });

  it('advanceStep: 校验失败 → stepIndex 越界', () => {
    service.start({
      sessionId: 'sess-svc-1',
      challengeId: 'CH-001',
      steps: sampleSteps,
      syndromeId: 'P003',
      source: 'user_request',
    });

    const result = service.advanceStep('sess-svc-1', {
      stepIndex: 10,
      steps: sampleSteps,
    });
    expect(result).toBeNull();
  });

  it('advanceStep: 校验失败 → stepIndex 负数', () => {
    service.start({
      sessionId: 'sess-svc-1',
      challengeId: 'CH-001',
      steps: sampleSteps,
      syndromeId: 'P003',
      source: 'user_request',
    });

    const result = service.advanceStep('sess-svc-1', { stepIndex: -1 });
    expect(result).toBeNull();
  });

  it('advanceStep: 校验失败 → 无 in_progress 训练', () => {
    const result = service.advanceStep('sess-svc-1', { stepIndex: 1 });
    expect(result).toBeNull();
  });

  // ─── updateDraft ───

  it('updateDraft: 正常路径 → 草稿持久化', () => {
    service.start({
      sessionId: 'sess-svc-1',
      challengeId: 'CH-001',
      steps: sampleSteps,
      syndromeId: 'P003',
      source: 'user_request',
    });

    const draft = '用户草稿: 雪覆盖了屋顶...';
    const updated = service.updateDraft('sess-svc-1', draft);
    expect(updated?.userDraft).toBe(draft);

    // 验证持久化
    const reloaded = service.getActive('sess-svc-1');
    expect(reloaded?.userDraft).toBe(draft);
  });

  it('updateDraft: 50K 字符阈值触发 warn', () => {
    service.start({
      sessionId: 'sess-svc-1',
      challengeId: 'CH-001',
      steps: sampleSteps,
      syndromeId: 'P003',
      source: 'user_request',
    });

    const warnSpy = vi.spyOn(console, 'warn');
    const longDraft = 'a'.repeat(50_001);
    service.updateDraft('sess-svc-1', longDraft);
    expect(warnSpy).toHaveBeenCalled();
  });

  it('updateDraft: 无 in_progress → 静默返回 null', () => {
    const result = service.updateDraft('sess-svc-1', 'test');
    expect(result).toBeNull();
  });

  // ─── evaluate ───

  it('evaluate: 正常路径 → 保存评估结果', () => {
    service.start({
      sessionId: 'sess-svc-1',
      challengeId: 'CH-001',
      steps: sampleSteps,
      syndromeId: 'P003',
      source: 'user_request',
    });

    const updated = service.evaluate('sess-svc-1', {
      passed: true,
      feedback: '改写得不错',
      score: 8,
    });
    expect(updated?.submissionResult).not.toBeNull();
    expect(updated?.submissionResult?.passed).toBe(true);
    expect(updated?.submissionResult?.score).toBe(8);
    // 状态保持 in_progress
    expect(updated?.status).toBe('in_progress');
  });

  it('evaluate: 校验失败 → 无 in_progress', () => {
    const result = service.evaluate('sess-svc-1', {
      passed: true,
      feedback: 'test',
    });
    expect(result).toBeNull();
  });

  // ─── complete ───

  it('complete: 正常路径 → InProgress → Completed', () => {
    service.start({
      sessionId: 'sess-svc-1',
      challengeId: 'CH-001',
      steps: sampleSteps,
      syndromeId: 'P003',
      source: 'user_request',
    });

    const completed = service.complete('sess-svc-1', 'rec-001');
    expect(completed?.status).toBe('completed');
    expect(completed?.recordId).toBe('rec-001');
    expect(completed?.completedAt).toMatch(/^\d{4}-\d{2}-\d{2}T/);
  });

  it('complete: 校验失败 → 缺 recordId', () => {
    service.start({
      sessionId: 'sess-svc-1',
      challengeId: 'CH-001',
      steps: sampleSteps,
      syndromeId: 'P003',
      source: 'user_request',
    });

    const result = service.complete('sess-svc-1', '');
    expect(result).toBeNull();
  });

  it('complete: 校验失败 → 无 in_progress', () => {
    const result = service.complete('sess-svc-1', 'rec-001');
    expect(result).toBeNull();
  });

  // ─── abort ───

  it('abort: 正常路径 → InProgress → Aborted', () => {
    service.start({
      sessionId: 'sess-svc-1',
      challengeId: 'CH-001',
      steps: sampleSteps,
      syndromeId: 'P003',
      source: 'user_request',
    });

    const aborted = service.abort('sess-svc-1');
    expect(aborted?.status).toBe('aborted');
    expect(aborted?.completedAt).toMatch(/^\d{4}-\d{2}-\d{2}T/);
  });

  it('abort: 校验失败 → 无 in_progress', () => {
    const result = service.abort('sess-svc-1');
    expect(result).toBeNull();
  });

  // ─── 状态机转换边界 ───

  it('状态机边界: Completed 后调 advanceStep 拒绝', () => {
    service.start({
      sessionId: 'sess-svc-1',
      challengeId: 'CH-001',
      steps: sampleSteps,
      syndromeId: 'P003',
      source: 'user_request',
    });
    service.complete('sess-svc-1', 'rec-001');

    const result = service.advanceStep('sess-svc-1', { stepIndex: 1 });
    expect(result).toBeNull();
  });

  it('状态机边界: Aborted 后调 evaluate 拒绝', () => {
    service.start({
      sessionId: 'sess-svc-1',
      challengeId: 'CH-001',
      steps: sampleSteps,
      syndromeId: 'P003',
      source: 'user_request',
    });
    service.abort('sess-svc-1');

    const result = service.evaluate('sess-svc-1', {
      passed: true,
      feedback: 'test',
    });
    expect(result).toBeNull();
  });

  it('状态机边界: Aborted 后调 complete 拒绝', () => {
    service.start({
      sessionId: 'sess-svc-1',
      challengeId: 'CH-001',
      steps: sampleSteps,
      syndromeId: 'P003',
      source: 'user_request',
    });
    service.abort('sess-svc-1');

    const result = service.complete('sess-svc-1', 'rec-001');
    expect(result).toBeNull();
  });

  // ─── 读操作 ───

  it('getActive: 读 in_progress;completed 后返回 null', () => {
    service.start({
      sessionId: 'sess-svc-1',
      challengeId: 'CH-001',
      steps: sampleSteps,
      syndromeId: 'P003',
      source: 'user_request',
    });
    expect(service.getActive('sess-svc-1')?.status).toBe('in_progress');

    service.complete('sess-svc-1', 'rec-001');
    expect(service.getActive('sess-svc-1')).toBeNull();
  });

  it('getBySession: 读最新一行(任意状态)', () => {
    service.start({
      sessionId: 'sess-svc-1',
      challengeId: 'CH-001',
      steps: sampleSteps,
      syndromeId: 'P003',
      source: 'user_request',
    });
    service.complete('sess-svc-1', 'rec-001');

    const read = service.getBySession('sess-svc-1');
    expect(read?.status).toBe('completed');
  });

  it('listActive: 全局查询进行中', () => {
    service.start({
      sessionId: 'sess-svc-1',
      challengeId: 'CH-001',
      steps: sampleSteps,
      syndromeId: 'P003',
      source: 'user_request',
    });
    service.start({
      sessionId: 'sess-svc-2',
      challengeId: 'CH-002',
      steps: sampleSteps,
      syndromeId: 'P005',
      source: 'user_request',
    });

    const active = service.listActive();
    expect(active).toHaveLength(2);
  });

  it('findBySyndrome: 按症候查询', () => {
    service.start({
      sessionId: 'sess-svc-1',
      challengeId: 'CH-001',
      steps: sampleSteps,
      syndromeId: 'P003',
      source: 'user_request',
    });
    const p003 = service.findBySyndrome('P003');
    expect(p003).toHaveLength(1);
  });

  it('getStatus: 返回状态字面量', () => {
    service.start({
      sessionId: 'sess-svc-1',
      challengeId: 'CH-001',
      steps: sampleSteps,
      syndromeId: 'P003',
      source: 'user_request',
    });
    expect(service.getStatus('sess-svc-1')).toBe('in_progress');
  });

  // ─── 异常隔离 ───

  it('异常隔离: DB 关闭后调用不抛错', () => {
    service.start({
      sessionId: 'sess-svc-1',
      challengeId: 'CH-001',
      steps: sampleSteps,
      syndromeId: 'P003',
      source: 'user_request',
    });

    db.close();

    expect(() => service.getActive('sess-svc-1')).not.toThrow();
    expect(() => service.advanceStep('sess-svc-1', { stepIndex: 1 })).not.toThrow();
    expect(() => service.complete('sess-svc-1', 'rec-001')).not.toThrow();
    expect(() => service.abort('sess-svc-1')).not.toThrow();
    expect(() => service.updateDraft('sess-svc-1', 'test')).not.toThrow();
  });
});
