/**
 * 训练状态管理（路径 B：训练工坊）
 *
 * 核心职责：
 * 1. centerMode 模式切换（chat ↔ training）
 * 2. 训练会话状态管理（activeTraining、draft 等）
 * 3. 数据加载（errorCards、recommendations、history 通过 IPC）
 *
 * 切换逻辑保证：
 * - 从 training 切回 chat 时不重置训练状态（草稿保留）
 * - 从 chat 切换到 training 时加载训练工坊数据
 * - 切换不会丢失对话消息（chat.store 独立管理）
 */

import { create } from 'zustand';
import { useChatStore } from './chat.store';
import { useDiagStore } from './diag.store';
import { getInvoke } from '../utils/ipc';
import { IPC_CHANNELS } from '../../shared/constants';
import { severityToNumber } from '../../shared/severity-utils';
import type {
  CenterMode,
  ErrorCard,
  TrainingRecommendation,
  ActiveTrainingSession,
  TrainingStep,
  TrainingRecord,
  EvaluationResult,
} from '../shared/types';

// ===== 类型定义 =====

interface TrainingSubmissionResult {
  passed: boolean;
  feedback: string;
  score?: number;
  improved?: boolean;
  nextStep?: string;
}

interface TrainingState {
  /** 中心面板模式：'chat' = 对话流，'training' = 训练工坊 */
  centerMode: CenterMode;

  /** 错误卡片数据（由历史诊断聚合生成） */
  errorCards: ErrorCard[];

  /** 推荐训练任务 */
  recommendations: TrainingRecommendation[];

  /** 当前活跃的训练会话（null = 未在进行训练） */
  activeTraining: ActiveTrainingSession | null;

  /** 训练历史记录 */
  history: TrainingRecord[];

  /** AI 提交评估结果（null = 未提交或已清除） */
  submissionResult: TrainingSubmissionResult | null;

  /** 训练评分结果（Evaluator Agent 输出，null = 未评估） */
  evaluationResult: EvaluationResult | null;

  /** 加载中 */
  isLoading: boolean;

  /** 加载错误 */
  error: string | null;

  /** 对话流桥接卡片推荐（null = 无推荐或已关闭） */
  bridgeRecommendation: TrainingRecommendation | null;

  // ===== 模式切换 =====

  /** 进入训练工坊（切换 centerMode 为 training） */
  enterWorkshop: () => Promise<void>;

  /** 返回对话流（切换 centerMode 为 chat） */
  backToChat: () => void;

  // ===== 训练操作 =====

  /** 开始训练（选择挑战模板） */
  startTraining: (challengeId: string) => Promise<void>;

  /** 更新草稿 */
  updateDraft: (content: string) => void;

  /** 提交练习步骤 */
  submitStep: () => Promise<void>;

  /** 跳过训练 */
  skipTraining: () => Promise<void>;

  /** 加载训练历史 */
  loadHistory: (sessionId: string) => Promise<void>;

  /** 刷新训练工坊数据（从诊断数据聚合 + IPC 推荐） */
  refreshFromDiagnosis: () => Promise<void>;

  /** 设置桥接卡片推荐（诊断后自动调用） */
  setBridgeRecommendation: (rec: TrainingRecommendation | null) => void;

  /** 关闭桥接卡片 */
  dismissBridge: () => void;

  /** 评估训练（调用 Evaluator Agent 获取评分） */
  evaluateTraining: () => Promise<void>;
}

// ===== 通用三步框架 =====

