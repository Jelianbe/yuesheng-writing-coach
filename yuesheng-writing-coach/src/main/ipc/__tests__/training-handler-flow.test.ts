// ============================================================
// Training IPC Handler 扩展集成测试
// 验证：
// 1. training:recommend — 推荐训练任务
// 2. training:assign — 分配训练记录
// 3. training:complete — 标记完成
// 4. training:history — 查询训练历史
// 5. retro:generate — 生成复盘总结
// 6. training:submit + training:evaluate — 提交评估链路
//
// 测试策略：
// - 使用 :memory: SQLite 创建真实数据库
// - TrainingRecordService 使用真实 DB 实例
// - evaluateTraining 使用 vi.mock 避免真实 LLM 调用
// - 使用 vi.mock('electron') 让 createHandler 将 wrapper 存入
//   ipcMain.handle.mock.calls，然后通过 await import('electron')
//   读取这些 wrapper 并调用。
// - 每次 beforeEach 清除 mock 调用记录并重新注册 handler，
//   确保闭包捕获最新依赖。
// ============================================================

import { describe, it, expect, vi, beforeEach } from 'vitest';
import { IPC_CHANNELS } from '../../../shared/constants';
import Database from 'better-sqlite3';
import { TrainingRecordService } from '../../domains/04-validation/training/training-record.service';
import { RetroService } from '../../domains/05-retro/retro.service';
import type { ConfigService } from '../../shared/services/config.service';
import type { StudentModelService } from '../../domains/02-prescription/student/student-model-service';
import type { TeachingStateService } from '../../domains/03-teaching/teaching-state.service';
import type { TeachingStrategyService } from '../../domains/02-prescription/strategy/service';
import type { SyndromeAggregation } from '../../domains/02-prescription/student/student-model-service.types';

// ============================================================
// 类型定义
// ============================================================

/** Handler 函数签名（createHandler 产生的包装函数） */
type HandlerFn = (event: unknown, args: Record<string, unknown>) => Promise<{ success: boolean; data?: unknown; error?: string }>;

// ============================================================
// Mock 设置（顶层 hoist）
// ============================================================

vi.mock('electron', () => ({
  ipcMain: { handle: vi.fn() },
  BrowserWindow: {
    getAllWindows: () => [{
      webContents: { send: vi.fn(), isDestroyed: () => false },
    }],
  },
  app: { getPath: () => ':memory:', getVersion: () => '1.0.0-test' },
}));

// 模拟 training-evaluator.service 中的 evaluateTraining，避免真实 LLM 调用
const mockEvaluateResult = {
  score: 8,
  feedback: '改写聚焦了核心场景，使用行动而非解释来展现世界观。',
  improved: true,
  nextStep: '尝试在更多场景中运用——让行动说话而非靠解释。',
};

vi.mock('../../domains/04-validation/training/training-evaluator.service', () => ({
  evaluateTraining: vi.fn().mockResolvedValue(mockEvaluateResult),
}));

// 模拟 ApiProxy 以防被 evaluateTraining 内部使用
vi.mock('../../../api-proxy', () => ({
  ApiProxy: vi.fn().mockImplementation(() => ({
    chatStream: vi.fn().mockReturnValue(
      (async function* () { /* no-op */ })(),
    ),
  })),
}));

// ============================================================
// 辅助函数
// ============================================================

/** 创建 :memory: SQLite 数据库（含训练所需的表结构） */
function createMemoryDb(): Database.Database {
  const db = new Database(':memory:');

  db.exec(`
    CREATE TABLE IF NOT EXISTS user_training_records (
      id TEXT PRIMARY KEY,
      session_id TEXT NOT NULL,
      task_id TEXT NOT NULL,
      syndrome_id TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'assigned',
      assigned_at TEXT NOT NULL DEFAULT (datetime('now')),
      completed_at TEXT,
      user_response TEXT,
      ai_feedback TEXT,
      effectiveness REAL,
      score INTEGER,
      task_type TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS student_model (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id TEXT NOT NULL,
      teaching_history TEXT DEFAULT '[]',
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now'))
    );
  `);

  return db;
}

/** 从 electron mock 中读取所有已注册的 handler，构建 Map */
async function collectHandlers(): Promise<Map<string, HandlerFn>> {
  const { ipcMain } = await import('electron');
  const handlers = new Map<string, HandlerFn>();
  const calls = vi.mocked(ipcMain.handle).mock.calls;
  for (const [channel, handler] of calls) {
    handlers.set(channel as string, handler as HandlerFn);
  }
  return handlers;
}

