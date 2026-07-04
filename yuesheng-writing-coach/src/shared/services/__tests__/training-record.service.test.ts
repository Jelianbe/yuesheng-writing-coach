/**
 * TrainingRecordService 单测 — Sprint 26 阶段 2 (T26-2.4)
 *
 * 覆盖 src/shared/services/training-record.service.ts(异步 + StorageAdapter 版本)
 * - 使用 BetterSqliteAdapter(:memory:) 跑通(完整 SQL 支持)
 * - 验证 7 个核心方法:assign / complete / skip / getById / getBySession / getAll / deleteBySession
 * - 验证 COALESCE 语义:complete() 不传字段时保留旧值
 *
 * 依据: dev-docs/tasks/sprint-26-2-4-plan.md
 * 决策: D-074
 */
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import Database from 'better-sqlite3';
import { BetterSqliteAdapter } from '../../storage/adapters/better-sqlite.adapter';
import { TrainingRecordService } from '../training-record.service';
import type { AssignTrainingRecordInput } from '../training-record.service';
import type { StorageAdapter } from '../../storage/storage-adapter';

describe('TrainingRecordService — Sprint 26 阶段 2 (BetterSqliteAdapter :memory:)', () => {
  let db: Database.Database;
  let adapter: StorageAdapter;
  let service: TrainingRecordService;

  /**
   * 预创建 sessions 记录以满足 user_training_records.session_id 外键约束
   * (生产环境由 sessions 表 + ON DELETE CASCADE 维护)
   */
  async function ensureSession(sessionId: string): Promise<void> {
    const now = new Date().toISOString();
    await adapter.execute(
      'INSERT INTO sessions (id, title, created_at, updated_at) VALUES (?, ?, ?, ?)',
      [sessionId, 'test', now, now],
    );
  }

  function makeAssignInput(overrides: Partial<AssignTrainingRecordInput> = {}): AssignTrainingRecordInput {
    return {
      sessionId: 'sess-1',
      taskId: 'TRAIN-P001-001',
      syndromeId: 'P001',
      userResponse: null,
      aiFeedback: null,
      effectiveness: null,
      score: null,
      taskType: 'writing',
      ...overrides,
    };
  }

  beforeEach(async () => {
    db = new Database(':memory:');
    adapter = new BetterSqliteAdapter({ db, dbName: 'test.db', version: 1 });
    await adapter.initialize();
    service = new TrainingRecordService(adapter);
  });

  afterEach(async () => {
    await adapter.close().catch(() => {});
  });

  it('assign: 应创建新记录,状态为 assigned,完成时间为 null', async () => {
    await ensureSession('sess-1');
    const record = await service.assign(makeAssignInput());

    expect(record.id).toMatch(/^sess-1_TRAIN-P001-001_\d+$/);
    expect(record.sessionId).toBe('sess-1');
    expect(record.taskId).toBe('TRAIN-P001-001');
    expect(record.syndromeId).toBe('P001');
    expect(record.status).toBe('assigned');
    expect(record.completedAt).toBeNull();
    expect(record.taskType).toBe('writing');
    expect(typeof record.assignedAt).toBe('string');
  });

  it('getById: 找到应返回对象,找不到应返回 null', async () => {
    await ensureSession('sess-1');
    const created = await service.assign(makeAssignInput());

    const found = await service.getById(created.id);
    expect(found?.id).toBe(created.id);

    const notFound = await service.getById('non-existent');
    expect(notFound).toBeNull();
  });

  it('complete: 应标记完成并更新字段(COALESCE 保留未传字段)', async () => {
    await ensureSession('sess-1');
    const created = await service.assign(
      makeAssignInput({
        userResponse: '初始回答',
        effectiveness: 3,
      }),
    );

    const completed = await service.complete(created.id, {
      aiFeedback: 'AI 反馈',
      score: 8,
    });

    expect(completed?.status).toBe('completed');
    expect(completed?.completedAt).not.toBeNull();
    // COALESCE 语义:未传字段保留旧值
    expect(completed?.userResponse).toBe('初始回答');
    expect(completed?.effectiveness).toBe(3);
    // 传入的新值生效
    expect(completed?.aiFeedback).toBe('AI 反馈');
    expect(completed?.score).toBe(8);
  });

  it('complete: 找不到时应返回 null', async () => {
    const result = await service.complete('non-existent', { score: 5 });
    expect(result).toBeNull();
  });

  it('skip: 应标记跳过,完成时间更新', async () => {
    await ensureSession('sess-1');
    const created = await service.assign(makeAssignInput());

    const skipped = await service.skip(created.id);
    expect(skipped?.status).toBe('skipped');
    expect(skipped?.completedAt).not.toBeNull();
  });

  it('skip: 找不到时应返回 null', async () => {
    const result = await service.skip('non-existent');
    expect(result).toBeNull();
  });

  it('getBySession: 应返回该 session 全部记录(按 assigned_at 升序)', async () => {
    await ensureSession('sess-A');
    await ensureSession('sess-B');

    const r1 = await service.assign(makeAssignInput({ sessionId: 'sess-A' }));
    await new Promise((r) => setTimeout(r, 5));
    const r2 = await service.assign(
      makeAssignInput({ sessionId: 'sess-A', taskId: 'TRAIN-P001-002' }),
    );
    await service.assign(makeAssignInput({ sessionId: 'sess-B', taskId: 'TRAIN-P001-003' }));

    const sessARecords = await service.getBySession('sess-A');
    expect(sessARecords).toHaveLength(2);
    expect(sessARecords[0]?.id).toBe(r1.id);
    expect(sessARecords[1]?.id).toBe(r2.id);
  });

  it('getAll: 应返回所有记录(跨 session)', async () => {
    await ensureSession('sess-X');
    await ensureSession('sess-Y');

    await service.assign(makeAssignInput({ sessionId: 'sess-X' }));
    await service.assign(makeAssignInput({ sessionId: 'sess-Y', taskId: 'TRAIN-P002-001' }));

    const all = await service.getAll();
    expect(all.length).toBeGreaterThanOrEqual(2);
    const taskIds = all.map((r) => r.taskId);
    expect(taskIds).toContain('TRAIN-P001-001');
    expect(taskIds).toContain('TRAIN-P002-001');
  });

  it('deleteBySession: 应批量删除,返回行数', async () => {
    await ensureSession('sess-D1');
    await ensureSession('sess-D2');

    await service.assign(makeAssignInput({ sessionId: 'sess-D1' }));
    await service.assign(makeAssignInput({ sessionId: 'sess-D1', taskId: 'T-T2' }));
    await service.assign(makeAssignInput({ sessionId: 'sess-D2', taskId: 'T-T3' }));

    const deleted = await service.deleteBySession('sess-D1');
    expect(deleted).toBe(2);

    const remaining = await service.getBySession('sess-D1');
    expect(remaining).toHaveLength(0);

    const d2 = await service.getBySession('sess-D2');
    expect(d2).toHaveLength(1);
  });
});
