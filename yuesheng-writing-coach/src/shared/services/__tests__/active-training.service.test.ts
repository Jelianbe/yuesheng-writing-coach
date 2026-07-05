/* eslint-disable @typescript-eslint/no-non-null-assertion */
/**
 * ActiveTrainingService 单测 — Sprint 26 阶段 2 (T26-2.5)
 *
 * 覆盖 src/shared/services/active-training.service.ts(异步 + StorageAdapter 版本)
 * - 使用 BetterSqliteAdapter(:memory:) 跑通(完整 SQL 支持)
 * - 验证 8 个核心方法:getBySession / getActiveBySession / create / update / updateStepResponses / delete / listActive / findBySyndrome
 * - 验证 JSON 字段(steps/stepResponses/submissionResult/trainingFlow)自动 parse/stringify
 *
 * 依据: dev-docs/tasks/sprint-26-2-5-plan.md
 * 决策: D-074
 */
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import Database from 'better-sqlite3';
import { BetterSqliteAdapter } from '../../storage/adapters/better-sqlite.adapter';
import { ActiveTrainingService } from '../active-training.service';
import type { CreateActiveTrainingInput, TrainingStep } from '../active-training.service';
import type { StorageAdapter } from '../../storage/storage-adapter';

describe('ActiveTrainingService — Sprint 26 阶段 2 (BetterSqliteAdapter :memory:)', () => {
  let db: Database.Database;
  let adapter: StorageAdapter;
  let service: ActiveTrainingService;

  /**
   * 预创建 sessions 记录以满足 active_training.session_id 外键约束
   * (生产环境由 sessions 表 + ON DELETE CASCADE 维护)
   */
  async function ensureSession(sessionId: string): Promise<void> {
    const now = new Date().toISOString();
    await adapter.execute(
      'INSERT INTO sessions (id, title, created_at, updated_at) VALUES (?, ?, ?, ?)',
      [sessionId, 'test', now, now],
    );
  }

  function makeSteps(): TrainingStep[] {
    return [
      { id: 's1', title: '解说', description: '用自己话复述技法', status: 'active' },
      { id: 's2', title: '例证', description: '给一个例子', status: 'pending' },
      { id: 's3', title: '确认', description: '确认理解', status: 'pending' },
    ];
  }

  function makeCreateInput(overrides: Partial<CreateActiveTrainingInput> = {}): CreateActiveTrainingInput {
    return {
      sessionId: 'sess-1',
      challengeId: 'CH-P001',
      challengeName: '测试挑战',
      mode: 'writing',
      steps: makeSteps(),
      flowType: 'flow5',
      syndromeId: 'P001',
      source: 'training_triggered',
      ...overrides,
    };
  }

  beforeEach(async () => {
    db = new Database(':memory:');
    adapter = new BetterSqliteAdapter({ db, dbName: 'test.db', version: 1 });
    await adapter.initialize();
    service = new ActiveTrainingService(adapter);
  });

  afterEach(async () => {
    await adapter.close().catch(() => {});
  });

  it('create: 应创建 in_progress 行,返回自增 id', async () => {
    await ensureSession('sess-1');
    const created = await service.create(makeCreateInput());

    expect(created).not.toBeNull();
    expect(created!.id).toBeGreaterThan(0);
    expect(created!.sessionId).toBe('sess-1');
    expect(created!.challengeId).toBe('CH-P001');
    expect(created!.status).toBe('in_progress');
    expect(created!.currentStepIndex).toBe(0);
    expect(created!.userDraft).toBe('');
    expect(created!.steps).toHaveLength(3);
    expect(created!.stepResponses).toEqual([]);
    expect(created!.flowType).toBe('flow5');
    expect(created!.syndromeId).toBe('P001');
    expect(created!.completedAt).toBeNull();
  });

  it('getBySession: 找到应返回最新一行,找不到应返回 null', async () => {
    await ensureSession('sess-1');
    const created = await service.create(makeCreateInput());

    const found = await service.getBySession('sess-1');
    expect(found?.id).toBe(created?.id);

    const notFound = await service.getBySession('non-existent');
    expect(notFound).toBeNull();
  });

  it('getActiveBySession: 找到 in_progress 行', async () => {
    await ensureSession('sess-1');
    await service.create(makeCreateInput());

    const active = await service.getActiveBySession('sess-1');
    expect(active?.status).toBe('in_progress');
  });

  it('getActiveBySession: completed 状态应返回 null', async () => {
    await ensureSession('sess-1');
    const created = await service.create(makeCreateInput());
    await service.update('sess-1', { status: 'completed', completedAt: new Date().toISOString() });

    const active = await service.getActiveBySession('sess-1');
    expect(active).toBeNull();

    // 但 getBySession 应仍能找到
    const bySession = await service.getBySession('sess-1');
    expect(bySession?.id).toBe(created?.id);
  });

  it('update: 应支持部分更新 + updatedAt 推进', async () => {
    await ensureSession('sess-1');
    const created = await service.create(makeCreateInput());
    await new Promise((r) => setTimeout(r, 10));

    const updated = await service.update('sess-1', {
      currentStepIndex: 2,
      userDraft: '用户开始写草稿',
    });

    expect(updated?.currentStepIndex).toBe(2);
    expect(updated?.userDraft).toBe('用户开始写草稿');
    expect(updated?.updatedAt).not.toBe(created?.updatedAt);
  });

  it('updateStepResponses: C-4 5 步分步回答整数组替换', async () => {
    await ensureSession('sess-1');
    await service.create(makeCreateInput());

    const responses = [
      { stepId: 1 as const, content: '复述内容', submittedAt: '2026-07-04T12:00:00.000Z' },
      { stepId: 2 as const, content: '例证内容', submittedAt: '2026-07-04T12:01:00.000Z' },
    ];
    const updated = await service.updateStepResponses('sess-1', responses);

    expect(updated?.stepResponses).toHaveLength(2);
    expect(updated?.stepResponses[0]?.stepId).toBe(1);
    expect(updated?.stepResponses[0]?.content).toBe('复述内容');

    // 重读验证持久化
    const reloaded = await service.getBySession('sess-1');
    expect(reloaded?.stepResponses).toHaveLength(2);
    expect(reloaded?.stepResponses[1]?.content).toBe('例证内容');
  });

  it('listActive: 全局 in_progress 查询', async () => {
    await ensureSession('sess-A');
    await ensureSession('sess-B');

    await service.create(makeCreateInput({ sessionId: 'sess-A' }));
    await service.create(makeCreateInput({ sessionId: 'sess-B', challengeId: 'CH-P002' }));

    // 把 sess-A 标记为 completed
    await service.update('sess-A', { status: 'completed', completedAt: new Date().toISOString() });

    const list = await service.listActive();
    expect(list).toHaveLength(1);
    expect(list[0]?.sessionId).toBe('sess-B');
  });

  it('findBySyndrome: 按症候查询', async () => {
    await ensureSession('sess-X');
    await ensureSession('sess-Y');

    await service.create(makeCreateInput({ sessionId: 'sess-X', syndromeId: 'P003' }));
    await service.create(
      makeCreateInput({ sessionId: 'sess-Y', syndromeId: 'P003', challengeId: 'CH-P003-2' }),
    );
    await service.create(
      makeCreateInput({ sessionId: 'sess-Y', syndromeId: 'P005', challengeId: 'CH-P005' }),
    );

    const p003List = await service.findBySyndrome('P003');
    expect(p003List).toHaveLength(2);

    const p005List = await service.findBySyndrome('P005');
    expect(p005List).toHaveLength(1);
  });

  it('delete: 成功应返回 true,二次删除应返回 false', async () => {
    await ensureSession('sess-1');
    await service.create(makeCreateInput());

    expect(await service.delete('sess-1')).toBe(true);
    expect(await service.delete('sess-1')).toBe(false);
    expect(await service.getBySession('sess-1')).toBeNull();
  });

  it('create: 同一 session 已有 in_progress 时,应先 abort 旧行', async () => {
    await ensureSession('sess-1');
    const first = await service.create(makeCreateInput());
    expect(first?.status).toBe('in_progress');

    // 创建第二次:业务规则要求先 abort 旧训练
    const second = await service.create(makeCreateInput({ challengeId: 'CH-P002' }));

    expect(second?.status).toBe('in_progress');
    expect(second?.challengeId).toBe('CH-P002');

    // 旧行应被标记为 aborted
    const allRows = await adapter.query<{ id: number; status: string; challenge_id: string }>(
      'SELECT id, status, challenge_id FROM active_training WHERE session_id = ? ORDER BY id',
      ['sess-1'],
    );
    expect(allRows).toHaveLength(2);
    expect(allRows[0]?.status).toBe('aborted');
    expect(allRows[0]?.challenge_id).toBe('CH-P001');
    expect(allRows[1]?.status).toBe('in_progress');
    expect(allRows[1]?.challenge_id).toBe('CH-P002');
  });
});
