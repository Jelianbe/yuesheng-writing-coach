/**
 * 教学状态 Handler 集成测试
 *
 * 测试目标：
 * 1. teachingState:get/update/confirm 通道的正确性
 * 2. 状态机阶段流转逻辑
 * 3. 边界条件和错误处理
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

vi.mock('electron', () => ({
  ipcMain: {
    handle: vi.fn(),
    removeHandler: vi.fn(),
  },
  BrowserWindow: vi.fn().mockImplementation(() => ({
    webContents: { send: vi.fn() },
    on: vi.fn(),
  })),
}));

vi.mock('../../shared/constants', () => ({
  IPC_CHANNELS: {
    TEACHING_STATE_GET: 'teachingState:get',
    TEACHING_STATE_UPDATE: 'teachingState:update',
    TEACHING_STATE_CONFIRM: 'teachingState:confirm',
    TEACHING_STATE_GET_PROMPT: 'teachingState:getPrompt',
    TEACHING_STATE_UPDATE_SUMMARY: 'teachingState:updateSummary',
    TEACHING_STATE_UPDATED: 'teachingState:updated',
  },
}));

// 模拟 TeachingStateStore：使用 class 确保支持 new 操作符
const mockStoreInstance = {
  getOrCreate: vi.fn(),
  getBySession: vi.fn(),
  update: vi.fn(),
  deleteBySession: vi.fn(),
};

vi.mock('../../services/teaching-state.store', () => ({
  TeachingStateStore: class {
    constructor() {
      return mockStoreInstance;
    }
  },
}));

vi.mock('better-sqlite3', () => ({
  default: vi.fn(() => ({ prepare: vi.fn(), exec: vi.fn(), close: vi.fn() })),
}));

describe('教学状态 Handler', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.resetAllMocks();
  });

  describe('teachingState:get', () => {
    it('会话无状态时返回默认初始化状态', async () => {
      mockStoreInstance.getOrCreate.mockReturnValue({
        sessionId: 'test-session',
        currentPhase: 'P0_INIT',
        currentSubphase: 'S1_INIT',
        completedActions: [],
        activeProblems: [],
        nextSuggestedActions: [],
        lastUserConfirmation: null,
        diagnosisSummary: '',
        updatedAt: new Date().toISOString(),
      });

      const { registerTeachingStateHandlers, initStore } = await import('../teaching-state.handler');
      initStore({} as any);
      registerTeachingStateHandlers();

      const { ipcMain } = await import('electron');
      const handleCalls = (ipcMain.handle as any).mock.calls;
      const getHandler = handleCalls.find((c: any[]) => c[0] === 'teachingState:get');

      const result = await getHandler[1]({}, { sessionId: 'test-session' });
      expect(result.data.currentPhase).toBe('P0_INIT');
      expect(result.data.currentSubphase).toBe('S1_INIT');
      expect(result.data.completedActions).toEqual([]);
    });

    it('会话已有状态时返回存储的状态', async () => {
      const now = new Date().toISOString();
      mockStoreInstance.getOrCreate.mockReturnValue({
        sessionId: 'test-session',
        currentPhase: 'P2_PRACTICE_LOOP',
        currentSubphase: 'S2_IDENTIFY',
        completedActions: ['diagnosis_viewed'],
        activeProblems: [{
          id: 'P004', name: '信息硬塞', severity: 'L2',
          evidence: ['他资质平平'], score: 0.75,
          firstDetected: now, status: 'active', suggestedActions: [],
        }],
        nextSuggestedActions: [],
        lastUserConfirmation: null,
        diagnosisSummary: '',
        updatedAt: now,
      });

      const { registerTeachingStateHandlers, initStore } = await import('../teaching-state.handler');
      initStore({} as any);
      registerTeachingStateHandlers();

      const { ipcMain } = await import('electron');
      const handleCalls = (ipcMain.handle as any).mock.calls;
      const getHandler = handleCalls.find((c: any[]) => c[0] === 'teachingState:get');

      const result = await getHandler[1]({}, { sessionId: 'test-session' });
      expect(result.data.currentPhase).toBe('P2_PRACTICE_LOOP');
      expect(result.data.currentSubphase).toBe('S2_IDENTIFY');
      expect(result.data.completedActions).toContain('diagnosis_viewed');
      expect(result.data.activeProblems).toHaveLength(1);
    });
  });

  describe('teachingState:confirm', () => {
    it('确认后推进到下一阶段', async () => {
      const now = new Date().toISOString();
      const oldState = {
        sessionId: 'test-session', currentPhase: 'P0_INIT', currentSubphase: 'S1_INIT',
        completedActions: [], activeProblems: [],
        nextSuggestedActions: [], lastUserConfirmation: null,
        diagnosisSummary: '', updatedAt: now,
      };

      mockStoreInstance.getBySession.mockReturnValue(oldState);
      mockStoreInstance.update.mockReturnValue({
        ...oldState,
        currentPhase: 'P1_WORLD',
        completedActions: ['confirmed_phase_0'],
      });

      const { registerTeachingStateHandlers, initStore } = await import('../teaching-state.handler');
      initStore({} as any);
      registerTeachingStateHandlers();

      const { ipcMain } = await import('electron');
      const handleCalls = (ipcMain.handle as any).mock.calls;
      const confirmHandler = handleCalls.find(
        (c: any[]) => c[0] === 'teachingState:confirm'
      );

      const result = await confirmHandler[1]({}, { sessionId: 'test-session' });
      expect(result).toBeDefined();
      expect(result.data.oldState.currentPhase).toBe('P0_INIT');
      expect(result.data.newState.currentPhase).toBe('P1_WORLD');
    });

    it('不存在的会话返回 null', async () => {
      mockStoreInstance.getBySession.mockReturnValue(null);

      const { registerTeachingStateHandlers, initStore } = await import('../teaching-state.handler');
      initStore({} as any);
      registerTeachingStateHandlers();

      const { ipcMain } = await import('electron');
      const handleCalls = (ipcMain.handle as any).mock.calls;
      const confirmHandler = handleCalls.find(
        (c: any[]) => c[0] === 'teachingState:confirm'
      );

      const result = await confirmHandler[1]({}, { sessionId: 'non-existent' });
      expect(result.success).toBe(false);
    });
  });
});
