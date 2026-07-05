// @vitest-environment jsdom
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { useTrainingStore } from '../training.store';
import { IPC_CHANNELS } from '../../../shared/constants';

// Sprint 26 阶段 3.6: enterRetro 改走 service-bridge 单端点
const BRIDGE_INVOKE_CHANNEL = IPC_CHANNELS.BRIDGE_INVOKE;

function clearMock() {
  delete window.electronAPI;
}

function flushPromises() {
  return new Promise((r) => setTimeout(r, 0));
}

describe('TrainingStore - Retro', () => {
  beforeEach(() => {
    useTrainingStore.setState({
      centerMode: 'chat',
      retroSummary: null,
      retroLoading: false,
      errorCards: [],
      recommendations: [],
      activeTraining: null,
      history: [],
      submissionResult: null,
      evaluationResult: null,
      isLoading: false,
      error: null,
      bridgeRecommendation: null,
      readingDecision: null,
      readingComplete: false,
      lastEvaluationScore: null,
      lastSyndromeId: null,
      derivationLoading: false,
      derivationResult: null,
      derivationError: null,
    });
    clearMock();
    vi.restoreAllMocks();
  });

  // ===== 初始状态 =====

  describe('初始状态', () => {
    it('retroSummary 初始为 null', () => {
      const state = useTrainingStore.getState();
      expect(state.retroSummary).toBeNull();
    });

    it('retroLoading 初始为 false', () => {
      const state = useTrainingStore.getState();
      expect(state.retroLoading).toBe(false);
    });
  });

  // ===== enterRetro =====

  describe('enterRetro', () => {
    const mockRetroSummary = {
      totalTrainingCount: 5,
      syndromeCount: 2,
      syndromeSummaries: [
        {
          syndromeId: 'P004',
          syndromeName: '信息硬塞',
          trainingCount: 3,
          initialScore: 3,
          currentScore: 7,
          improvement: 4,
          mastered: false,
        },
        {
          syndromeId: 'P002',
          syndromeName: '角色工具化',
          trainingCount: 2,
          initialScore: 4,
          currentScore: 8,
          improvement: 4,
          mastered: true,
        },
      ],
      overallImprovement: 4,
      masteredTechniques: ['角色工具化'],
      recommendedFocus: ['信息硬塞'],
      summary: '你在写作方面有显著进步。',
    };

    it('成功时设置 retroSummary 并切换 centerMode 为 retro', async () => {
      const invoke = vi.fn().mockResolvedValue({ success: true, data: mockRetroSummary });
      window.electronAPI = { invoke: invoke as any, on: vi.fn() as any, send: vi.fn() as any };

      const enterRetroPromise = useTrainingStore.getState().enterRetro('session-1');
      // 加载中
      expect(useTrainingStore.getState().retroLoading).toBe(true);
      await enterRetroPromise;

      const state = useTrainingStore.getState();
      expect(state.retroLoading).toBe(false);
      expect(state.retroSummary).toEqual(mockRetroSummary);
      expect(state.centerMode).toBe('retro');
      expect(invoke).toHaveBeenCalledWith(
        BRIDGE_INVOKE_CHANNEL,
        { method: 'retro:generate', args: { sessionId: 'session-1' } },
      );
    });

    it('IPC 返回失败时 retroSummary 保持 null', async () => {
      const invoke = vi.fn().mockResolvedValue({ success: false });
      window.electronAPI = { invoke: invoke as any, on: vi.fn() as any, send: vi.fn() as any };

      await useTrainingStore.getState().enterRetro('session-1');

      const state = useTrainingStore.getState();
      expect(state.retroLoading).toBe(false);
      expect(state.retroSummary).toBeNull();
      expect(state.centerMode).toBe('chat');
    });

    it('IPC 抛出异常时 retroSummary 保持 null', async () => {
      const invoke = vi.fn().mockRejectedValue(new Error('Network error'));
      window.electronAPI = { invoke: invoke as any, on: vi.fn() as any, send: vi.fn() as any };

      await useTrainingStore.getState().enterRetro('session-1');

      const state = useTrainingStore.getState();
      expect(state.retroLoading).toBe(false);
      expect(state.retroSummary).toBeNull();
      expect(state.centerMode).toBe('chat');
    });
  });

  // ===== backToChat =====

  describe('backToChat', () => {
    const mockRetroSummary = {
      totalTrainingCount: 3,
      syndromeCount: 1,
      syndromeSummaries: [
        {
          syndromeId: 'P004',
          syndromeName: '信息硬塞',
          trainingCount: 3,
          initialScore: 3,
          currentScore: 7,
          improvement: 4,
          mastered: false,
        },
      ],
      overallImprovement: 4,
      masteredTechniques: [],
      recommendedFocus: ['信息硬塞'],
      summary: '继续加油。',
    };

    it('从 retro 模式返回 chat，retroSummary 被保留', () => {
      useTrainingStore.setState({ centerMode: 'retro', retroSummary: mockRetroSummary });
      useTrainingStore.getState().backToChat();

      const state = useTrainingStore.getState();
      expect(state.centerMode).toBe('chat');
      expect(state.retroSummary).toEqual(mockRetroSummary);
    });
  });

  // ===== 模式切换不影响 retro 数据 =====

  describe('模式切换不影响 retro 数据', () => {
    const mockRetroSummary = {
      totalTrainingCount: 3,
      syndromeCount: 1,
      syndromeSummaries: [
        {
          syndromeId: 'P004',
          syndromeName: '信息硬塞',
          trainingCount: 3,
          initialScore: 3,
          currentScore: 7,
          improvement: 4,
          mastered: false,
        },
      ],
      overallImprovement: 4,
      masteredTechniques: [],
      recommendedFocus: ['信息硬塞'],
      summary: '继续加油。',
    };

    it('从 chat 切换到 training 再切回，retroSummary 数据保留', async () => {
      useTrainingStore.setState({ retroSummary: mockRetroSummary, centerMode: 'chat' });

      // 切换到 training
      useTrainingStore.setState({ centerMode: 'training' });
      expect(useTrainingStore.getState().retroSummary).toEqual(mockRetroSummary);
      await flushPromises();

      // 切回 chat
      useTrainingStore.getState().backToChat();
      expect(useTrainingStore.getState().centerMode).toBe('chat');
      expect(useTrainingStore.getState().retroSummary).toEqual(mockRetroSummary);
    });
  });
});
