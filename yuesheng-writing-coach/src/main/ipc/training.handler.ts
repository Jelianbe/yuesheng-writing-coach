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

import { IPC_CHANNELS } from '../../shared/constants';
import type { ActiveProblem } from '../../shared/types/index';
import { SYNDROME_NAMES } from '../../shared/mappings';
import type { TrainingCatalogRequest } from '../../shared/api-contracts/training.contract';
import { validatePayload } from './utils/validate-payload';
import { createHandler } from './utils/create-handler';
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

/**
 * 技法目录项类型
 *
 * 对应 resources/config/technique-library.json 中每一项的结构。
 * 使用接口索引签名兼容 JSON 中可能存在的其他可选字段。
 */
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
}

let deps: TrainingHandlerDeps | null = null;

export function initTrainingHandlers(d: TrainingHandlerDeps): void {
  deps = d;
}

// Sprint 21 E-1: 载荷脱敏注入
let trainingSanitizerInstance: PayloadSanitizer | null = null;

/** Sprint 21 E-1: 注入 PayloadSanitizer(可选,未注入则不脱敏) */
export function setTrainingSanitizer(s: PayloadSanitizer): void {
  trainingSanitizerInstance = s;
}

// ===== IPC Handlers =====

/**
 * training:recommend
 */
export function registerTrainingHandlers(): void {
  createHandler(IPC_CHANNELS.TRAINING_RECOMMEND, async (_event, args) => {
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

  createHandler(IPC_CHANNELS.TRAINING_ASSIGN, async (_event, args) => {
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

  createHandler(IPC_CHANNELS.TRAINING_COMPLETE, async (_event, args) => {
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

  createHandler(IPC_CHANNELS.TRAINING_SKIP, async (_event, args) => {
    const validation = validatePayload<{ recordId: string }>(args, { required: ['recordId'], types: { recordId: 'string' } });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    if (!deps) throw new Error('TrainingHandler deps not initialized');

    const record = deps.trainingRecordService.skip(validation.data.recordId);

    if (!record) {
      throw new Error(`Record not found: ${validation.data.recordId}`);
    }

    return { record };
  });

  createHandler(IPC_CHANNELS.TRAINING_HISTORY, async (_event, args) => {
    const validation = validatePayload<{ sessionId: string }>(args, { required: ['sessionId'], types: { sessionId: 'string' } });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    if (!deps) throw new Error('TrainingHandler deps not initialized');

    const records = deps.trainingRecordService.getBySession(validation.data.sessionId);
    return { records };
  });

  createHandler(IPC_CHANNELS.TRAINING_SUBMIT, async (_event, args) => {
    const validation = validatePayload<{ challengeDescription: string; constraint: string; originalQuote: string; userDraft: string }>(args, { required: ['challengeDescription', 'constraint', 'originalQuote', 'userDraft'], types: { challengeDescription: 'string', constraint: 'string', originalQuote: 'string', userDraft: 'string' } });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    if (!deps) throw new Error('TrainingHandler deps not initialized');

    const result = await evaluateTraining(validation.data, deps.configService);

    // Sprint 21 E-1: 载荷脱敏(feedback / nextStep 走 truncate)
    const payload = {
      passed: result.score >= 7,
      feedback: result.feedback,
      score: result.score,
      improved: result.improved,
      nextStep: result.nextStep,
    };
    return trainingSanitizerInstance?.sanitize('training', payload) ?? payload;
  });

  createHandler(IPC_CHANNELS.TRAINING_EVALUATE, async (_event, args) => {
    const validation = validatePayload<{ recordId: string; sessionId: string; syndromeId: string; challengeDescription: string; constraint: string; originalQuote: string; userDraft: string }>(args, { required: ['recordId', 'sessionId', 'syndromeId', 'challengeDescription', 'constraint', 'originalQuote', 'userDraft'], types: { recordId: 'string', sessionId: 'string', syndromeId: 'string', challengeDescription: 'string', constraint: 'string', originalQuote: 'string', userDraft: 'string' } });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    if (!deps) throw new Error('TrainingHandler deps not initialized');

    const result = await evaluateTraining(validation.data, deps.configService);

    // 持久化评分到训练记录
    if (validation.data.recordId) {
      deps.trainingRecordService.complete(validation.data.recordId, {
        userResponse: validation.data.userDraft,
        aiFeedback: result.feedback,
        score: result.score,
      });
    }

    // 评分 >= 7 时降低症候严重度
    if (result.score >= 7 && validation.data.sessionId && validation.data.syndromeId) {
      try {
        deps.teachingStateService.downgradeSeverity(validation.data.sessionId, validation.data.syndromeId, result.score);
      } catch (e) {
        console.warn('[training:evaluate] severity downgrade failed:', e);
      }
    }

    // Sprint 21 E-1: 载荷脱敏(feedback / nextStep 走 truncate)
    return trainingSanitizerInstance?.sanitize('training', result) ?? result;
  });

  /**
   * training:decideReading — B-02 阅读前置决策
   *
   * 判断在分配训练前是否需要先执行阅读分析步骤。
   * 依据：教学态度档位（doubao→must read, yuesheng→recommend, sensei→skip）
   */
  createHandler(IPC_CHANNELS.TRAINING_DECIDE_READING, async (_event, args) => {
    const validation = validatePayload<{ attitude: string }>(args, { required: ['attitude'], types: { attitude: 'string' } });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    if (!deps) throw new Error('TrainingHandler deps not initialized');
    if (!deps.teachingStrategyService.router) throw new Error('TeachingStrategyRouter not initialized');

    const readingDecision = deps.teachingStrategyService.router.decideReading(validation.data.attitude);

    return readingDecision;
  });

  /**
   * training:deriveBehavior - F-03 角色行为推导
   */
  createHandler(IPC_CHANNELS.TRAINING_DERIVE_BEHAVIOR, async (_event, input: DerivationInput) => {
    if (!deps) throw new Error('TrainingHandler deps not initialized');

    const result = await deriveBehavior(input, deps.configService);

    return result;
  });

  /**
   * teachingHistory:add — RWR-P1-9 / C-3 训练反馈回路
   *
   * 训练完成后由渲染端发起,流程:
   *   1. 调 deps.studentModelService.appendTeachingHistory 写入
   *   2. 计算精通门控(consumed/total ≥ MASTERY_THRESHOLD)
   *   3. 达成门控时 emit teachingState:mastery 事件
   *
   * 约束:
   *   - R-020 循环依赖:此处是渲染端→主进程唯一调用入口
   *   - R-010 最小化:不扩 StudentModelService(consumed/total 由调用方传)
   *   - TODO R-014:0.8 门控值后续外置到配置文件
   *
   * 注意:事件通过 event.sender.send 发送(当前调用窗口的 webContents),
   * 避免引入 mainWindow 依赖注入。
   */
  createHandler(IPC_CHANNELS.TEACHING_HISTORY_ADD, async (event, args) => {
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

    // 精通门控(0.8 阈值,TODO R-014 外置)
    const MASTERY_THRESHOLD = 0.8;
    const masteryReached = total > 0 && consumed / total >= MASTERY_THRESHOLD;

    if (masteryReached) {
      event.sender.send(IPC_CHANNELS.TEACHING_STATE_MASTERY, {
        sessionId,
        consumed,
        total,
        threshold: MASTERY_THRESHOLD,
      });
    }

    return { added: true, masteryReached, consumed, total };
  });

  /**
   * training:generateFlow — S8 五步通用训练流生成
   */
  createHandler(IPC_CHANNELS.TRAINING_GENERATE_FLOW, async (_event, args) => {
    const validation = validatePayload<{
      syndromeId: string;
      techniqueName: string;
      userLevel?: number;
      syndromeDescription?: string;
      challengeConstraint?: string;
    }>(args, { required: ['syndromeId', 'techniqueName'], types: { syndromeId: 'string', techniqueName: 'string' } });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);

    const flow = generateTrainingFlow({
      syndromeId: validation.data.syndromeId,
      techniqueName: validation.data.techniqueName,
      userLevel: validation.data.userLevel ?? 1,
      syndromeDescription: validation.data.syndromeDescription,
      challengeConstraint: validation.data.challengeConstraint,
    });

    return flow;
  });

  /**
   * training:catalog — I-01 技法目录
   *
   * 从 technique-library.json 读取技法数据，按 coreId 分组后返回。
   * 无输入校验需求（只读操作，过滤参数可选）。
   */
  createHandler(IPC_CHANNELS.TRAINING_CATALOG, async (_event, args?: TrainingCatalogRequest) => {
    const grouped: Record<string, { coreName: string; techniques: Array<{
      id: string; name: string; difficulty: string; difficultyOrder: number;
      description: string; source: string; category: string;
    }> }> = {};

    for (const t of (techniqueLibrary as TechniqueItem[])) {
      // 可选过滤
      if (args?.difficulty && t.difficulty !== args.difficulty) continue;
      if (args?.coreId && t.coreId !== args.coreId) continue;
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
