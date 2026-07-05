/**
 * 训练 Store — 大型 Action 函数
 *
 * ⚠️ 本文件 catch 块中的 console.error / console.warn 仅用于开发调试，
 *    生产环境应通过构建工具（如 terser drop_console）自动移除。
 *
 * 每个函数接收 Zustand 的 set/get，返回 action 实现。
 * 由 training.store.ts 在 create() 中组装。
 *
 * Sprint 26 阶段 3.6: 调用方迁移到 service-bridge 单端点
 */

import { useChatStore } from './chat.store';
import { useProgressStore } from './progress.store';
import { serviceBridge } from '../services/service-bridge';
import { activeTrainingService } from '../services/active-training.service';
import { severityToNumber } from '../../shared/severity-utils';
import type {
  EvaluationResult,
  ActiveTrainingSession,
  TrainingStep,
  TrainingRecord,
  TrainingFlow,
} from '../shared/types';
import type { TrainingState } from './training.types';
import { DEFAULT_STEPS, READING_STEPS } from './training.types';

/** 行为推导结果(sprint 26:与 behavior-derivation.service.DerivationResult 同构) */
interface DerivationResult {
  derivedBehavior: string;
  analysis: string;
  consistencyCheck: string;
}

// ===== Action 工厂类型 =====

type SetStateFn = (partial: Partial<TrainingState> | ((state: TrainingState) => Partial<TrainingState>), replace?: boolean) => void;
type GetStateFn = () => TrainingState;

// ===== 训练操作 Actions =====

export function createStartAction(set: SetStateFn, get: GetStateFn) {
  return async (challengeId: string): Promise<void> => {
    // P0-1: B-02 守卫 — readingDecision.required 时重定向到阅读前置
    const decision = get().readingDecision;
    if (decision?.required) {
      return get().startReading(challengeId);
    }

    set({ isLoading: true, error: null });
    try {
      const sessionId = useChatStore.getState().currentSessionId;
      if (!sessionId) throw new Error('No active session');

      const result = await serviceBridge.invoke<
        { sessionId: string; challengeId: string },
        { record?: TrainingRecord }
      >('training:assign', { sessionId, challengeId });

      if (!result) throw new Error('training:assign returned null');
      const assignedRecord = result.record;

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
        recordId: assignedRecord?.id,
        syndromeId: match?.syndromeId,
        targetSyndrome: match?.syndromeName,
        longTermProgress,
      };

      // S8: 非阅读任务时，异步获取五步通用训练流
      if (match?.mode !== 'reading_task' && match?.syndromeId) {
        try {
          const flow = await serviceBridge.invoke<
            {
              syndromeId: string;
              techniqueName: string;
              challengeConstraint?: string;
              userLevel?: number;
              syndromeDescription?: string;
            },
            TrainingFlow
          >('training:generateFlow', {
            syndromeId: match.syndromeId,
            techniqueName: match.challengeName ?? challengeId,
            challengeConstraint: match.constraint,
          });
          if (flow) {
            session.trainingFlow = flow;
            // S16: 标记走五步流（UI 切到 FlowPanel）
            session.flowType = 'flow5';
          } else {
            session.flowType = 'legacy';
          }
        } catch (e) {
          console.warn('[TrainingStore] generateTrainingFlow failed (non-fatal):', e);
          // 降级到传统 3 步流
          session.flowType = 'legacy';
        }
      } else {
        // reading_task 走传统流
        session.flowType = 'legacy';
      }

      set({ activeTraining: session, isLoading: false, submissionResult: null, evaluationResult: null });
    } catch (error) {
      console.error('[TrainingStore] startTraining failed:', error);
      set({ error: String(error), isLoading: false });
    }
  };
}

