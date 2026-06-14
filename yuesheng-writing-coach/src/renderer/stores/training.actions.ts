/**
 * 训练 Store — 大型 Action 函数
 *
 * ⚠️ 本文件 catch 块中的 console.error / console.warn 仅用于开发调试，
 *    生产环境应通过构建工具（如 terser drop_console）自动移除。
 *
 * 每个函数接收 Zustand 的 set/get，返回 action 实现。
 * 由 training.store.ts 在 create() 中组装。
 */

import { useChatStore } from './chat.store';
import { useDiagStore } from './diag.store';
import { useConfigStore } from './config.store';
import { getInvoke } from '../utils/ipc';
import { IPC_CHANNELS } from '../../shared/constants';
import { TrainingApi } from '../../shared/api-contracts/training.contract';
import { severityToNumber } from '../../shared/severity-utils';
import type {
  ErrorCard,
  TrainingRecord,
  TrainingRecommendation,
  EvaluationResult,
  ActiveTrainingSession,
  TrainingStep,
} from '../shared/types';
import type { TrainingState } from './training.types';
import { DEFAULT_STEPS, READING_STEPS } from './training.types';

// ===== Action 工厂类型 =====

type SetStateFn = (partial: Partial<TrainingState> | ((state: TrainingState) => Partial<TrainingState>), replace?: boolean) => void;
type GetStateFn = () => TrainingState;

// ===== 训练操作 Actions =====

