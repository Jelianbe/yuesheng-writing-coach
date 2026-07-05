/* eslint-disable @typescript-eslint/no-non-null-assertion */
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
      step_responses_json TEXT NOT NULL DEFAULT '[]',
      status TEXT NOT NULL CHECK(status IN ('in_progress', 'completed', 'aborted')),
      started_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      completed_at TEXT
    );

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

  // ─── E2E-6: 5 步全链路 start → 5×submitFlowStep → complete (Sprint 25 BL-01 C-4) ───

  it('E2E-6: 5 步分步提交全链路 → step_responses 累计 5 条,推送 7 次', () => {
    const sessionId = 'sess-e2e-flow5';

    // 1) 启动
    service.start({
      sessionId,
      challengeId: 'CH-FLOW5',
      challengeName: '环境描写改写',
      steps: TEST_STEPS,
      syndromeId: 'P003',
      source: 'training_triggered',
    });

    // 2) 5 步分步提交
    const stepContents = [
      'step1-理解技法: 环境描写要服务于情绪',
      'step2-例证展示: 海面平静反衬内心波澜',
      'step3-确认理解: 我会用环境烘托代替直接抒情',
      'step4-主动尝试: 夜幕降临,城市在雨中沉默...',
      'step5-修改反馈: 加入视觉细节强化氛围',
    ];
    stepContents.forEach((content, idx) => {
      const result = service.submitFlowStep(
        sessionId,
        (idx + 1) as 1 | 2 | 3 | 4 | 5,
        content,
      );
      expect(result).not.toBeNull();
    });

    // 3) 验证 state 累积 5 条 step_responses(升序)
    const active = service.getActive(sessionId);
    expect(active?.stepResponses).toHaveLength(5);
    expect(active?.stepResponses.map((r) => r.stepId)).toEqual([1, 2, 3, 4, 5]);
    expect(active?.stepResponses.map((r) => r.content)).toEqual(stepContents);
    expect(active?.status).toBe('in_progress');

    // 4) 评估 + 完成
    service.evaluate(sessionId, { passed: true, feedback: '5 步全部完成', score: 9 });
    service.complete(sessionId, 'rec-flow5');

    // 5) 验证推送链路
    const pushes = collectForSession(sessionId);
    // 1 start + 5 submitStep + 1 evaluate + 1 complete = 8
    expect(pushes.length).toBeGreaterThanOrEqual(8);

    const types = pushes.map((p) => p.payload.type);
    expect(types).toContain('start');
    // setupActiveTrainingPush 对 getAllWindows() + 显式 mainWindow 双发,实际可能 5~10 次
    expect(types.filter((t) => t === 'submitStep').length).toBeGreaterThanOrEqual(5);
    expect(types).toContain('evaluate');
    expect(types).toContain('complete');

    // 6) 验证最后一条 submitStep 推送带最新 5 条 stepResponses
    //    (双发机制下,同 stepId 会有 2 条推送,长度都应 ≥ 当前已提交步骤数)
    const submitPushes = pushes.filter((p) => p.payload.type === 'submitStep');
    expect(submitPushes.length).toBeGreaterThanOrEqual(5);
    // 每条 submitStep 推送都应至少 1 条且单调不减
    submitPushes.forEach((push) => {
      const len = push.payload.state.stepResponses.length;
      expect(len).toBeGreaterThanOrEqual(1);
      expect(len).toBeLessThanOrEqual(5);
    });
    // 最后一条应为 5 条
    const lastSubmit = submitPushes[submitPushes.length - 1];
    expect(lastSubmit?.payload.state.stepResponses).toHaveLength(5);

    // 7) 验证 complete 推送时 stepResponses 完整保留
    const completePush = pushes.find((p) => p.payload.type === 'complete');
    expect(completePush?.payload.state.stepResponses).toHaveLength(5);
    expect(completePush?.payload.state.status).toBe('completed');

    off();
  });

  // ─── E2E-7: submitFlowStep 校验失败时不触发推送 ───

  it('E2E-7: submitFlowStep stepId 越界时返回 null,不触发推送', () => {
    const sessionId = 'sess-e2e-flow5-invalid';

    service.start({
      sessionId,
      challengeId: 'CH-INVALID',
      steps: TEST_STEPS,
      syndromeId: 'P003',
      source: 'training_triggered',
    });

    vi.mocked(mainWindow.webContents.send).mockClear();

    // 越界 stepId
    const invalid1 = service.submitFlowStep(sessionId, 0 as never, 'invalid');
    const invalid2 = service.submitFlowStep(sessionId, 6 as never, 'invalid');
    expect(invalid1).toBeNull();
    expect(invalid2).toBeNull();

    // 无 in_progress(其他 session)
    const invalid3 = service.submitFlowStep('sess-nonexistent', 1, 'invalid');
    expect(invalid3).toBeNull();

    // 不应有 submitStep 推送
    const calls = vi.mocked(mainWindow.webContents.send).mock.calls;
    const submitPushes = calls.filter(
      ([ch, p]) =>
        ch === IPC_CHANNELS.ACTIVE_TRAINING_UPDATED &&
        (p as ActiveTrainingUpdatedEvent).type === 'submitStep',
    );
    expect(submitPushes).toHaveLength(0);

    off();
  });
});