export function createSubmitStepAction(set: SetStateFn, get: GetStateFn) {
  return async (stepId?: 1 | 2 | 3 | 4 | 5, content?: string): Promise<void> => {
    // Sprint 25 BL-01 C-4: 5 步分步提交分支
    // - stepId 存在时:仅持久化本步内容到主进程 step_responses_json
    // - 不影响 store.currentStepIndex(由 V6.2 FlowPanel 本地 state 管理)
    // - 不评估、不走 S8 评估流(评估由 V6.2 FlowPanel 在第 4 步主动调 evaluateTraining)
    // - stepId 不存在时:走原 S8 评估流(向后兼容)
    if (stepId !== undefined) {
      set({ error: null });
      const sessionId = useChatStore.getState().currentSessionId;
      if (!sessionId) {
        set({ error: 'No active session' });
        return;
      }

      // 异步持久化到主进程 step_responses(异常隔离:失败仅 console.warn)
      const result = await activeTrainingService.submitStep({
        sessionId,
        stepId,
        content: content ?? '',
      });
      if (!result) {
        console.warn(
          `[TrainingStore] submitStep(${stepId}) persist failed (non-fatal)`,
        );
      }
      return;
    }

    set({ isLoading: true, error: null, submissionResult: null });
    try {
      const active = get().activeTraining;
      if (!active) throw new Error('No active training');

      // Step 2 → 提交给 AI 评估
      if (active.currentStepIndex === 1) {
        // P0-2: reading_task 跳过通用训练评估管道
        if (active.mode === 'reading_task') {
          // 阅读分析直接标记通过，推进到 Step 3（提交确认）
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
            submissionResult: { passed: true, feedback: '阅读分析已记录。请在下一步确认完成。' },
            evaluationResult: null,
            isLoading: false,
          });
          return;
        }

        const result = await serviceBridge.invoke<
          {
            challengeDescription: string;
            constraint: string;
            originalQuote: string;
            userDraft: string;
          },
          { passed: boolean; feedback: string; score?: number; improved?: boolean; nextStep?: string }
        >('training:submit', {
          challengeDescription: active.challengeDescription,
          constraint: active.constraint,
          originalQuote: active.originalQuote,
          userDraft: active.userDraft,
        });

        if (!result) throw new Error('training:submit returned null');

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
            await serviceBridge.invoke<
              {
                recordId: string;
                userResponse: string;
                aiFeedback?: string;
                effectiveness?: number;
              },
              { record?: TrainingRecord }
            >('training:complete', {
              recordId: active.recordId,
              userResponse: active.userDraft,
              aiFeedback: get().submissionResult?.feedback ?? '',
            });
          } catch (e) {
            console.warn('[TrainingStore] complete IPC failed:', e);
          }
        }

        // RWR-P1-9 / C-3 训练反馈回路:
        //   1. progress.store 分子+1(触发 ProgressSummary 高亮)
        //   2. IPC teachingHistory:add → StudentModelService.appendTeachingHistory
        //   3. 主进程 handler 算精通门控,达成时 emit teachingState:mastery
        const sessionId = useChatStore.getState().currentSessionId;
        const syndromeId = active.syndromeId;
        if (sessionId && syndromeId) {
          // 步骤 1:分子+1(同步,zustand setter 立即生效)
          useProgressStore.getState().updateResolved(sessionId, syndromeId);
          // 步骤 2-3:钉 C-1 钉子 + 门控判断
          try {
            const progress = useProgressStore.getState().progressMap[sessionId];
            const consumed = progress?.resolvedIssues ?? 0;
            const total = progress?.totalIssues ?? 0;
            await serviceBridge.invoke<
              {
                sessionId: string;
                entry: { action: string; syndromeId: string; outcome: 'success' | 'partial' | 'frustrated' | 'unknown' };
                consumed: number;
                total: number;
              },
              { added: boolean; masteryReached: boolean; consumed: number; total: number }
            >('teachingHistory:add', {
              sessionId,
              entry: {
                action: 'training:complete',
                syndromeId,
                outcome: 'success',
              },
              consumed,
              total,
            });
          } catch (e) {
            console.warn('[TrainingStore] teachingHistory:add IPC failed:', e);
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

        // A3: 保存评估分数和症候ID，用于自荐阅读框架
        if (evalResult?.score != null && active.syndromeId) {
          set({
            lastEvaluationScore: evalResult.score,
            lastSyndromeId: active.syndromeId,
          });
        }

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

// ===== 评估 Actions =====

export function createEvaluateTrainingAction(set: SetStateFn, get: GetStateFn) {
  return async (): Promise<void> => {
    set({ isLoading: true, error: null });
    try {
      const active = get().activeTraining;
      if (!active) throw new Error('No active training');

      const sessionId = useChatStore.getState().currentSessionId;

      const result = await serviceBridge.invoke<
        {
          recordId?: string;
          sessionId?: string;
          syndromeId?: string;
          challengeDescription: string;
          constraint: string;
          originalQuote: string;
          userDraft: string;
        },
        EvaluationResult
      >('training:evaluate', {
        recordId: active.recordId,
        sessionId,
        syndromeId: active.syndromeId,
        challengeDescription: active.challengeDescription,
        constraint: active.constraint,
        originalQuote: active.originalQuote,
        userDraft: active.userDraft,
      });

      if (!result) throw new Error('evaluateTraining returned null');

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
      const res = await serviceBridge.invoke<
        {
          characterName: string;
          sceneDescription: string;
          question1: string;
          question2: string;
          question3: string;
        },
        DerivationResult
      >('training:deriveBehavior', params);
      if (res) {
        set({ derivationResult: res, derivationLoading: false });
      } else {
        set({ derivationError: '推导失败', derivationLoading: false });
      }
    } catch (e) {
      set({ derivationError: String(e), derivationLoading: false });
    }
  };
}