/** 构建 TrainingHandlerDeps 和相关服务的引用 */
function createTrainingTestHarness(db: Database.Database) {
  const trainingRecordService = new TrainingRecordService(db);

  const mockStudentModel = {
    getSyndromeProfile: vi.fn(),
    appendTeachingHistory: vi.fn(),
  };

  const mockTeachingState = {
    downgradeSeverity: vi.fn(),
  };

  const mockTeachingStrategy = {
    router: {
      decideReading: vi.fn().mockReturnValue({
        required: false, recommended: true, label: 'recommend_read', reason: '当前档位 yuesheng，推荐先阅读再训练。',
      }),
    },
  };

  const mockConfigService = {
    getConfig: () => ({ modelName: 'gpt-4', baseUrl: 'https://api.deepseek.com', apiKey: 'test-key' }),
    getConfigKey: vi.fn(),
    setConfigKey: vi.fn(),
  } as unknown as ConfigService;

  const deps = {
    configService: mockConfigService,
    trainingRecordService,
    studentModelService: mockStudentModel as unknown as StudentModelService,
    teachingStateService: mockTeachingState as unknown as TeachingStateService,
    teachingStrategyService: mockTeachingStrategy as unknown as TeachingStrategyService,
  };

  return {
    deps,
    trainingRecordService,
    mockStudentModel,
    mockTeachingState,
    mockTeachingStrategy,
  };
}

/** 创建可测试的 profile mock 数据 */
function createMockSyndromeProfile(): Record<string, Partial<SyndromeAggregation>> {
  return {
    P001: {
      latestSeverity: 'L2' as const,
      lastSeenAt: new Date('2026-06-01').toISOString(),
      trend: 'stable',
    },
    P003: {
      latestSeverity: 'L3' as const,
      lastSeenAt: new Date('2026-06-15').toISOString(),
      trend: 'worsening',
    },
  };
}

/** 从 handler map 中安全获取 handler */
function getHandler(handlers: Map<string, HandlerFn>, channel: string): HandlerFn {
  const handler = handlers.get(channel);
  expect(handler, `Handler for channel "${channel}" should be registered`).toBeDefined();
  return handler!;
}

// ============================================================
// 测试数据
// ============================================================

const TEST_SESSION_ID = 'test-session-001';
const TEST_CHALLENGE_ID = 'CH-P001-001';
const TEST_USER_DRAFT = '主角李明站在城门前，抬头望去。城墙上的石砖布满苔藓，城门两侧的石狮已经风化得看不清五官。他深吸一口气，迈步走了进去。';

// ============================================================
// 测试套件
// ============================================================

