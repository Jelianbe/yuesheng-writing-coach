/**
 * TeachingStateService 单测 — Sprint 26 阶段 2 (T26-2.3)
 *
 * 覆盖 src/shared/services/teaching-state.service.ts(异步 + StorageAdapter 版本)
 * - 使用 BetterSqliteAdapter(:memory:) 跑通(完整 SQL 支持)
 * - 验证 5 个核心方法:getBySession / create / update / getOrCreate / delete
 * - 验证 JSON 字段自动 parse/stringify
 *
 * 依据: dev-docs/tasks/sprint-26-2-3-plan.md
 * 决策: D-074
 */
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import Database from 'better-sqlite3';
import { BetterSqliteAdapter } from '../../storage/adapters/better-sqlite.adapter';
import { TeachingStateService } from '../teaching-state.service';
import type { StorageAdapter } from '../../storage/storage-adapter';
import { TeachingPhase, TeachingSubphase } from '../../constants';

describe('TeachingStateService — Sprint 26 阶段 2 (BetterSqliteAdapter :memory:)', () => {
  let db: Database.Database;
  let adapter: StorageAdapter;
  let service: TeachingStateService;

  /**
   * 预创建 sessions 记录以满足 teaching_state.session_id 外键约束
   * (生产环境由 sessions 表 + ON DELETE CASCADE 维护)
   */
  async function ensureSession(sessionId: string): Promise<void> {
    const now = new Date().toISOString();
    await adapter.execute(
      'INSERT INTO sessions (id, title, created_at, updated_at) VALUES (?, ?, ?, ?)',
      [sessionId, 'test', now, now],
    );
  }

  beforeEach(async () => {
    db = new Database(':memory:');
    adapter = new BetterSqliteAdapter({ db, dbName: 'test.db', version: 1 });
    await adapter.initialize();
    service = new TeachingStateService(adapter);
  });

  afterEach(async () => {
    await adapter.close().catch(() => {});
  });

  it('getBySession: 空表应返回 null', async () => {
    const result = await service.getBySession('non-existent');
    expect(result).toBeNull();
  });

  it('create: 应创建并返回默认初始状态', async () => {
    await ensureSession('sess-1');
    const state = await service.create({ sessionId: 'sess-1' });
    expect(state.sessionId).toBe('sess-1');
    expect(state.currentPhase).toBe(TeachingPhase.INIT);
    expect(state.currentSubphase).toBe(TeachingSubphase.WORLD_PROTAGONIST);
    expect(state.completedActions).toEqual([]);
    expect(state.completedTasks).toEqual([]);
    expect(state.activeProblems).toEqual([]);
    expect(state.nextSuggestedActions).toEqual([]);
    expect(state.diagnosisSummary).toBe('');
    expect(state.focusArea).toBeNull();
    expect(state.transitionOffered).toBe(false);
    expect(state.lockedSyndromes).toEqual([]);
    expect(state.activeTrainingMeta).toBeNull();
    expect(typeof state.updatedAt).toBe('string');
  });

  it('getBySession: 找到应返回对象(已 create)', async () => {
    await ensureSession('sess-2');
    await service.create({ sessionId: 'sess-2' });
    const found = await service.getBySession('sess-2');
    expect(found?.sessionId).toBe('sess-2');
  });

  it('update: 应支持部分字段更新 + updatedAt 推进', async () => {
    await ensureSession('sess-3');
    const created = await service.create({ sessionId: 'sess-3' });
    await new Promise((r) => setTimeout(r, 10));
    const updated = await service.update('sess-3', {
      currentPhase: TeachingPhase.ENGAGE,
      diagnosisSummary: '用户表现出叙事能力',
      transitionOffered: true,
    });
    expect(updated?.currentPhase).toBe(TeachingPhase.ENGAGE);
    expect(updated?.diagnosisSummary).toBe('用户表现出叙事能力');
    expect(updated?.transitionOffered).toBe(true);
    expect(updated?.updatedAt).not.toBe(created.updatedAt);
  });

  it('update: JSON 数组字段应自动 serialize/parse', async () => {
    await ensureSession('sess-4');
    await service.create({ sessionId: 'sess-4' });
    const updated = await service.update('sess-4', {
      completedActions: ['A1', 'A2'] as never,
      lockedSyndromes: ['P003', 'P005'],
      activeTrainingMeta: {
        syndromeId: 'P003',
        techniqueId: 'T001',
        triggeredAt: '2026-07-04T12:00:00.000Z',
        source: 'training_triggered',
      },
    });
    expect(updated?.completedActions).toEqual(['A1', 'A2']);
    expect(updated?.lockedSyndromes).toEqual(['P003', 'P005']);
    expect(updated?.activeTrainingMeta?.syndromeId).toBe('P003');
    expect(updated?.activeTrainingMeta?.techniqueId).toBe('T001');

    // 重读验证持久化
    const reloaded = await service.getBySession('sess-4');
    expect(reloaded?.completedActions).toEqual(['A1', 'A2']);
    expect(reloaded?.lockedSyndromes).toEqual(['P003', 'P005']);
    expect(reloaded?.activeTrainingMeta?.syndromeId).toBe('P003');
  });

  it('getOrCreate: 存在应返回已有,不存在应创建', async () => {
    await ensureSession('sess-5');
    const first = await service.getOrCreate('sess-5');
    expect(first.sessionId).toBe('sess-5');

    const second = await service.getOrCreate('sess-5');
    expect(second.sessionId).toBe('sess-5');
    expect(second.updatedAt).toBe(first.updatedAt);
  });

  it('delete: 成功应返回 true,二次删除应返回 false', async () => {
    await ensureSession('sess-6');
    await service.create({ sessionId: 'sess-6' });
    expect(await service.delete('sess-6')).toBe(true);
    expect(await service.delete('sess-6')).toBe(false);
    expect(await service.getBySession('sess-6')).toBeNull();
  });
});
