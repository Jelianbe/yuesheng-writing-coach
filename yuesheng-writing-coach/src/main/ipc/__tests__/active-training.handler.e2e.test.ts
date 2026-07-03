/**
 * ActiveTraining 状态推送 — 端到端集成测试
 *
 * Sprint 24 A-4 DoD:
 *   - E2E 测试: 完整 start → 推进 → 草稿 → 评估 → complete 链路
 *   - 至少 2 个端到端训练生命周期 (start→complete, start→abort)
 *
 * 链路覆盖:
 *   ActiveTrainingService (主进程)
 *     → onStateChange 事件
 *     → setupActiveTrainingPush 桥接
 *     → BrowserWindow.webContents.send (mock 捕获)
 *     → ActiveTrainingUpdatedEvent (推送 payload)
 *
 * 验证要点:
 *   1. 真实 service 操作触发的推送事件能被正确捕获
 *   2. payload 字段完整(状态/会话/领域对象映射)
 *   3. 推送事件类型与操作一致
 *   4. 端到端状态最终一致
 *
 * 依据: dev-docs/tasks/sprint-24-plan.md §A-4
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import Database from 'better-sqlite3';
import { IPC_CHANNELS } from '../../../shared/constants';
import { ActiveTrainingStore } from '../../domains/03-teaching/state/active-training.store';
import { ActiveTrainingService } from '../../domains/03-teaching/state/active-training.service';
import { initActiveTrainingHandlers, setupActiveTrainingPush } from '../active-training.handler';
import type { TrainingStep } from '../../domains/03-teaching/state/active-training.types';
import type { ActiveTrainingUpdatedEvent } from '../../../shared/api-contracts/active-training.contract';

// ─── 静态 mock electron(必须在 import 之前)───

const mockWindows: Array<{
  isDestroyed: () => boolean;
  webContents: { send: ReturnType<typeof vi.fn>; isDestroyed: () => boolean; id: number };
}> = [];

vi.mock('electron', () => ({
  ipcMain: { handle: vi.fn() },
  BrowserWindow: {
    getAllWindows: vi.fn(() => mockWindows),
  },
  app: { getPath: () => ':memory:', getVersion: () => '1.0.0-test' },
}));

function makeWindow() {
  const win = {
    isDestroyed: () => false,
    webContents: {
      send: vi.fn(),
      isDestroyed: () => false,
      id: mockWindows.length + 1,
    },
  };
  mockWindows.push(win);
  return win;
}

function resetWindows() {
  mockWindows.length = 0;
}

// ─── 基础设施 ───

function createTestDb(): Database.Database {
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

const TEST_STEPS: TrainingStep[] = [
  { id: 's1', title: '解说', description: '解说', status: 'active' as const },
  { id: 's2', title: '改写', description: '改写', status: 'pending' as const },
  { id: 's3', title: '评估', description: '评估', status: 'pending' as const },
];

interface CapturedPush {
  channel: string;
  payload: ActiveTrainingUpdatedEvent;
}

function collectPushes(): CapturedPush[] {
  const result: CapturedPush[] = [];
  for (const win of mockWindows) {
    const calls = vi.mocked(win.webContents.send).mock.calls;
    for (const [channel, payload] of calls) {
      result.push({ channel: channel as string, payload: payload as ActiveTrainingUpdatedEvent });
    }
  }
  return result;
}

function collectForSession(sessionId: string): CapturedPush[] {
  return collectPushes().filter((p) => p.payload.sessionId === sessionId);
}

// ─── 测试 ───

describe('ActiveTraining 状态推送 E2E (Sprint 24 A-4)', () => {
  let db: Database.Database;
  let service: ActiveTrainingService;
  let mainWindow: ReturnType<typeof makeWindow>;
  let off: () => void;

  beforeEach(() => {
    resetWindows();
    db = createTestDb();
    const store = new ActiveTrainingStore(db);
    service = new ActiveTrainingService(store);
    initActiveTrainingHandlers(service);

    mainWindow = makeWindow();
    off = setupActiveTrainingPush(mainWindow as never);
  });

  // ─── E2E-1: 完整生命周期 start → advanceStep → updateDraft → evaluate → complete ───

  it('E2E-1: 完整 start → advanceStep → updateDraft → evaluate → complete 链路', () => {
    const sessionId = 'sess-e2e-complete';

    // 1) 启动训练
    service.start({
      sessionId,
      challengeId: 'CH-E2E-1',
      challengeName: '环境描写改写',
      steps: TEST_STEPS,
      syndromeId: 'P003',
      source: 'training_triggered',
    });

    // 2) 推进到第 2 步
    service.advanceStep(sessionId, { stepIndex: 1 });

    // 3) 更新草稿
    service.updateDraft(sessionId, '用户尝试改写:夜幕降临,城市在雨中沉默');

    // 4) AI 评估
    service.evaluate(sessionId, { passed: true, feedback: '改写得不错', score: 8 });

    // 5) 完成训练
    service.complete(sessionId, 'rec-e2e-1');

    // ── 断言推送链路 ──
    const pushes = collectForSession(sessionId);
    expect(pushes.length).toBeGreaterThanOrEqual(5);

    // 验证 5 个操作各自产生 1 次推送
    const types = pushes.map((p) => p.payload.type);
    expect(types).toContain('start');
    expect(types).toContain('advanceStep');
    expect(types).toContain('updateDraft');
    expect(types).toContain('evaluate');
    expect(types).toContain('complete');

    // 验证通道名
    pushes.forEach((p) => {
      expect(p.channel).toBe(IPC_CHANNELS.ACTIVE_TRAINING_UPDATED);
      expect(p.channel).toBe('activeTraining:updated');
    });

    // 验证 start 事件的 payload 完整性
    const startPush = pushes.find((p) => p.payload.type === 'start');
    expect(startPush).toBeDefined();
    expect(startPush?.payload.sessionId).toBe(sessionId);
    expect(startPush?.payload.state).toMatchObject({
      sessionId,
      challengeId: 'CH-E2E-1',
      challengeName: '环境描写改写',
      currentStepIndex: 0,
      steps: expect.any(Array),
      userDraft: '',
      syndromeId: 'P003',
      status: 'in_progress',
    });

    // 验证 advanceStep 事件反映了步骤推进
    const advancePush = pushes.find((p) => p.payload.type === 'advanceStep');
    expect(advancePush?.payload.state.currentStepIndex).toBe(1);

    // 验证 updateDraft 事件反映了草稿保存
    const draftPush = pushes.find((p) => p.payload.type === 'updateDraft');
    expect(draftPush?.payload.state.userDraft).toBe('用户尝试改写:夜幕降临,城市在雨中沉默');

    // 验证 evaluate 事件反映了评估结果
    const evalPush = pushes.find((p) => p.payload.type === 'evaluate');
    expect(evalPush?.payload.state.submissionResult).toMatchObject({
      passed: true,
      feedback: '改写得不错',
      score: 8,
    });
    // evaluate 不改变 status
    expect(evalPush?.payload.state.status).toBe('in_progress');

    // 验证 complete 事件状态变 completed
    const completePush = pushes.find((p) => p.payload.type === 'complete');
    expect(completePush?.payload.state.status).toBe('completed');
    expect(completePush?.payload.state.recordId).toBe('rec-e2e-1');
    expect(completePush?.payload.state.completedAt).toMatch(/^\d{4}-\d{2}-\d{2}T/);

    off();
  });

  // ─── E2E-2: 简化生命周期 start → abort ───

  it('E2E-2: 完整 start → abort 链路', () => {
    const sessionId = 'sess-e2e-abort';

    // 1) 启动训练
    service.start({
      sessionId,
      challengeId: 'CH-E2E-2',
      steps: TEST_STEPS,
      syndromeId: 'P006',
      source: 'user_request',
    });

    // 2) 中止训练
    service.abort(sessionId);

    const pushes = collectForSession(sessionId);
    expect(pushes.length).toBeGreaterThanOrEqual(2);

    const types = pushes.map((p) => p.payload.type);
    expect(types).toContain('start');
    expect(types).toContain('abort');

    // 验证 abort 事件状态变 aborted
    const abortPush = pushes.find((p) => p.payload.type === 'abort');
    expect(abortPush?.payload.sessionId).toBe(sessionId);
    expect(abortPush?.payload.state.status).toBe('aborted');
    expect(abortPush?.payload.state.completedAt).toMatch(/^\d{4}-\d{2}-\d{2}T/);

    // 验证 start 状态是 in_progress
    const startPush = pushes.find((p) => p.payload.type === 'start');
    expect(startPush?.payload.state.status).toBe('in_progress');

    off();
  });

  // ─── E2E-3: 多窗口同步 ───

  it('E2E-3: 状态推送广播到多个窗口(主窗口 + 副窗口)', () => {
    const sessionId = 'sess-e2e-multi';

    // 注册第二个窗口
    const extraWin = makeWindow();

    service.start({
      sessionId,
      challengeId: 'CH-E2E-3',
      steps: TEST_STEPS,
      syndromeId: 'P003',
      source: 'training_triggered',
    });

    // 两个窗口都应收到推送
    const mainCalls = vi.mocked(mainWindow.webContents.send).mock.calls;
    const extraCalls = vi.mocked(extraWin.webContents.send).mock.calls;
    expect(mainCalls.length).toBeGreaterThanOrEqual(1);
    expect(extraCalls.length).toBeGreaterThanOrEqual(1);

    // 两个窗口收到的 payload 一致
    const [mainChannel, mainPayload] = mainCalls[0]!;
    const [extraChannel, extraPayload] = extraCalls[0]!;
    expect(mainChannel).toBe(IPC_CHANNELS.ACTIVE_TRAINING_UPDATED);
    expect(extraChannel).toBe(IPC_CHANNELS.ACTIVE_TRAINING_UPDATED);
    expect(mainPayload).toEqual(extraPayload);

    off();
  });

  // ─── E2E-4: 取消订阅后停止推送 ───

  it('E2E-4: 取消订阅函数 off() 停止推送', () => {
    // 先取消订阅
    off();

    // 清空 mock 计数
    vi.mocked(mainWindow.webContents.send).mockClear();

    // 触发状态变更
    service.start({
      sessionId: 'sess-e2e-unsub',
      challengeId: 'CH-E2E-4',
      steps: TEST_STEPS,
      syndromeId: 'P003',
      source: 'training_triggered',
    });

    // 取消订阅后不应有推送
    expect(mainWindow.webContents.send).not.toHaveBeenCalled();
  });

  // ─── E2E-5: 训练生命周期结束后,新 start() 仍触发推送 ───

  it('E2E-5: 训练完成后再 start 新训练,推送链路继续工作', () => {
    const sessionId = 'sess-e2e-reuse';

    // 第一轮: 启动 → 完成
    service.start({
      sessionId,
      challengeId: 'CH-FIRST',
      steps: TEST_STEPS,
      syndromeId: 'P003',
      source: 'training_triggered',
    });
    service.complete(sessionId, 'rec-first');

    vi.mocked(mainWindow.webContents.send).mockClear();

    // 第二轮: 重新启动
    service.start({
      sessionId,
      challengeId: 'CH-SECOND',
      steps: TEST_STEPS,
      syndromeId: 'P005',
      source: 'user_request',
    });

    // 第二轮应触发新的 start 推送
    const calls = vi.mocked(mainWindow.webContents.send).mock.calls;
    expect(calls.length).toBeGreaterThanOrEqual(1);
    const [channel, payload] = calls[0]!;
    expect(channel).toBe(IPC_CHANNELS.ACTIVE_TRAINING_UPDATED);
    expect(payload).toMatchObject({
      type: 'start',
      sessionId,
    });
    expect((payload as ActiveTrainingUpdatedEvent).state.challengeId).toBe('CH-SECOND');

    off();
  });
});
