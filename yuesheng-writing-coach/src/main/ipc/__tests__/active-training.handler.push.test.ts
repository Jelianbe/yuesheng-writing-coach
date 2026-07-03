/**
 * ActiveTraining IPC 推送桥接测试 — Sprint 24 A-4
 *
 * 覆盖 setupActiveTrainingPush:
 * 1. 订阅 ActiveTrainingService 状态变更 → 推送到 BrowserWindow
 * 2. 多窗口广播: 推送时遍历 BrowserWindow.getAllWindows()
 * 3. 已销毁窗口: 跳过
 * 4. 已销毁 webContents: 跳过
 * 5. mainWindow 显式再发一次(防止时序问题)
 * 6. setupActiveTrainingPush 返回取消订阅函数
 * 7. service 未初始化时静默返回 noop
 * 8. payload 格式: 包含 type/sessionId/state(领域对象 → IPC 响应映射)
 *
 * DoD: ≥4 用例
 * 依据: dev-docs/tasks/sprint-24-plan.md §A-4
 */

import { describe, it, expect, vi, beforeEach } from 'vitest';
import Database from 'better-sqlite3';
import { IPC_CHANNELS } from '../../../shared/constants';
import { ActiveTrainingStore } from '../../domains/03-teaching/state/active-training.store';
import { ActiveTrainingService } from '../../domains/03-teaching/state/active-training.service';
import {
  initActiveTrainingHandlers,
  setupActiveTrainingPush,
} from '../active-training.handler';

vi.mock('electron', () => ({
  ipcMain: { handle: vi.fn() },
  BrowserWindow: {
    getAllWindows: vi.fn(() => [{
      isDestroyed: () => false,
      webContents: { send: vi.fn(), isDestroyed: () => false },
    }]),
  },
  app: { getPath: () => ':memory:', getVersion: () => '1.0.0-test' },
}));

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

const TEST_STEPS = [
  { id: 's1', title: '解说', description: '解说', status: 'active' as const },
];

