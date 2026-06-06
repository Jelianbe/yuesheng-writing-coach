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

import { ipcMain, BrowserWindow } from 'electron';
import { IPC_CHANNELS } from '../../shared/constants';
import { ActiveProblem, apiSuccess, apiError } from '../../renderer/shared/types';
import { SYNDROME_NAMES } from '../../shared/mappings';
import { generateRecommendations, getChallengeTemplate } from '../services/training-recommendation.service';
import { TrainingRecordService, TrainingRecord } from '../services/training-record.service';
import { StudentModelService } from '../services/student-model.service';
import { ApiProxy } from '../api-proxy';
import { ConfigService } from '../services/config.service';
import * as path from 'path';
import * as fs from 'fs';

// ===== 服务引用 =====

let configService: ConfigService | null = null;
let trainingRecordService: TrainingRecordService | null = null;
let studentModelService: StudentModelService | null = null;
let mainWindow: BrowserWindow | null = null;

export function setConfigService(svc: ConfigService): void {
  configService = svc;
}

export function setTrainingRecordService(service: TrainingRecordService): void {
  trainingRecordService = service;
}

export function setStudentModelService(service: StudentModelService): void {
  studentModelService = service;
}

export function setMainWindow(window: BrowserWindow | null): void {
  mainWindow = window;
}

// ===== IPC Handlers =====

/**
 * training:recommend
 *
 * 输入：{ sessionId: string }
 * 输出：TrainingRecommendation[]（按严重度排序）
 *
 * 流程：
 * 1. 从 StudentModelService 获取活跃症候
 * 2. 调用 TrainingRecommendationService 生成推荐
 * 3. 返回前端
 */
export function registerTrainingHandlers(): void {
  // 1. training:recommend - 推荐训练
  ipcMain.handle(IPC_CHANNELS.TRAINING_RECOMMEND, async (_event, args: { sessionId: string }) => {
    try {
      if (!studentModelService) {
        return apiError('StudentModelService not initialized');
      }

      const profile = await studentModelService.getSyndromeProfile(args.sessionId);
      if (!profile || Object.keys(profile).length === 0) {
        return apiSuccess({ recommendations: [] });
      }

      // 将 Record<string, SyndromeAggregation> 转换为 ActiveProblem 数组
      const activeProblems: ActiveProblem[] = Object.entries(profile).map(
        ([id, agg]) => ({
          id,
          name: SYNDROME_NAMES[id] ?? id,
          severity: agg.latestSeverity,
          evidence: [], // Phase 1: 不传证据（T-021.1 的证据在诊断记录中）
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

  // 2. training:assign - 分配训练
  ipcMain.handle(IPC_CHANNELS.TRAINING_ASSIGN, async (_event, args: { sessionId: string; challengeId: string }) => {
    try {
      if (!trainingRecordService) {
        return apiError('TrainingRecordService not initialized');
      }

      const template = getChallengeTemplate(args.challengeId);
      if (!template) {
        return apiError(`Challenge template not found: ${args.challengeId}`);
      }

      const record = trainingRecordService.assign({
        sessionId: args.sessionId,
        taskId: args.challengeId,
        syndromeId: template.syndromeId,
        userResponse: null,
        aiFeedback: null,
        effectiveness: null,
      });

      return apiSuccess({ record });
    } catch (error) {
      console.error('[training:assign] Error:', error);
      return apiError(String(error));
    }
  });

  // 3. training:complete - 完成训练
  ipcMain.handle(IPC_CHANNELS.TRAINING_COMPLETE, async (_event, args: {
    recordId: string;
    userResponse: string;
    aiFeedback?: string;
    effectiveness?: number;
  }) => {
    try {
      if (!trainingRecordService) {
        return apiError('TrainingRecordService not initialized');
      }

      const record = trainingRecordService.complete(args.recordId, {
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

  // 4. training:skip - 跳过训练
  ipcMain.handle(IPC_CHANNELS.TRAINING_SKIP, async (_event, args: { recordId: string }) => {
    try {
      if (!trainingRecordService) {
        return apiError('TrainingRecordService not initialized');
      }

      const record = trainingRecordService.skip(args.recordId);

      if (!record) {
        return apiError(`Record not found: ${args.recordId}`);
      }

      return apiSuccess({ record });
    } catch (error) {
      console.error('[training:skip] Error:', error);
      return apiError(String(error));
    }
  });

  // 5. training:history - 查询训练历史
  ipcMain.handle(IPC_CHANNELS.TRAINING_HISTORY, async (_event, args: { sessionId: string }) => {
    try {
      if (!trainingRecordService) {
        return apiError('TrainingRecordService not initialized');
      }

      const records = trainingRecordService.getBySession(args.sessionId);
      return apiSuccess({ records });
    } catch (error) {
      console.error('[training:history] Error:', error);
      return apiError(String(error));
    }
  });

  // 6. training:submit - 提交改写稿给 AI 评估
  ipcMain.handle(IPC_CHANNELS.TRAINING_SUBMIT, async (_event, args: {
    challengeDescription: string;
    constraint: string;
    originalQuote: string;
    userDraft: string;
  }) => {
    try {
      const config = configService!.getConfig();
      const proxy = new ApiProxy(config);

      // 读取评估 Prompt
      const promptPath = path.join(__dirname, '../../resources/prompts/training-evaluator-prompt-v1.md');
      let systemPrompt: string;
      try {
        systemPrompt = fs.readFileSync(promptPath, 'utf-8');
      } catch {
        systemPrompt = '你是一个写作教练。评估用户的改写是否达到了训练要求。只输出 JSON: { "passed": true/false, "feedback": "2-3句话的评价" }';
      }

      const userMessage = [
        '## 训练目标',
        args.challengeDescription,
        '',
        '## 约束条件',
        args.constraint,
        '',
        '## 用户原始文本',
        args.originalQuote,
        '',
        '## 用户改写稿',
        args.userDraft,
      ].join('\n');

      const messages = [
        { role: 'system' as const, content: systemPrompt },
        { role: 'user' as const, content: userMessage },
      ];

      let fullResponse = '';
      for await (const chunk of proxy.chatStream(messages)) {
        fullResponse += chunk;
      }

      const jsonMatch = fullResponse.match(/\{[\s\S]*\}/);
      if (!jsonMatch) {
        return apiError('评估服务暂时不可用，请稍后重试。');
      }

      const result = JSON.parse(jsonMatch[0]);
      return apiSuccess({
        passed: result.passed === true,
        feedback: result.feedback ?? '改写稿已收到。',
      });
    } catch (error) {
      console.error('[training:submit] Error:', error);
      return apiError('评估服务异常，请稍后重试。');
    }
  });

  console.log('[TrainingHandler] All training IPC handlers registered');
}
