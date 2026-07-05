/**
 * 训练 IPC Handler — Sprint 26 阶段 3.5 方案 4a bridge 注册
 *
 * 原 IPC handler 已废弃,改为 registerMethod 走单端点 bridge:invoke。
 * 调用方:`serviceBridge.invoke('training:recommend' | 'training:assign' | ...)`
 *
 * 依赖: TrainingRecordService, StudentModelService, TeachingStateService,
 *       TeachingStrategyService, ConfigService
 *
 * 事件: teachingState:mastery 仍走 webContents.send(由 initTrainingHandlers 注入 mainWindow)
 *       改造前用 event.sender.send,改造后用注入的 mainWindow.webContents.send
 *       (R-021 最小化:保持同一 channel 字符串,renderer 订阅端不动)
 */

import type { ActiveProblem } from '../../shared/types/index';
import { SYNDROME_NAMES } from '../../shared/mappings';
import type { TrainingCatalogRequest } from '../../shared/api-contracts/training.contract';
import { validatePayload } from './utils/validate-payload';
import { registerMethod } from '../core/service-bridge';
import techniqueLibrary from '../../../resources/config/technique-library.json';
import { generateRecommendations, getChallengeTemplate } from '../domains/04-validation/training/training-recommendation.service';
import { generateTrainingFlow } from '../domains/04-validation/training/training-flow.service';
import type { TrainingRecordService } from '../domains/04-validation/training/training-record.service';
import type { StudentModelService } from '../domains/02-prescription/student/student-model-service';
import { evaluateTraining } from '../domains/04-validation/training/training-evaluator.service';
import { deriveBehavior, type DerivationInput } from '../domains/04-validation/training/behavior-derivation.service';
import type { ConfigService } from '../shared/services/config.service';
import type { TeachingStateService } from '../domains/03-teaching/teaching-state.service';
import type { TeachingStrategyService } from '../domains/02-prescription/strategy/service';
import type { PayloadSanitizer } from '../core/payload-sanitizer.service';
import type { BrowserWindow } from 'electron';
import { IPC_CHANNELS } from '../../shared/constants';

interface TechniqueItem {
  id: string;
  name: string;
  difficulty: string;
  difficultyOrder: number;
  description: string;
  source: string;
  category: string;
  coreId?: string;
  coreName?: string;
  [key: string]: unknown;
}

export interface TrainingHandlerDeps {
  configService: ConfigService;
  trainingRecordService: TrainingRecordService;
  studentModelService: StudentModelService;
  teachingStateService: TeachingStateService;
  teachingStrategyService: TeachingStrategyService;
  mainWindow?: BrowserWindow | null;
}

let deps: TrainingHandlerDeps | null = null;

export function initTrainingHandlers(d: TrainingHandlerDeps): void {
  deps = d;
}

let trainingSanitizerInstance: PayloadSanitizer | null = null;

export function setTrainingSanitizer(s: PayloadSanitizer): void {
  trainingSanitizerInstance = s;
}