const DEFAULT_STEPS: Omit<TrainingStep, 'status'>[] = [
  { id: 'review', title: '阅读你的原始文本', description: '回顾你这段写作中暴露的问题' },
  { id: 'rewrite', title: '约束改写', description: '在给定的约束条件下改写这段内容' },
  { id: 'submit', title: '提交评估', description: '提交修改稿并接收 AI 评估反馈' },
];

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

  enterWorkshop: async () => {
    set({ centerMode: 'training' });
    // 进入工坊时刷新数据
    await get().refreshFromDiagnosis();
    const sessionId = useChatStore.getState().currentSessionId;
    if (sessionId) {
      await get().loadHistory(sessionId);
    }
  },

  backToChat: () => {
    set({ centerMode: 'chat' });
    // 注意：不重置 activeTraining，草稿保留
  },

  startTraining: async (challengeId: string) => {
    set({ isLoading: true, error: null });
    try {
      const sessionId = useChatStore.getState().currentSessionId;
      if (!sessionId) throw new Error('No active session');

      const result = await getInvoke()(IPC_CHANNELS.TRAINING_ASSIGN, {
        sessionId,
        challengeId,
      }) as { error?: string; record?: TrainingRecord };

      if (result.error) throw new Error(result.error);

      // 从 recommendations 中查找匹配模板
      const match = get().recommendations.find(r => r.challengeId === challengeId);

      // 从 errorCards 中查找匹配的 evidence
      const errorCard = match
        ? get().errorCards.find(c => c.syndromeId === match.syndromeId)
        : null;

      // 计算长期目标改善进度（基于症候最新严重度）
      // L3=0%, L2=50%, L1=100%
      const longTermProgress = errorCard
        ? Math.round(((3 - severityToNumber(errorCard.severity)) / 2) * 100)
        : 0;

      // 构建活跃训练会话
      const session: ActiveTrainingSession = {
        challengeId,
        challengeName: match?.challengeName ?? challengeId,
        challengeDescription: match?.description ?? '',
        mode: match?.mode ?? 'generic',
        steps: DEFAULT_STEPS.map((s, i) => ({
          ...s,
          status: i === 0 ? 'active' as const : 'pending' as const,
        })),
        currentStepIndex: 0,
        originalQuote: errorCard?.lastQuote ?? '',
        constraint: match?.constraint ?? '',
        userDraft: '',
        recordId: result.record?.id,
        syndromeId: match?.syndromeId,
        targetSyndrome: match?.syndromeName,
        longTermProgress,
      };

      set({ activeTraining: session, isLoading: false, submissionResult: null, evaluationResult: null });
    } catch (error) {
      console.error('[TrainingStore] startTraining failed:', error);
      set({ error: String(error), isLoading: false });
    }
  },

  updateDraft: (content: string) => {
    set((state) => {
      if (!state.activeTraining) return {};
      return {
        activeTraining: { ...state.activeTraining, userDraft: content },
      };
    });
  },

  submitStep: async () => {
    set({ isLoading: true, error: null, submissionResult: null });
    try {
      const active = get().activeTraining;
      if (!active) throw new Error('No active training');

      // Step 2 → 提交给 AI 评估
      if (active.currentStepIndex === 1) {
        const result = await getInvoke()(IPC_CHANNELS.TRAINING_SUBMIT, {
          challengeDescription: active.challengeDescription,
          constraint: active.constraint,
          originalQuote: active.originalQuote,
          userDraft: active.userDraft,
        }) as { passed: boolean; feedback: string; score?: number; improved?: boolean; nextStep?: string };

        // 构建评估结果
        const evalResult: EvaluationResult | null = result.score != null
          ? { score: result.score, feedback: result.feedback, improved: result.improved ?? result.passed, nextStep: result.nextStep ?? '继续练习' }
          : null;

        if (!result.passed) {
          // 未通过：停在 Step 2，展示 AI 反馈，不清空草稿
          set({
            submissionResult: result,
            evaluationResult: evalResult,
            isLoading: false,
          });
          return;
        }

        // 通过：推进到 Step 3（提交评估）
        const updatedSteps = active.steps.map((s, i) => ({
          ...s,
          status: i === active.currentStepIndex ? 'completed' as const : s.status,
        })) as TrainingStep[];
        const step3Index = active.currentStepIndex + 1;
        updatedSteps[step3Index] = { ...updatedSteps[step3Index], status: 'active' as const };

        set({
          activeTraining: {
            ...active,
            currentStepIndex: step3Index,
            steps: updatedSteps,
          },
          submissionResult: { passed: true, feedback: result.feedback, score: result.score, improved: result.improved, nextStep: result.nextStep },
          evaluationResult: evalResult,
          isLoading: false,
        });
        return;
      }

      // 其他步骤（Step 0 → 1，Step 2 完成）
      const nextIndex = active.currentStepIndex + 1;
      if (nextIndex < active.steps.length) {
        const updatedSteps = active.steps.map((s, i) => ({
          ...s,
          status: i < nextIndex ? 'completed' as const : i === nextIndex ? 'active' as const : 'pending' as const,
        }));
        set({
          activeTraining: {
            ...active,
            currentStepIndex: nextIndex,
            steps: updatedSteps,
          },
          isLoading: false,
        });
      } else {
        // 所有步骤完成 → 调用 training:complete 保存记录 + 切回对话
        if (active.recordId) {
          try {
            await getInvoke()(IPC_CHANNELS.TRAINING_COMPLETE, {
              recordId: active.recordId,
              userResponse: active.userDraft,
              aiFeedback: get().submissionResult?.feedback ?? '',
              score: get().evaluationResult?.score,
            });
          } catch (e) {
            console.warn('[TrainingStore] complete IPC failed:', e);
          }
        }

        // 在对话流中添加训练完成反馈消息
        const feedback = get().submissionResult?.feedback;
        const evalResult = get().evaluationResult;
        if (feedback) {
          const { addMessage } = useChatStore.getState();
          const scoreText = evalResult ? ` | 评分：${evalResult.score}/10` : '';
          const improvedText = evalResult?.improved ? ' | 相比原文有改善' : '';
          addMessage({
            id: `training_complete_${Date.now()}`,
            role: 'assistant',
            content: `**训练完成**\n\n你的「${active.challengeName}」练习已完成${scoreText}${improvedText}。\n\n${feedback}${evalResult?.nextStep ? `\n\n**下一步建议：**${evalResult.nextStep}` : ''}`,
            timestamp: Date.now(),
          });
        }

        set({ activeTraining: null, isLoading: false, submissionResult: null, evaluationResult: null });
        // 自动切回对话模式
        set({ centerMode: 'chat' });
      }
    } catch (error) {
      console.error('[TrainingStore] submitStep failed:', error);
      set({ error: String(error), isLoading: false });
    }
  },

  skipTraining: async () => {
    set({ activeTraining: null, error: null, isLoading: false });
  },

  loadHistory: async (sessionId: string) => {
    set({ isLoading: true, error: null });
    try {
      const result = await getInvoke()(IPC_CHANNELS.TRAINING_HISTORY, { sessionId }) as { error?: string; records?: TrainingRecord[] };
      if (result.error) throw new Error(result.error);
      set({ history: result.records ?? [], isLoading: false });
    } catch (error) {
      console.error('[TrainingStore] loadHistory failed:', error);
      set({ error: String(error), isLoading: false });
    }
  },

  refreshFromDiagnosis: async () => {
    set({ isLoading: true, error: null });
    try {
      const sessionId = useChatStore.getState().currentSessionId;
      if (!sessionId) {
        set({ errorCards: [], recommendations: [], isLoading: false });
        return;
      }

      // 1. 从 diag.store 聚合 ErrorCards
      const diagHistory = useDiagStore.getState().getHistoryBySession(sessionId);
      const syndromeMap = new Map<string, {
        syndromeId: string;
        syndromeName: string;
        severity: string;
        diagnosisCount: number;
        lastQuote: string;
        lastDiagnosedAt: string;
      }>();

      const severityOrder: Record<string, number> = { L3: 3, L2: 2, L1: 1 };

      for (const entry of diagHistory) {
        for (const syndrome of entry.syndromes) {
          const existing = syndromeMap.get(syndrome.id);
          if (!existing || new Date(entry.timestamp) > new Date(existing.lastDiagnosedAt)) {
            syndromeMap.set(syndrome.id, {
              syndromeId: syndrome.id,
              syndromeName: syndrome.name,
              severity: syndrome.severity,
              diagnosisCount: (existing?.diagnosisCount ?? 0) + 1,
              lastQuote: syndrome.evidence[0] ?? '',
              lastDiagnosedAt: entry.timestamp,
            });
          } else if (existing) {
            existing.diagnosisCount += 1;
          }
        }
      }

      // 按严重度排序
      const errorCards: ErrorCard[] = Array.from(syndromeMap.values())
        .sort((a, b) => (severityOrder[b.severity] ?? 0) - (severityOrder[a.severity] ?? 0))
        .map(c => ({
          syndromeId: c.syndromeId,
          syndromeName: c.syndromeName,
          severity: c.severity as ErrorCard['severity'],
          diagnosisCount: c.diagnosisCount,
          lastQuote: c.lastQuote,
          lastDiagnosedAt: c.lastDiagnosedAt,
        }));

      // 2. 调用 training:recommend 获取推荐
      const recResult = await getInvoke()(IPC_CHANNELS.TRAINING_RECOMMEND, { sessionId }) as { recommendations?: TrainingRecommendation[] };
      const recommendations = recResult.recommendations ?? [];

      // 3. 关联匹配的 challengeId 到 errorCards
      if (recommendations.length > 0) {
        for (const card of errorCards) {
          const match = recommendations.find(r => r.syndromeId === card.syndromeId);
          if (match) {
            card.matchedChallengeId = match.challengeId;
          }
        }
      }

      set({ errorCards, recommendations, isLoading: false });

      // 自动设置桥接卡片推荐（推荐 L2+ 的第一个症候）
      if (recommendations.length > 0) {
        set({ bridgeRecommendation: recommendations[0] });
      } else {
        set({ bridgeRecommendation: null });
      }
    } catch (error) {
      console.error('[TrainingStore] refreshFromDiagnosis failed:', error);
      set({ error: String(error), isLoading: false });
    }
  },

  setBridgeRecommendation: (rec: TrainingRecommendation | null) => {
    set({ bridgeRecommendation: rec });
  },

  dismissBridge: () => {
    set({ bridgeRecommendation: null });
  },

  evaluateTraining: async () => {
    set({ isLoading: true, error: null });
    try {
      const active = get().activeTraining;
      if (!active) throw new Error('No active training');

      const sessionId = useChatStore.getState().currentSessionId;

      const result = await getInvoke()(IPC_CHANNELS.TRAINING_EVALUATE, {
        recordId: active.recordId,
        sessionId,
        syndromeId: active.syndromeId,
        challengeDescription: active.challengeDescription,
        constraint: active.constraint,
        originalQuote: active.originalQuote,
        userDraft: active.userDraft,
      }) as EvaluationResult;

      set({ evaluationResult: result, isLoading: false });
    } catch (error) {
      console.error('[TrainingStore] evaluateTraining failed:', error);
      set({ error: String(error), isLoading: false });
    }
  },
}));

// ===== Selectors =====

export const selectCenterMode = (state: TrainingState) => state.centerMode;
export const selectActiveTraining = (state: TrainingState) => state.activeTraining;
export const selectErrorCards = (state: TrainingState) => state.errorCards;
export const selectRecommendations = (state: TrainingState) => state.recommendations;
export const selectTrainingHistory = (state: TrainingState) => state.history;
export const selectIsLoading = (state: TrainingState) => state.isLoading;
