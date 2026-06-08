/**
 * 训练 IPC 处理器
 *
 * 负责：
 * 1. training:recommend - 根据当前活跃症候生成推荐列表
 * 2. training:assign - 分配挑战任务
 * 3. training:complete - 标记训练完成 + AI 评估
 * 4. training:skip - 标记训练跳过
 * 5. training:history - 查询训练历史
 *
 * 依赖：TrainingRecommendationService, TrainingRecordService, StudentModelService
 */

import { ipcMain } from 'electron';
import { IPC_CHANNELS } from '../../shared/constants';
import { ActiveProblem, apiSuccess, apiError } from '../../renderer/shared/types';
import { SYNDROME_NAMES } from '../../shared/mappings';
import { validatePayload } from './utils/validate-payload';
import { generateRecommendations, getChallengeTemplate } from '../services/training-recommendation.service';
import { TrainingRecordService } from '../services/training-record.service';
import { StudentModelService } from '../services/student-model.service';
import { evaluateTraining } from '../services/training-evaluator.service';
import { deriveBehavior, type DerivationInput } from '../services/behavior-derivation.service';
import { downgradeSyndromeSeverity } from '../services/teaching-state-machine';
import { getTeachingStateStore } from './teaching-state.handler';
import { ConfigService } from '../services/config.service';

export interface TrainingHandlerDeps {
  configService: ConfigService;
  trainingRecordService: TrainingRecordService;
  studentModelService: StudentModelService;
}

let deps: TrainingHandlerDeps | null = null;

export function initTrainingHandlers(d: TrainingHandlerDeps): void {
  deps = d;
}

// ===== IPC Handlers =====

/**
 * training:recommend
 */