export function registerTrainingHandlers(): void {
  registerMethod('training:recommend', async (args) => {
    const validation = validatePayload<{ sessionId: string }>(args, { required: ['sessionId'], types: { sessionId: 'string' } });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    if (!deps) throw new Error('TrainingHandler deps not initialized');

    const profile = await deps.studentModelService.getSyndromeProfile(validation.data.sessionId);
    if (!profile || Object.keys(profile).length === 0) {
      return { recommendations: [] };
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
        detectionCount: 1,
        missedCount: 0,
        suggestedActions: [],
      }),
    );

    const recommendations = generateRecommendations(activeProblems);

    return { recommendations };
  });

  registerMethod('training:assign', async (args) => {
    const validation = validatePayload<{ sessionId: string; challengeId: string }>(args, { required: ['sessionId', 'challengeId'], types: { sessionId: 'string', challengeId: 'string' } });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    if (!deps) throw new Error('TrainingHandler deps not initialized');

    const template = getChallengeTemplate(validation.data.challengeId);
    if (!template) {
      throw new Error(`Challenge template not found: ${validation.data.challengeId}`);
    }

    const record = deps.trainingRecordService.assign({
      sessionId: validation.data.sessionId,
      taskId: validation.data.challengeId,
      syndromeId: template.syndromeId,
      taskType: template.mode,
      userResponse: null,
      aiFeedback: null,
      effectiveness: null,
      score: null,
    });

    return { record };
  });

  registerMethod('training:complete', async (args) => {
    const validation = validatePayload<{ recordId: string; userResponse: string; aiFeedback?: string; effectiveness?: number }>(args, { required: ['recordId', 'userResponse'], types: { recordId: 'string', userResponse: 'string', aiFeedback: 'string', effectiveness: 'number' } });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    if (!deps) throw new Error('TrainingHandler deps not initialized');

    const record = deps.trainingRecordService.complete(validation.data.recordId, {
      userResponse: validation.data.userResponse,
      aiFeedback: validation.data.aiFeedback ?? undefined,
      effectiveness: validation.data.effectiveness ?? undefined,
    });

    if (!record) {
      throw new Error(`Record not found: ${validation.data.recordId}`);
    }

    return { record };
  });

  registerMethod('training:skip', async (args) => {
    const validation = validatePayload<{ recordId: string }>(args, { required: ['recordId'], types: { recordId: 'string' } });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    if (!deps) throw new Error('TrainingHandler deps not initialized');

    const record = deps.trainingRecordService.skip(validation.data.recordId);

    if (!record) {
      throw new Error(`Record not found: ${validation.data.recordId}`);
    }

    return { record };
  });

  registerMethod('training:history', async (args) => {
    const validation = validatePayload<{ sessionId: string }>(args, { required: ['sessionId'], types: { sessionId: 'string' } });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    if (!deps) throw new Error('TrainingHandler deps not initialized');

    const records = deps.trainingRecordService.getBySession(validation.data.sessionId);
    return { records };
  });

  registerMethod('training:submit', async (args) => {
    const validation = validatePayload<{ challengeDescription: string; constraint: string; originalQuote: string; userDraft: string }>(args, { required: ['challengeDescription', 'constraint', 'originalQuote', 'userDraft'], types: { challengeDescription: 'string', constraint: 'string', originalQuote: 'string', userDraft: 'string' } });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    if (!deps) throw new Error('TrainingHandler deps not initialized');

    const result = await evaluateTraining(validation.data, deps.configService);

    const payload = {
      passed: result.score >= 7,
      feedback: result.feedback,
      score: result.score,
      improved: result.improved,
      nextStep: result.nextStep,
    };
    return trainingSanitizerInstance?.sanitize('training', payload) ?? payload;
  });

  registerMethod('training:evaluate', async (args) => {
    const validation = validatePayload<{ recordId: string; sessionId: string; syndromeId: string; challengeDescription: string; constraint: string; originalQuote: string; userDraft: string }>(args, { required: ['recordId', 'sessionId', 'syndromeId', 'challengeDescription', 'constraint', 'originalQuote', 'userDraft'], types: { recordId: 'string', sessionId: 'string', syndromeId: 'string', challengeDescription: 'string', constraint: 'string', originalQuote: 'string', userDraft: 'string' } });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    if (!deps) throw new Error('TrainingHandler deps not initialized');

    const result = await evaluateTraining(validation.data, deps.configService);

    if (validation.data.recordId) {
      deps.trainingRecordService.complete(validation.data.recordId, {
        userResponse: validation.data.userDraft,
        aiFeedback: result.feedback,
        score: result.score,
      });
    }

    if (result.score >= 7 && validation.data.sessionId && validation.data.syndromeId) {
      try {
        deps.teachingStateService.downgradeSeverity(validation.data.sessionId, validation.data.syndromeId, result.score);
      } catch (e) {
        console.warn('[training:evaluate] severity downgrade failed:', e);
      }
    }

    return trainingSanitizerInstance?.sanitize('training', result) ?? result;
  });

  registerMethod('training:decideReading', async (args) => {
    const validation = validatePayload<{ attitude: string }>(args, { required: ['attitude'], types: { attitude: 'string' } });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    if (!deps) throw new Error('TrainingHandler deps not initialized');
    if (!deps.teachingStrategyService.router) throw new Error('TeachingStrategyRouter not initialized');

    return deps.teachingStrategyService.router.decideReading(validation.data.attitude);
  });

  registerMethod('training:deriveBehavior', async (input) => {
    if (!deps) throw new Error('TrainingHandler deps not initialized');
    return await deriveBehavior(input as DerivationInput, deps.configService);
  });

  registerMethod('teachingHistory:add', async (args) => {
    const validation = validatePayload<{
      sessionId: string;
      entry: {
        action: string;
        syndromeId: string;
        outcome: 'success' | 'partial' | 'frustrated' | 'unknown';
      };
      consumed: number;
      total: number;
    }>(args, {
      required: ['sessionId', 'entry', 'consumed', 'total'],
      types: {
        sessionId: 'string',
        entry: 'object',
        consumed: 'number',
        total: 'number',
      },
    });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    if (!deps) throw new Error('TrainingHandler deps not initialized');

    const { sessionId, entry, consumed, total } = validation.data;
    deps.studentModelService.appendTeachingHistory(sessionId, entry);

    const MASTERY_THRESHOLD = 0.8;
    const masteryReached = total > 0 && consumed / total >= MASTERY_THRESHOLD;

    if (masteryReached && deps.mainWindow && !deps.mainWindow.isDestroyed()) {
      deps.mainWindow.webContents.send(IPC_CHANNELS.TEACHING_STATE_MASTERY, {
        sessionId,
        consumed,
        total,
        threshold: MASTERY_THRESHOLD,
      });
    }

    return { added: true, masteryReached, consumed, total };
  });

  registerMethod('training:generateFlow', async (args) => {
    const validation = validatePayload<{
      syndromeId: string;
      techniqueName: string;
      userLevel?: number;
      syndromeDescription?: string;
      challengeConstraint?: string;
    }>(args, { required: ['syndromeId', 'techniqueName'], types: { syndromeId: 'string', techniqueName: 'string' } });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);

    return generateTrainingFlow({
      syndromeId: validation.data.syndromeId,
      techniqueName: validation.data.techniqueName,
      userLevel: validation.data.userLevel ?? 1,
      syndromeDescription: validation.data.syndromeDescription,
      challengeConstraint: validation.data.challengeConstraint,
    });
  });

  registerMethod('training:catalog', async (args) => {
    const req = (args ?? {}) as TrainingCatalogRequest;
    const grouped: Record<string, { coreName: string; techniques: Array<{
      id: string; name: string; difficulty: string; difficultyOrder: number;
      description: string; source: string; category: string;
    }> }> = {};

    for (const t of (techniqueLibrary as TechniqueItem[])) {
      if (req.difficulty && t.difficulty !== req.difficulty) continue;
      if (req.coreId && t.coreId !== req.coreId) continue;
      if (!t.coreId) continue;

      if (!grouped[t.coreId]) {
        grouped[t.coreId] = { coreName: t.coreName || t.coreId, techniques: [] };
      }

      grouped[t.coreId].techniques.push({
        id: t.id,
        name: t.name,
        difficulty: t.difficulty || 'beginner',
        difficultyOrder: t.difficultyOrder || 1,
        description: t.description || '',
        source: t.source || '',
        category: t.category || '',
      });
    }

    const groups = Object.entries(grouped).map(([coreId, g]) => ({
      coreId,
      coreName: g.coreName,
      count: g.techniques.length,
      techniques: g.techniques,
    }));

    const total = groups.reduce((sum, g) => sum + g.count, 0);

    return { groups, total };
  });
}
