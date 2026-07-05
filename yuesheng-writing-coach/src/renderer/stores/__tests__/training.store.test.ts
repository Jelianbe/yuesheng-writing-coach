/* eslint-disable @typescript-eslint/no-non-null-assertion */
// @vitest-environment jsdom
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { useTrainingStore } from '../training.store';
import { useChatStore } from '../chat.store';
import { useDiagStore } from '../diag.store';
import { IPC_CHANNELS } from '../../../shared/constants';

// Sprint 26 阶段 3.6: 调用方迁移到 service-bridge 单端点,
// 训练 store 调 training:history / training:complete 均经 BRIDGE_INVOKE 通道,
// payload 为 { method, args } 形式。测试验证 BRIDGE_INVOKE 通道与方法名。
const BRIDGE_INVOKE_CHANNEL = IPC_CHANNELS.BRIDGE_INVOKE;

function clearMock() {
  delete window.electronAPI;
}

/** 辅助：等待微任务队列，使得 Zustand 中的 await 执行完毕 */
function flushPromises() {
  return new Promise((r) => setTimeout(r, 0));
}

describe('TrainingStore', () => {
  beforeEach(() => {
    useTrainingStore.setState({
      centerMode: 'chat',
      errorCards: [],
      recommendations: [],
      activeTraining: null,
      history: [],
      submissionResult: null,
      isLoading: false,
      error: null,
      bridgeRecommendation: null,
    });

    useChatStore.setState({
      messages: [],
      currentSessionId: 'test-session',
      isLoading: false,
      error: null,
    });

    useDiagStore.setState({
      currentDiagnosis: null,
      history: {},
      error: null,
      isLoading: false,
    });

    clearMock();
    vi.restoreAllMocks();
  });

  // ===== 基础状态 =====

  describe('基础状态', () => {
    it('初始状态为 chat 模式', () => {
      const state = useTrainingStore.getState();
      expect(state.centerMode).toBe('chat');
      expect(state.errorCards).toEqual([]);
      expect(state.activeTraining).toBeNull();
      expect(state.isLoading).toBe(false);
      expect(state.error).toBeNull();
      expect(state.bridgeRecommendation).toBeNull();
    });
  });

  // ===== 模式切换 =====

  describe('模式切换', () => {
    it('backToChat 切换到 chat 模式', () => {
      useTrainingStore.setState({ centerMode: 'training' });
      useTrainingStore.getState().backToChat();
      expect(useTrainingStore.getState().centerMode).toBe('chat');
    });

    it('backToChat 不重置 activeTraining', () => {
      const mockSession = {
        challengeId: 'CH-001',
        challengeName: '测试训练',
        challengeDescription: '测试描述',
        mode: 'generic',
        steps: [
          { id: 'review', title: '阅读', description: '先阅读', status: 'active' as const },
        ],
        currentStepIndex: 0,
        originalQuote: '引用原文',
        constraint: '约束条件',
        userDraft: '我的草稿',
      };
      useTrainingStore.setState({ centerMode: 'training', activeTraining: mockSession as any });
      useTrainingStore.getState().backToChat();
      const state = useTrainingStore.getState();
      expect(state.centerMode).toBe('chat');
      expect(state.activeTraining).toBe(mockSession as any);
    });
  });

  // ===== 桥接卡片 =====

  describe('桥接卡片', () => {
    it('setBridgeRecommendation 设置推荐', () => {
      const rec = {
        challengeId: 'CH-001',
        challengeName: '测试',
        description: 'desc',
        syndromeId: 'P004',
        severity: 'L2' as const,
        tier: 'structural',
        constraint: '限',
        expectedOutcome: '效果',
        mode: 'generic',
      };
      useTrainingStore.getState().setBridgeRecommendation(rec);
      expect(useTrainingStore.getState().bridgeRecommendation).toEqual(rec);
    });

    it('dismissBridge 清除推荐', () => {
      const rec = {
        challengeId: 'CH-001',
        challengeName: '测试',
        description: 'desc',
        syndromeId: 'P004',
        severity: 'L2' as const,
        tier: 'structural',
        constraint: '',
        expectedOutcome: '效果',
        mode: 'generic',
      };
      useTrainingStore.setState({ bridgeRecommendation: rec });
      useTrainingStore.getState().dismissBridge();
      expect(useTrainingStore.getState().bridgeRecommendation).toBeNull();
    });
  });

  // ===== 更新草稿 =====

  describe('updateDraft', () => {
    it('有活跃训练时更新草稿', () => {
      useTrainingStore.setState({
        activeTraining: {
          challengeId: 'CH-001',
          challengeName: '测试',
          challengeDescription: '',
          mode: 'generic',
          steps: [],
          currentStepIndex: 0,
          originalQuote: '',
          constraint: '',
          userDraft: '',
        } as any,
      });
      useTrainingStore.getState().updateDraft('新的改写');
      expect(useTrainingStore.getState().activeTraining!.userDraft).toBe('新的改写');
    });

    it('无活跃训练时静默不更新', () => {
      expect(() => {
        useTrainingStore.getState().updateDraft('内容');
      }).not.toThrow();
    });
  });

  // ===== skipTraining =====

  describe('skipTraining', () => {
    it('清除 activeTraining', () => {
      useTrainingStore.setState({
        activeTraining: { challengeId: 'CH-001' } as any,
        error: '旧错误',
      });
      useTrainingStore.getState().skipTraining();
      const state = useTrainingStore.getState();
      expect(state.error).toBeNull();
      expect(state.isLoading).toBe(false);
    });
  });

  // ===== startTraining =====

  describe('startTraining', () => {
    it('无活跃会话时设置错误', async () => {
      useChatStore.setState({ currentSessionId: '' });
      await useTrainingStore.getState().startTraining('CH-001');
      expect(useTrainingStore.getState().error).toBeTruthy();
      expect(useTrainingStore.getState().isLoading).toBe(false);
    });

    it('IPC 返回 error 时设置错误', async () => {
      // bridge 模式: handler 抛错 → createHandler 包装为 { success: false, error: '...' }
      //       → serviceBridge.invoke 内部 console.error + return null
      //       → store 抛 'training:assign returned null'
      // 测试用 reject 模拟抛错路径(与 bridge 端行为一致)
      const invoke = vi.fn().mockRejectedValue(new Error('assign failed'));
      window.electronAPI = { invoke: invoke as any, on: vi.fn() as any, send: vi.fn() as any };
      useTrainingStore.setState({
        recommendations: [{ challengeId: 'CH-001', syndromeId: 'P004', description: 'desc', mode: 'generic' } as any],
        errorCards: [{ syndromeId: 'P004', lastQuote: '原文引用' } as any],
      });
      await useTrainingStore.getState().startTraining('CH-001');
      expect(useTrainingStore.getState().error).toBe('Error: assign failed');
      expect(useTrainingStore.getState().isLoading).toBe(false);
    });

    it('IPC 返回记录时创建活跃训练', async () => {
      // bridge 模式: createHandler 包装为 { success: true, data: { record: { id: 'rec-001' } } }
      const invoke = vi.fn().mockResolvedValue({ success: true, data: { record: { id: 'rec-001' } } });
      window.electronAPI = { invoke: invoke as any, on: vi.fn() as any, send: vi.fn() as any };
      useTrainingStore.setState({
        recommendations: [{
          challengeId: 'CH-001',
          challengeName: '信息硬塞训练',
          description: '请改写这段文字',
          syndromeId: 'P004',
          mode: 'generic',
          constraint: '不直接交代信息',
        } as any],
        errorCards: [{
          syndromeId: 'P004',
          lastQuote: '他资质平平，只是一个普通的散修。',
        } as any],
      });
      await useTrainingStore.getState().startTraining('CH-001');
      const state = useTrainingStore.getState();
      expect(state.activeTraining).not.toBeNull();
      expect(state.activeTraining!.challengeName).toBe('信息硬塞训练');
      expect(state.activeTraining!.originalQuote).toBe('他资质平平，只是一个普通的散修。');
      expect(state.activeTraining!.constraint).toBe('不直接交代信息');
      expect(state.activeTraining!.recordId).toBe('rec-001');
      expect(state.activeTraining!.userDraft).toBe('');
      expect(state.activeTraining!.currentStepIndex).toBe(0);
      expect(state.activeTraining!.steps[0].status).toBe('active');
    });
  });

  // ===== loadHistory =====

  describe('loadHistory', () => {
    it('设置加载状态后加载历史记录', async () => {
      const mockRecords = [
        { recordId: 'r1', syndromeId: 'P004', title: '信息硬塞' },
        { recordId: 'r2', syndromeId: 'P002', title: '角色工具人化' },
      ];
      // bridge 模式: createHandler 包装为 { success: true, data: { records } }
      const invoke = vi.fn().mockResolvedValue({ success: true, data: { records: mockRecords } });
      window.electronAPI = { invoke: invoke as any, on: vi.fn() as any, send: vi.fn() as any };
      await useTrainingStore.getState().loadHistory('test-session');
      const expected = [
        { id: 'r1', sessionId: 'test-session', challengeId: 'P004', challengeName: '信息硬塞', status: 'completed', score: undefined, assignedAt: '' },
        { id: 'r2', sessionId: 'test-session', challengeId: 'P002', challengeName: '角色工具人化', status: 'completed', score: undefined, assignedAt: '' },
      ];
      expect(useTrainingStore.getState().history).toEqual(expected as any);
      expect(useTrainingStore.getState().isLoading).toBe(false);
      expect(invoke).toHaveBeenCalledWith(
        BRIDGE_INVOKE_CHANNEL,
        { method: 'training:history', args: { sessionId: 'test-session' } },
      );
    });

    it('IPC 错误时设置 error', async () => {
      // bridge 模式: handler 抛错 → serviceBridge.invoke 内部 console.error + return null
      // 测试用 reject 模拟抛错路径(与 bridge 端行为一致)
      const invoke = vi.fn().mockRejectedValue(new Error('load failed'));
      window.electronAPI = { invoke: invoke as any, on: vi.fn() as any, send: vi.fn() as any };
      await useTrainingStore.getState().loadHistory('test-session');
      expect(useTrainingStore.getState().error).toBe('Error: load failed');
      expect(useTrainingStore.getState().isLoading).toBe(false);
    });

    it('无 electronAPI 时设置错误', async () => {
      (window as any).electronAPI = undefined;
      await useTrainingStore.getState().loadHistory('test-session');
      expect(useTrainingStore.getState().error).toBeTruthy();
      expect(useTrainingStore.getState().isLoading).toBe(false);
    });
  });

  // ===== refreshFromDiagnosis =====

  describe('refreshFromDiagnosis', () => {
    it('无活跃会话时清空数据', async () => {
      useChatStore.setState({ currentSessionId: '' });
      useTrainingStore.setState({ errorCards: [{ syndromeId: 'P001' } as any] });
      await useTrainingStore.getState().refreshFromDiagnosis();
      const state = useTrainingStore.getState();
      expect(state.errorCards).toEqual([]);
      expect(state.recommendations).toEqual([]);
      expect(state.isLoading).toBe(false);
    });

    it('从 diag.store 聚合 errorCards 并获取推荐', async () => {
      const now = new Date().toISOString();
      useDiagStore.setState({
        history: {
          'test-session': [{
            sessionId: 'test-session',
            messageId: 'msg-1',
            syndromes: [
              { id: 'P004', name: '信息硬塞', severity: 'L2', evidence: ['他资质平平'], score: 0.75, suggestedActions: [] },
              { id: 'P002', name: '角色工具化', severity: 'L3', evidence: ['散修是最底层'], score: 0.82, suggestedActions: [] },
            ],
            suggestedActions: [],
            confidence: 0.85,
            timestamp: now,
          }],
        },
      });

      const mockRecs = [
        { challengeId: 'CH-001', challengeName: '信息硬塞', syndromeId: 'P004', severity: 'L2', tier: 'structural', mode: 'generic' },
        { challengeId: 'CH-002', challengeName: '角色工具化', syndromeId: 'P002', severity: 'L3', tier: 'structural', mode: 'generic' },
      ];
      // bridge 模式: createHandler 包装为 { success: true, data: { recommendations: ... } }
      const invoke = vi.fn().mockResolvedValue({ success: true, data: { recommendations: mockRecs } });
      window.electronAPI = { invoke: invoke as any, on: vi.fn() as any, send: vi.fn() as any };

      await useTrainingStore.getState().refreshFromDiagnosis();
      await flushPromises();

      const state = useTrainingStore.getState();
      expect(state.errorCards).toHaveLength(2);
      expect(state.errorCards[0].syndromeId).toBe('P002'); // L3 优先
      expect(state.errorCards[1].syndromeId).toBe('P004');
      expect(state.recommendations).toEqual(mockRecs as any);
      expect(state.bridgeRecommendation).toEqual(mockRecs[0] as any);
    });

    it('无诊断历史时清空 errorCards', async () => {
      const invoke = vi.fn().mockResolvedValue({ success: true, data: { recommendations: [] } });
      window.electronAPI = { invoke: invoke as any, on: vi.fn() as any, send: vi.fn() as any };
      await useTrainingStore.getState().refreshFromDiagnosis();
      expect(useTrainingStore.getState().errorCards).toEqual([]);
    });
  });

  // ===== submitStep =====

  describe('submitStep', () => {
    it('无活跃训练时设置错误', async () => {
      await useTrainingStore.getState().submitStep();
      expect(useTrainingStore.getState().error).toBeTruthy();
      expect(useTrainingStore.getState().isLoading).toBe(false);
    });

    it('Step 0 → 推进到 Step 1', async () => {
      useTrainingStore.setState({
        activeTraining: {
          challengeId: 'CH-001',
          challengeName: '测试',
          challengeDescription: '',
          mode: 'generic',
          steps: [
            { id: 'review', title: '阅读', description: '先阅读', status: 'active' as const },
            { id: 'rewrite', title: '改写', description: '动手改写', status: 'pending' as const },
            { id: 'submit', title: '提交', description: '提交评估', status: 'pending' as const },
          ],
          currentStepIndex: 0,
          originalQuote: '原文',
          constraint: '约束',
          userDraft: '',
        } as any,
      });
      await useTrainingStore.getState().submitStep();
      const state = useTrainingStore.getState();
      expect(state.activeTraining!.currentStepIndex).toBe(1);
      expect(state.activeTraining!.steps[0].status).toBe('completed');
      expect(state.activeTraining!.steps[1].status).toBe('active');
    });

    it('Step 1 提交后评估未通过时停在 Step 1 并显示反馈', async () => {
      useTrainingStore.setState({
        activeTraining: {
          challengeId: 'CH-001',
          challengeName: '测试',
          challengeDescription: '描述',
          mode: 'generic',
          steps: [
            { id: 'review', title: '阅读', description: '', status: 'completed' as const },
            { id: 'rewrite', title: '改写', description: '', status: 'active' as const },
            { id: 'submit', title: '提交', description: '', status: 'pending' as const },
          ],
          currentStepIndex: 1,
          originalQuote: '原文',
          constraint: '约束',
          userDraft: '我的改写稿',
        } as any,
      });
      // bridge 模式: training:submit 评估结果经 createHandler 包装
      const invoke = vi.fn().mockResolvedValue({ success: true, data: { passed: false, feedback: '改写还不够，缺少具体动作。' } });
      window.electronAPI = { invoke: invoke as any, on: vi.fn() as any, send: vi.fn() as any };
      await useTrainingStore.getState().submitStep();
      const state = useTrainingStore.getState();
      expect(state.activeTraining!.currentStepIndex).toBe(1);
      expect(state.submissionResult).toEqual({ passed: false, feedback: '改写还不够，缺少具体动作。' });
      expect(state.isLoading).toBe(false);
    });

    it('Step 1 提交后评估通过时推进到 Step 2', async () => {
      useTrainingStore.setState({
        activeTraining: {
          challengeId: 'CH-001',
          challengeName: '测试',
          challengeDescription: '描述',
          mode: 'generic',
          steps: [
            { id: 'review', title: '阅读', description: '', status: 'completed' as const },
            { id: 'rewrite', title: '改写', description: '', status: 'active' as const },
            { id: 'submit', title: '提交', description: '', status: 'pending' as const },
          ],
          currentStepIndex: 1,
          originalQuote: '原文',
          constraint: '约束',
          userDraft: '改写稿已通过',
        } as any,
      });
      // bridge 模式: training:submit 评估结果经 createHandler 包装
      const invoke = vi.fn().mockResolvedValue({ success: true, data: { passed: true, feedback: '改得很好！' } });
      window.electronAPI = { invoke: invoke as any, on: vi.fn() as any, send: vi.fn() as any };
      await useTrainingStore.getState().submitStep();
      const state = useTrainingStore.getState();
      expect(state.activeTraining!.currentStepIndex).toBe(2);
      expect(state.activeTraining!.steps[1].status).toBe('completed');
      expect(state.activeTraining!.steps[2].status).toBe('active');
      expect(state.submissionResult).toEqual({ passed: true, feedback: '改得很好！' });
    });

    it('Step 2 完成后调用 complete IPC 并保留评估视图', async () => {
      useTrainingStore.setState({
        activeTraining: {
          challengeId: 'CH-001',
          challengeName: '测试',
          challengeDescription: '',
          mode: 'generic',
          steps: [
            { id: 'review', title: '阅读', description: '', status: 'completed' as const },
            { id: 'rewrite', title: '改写', description: '', status: 'completed' as const },
            { id: 'submit', title: '提交', description: '', status: 'active' as const },
          ],
          currentStepIndex: 2,
          originalQuote: '原文',
          constraint: '',
          userDraft: '最终稿',
          recordId: 'rec-001',
        } as any,
        submissionResult: { passed: true, feedback: '做得好！' },
      });
      // bridge 模式: training:complete 经 BRIDGE_INVOKE 通道, payload { method, args }
      const invoke = vi.fn().mockResolvedValue({ success: true, data: { record: { id: 'rec-001' } } });
      window.electronAPI = { invoke: invoke as any, on: vi.fn() as any, send: vi.fn() as any };
      await useTrainingStore.getState().submitStep();
      const state = useTrainingStore.getState();
      expect(invoke).toHaveBeenCalledWith(
        BRIDGE_INVOKE_CHANNEL,
        expect.objectContaining({
          method: 'training:complete',
          args: expect.objectContaining({ recordId: 'rec-001', userResponse: '最终稿' }),
        }),
      );
      // B3: 评估视图保留，不再自动切回
      expect(state.activeTraining).not.toBeNull();
      expect(state.activeTraining?.currentStepIndex).toBe(2);
      // centerMode 不受影响（测试默认是 chat，B3 不主动改它）
    });
  });
});
