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
  createStartReadingAction,
  createSubmitStepAction,
  createLoadHistoryAction,
  createRefreshFromDiagnosisAction,
  createEvaluateTrainingAction,
  createDeriveBehaviorAction,
} from './training.actions';
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
}));