export function createStartAction(set: SetStateFn, get: GetStateFn) {
  return async (challengeId: string): Promise<void> => {
    set({ isLoading: true, error: null });
    try {
      const sessionId = useChatStore.getState().currentSessionId;
      if (!sessionId) throw new Error('No active session');

      const result = await getInvoke()(TrainingApi.assign.channel, {
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
        steps: (match?.mode === 'reading_task' ? READING_STEPS : DEFAULT_STEPS).map((s, i) => ({
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
  };
}

/**
 * startReading — M2: B-02 决策触发的阅读前置任务
 *
 * 当 readingDecision.required 时调用，加载 reading-library 条目
 * 并创建 mode: 'reading_task' 的活跃会话。
 * 完成分析步骤后关闭阅读会话，训练流程继续。
 */
export function createStartReadingAction(set: SetStateFn, get: GetStateFn) {
  return async (challengeId: string): Promise<void> => {
    set({ isLoading: true, error: null });
    try {
      const sessionId = useChatStore.getState().currentSessionId;
      if (!sessionId) throw new Error('No active session');

      // 从 recommendations 查找匹配症候
      const match = get().recommendations.find(r => r.challengeId === challengeId);
      const syndromeId = match?.syndromeId ?? 'P003';

      // 加载阅读库条目
      const readingResult = await getInvoke()(IPC_CHANNELS.CONFIG_GET_READING_ENTRY, { syndromeId }) as { entries: Array<{ id: string; title: string; excerpt: string; analysisPrompt: string }> };
      const entry = readingResult.entries[0];

      // 构建阅读内容
      const readingContent = entry
        ? `${entry.excerpt}\n\n【分析引导】\n${entry.analysisPrompt}`
        : `请仔细阅读你的文本，关注本次训练涉及的写作问题（${syndromeId}）。在下一步中写下你的分析和观察。`;

      // 构建阅读会话
      const session: ActiveTrainingSession = {
        challengeId: `reading-${syndromeId}`,
        challengeName: entry?.title ?? `阅读分析 · ${syndromeId}`,
        challengeDescription: readingContent,
        mode: 'reading_task',
        steps: READING_STEPS.map((s, i) => ({
          ...s,
          status: i === 0 ? 'active' as const : 'pending' as const,
        })),
        currentStepIndex: 0,
        originalQuote: '',
        constraint: '',
        userDraft: '',
        syndromeId,
        targetSyndrome: match?.syndromeName,
      };

      set({ activeTraining: session, isLoading: false, submissionResult: null, evaluationResult: null });
    } catch (error) {
      console.error('[TrainingStore] startReading failed:', error);
      set({ error: String(error), isLoading: false });
    }
  };
}

export function createSubmitStepAction(set: SetStateFn, get: GetStateFn) {
  return async (): Promise<void> => {
    set({ isLoading: true, error: null, submissionResult: null });
    try {
      const active = get().activeTraining;
      if (!active) throw new Error('No active training');

      // Step 2 → 提交给 AI 评估
      if (active.currentStepIndex === 1) {
        const result = await getInvoke()(TrainingApi.submit.channel, {
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
        // 所有步骤完成 → 调用 training:complete 保存记录
        // B3: 不切回对话，用户可通过 onBackToChat 手动返回；评估结果保持可见
        if (active.recordId) {
          try {
            await getInvoke()(TrainingApi.complete.channel, {
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

        // B3: 不主动清除 activeTraining，保留评估视图供用户回顾
        // 用户通过 onBackToChat（返回按钮）手动退出

        // M3+M4: reading_task 完成后自动刷新推荐并回到工坊
        if (active.mode === 'reading_task') {
          await get().refreshFromDiagnosis();
          set({ activeTraining: null, readingComplete: true, isLoading: false });
          return;
        }

        set({ isLoading: false });
      }
    } catch (error) {
      console.error('[TrainingStore] submitStep failed:', error);
      set({ error: String(error), isLoading: false });
    }
  };
}

// ===== 数据加载 Actions =====

export function createLoadHistoryAction(set: SetStateFn, _get: GetStateFn) {
  return async (sessionId: string): Promise<void> => {
    set({ isLoading: true, error: null });
    try {
      const result = await getInvoke()(TrainingApi.history.channel, { sessionId }) as { error?: string; records?: TrainingRecord[] };
      if (result.error) throw new Error(result.error);
      set({ history: result.records ?? [], isLoading: false });
    } catch (error) {
      console.error('[TrainingStore] loadHistory failed:', error);
      set({ error: String(error), isLoading: false });
    }
  };
}

export function createRefreshFromDiagnosisAction(set: SetStateFn, _get: GetStateFn) {
  return async (): Promise<void> => {
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

      // 1.5 B-02：阅读前置决策
      const attitude = useConfigStore.getState().attitudeLevel;
      let readingDecision = null;
      try {
        const result = await getInvoke()(TrainingApi.decideReading.channel, { attitude }) as { required: boolean; recommended: boolean; label: string; reason?: string };
        readingDecision = result;
      } catch {
        // B-02 不可用时静默降级
      }
      set({ readingDecision: readingDecision ?? null });

      // 2. 调用 training:recommend 获取推荐
      const recResult = await getInvoke()(TrainingApi.recommend.channel, { sessionId }) as { recommendations?: TrainingRecommendation[] };
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
  };
}

// ===== 评估 Actions =====

export function createEvaluateTrainingAction(set: SetStateFn, get: GetStateFn) {
  return async (): Promise<void> => {
    set({ isLoading: true, error: null });
    try {
      const active = get().activeTraining;
      if (!active) throw new Error('No active training');

      const sessionId = useChatStore.getState().currentSessionId;

      const result = await getInvoke()(TrainingApi.evaluate.channel, {
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
  };
}

// ===== C2: 行为推导 Actions =====

export function createDeriveBehaviorAction(set: SetStateFn, _get: GetStateFn) {
  return async (params: {
    characterName: string;
    sceneDescription: string;
    question1: string;
    question2: string;
    question3: string;
  }): Promise<void> => {
    set({ derivationLoading: true, derivationError: null, derivationResult: null });
    try {
      const res = await getInvoke()(TrainingApi.deriveBehavior.channel, params) as {
        success: boolean;
        data?: { derivedBehavior: string; analysis: string; consistencyCheck: string };
        error?: string;
      };
      if (res?.success && res.data) {
        set({ derivationResult: res.data, derivationLoading: false });
      } else {
        set({ derivationError: res?.error ?? '推导失败', derivationLoading: false });
      }
    } catch (e) {
      set({ derivationError: String(e), derivationLoading: false });
    }
  };
}
