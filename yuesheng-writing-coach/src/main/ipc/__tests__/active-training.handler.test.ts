/**
 * ActiveTraining IPC handler 集成测试 — Sprint 24 A-3
 *
 * 验证契约:
 *   1. activeTraining:updateDraft — 委托给 service.updateDraft,响应字段完整
 *   2. activeTraining:get        — 返回当前 in_progress 训练快照
 *   3. payload 校验: 缺字段/类型错误 → success=false
 *   4. 异常隔离: service 未初始化时抛错(createHandler 兜底)
 *
 * 测试策略:
 *   - 使用 :memory: SQLite 真实库(无 native module 依赖问题)
 *   - vi.mock('electron') 让 createHandler 把 wrapper 存入 ipcMain.handle.mock.calls
 *   - 每次 beforeEach 重建 store + service + 注册 handler
 *
 * DoD: ≥6 用例
 * 依据: dev-docs/tasks/sprint-24-plan.md §A-3
 */

import { describe, it, expect, vi, beforeEach } from 'vitest';
import Database from 'better-sqlite3';
import { IPC_CHANNELS } from '../../../shared/constants';
import { ActiveTrainingStore } from '../../domains/03-teaching/state/active-training.store';
import { ActiveTrainingService } from '../../domains/03-teaching/state/active-training.service';
import {
  initActiveTrainingHandlers,
  registerActiveTrainingHandlers,
} from '../active-training.handler';

vi.mock('electron', () => ({
  ipcMain: { handle: vi.fn() },
  BrowserWindow: {
    getAllWindows: () => [{
      webContents: { send: vi.fn(), isDestroyed: () => false },
    }],
  },
  app: { getPath: () => ':memory:', getVersion: () => '1.0.0-test' },
}));

type HandlerFn = (event: unknown, args: Record<string, unknown>) => Promise<{ success: boolean; data?: unknown; error?: string }>;

function createMemoryDb(): Database.Database {
  const db = new Database(':memory:');
  db.exec(`
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
      status TEXT NOT NULL CHECK(status IN ('in_progress', 'completed', 'aborted')),
      started_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      completed_at TEXT
    );
  `);
  return db;
}

async function collectHandlers(): Promise<Map<string, HandlerFn>> {
  const { ipcMain } = await import('electron');
  const handlers = new Map<string, HandlerFn>();
  const calls = vi.mocked(ipcMain.handle).mock.calls;
  for (const [channel, handler] of calls) {
    handlers.set(channel as string, handler as HandlerFn);
  }
  return handlers;
}

function getHandler(handlers: Map<string, HandlerFn>, channel: string): HandlerFn {
  const handler = handlers.get(channel);
  expect(handler, `Handler for channel "${channel}" should be registered`).toBeDefined();
  return handler!;
}

const TEST_SESSION_ID = 'test-session-a3';
const TEST_CHALLENGE_ID = 'CH-P001-001';
const TEST_DRAFT_CONTENT = '用户训练草稿';
const TEST_STEPS = [
  { id: 's1', title: '解说', description: '解说技法', status: 'active' as const },
  { id: 's2', title: '例证', description: '展示例证', status: 'pending' as const },
];

