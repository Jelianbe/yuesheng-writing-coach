/**
 * 训练状态管理（路径 B：训练工坊）— 核心 Store 定义
 *
 * 类型与常量 → training.types.ts
 * 大型 Action  → training.actions.ts
 * 选择器       → training.selectors.ts
 */

import { create } from 'zustand';
import type { TrainingState } from './training.types';
import {
  createStartAction,
  createSubmitStepAction,
  createEvaluateTrainingAction,
  createDeriveBehaviorAction,
} from './training.actions';
import { createStartReadingAction } from './training-reading.actions';
import { createLoadHistoryAction, createRefreshFromDiagnosisAction } from './training-data.actions';
import { RetroApi } from '../../shared/api-contracts/retro.contract';
import { getInvoke } from '../utils/ipc';
export { selectCenterMode, selectActiveTraining, selectErrorCards, selectRecommendations, selectTrainingHistory, selectIsLoading } from './training.selectors';
export type { TrainingState, TrainingSubmissionResult } from './training.types';
export { DEFAULT_STEPS, READING_STEPS } from './training.types';

// ===== Store =====

export const useTrainingStore = create<TrainingState>((set, get) => ({
  centerMode: 'chat',
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
  // A3: 自荐阅读框架
  lastEvaluationScore: null,
  lastSyndromeId: null,
  derivationLoading: false,
  derivationResult: null,
  derivationError: null,
  retroSummary: null,
  retroLoading: false,

  // ===== 模式切换 =====

  enterWorkshop: async () => {
    set({ centerMode: 'training' });
    await get().refreshFromDiagnosis();
    const { useChatStore } = await import('./chat.store');
    const sessionId = useChatStore.getState().currentSessionId;
    if (sessionId) {
      await get().loadHistory(sessionId);
    }
  },

  backToChat: () => {
    const state = get();
    if (state.evaluationResult || state.submissionResult) {
      set({ centerMode: 'chat', activeTraining: null, submissionResult: null, evaluationResult: null });
    } else {
      set({ centerMode: 'chat' });
    }
  },

  // Sprint 3: 进入编辑器
  enterEditor: () => {
    set({ centerMode: 'editor' });
  },

  // ===== 训练操作（大型 action 从 training.actions.ts 引入） =====

  startTraining: createStartAction(set, get),

  /** B-02: 阅读前置任务 */
  startReading: createStartReadingAction(set, get),

  /** M4: 关闭阅读完成横幅 */
  dismissReadingComplete: () => set({ readingComplete: false }),

  updateDraft: (content: string) => {
    set((state) => {
      if (!state.activeTraining) return {};
      return { activeTraining: { ...state.activeTraining, userDraft: content } };
    });
  },

  submitStep: createSubmitStepAction(set, get),

  skipTraining: async () => {
    set({ activeTraining: null, error: null, isLoading: false });
  },

  // ===== 数据加载（大型 action 从 training.actions.ts 引入） =====

  loadHistory: createLoadHistoryAction(set, get),

  refreshFromDiagnosis: createRefreshFromDiagnosisAction(set, get),

  // ===== 桥接推荐 =====

  setBridgeRecommendation: (rec) => { set({ bridgeRecommendation: rec }); },
  dismissBridge: () => { set({ bridgeRecommendation: null }); },

  // ===== 评估（从 training.actions.ts 引入） =====

  evaluateTraining: createEvaluateTrainingAction(set, get),

  // ===== C2: 行为推导（从 training.actions.ts 引入） =====

  deriveBehavior: createDeriveBehaviorAction(set, get),
  resetDerivation: () => { set({ derivationResult: null, derivationError: null, derivationLoading: false }); },

  // ===== X-02: 编辑器写入 =====

  sendToEditor: () => {
    const { activeTraining } = get();
    if (!activeTraining?.userDraft) return;
    // 将改写结果暂存到 chapter store 的 pendingRewrite，由编辑器横幅消费
    void import('./chapter.store').then(({ useChapterStore }) => {
      useChapterStore.setState({ pendingRewrite: activeTraining.userDraft });
    });
  },

  // F-03: 进入复盘总结
  enterRetro: async (sessionId: string) => {
    set({ retroLoading: true });
    try {
      const result = await getInvoke()(RetroApi.generate.channel, { sessionId }) as { success: boolean; data: TrainingState['retroSummary'] };
      if (result.success && result.data) {
        set({ retroSummary: result.data, centerMode: 'retro', retroLoading: false });
      } else {
        set({ retroLoading: false });
      }
    } catch (err) {
      console.error('[TrainingStore] enterRetro failed:', err);
      set({ retroLoading: false });
    }
  },
}));