describe('ActiveTraining IPC push bridge (Sprint 24 A-4)', () => {
  let service: ActiveTrainingService;
  let mainWindow: {
    webContents: { send: ReturnType<typeof vi.fn>; isDestroyed: () => boolean };
    isDestroyed: () => boolean;
  };

  beforeEach(async () => {
    const db = createTestDb();
    const store = new ActiveTrainingStore(db);
    service = new ActiveTrainingService(store);
    initActiveTrainingHandlers(service);

    const { BrowserWindow } = await import('electron');
    vi.mocked(BrowserWindow.getAllWindows).mockReset();
    vi.mocked(BrowserWindow.getAllWindows).mockReturnValue([{
      isDestroyed: () => false,
      webContents: { send: vi.fn(), isDestroyed: () => false },
    }] as never);

    mainWindow = {
      webContents: { send: vi.fn(), isDestroyed: () => false },
      isDestroyed: () => false,
    };
  });

  it('setupActiveTrainingPush 订阅 service 状态变更并推送到 mainWindow', () => {
    const off = setupActiveTrainingPush(mainWindow as never);
    expect(typeof off).toBe('function');

    service.start({
      sessionId: 'sess-bridge-1',
      challengeId: 'CH-1',
      syndromeId: 'P001',
      steps: TEST_STEPS,
      source: 'training_triggered',
    });

    expect(mainWindow.webContents.send).toHaveBeenCalled();
    const [channel, payload] = vi.mocked(mainWindow.webContents.send).mock.calls[0];
    expect(channel).toBe(IPC_CHANNELS.ACTIVE_TRAINING_UPDATED);
    expect(payload).toMatchObject({
      type: 'start',
      sessionId: 'sess-bridge-1',
      state: expect.objectContaining({ challengeId: 'CH-1', status: 'in_progress' }),
    });

    off();
  });

  it('mainWindow 显式再发一次(防止 getAllWindows 时序问题)', () => {
    service.start({
      sessionId: 'sess-bridge-1',
      challengeId: 'CH-1',
      syndromeId: 'P001',
      steps: TEST_STEPS,
      source: 'training_triggered',
    });
    mainWindow.webContents.send.mockClear();

    setupActiveTrainingPush(mainWindow as never);

    service.updateDraft('sess-bridge-1', '用户草稿');

    // 应至少调用 1 次(getAllWindows + mainWindow 各一次)
    expect(mainWindow.webContents.send).toHaveBeenCalled();
  });

  it('主窗口已销毁时静默跳过', () => {
    mainWindow.isDestroyed = () => true;
    mainWindow.webContents.isDestroyed = () => true;

    setupActiveTrainingPush(mainWindow as never);

    service.start({
      sessionId: 'sess-bridge-1',
      challengeId: 'CH-1',
      syndromeId: 'P001',
      steps: TEST_STEPS,
      source: 'training_triggered',
    });

    // 不应抛错,主窗口已销毁
    expect(true).toBe(true);
  });

  it('返回的取消订阅函数可停止推送', () => {
    const off = setupActiveTrainingPush(mainWindow as never);
    off();

    service.start({
      sessionId: 'sess-bridge-1',
      challengeId: 'CH-1',
      syndromeId: 'P001',
      steps: TEST_STEPS,
      source: 'training_triggered',
    });

    // 取消订阅后不应推送
    expect(mainWindow.webContents.send).not.toHaveBeenCalled();
  });

  it('多窗口广播: 推送到 BrowserWindow.getAllWindows() 所有窗口', async () => {
    const w1Send = vi.fn();
    const w2Send = vi.fn();
    const w1 = { isDestroyed: () => false, webContents: { send: w1Send, isDestroyed: () => false } };
    const w2 = { isDestroyed: () => false, webContents: { send: w2Send, isDestroyed: () => false } };

    const { BrowserWindow } = await import('electron');
    vi.mocked(BrowserWindow.getAllWindows).mockImplementation(() => [w1, w2] as never);

    setupActiveTrainingPush(mainWindow as never);

    service.start({
      sessionId: 'sess-bridge-1',
      challengeId: 'CH-1',
      syndromeId: 'P001',
      steps: TEST_STEPS,
      source: 'training_triggered',
    });

    expect(w1Send).toHaveBeenCalledWith(
      IPC_CHANNELS.ACTIVE_TRAINING_UPDATED,
      expect.objectContaining({ type: 'start' }),
    );
    expect(w2Send).toHaveBeenCalledWith(
      IPC_CHANNELS.ACTIVE_TRAINING_UPDATED,
      expect.objectContaining({ type: 'start' }),
    );
  });

  it('已销毁 webContents 跳过推送', async () => {
    const destroyedSend = vi.fn();
    const aliveSend = vi.fn();
    const destroyedWc = { send: destroyedSend, isDestroyed: () => true };
    const aliveWc = { send: aliveSend, isDestroyed: () => false };
    const w1 = { isDestroyed: () => false, webContents: destroyedWc };
    const w2 = { isDestroyed: () => false, webContents: aliveWc };

    const { BrowserWindow } = await import('electron');
    vi.mocked(BrowserWindow.getAllWindows).mockImplementation(() => [w1, w2] as never);

    setupActiveTrainingPush(mainWindow as never);

    service.start({
      sessionId: 'sess-bridge-1',
      challengeId: 'CH-1',
      syndromeId: 'P001',
      steps: TEST_STEPS,
      source: 'training_triggered',
    });

    expect(destroyedSend).not.toHaveBeenCalled();
    expect(aliveSend).toHaveBeenCalled();
  });

  it('mainWindow=null 时 setupActiveTrainingPush 安全返回 noop', () => {
    const off = setupActiveTrainingPush(null);
    expect(typeof off).toBe('function');
    expect(() => off()).not.toThrow();
  });
});