describe('Training IPC Handler 扩展集成测试', () => {
  let handlers: Map<string, HandlerFn>;
  let db: Database.Database;
  let harness: ReturnType<typeof createTrainingTestHarness>;

  beforeEach(async () => {
    vi.clearAllMocks();

    db = createMemoryDb();
    handlers = new Map();

    // 创建依赖
    harness = createTrainingTestHarness(db);

    // 注册 training handler
    const { initTrainingHandlers, registerTrainingHandlers } = await import('../training.handler');
    initTrainingHandlers(harness.deps);
    registerTrainingHandlers();

    // 注册 retro handler
    const { registerRetroHandlers } = await import('../retro.handler');
    registerRetroHandlers({
      retroService: new RetroService(harness.trainingRecordService),
    });

    // 收集所有注册的 handler
    handlers = await collectHandlers();
  });

  // ============================================================
  // 验证 1: training:recommend handler
  // ============================================================
  describe('training:recommend', () => {
    it('应根据症候画像返回 recommendations 列表', async () => {
      const handler = getHandler(handlers, IPC_CHANNELS.TRAINING_RECOMMEND);

      harness.mockStudentModel.getSyndromeProfile.mockReturnValue(createMockSyndromeProfile());

      const res = await handler({}, { sessionId: TEST_SESSION_ID });

      expect(res.success).toBe(true);
      expect(res.data).toHaveProperty('recommendations');
      const recommendations = (res.data as Record<string, unknown>).recommendations as Array<unknown>;
      expect(Array.isArray(recommendations)).toBe(true);
      expect(recommendations.length).toBeGreaterThan(0);

      const first = recommendations[0] as Record<string, unknown>;
      expect(first).toHaveProperty('challengeId');
      expect(first).toHaveProperty('challengeName');
      expect(first).toHaveProperty('description');
      expect(first).toHaveProperty('syndromeId');
      expect(first).toHaveProperty('severity');
    });

    it('症候画像为空时应返回空 recommendations 列表', async () => {
      const handler = getHandler(handlers, IPC_CHANNELS.TRAINING_RECOMMEND);

      harness.mockStudentModel.getSyndromeProfile.mockReturnValue({});

      const res = await handler({}, { sessionId: TEST_SESSION_ID });

      expect(res.success).toBe(true);
      expect(res.data).toHaveProperty('recommendations');
      expect((res.data as Record<string, unknown>).recommendations).toEqual([]);
    });

    it('缺少 sessionId 时应返回错误', async () => {
      const handler = getHandler(handlers, IPC_CHANNELS.TRAINING_RECOMMEND);

      const res = await handler({}, {});

      expect(res.success).toBe(false);
      expect(res.error).toBeDefined();
    });
  });

  // ============================================================
  // 验证 2: training:assign handler
  // ============================================================
  describe('training:assign', () => {
    it('应创建训练记录并返回完整的 record 结构', async () => {
      const handler = getHandler(handlers, IPC_CHANNELS.TRAINING_ASSIGN);

      const res = await handler({}, {
        sessionId: TEST_SESSION_ID,
        challengeId: TEST_CHALLENGE_ID,
      });

      expect(res.success).toBe(true);
      expect(res.data).toHaveProperty('record');

      const record = (res.data as Record<string, unknown>).record as Record<string, unknown>;
      expect(record).toHaveProperty('id');
      expect(record).toHaveProperty('sessionId', TEST_SESSION_ID);
      expect(record).toHaveProperty('taskId', TEST_CHALLENGE_ID);
      expect(record).toHaveProperty('syndromeId', 'P001');
      expect(record).toHaveProperty('status', 'assigned');
      expect(record).toHaveProperty('assignedAt');
      expect(record).toHaveProperty('taskType');

      const savedRecord = harness.trainingRecordService.getById(record.id as string);
      expect(savedRecord).not.toBeNull();
      expect(savedRecord!.status).toBe('assigned');
    });

    it('使用不存在的 challengeId 时应返回错误', async () => {
      const handler = getHandler(handlers, IPC_CHANNELS.TRAINING_ASSIGN);

      const res = await handler({}, {
        sessionId: TEST_SESSION_ID,
        challengeId: 'NONEXISTENT',
      });

      expect(res.success).toBe(false);
      expect(res.error).toBeDefined();
      expect(res.error).toContain('Challenge template not found');
    });

    it('缺少必填字段时应返回错误', async () => {
      const handler = getHandler(handlers, IPC_CHANNELS.TRAINING_ASSIGN);

      const res = await handler({}, { sessionId: TEST_SESSION_ID });
      expect(res.success).toBe(false);
      expect(res.error).toBeDefined();
    });
  });

  // ============================================================
  // 验证 3: training:complete handler
  // ============================================================
  describe('training:complete', () => {
    it('应标记记录为 completed 并保存用户反馈', async () => {
      const assignHandler = getHandler(handlers, IPC_CHANNELS.TRAINING_ASSIGN);
      const completeHandler = getHandler(handlers, IPC_CHANNELS.TRAINING_COMPLETE);

      const assignRes = await assignHandler({}, {
        sessionId: TEST_SESSION_ID,
        challengeId: TEST_CHALLENGE_ID,
      });
      const recordId = ((assignRes.data as Record<string, unknown>).record as Record<string, unknown>).id as string;

      const completeRes = await completeHandler({}, {
        recordId,
        userResponse: TEST_USER_DRAFT,
        aiFeedback: '改写很棒，聚焦了场景。',
        effectiveness: 4,
      });

      expect(completeRes.success).toBe(true);
      const updatedRecord = (completeRes.data as Record<string, unknown>).record as Record<string, unknown>;
      expect(updatedRecord.status).toBe('completed');
      expect(updatedRecord.userResponse).toBe(TEST_USER_DRAFT);
      expect(updatedRecord.aiFeedback).toBe('改写很棒，聚焦了场景。');
      expect(updatedRecord.effectiveness).toBe(4);
      expect(updatedRecord.completedAt).not.toBeNull();

      const savedRecord = harness.trainingRecordService.getById(recordId);
      expect(savedRecord).not.toBeNull();
      expect(savedRecord!.status).toBe('completed');
      expect(savedRecord!.userResponse).toBe(TEST_USER_DRAFT);
    });

    it('不存在的 recordId 应返回错误', async () => {
      const handler = getHandler(handlers, IPC_CHANNELS.TRAINING_COMPLETE);

      const res = await handler({}, {
        recordId: 'nonexistent',
        userResponse: 'test',
      });

      expect(res.success).toBe(false);
      expect(res.error).toBeDefined();
    });
  });

  // ============================================================
  // 验证 4: training:history handler
  // ============================================================
  describe('training:history', () => {
    it('应返回会话的所有训练记录', async () => {
      const assignHandler = getHandler(handlers, IPC_CHANNELS.TRAINING_ASSIGN);
      const historyHandler = getHandler(handlers, IPC_CHANNELS.TRAINING_HISTORY);

      for (let i = 0; i < 3; i++) {
        await assignHandler({}, {
          sessionId: TEST_SESSION_ID,
          challengeId: `CH-P001-00${i + 1}`,
        });
      }

      const res = await historyHandler({}, { sessionId: TEST_SESSION_ID });

      expect(res.success).toBe(true);
      const records = (res.data as Record<string, unknown>).records as Array<unknown>;
      expect(Array.isArray(records)).toBe(true);
      expect(records.length).toBe(3);

      records.forEach((r) => {
        const record = r as Record<string, unknown>;
        expect(record).toHaveProperty('id');
        expect(record).toHaveProperty('sessionId', TEST_SESSION_ID);
        expect(record).toHaveProperty('status');
      });
    });

    it('没有训练记录的会话应返回空数组', async () => {
      const handler = getHandler(handlers, IPC_CHANNELS.TRAINING_HISTORY);

      const res = await handler({}, { sessionId: 'empty-session' });

      expect(res.success).toBe(true);
      expect((res.data as Record<string, unknown>).records).toEqual([]);
    });
  });

  // ============================================================
  // 验证 5: retro:generate handler
  // ============================================================
  describe('retro:generate', () => {
    it('有训练记录时应返回完整的 RetroSummary', async () => {
      const assignHandler = getHandler(handlers, IPC_CHANNELS.TRAINING_ASSIGN);
      const completeHandler = getHandler(handlers, IPC_CHANNELS.TRAINING_COMPLETE);
      const retroHandler = getHandler(handlers, IPC_CHANNELS.RETRO_GENERATE);

      // 创建多条训练记录
      const assign1 = await assignHandler({}, {
        sessionId: TEST_SESSION_ID,
        challengeId: 'CH-P001-001',
      });
      const record1Id = ((assign1.data as Record<string, unknown>).record as Record<string, unknown>).id as string;
      await completeHandler({}, {
        recordId: record1Id,
        userResponse: TEST_USER_DRAFT,
        score: 8,
      });

      const assign2 = await assignHandler({}, {
        sessionId: TEST_SESSION_ID,
        challengeId: 'CH-P003-001',
      });
      const record2Id = ((assign2.data as Record<string, unknown>).record as Record<string, unknown>).id as string;
      await completeHandler({}, {
        recordId: record2Id,
        userResponse: TEST_USER_DRAFT,
        score: 6,
      });

      // 生成复盘总结
      const res = await retroHandler({}, { sessionId: TEST_SESSION_ID });

      expect(res.success).toBe(true);
      const summary = res.data as Record<string, unknown>;
      expect(summary).toHaveProperty('totalTrainingCount');
      expect(summary).toHaveProperty('syndromeCount');
      expect(summary).toHaveProperty('syndromeSummaries');
      expect(summary).toHaveProperty('overallImprovement');
      expect(summary).toHaveProperty('masteredTechniques');
      expect(summary).toHaveProperty('recommendedFocus');
      expect(summary).toHaveProperty('summary');

      expect(summary.totalTrainingCount).toBe(2);
      expect(summary.syndromeCount).toBe(2);

      const syndromeSummaries = summary.syndromeSummaries as Array<Record<string, unknown>>;
      expect(syndromeSummaries.length).toBe(2);
      syndromeSummaries.forEach((s) => {
        expect(s).toHaveProperty('syndromeId');
        expect(s).toHaveProperty('syndromeName');
        expect(s).toHaveProperty('trainingCount');
        expect(s).toHaveProperty('initialScore');
        expect(s).toHaveProperty('currentScore');
        expect(s).toHaveProperty('improvement');
        expect(s).toHaveProperty('mastered');
      });
    });

    it('没有训练记录时应返回空的 RetroSummary', async () => {
      const handler = getHandler(handlers, IPC_CHANNELS.RETRO_GENERATE);

      const res = await handler({}, { sessionId: 'empty-session' });

      expect(res.success).toBe(true);
      const summary = res.data as Record<string, unknown>;
      expect(summary.totalTrainingCount).toBe(0);
      expect(summary.syndromeCount).toBe(0);
      expect(summary.syndromeSummaries).toEqual([]);
      expect(summary.overallImprovement).toBe(0);
      expect(summary.masteredTechniques).toEqual([]);
      expect(summary.recommendedFocus).toEqual([]);
      expect(summary.summary).toContain('暂无训练记录');
    });
  });

  // ============================================================
  // 验证 6: training:submit + training:evaluate 链路
  // ============================================================
  describe('training:submit + training:evaluate 链路', () => {
    it('training:submit 应返回评估结果（不修改记录）', async () => {
      const handler = getHandler(handlers, IPC_CHANNELS.TRAINING_SUBMIT);

      const res = await handler({}, {
        challengeDescription: '聚焦一个具体场景',
        constraint: '只能保留一个场景，其余全部删除',
        originalQuote: '这个世界有三千大世界，亿万小世界...',
        userDraft: TEST_USER_DRAFT,
      });

      expect(res.success).toBe(true);
      expect(res.data).toHaveProperty('passed');
      expect(res.data).toHaveProperty('feedback');
      expect(res.data).toHaveProperty('score');
      expect(res.data).toHaveProperty('improved');
      expect(res.data).toHaveProperty('nextStep');

      expect((res.data as Record<string, unknown>).passed).toBe(true);
      expect((res.data as Record<string, unknown>).score).toBe(8);
    });

    it('training:evaluate 应完成记录并降低严重度', async () => {
      const assignHandler = getHandler(handlers, IPC_CHANNELS.TRAINING_ASSIGN);
      const evaluateHandler = getHandler(handlers, IPC_CHANNELS.TRAINING_EVALUATE);

      const assignRes = await assignHandler({}, {
        sessionId: TEST_SESSION_ID,
        challengeId: TEST_CHALLENGE_ID,
      });
      const recordId = ((assignRes.data as Record<string, unknown>).record as Record<string, unknown>).id as string;

      const res = await evaluateHandler({}, {
        recordId,
        sessionId: TEST_SESSION_ID,
        syndromeId: 'P001',
        challengeDescription: '聚焦一个具体场景',
        constraint: '只能保留一个场景',
        originalQuote: '这个世界有三千大世界...',
        userDraft: TEST_USER_DRAFT,
      });

      expect(res.success).toBe(true);
      const evaluation = res.data as Record<string, unknown>;
      expect(evaluation).toHaveProperty('score');
      expect(evaluation).toHaveProperty('feedback');
      expect(evaluation).toHaveProperty('improved');
      expect(evaluation).toHaveProperty('nextStep');

      const savedRecord = harness.trainingRecordService.getById(recordId);
      expect(savedRecord).not.toBeNull();
      expect(savedRecord!.status).toBe('completed');
      expect(savedRecord!.userResponse).toBe(TEST_USER_DRAFT);
      expect(savedRecord!.score).toBe(8);

      expect(harness.mockTeachingState.downgradeSeverity).toHaveBeenCalledWith(
        TEST_SESSION_ID,
        'P001',
        8,
      );
    });

    it('training:evaluate 低分时不降低严重度', async () => {
      const evaluateTrainingMock = (await import('../../domains/04-validation/training/training-evaluator.service')).evaluateTraining as ReturnType<typeof vi.fn>;
      evaluateTrainingMock.mockResolvedValueOnce({
        score: 4,
        feedback: '改写还需要聚焦。',
        improved: false,
        nextStep: '重新阅读约束条件',
      });

      const assignHandler = getHandler(handlers, IPC_CHANNELS.TRAINING_ASSIGN);
      const evaluateHandler = getHandler(handlers, IPC_CHANNELS.TRAINING_EVALUATE);

      const assignRes = await assignHandler({}, {
        sessionId: TEST_SESSION_ID,
        challengeId: TEST_CHALLENGE_ID,
      });
      const recordId = ((assignRes.data as Record<string, unknown>).record as Record<string, unknown>).id as string;

      const res = await evaluateHandler({}, {
        recordId,
        sessionId: TEST_SESSION_ID,
        syndromeId: 'P001',
        challengeDescription: '聚焦一个具体场景',
        constraint: '只能保留一个场景',
        originalQuote: '这个世界有三千大世界...',
        userDraft: '测试改写',
      });

      expect(res.success).toBe(true);
      expect((res.data as Record<string, unknown>).score).toBe(4);

      expect(harness.mockTeachingState.downgradeSeverity).not.toHaveBeenCalled();
    });
  });
});