describe('ActiveTraining IPC handler (Sprint 24 A-3)', () => {
  let service: ActiveTrainingService;

  beforeEach(async () => {
    // 重建 DB + service(每个测试独立 SQLite,完全隔离)
    const db = createMemoryDb();
    const store = new ActiveTrainingStore(db);
    service = new ActiveTrainingService(store);

    // 清理 mock 调用
    const { ipcMain } = await import('electron');
    vi.mocked(ipcMain.handle).mockClear();

    // 注入 + 注册
    initActiveTrainingHandlers(service);
    registerActiveTrainingHandlers();
  });

  it('updateDraft: in_progress 训练存在时返回 success + length + persistedAt', async () => {
    service.start({
      sessionId: TEST_SESSION_ID,
      challengeId: TEST_CHALLENGE_ID,
      syndromeId: 'P001',
      steps: TEST_STEPS,
      source: 'training_triggered',
    });

    const handlers = await collectHandlers();
    const handler = getHandler(handlers, IPC_CHANNELS.ACTIVE_TRAINING_UPDATE_DRAFT);

    const res = await handler({}, { sessionId: TEST_SESSION_ID, content: TEST_DRAFT_CONTENT });

    expect(res.success).toBe(true);
    const data = res.data as { length: number; persistedAt: string; status: string };
    expect(data.length).toBe(TEST_DRAFT_CONTENT.length);
    expect(typeof data.persistedAt).toBe('string');
    expect(data.status).toBe('in_progress');

    // 验证 SQLite 实际持久化了
    const active = service.getActive(TEST_SESSION_ID);
    expect(active?.userDraft).toBe(TEST_DRAFT_CONTENT);
  });

  it('updateDraft: 缺 content 字段时返回 INVALID_PAYLOAD 错误', async () => {
    const handlers = await collectHandlers();
    const handler = getHandler(handlers, IPC_CHANNELS.ACTIVE_TRAINING_UPDATE_DRAFT);

    const res = await handler({}, { sessionId: TEST_SESSION_ID });

    expect(res.success).toBe(false);
    expect(res.error).toMatch(/INVALID_PAYLOAD|MISSING_FIELD|INVALID_TYPE/);
  });

  it('updateDraft: 缺 sessionId 字段时返回 INVALID_PAYLOAD 错误', async () => {
    const handlers = await collectHandlers();
    const handler = getHandler(handlers, IPC_CHANNELS.ACTIVE_TRAINING_UPDATE_DRAFT);

    const res = await handler({}, { content: '草稿' });

    expect(res.success).toBe(false);
    expect(res.error).toMatch(/INVALID_PAYLOAD|MISSING_FIELD|INVALID_TYPE/);
  });

  it('updateDraft: content 字段类型错误时返回 INVALID_PAYLOAD', async () => {
    const handlers = await collectHandlers();
    const handler = getHandler(handlers, IPC_CHANNELS.ACTIVE_TRAINING_UPDATE_DRAFT);

    const res = await handler({}, { sessionId: TEST_SESSION_ID, content: 12345 });

    expect(res.success).toBe(false);
    expect(res.error).toMatch(/INVALID_PAYLOAD|INVALID_TYPE/);
  });

  it('get: 无 in_progress 训练时返回 null', async () => {
    const handlers = await collectHandlers();
    const handler = getHandler(handlers, IPC_CHANNELS.ACTIVE_TRAINING_GET);

    const res = await handler({}, { sessionId: 'no-active-session' });

    expect(res.success).toBe(true);
    expect(res.data).toBeNull();
  });

  it('get: in_progress 训练存在时返回完整快照', async () => {
    service.start({
      sessionId: TEST_SESSION_ID,
      challengeId: TEST_CHALLENGE_ID,
      challengeName: '测试挑战',
      mode: 'generic',
      syndromeId: 'P001',
      steps: TEST_STEPS,
      source: 'training_triggered',
    });
    service.updateDraft(TEST_SESSION_ID, '草稿内容');

    const handlers = await collectHandlers();
    const handler = getHandler(handlers, IPC_CHANNELS.ACTIVE_TRAINING_GET);

    const res = await handler({}, { sessionId: TEST_SESSION_ID });

    expect(res.success).toBe(true);
    const data = res.data as Record<string, unknown>;
    expect(data.sessionId).toBe(TEST_SESSION_ID);
    expect(data.challengeId).toBe(TEST_CHALLENGE_ID);
    expect(data.challengeName).toBe('测试挑战');
    expect(data.mode).toBe('generic');
    expect(data.status).toBe('in_progress');
    expect(data.userDraft).toBe('草稿内容');
    expect(data.steps).toEqual(TEST_STEPS);
    expect(typeof data.startedAt).toBe('string');
    expect(typeof data.updatedAt).toBe('string');
    expect(data.completedAt).toBeNull();
  });

  it('get: 缺 sessionId 字段时返回 INVALID_PAYLOAD', async () => {
    const handlers = await collectHandlers();
    const handler = getHandler(handlers, IPC_CHANNELS.ACTIVE_TRAINING_GET);

    const res = await handler({}, {});

    expect(res.success).toBe(false);
    expect(res.error).toMatch(/INVALID_PAYLOAD|MISSING_FIELD|INVALID_TYPE/);
  });

  it('updateDraft → get 链路: 草稿持久化后可被 get 读到', async () => {
    service.start({
      sessionId: TEST_SESSION_ID,
      challengeId: TEST_CHALLENGE_ID,
      syndromeId: 'P001',
      steps: TEST_STEPS,
      source: 'training_triggered',
    });

    const handlers = await collectHandlers();
    const updateHandler = getHandler(handlers, IPC_CHANNELS.ACTIVE_TRAINING_UPDATE_DRAFT);
    const readHandler = getHandler(handlers, IPC_CHANNELS.ACTIVE_TRAINING_GET);

    const updateRes = await updateHandler({}, { sessionId: TEST_SESSION_ID, content: '改写后' });
    expect(updateRes.success).toBe(true);

    const getRes = await readHandler({}, { sessionId: TEST_SESSION_ID });
    const data = getRes.data as { userDraft: string };
    expect(data.userDraft).toBe('改写后');
  });

  it('updateDraft 隔离: A 会话存在训练不影响 B 会话', async () => {
    // 准备:仅给会话 A 启动训练
    service.start({
      sessionId: 'session-A',
      challengeId: 'CH-A',
      syndromeId: 'P001',
      steps: TEST_STEPS,
      source: 'training_triggered',
    });

    const handlers = await collectHandlers();
    const handler = getHandler(handlers, IPC_CHANNELS.ACTIVE_TRAINING_UPDATE_DRAFT);

    // B 会话无训练 → 应返回 success=false (createHandler 外层 success 始终为 true,内层 success 在 data 里)
    const resB = await handler({}, { sessionId: 'session-B', content: 'B 草稿' });
    expect(resB.success).toBe(true);
    const dataB = resB.data as { success: boolean; status: string | null; length: number };
    expect(dataB.success).toBe(false);
    expect(dataB.status).toBeNull();
    expect(dataB.length).toBe(4);

    // A 会话有训练 → 应返回 success=true
    const resA = await handler({}, { sessionId: 'session-A', content: 'A 草稿' });
    expect(resA.success).toBe(true);
    const dataA = resA.data as { success: boolean; status: string };
    expect(dataA.success).toBe(true);
    expect(dataA.status).toBe('in_progress');
  });
});