export function registerTrainingHandlers(): void {
  ipcMain.handle(IPC_CHANNELS.TRAINING_RECOMMEND, async (_event, args) => {
    const validation = validatePayload<{ sessionId: string }>(args, { required: ['sessionId'], types: { sessionId: 'string' } });
    if (!validation.valid) return apiError(`INVALID_PAYLOAD: ${validation.error.message}`);
    try {
      if (!deps) return apiError('TrainingHandler deps not initialized');

      const profile = await deps.studentModelService.getSyndromeProfile(validation.data.sessionId);
      if (!profile || Object.keys(profile).length === 0) {
        return apiSuccess({ recommendations: [] });
      }

      const activeProblems: ActiveProblem[] = Object.entries(profile).map(
        ([id, agg]) => ({
          id,
          name: SYNDROME_NAMES[id] ?? id,
          severity: agg.latestSeverity,
          evidence: [],
          firstDetected: agg.lastSeenAt,
          status:
            agg.trend === 'improving'
              ? 'improving'
              : agg.trend === 'worsening'
                ? 'active'
                : 'active',
          suggestedActions: [],
        }),
      );

      const recommendations = generateRecommendations(activeProblems);

      return apiSuccess({ recommendations });
    } catch (error) {
      console.error('[training:recommend] Error:', error);
      return apiError(String(error));
    }
  });

  ipcMain.handle(IPC_CHANNELS.TRAINING_ASSIGN, async (_event, args: { sessionId: string; challengeId: string }) => {
    try {
      if (!deps) return apiError('TrainingHandler deps not initialized');

      const template = getChallengeTemplate(args.challengeId);
      if (!template) {
        return apiError(`Challenge template not found: ${args.challengeId}`);
      }

      const record = deps.trainingRecordService.assign({
        sessionId: args.sessionId,
        taskId: args.challengeId,
        syndromeId: template.syndromeId,
        userResponse: null,
        aiFeedback: null,
        effectiveness: null,
        score: null,
      });

      return apiSuccess({ record });
    } catch (error) {
      console.error('[training:assign] Error:', error);
      return apiError(String(error));
    }
  });

  ipcMain.handle(IPC_CHANNELS.TRAINING_COMPLETE, async (_event, args: {
    recordId: string;
    userResponse: string;
    aiFeedback?: string;
    effectiveness?: number;
  }) => {
    try {
      if (!deps) return apiError('TrainingHandler deps not initialized');

      const record = deps.trainingRecordService.complete(args.recordId, {
        userResponse: args.userResponse,
        aiFeedback: args.aiFeedback ?? undefined,
        effectiveness: args.effectiveness ?? undefined,
      });

      if (!record) {
        return apiError(`Record not found: ${args.recordId}`);
      }

      return apiSuccess({ record });
    } catch (error) {
      console.error('[training:complete] Error:', error);
      return apiError(String(error));
    }
  });

  ipcMain.handle(IPC_CHANNELS.TRAINING_SKIP, async (_event, args: { recordId: string }) => {
    try {
      if (!deps) return apiError('TrainingHandler deps not initialized');

      const record = deps.trainingRecordService.skip(args.recordId);

      if (!record) {
        return apiError(`Record not found: ${args.recordId}`);
      }

      return apiSuccess({ record });
    } catch (error) {
      console.error('[training:skip] Error:', error);
      return apiError(String(error));
    }
  });

  ipcMain.handle(IPC_CHANNELS.TRAINING_HISTORY, async (_event, args: { sessionId: string }) => {
    try {
      if (!deps) return apiError('TrainingHandler deps not initialized');

      const records = deps.trainingRecordService.getBySession(args.sessionId);
      return apiSuccess({ records });
    } catch (error) {
      console.error('[training:history] Error:', error);
      return apiError(String(error));
    }
  });

  ipcMain.handle(IPC_CHANNELS.TRAINING_SUBMIT, async (_event, args: {
    challengeDescription: string;
    constraint: string;
    originalQuote: string;
    userDraft: string;
  }) => {
    try {
      if (!deps) return apiError('TrainingHandler deps not initialized');

      const result = await evaluateTraining(args, deps.configService);

      return apiSuccess({
        passed: result.score >= 7,
        feedback: result.feedback,
        score: result.score,
        improved: result.improved,
        nextStep: result.nextStep,
      });
    } catch (error) {
      console.error('[training:submit] Error:', error);
      return apiError('评估服务异常，请稍后重试。');
    }
  });

  ipcMain.handle(IPC_CHANNELS.TRAINING_EVALUATE, async (_event, args: {
    recordId: string;
    sessionId: string;
    syndromeId: string;
    challengeDescription: string;
    constraint: string;
    originalQuote: string;
    userDraft: string;
  }) => {
    try {
      if (!deps) return apiError('TrainingHandler deps not initialized');

      const result = await evaluateTraining(args, deps.configService);

      // 持久化评分到训练记录
      if (args.recordId) {
        deps.trainingRecordService.complete(args.recordId, {
          userResponse: args.userDraft,
          aiFeedback: result.feedback,
          score: result.score,
        });
      }

      // 评分 >= 7 时降低症候严重度
      if (result.score >= 7 && args.sessionId && args.syndromeId) {
        try {
          const teachingStateStore = getTeachingStateStore();
          const state = teachingStateStore.getBySession(args.sessionId);
          if (state) {
            const { activeProblems } = downgradeSyndromeSeverity(state, args.syndromeId, result.score);
            teachingStateStore.update(args.sessionId, { activeProblems });
          }
        } catch (e) {
          console.warn('[training:evaluate] severity downgrade failed:', e);
        }
      }

      return apiSuccess(result);
    } catch (error) {
      console.error('[training:evaluate] Error:', error);
      return apiError('评估服务异常，请稍后重试。');
    }
  });

  /**
   * training:derive-behavior - F-03 角色行为推导
   */
  ipcMain.handle(IPC_CHANNELS.TRAINING_DERIVE_BEHAVIOR, async (_event, input: DerivationInput) => {
    try {
      if (!deps) return apiError('TrainingHandler deps not initialized');

      const result = await deriveBehavior(input, deps.configService);

      return apiSuccess(result);
    } catch (error) {
      console.error('[training:derive-behavior] Error:', error);
      return apiError('角色推导服务异常，请稍后重试。');
    }
  });

  console.log('[TrainingHandler] All training IPC handlers registered');
}
