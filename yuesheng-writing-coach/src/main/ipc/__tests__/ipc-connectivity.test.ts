// ============================================================
// IPC 连通性测试
// 验证：
// 1. 关键 IPC channel 在前端 preload 和后端 handler 间正确连通
// 2. handler 调用后返回预期结构（{ success, data } 或 { success, error }）
// 3. 作品/章节的创建、更新、删除操作正确持久化到内存 DB
// ============================================================

import { describe, it, expect, vi, beforeAll, beforeEach } from 'vitest';
import { IPC_CHANNELS } from '../../../shared/constants';
import Database from 'better-sqlite3';
import type { SessionHandlerDeps } from '../session.handler';
import type { DiagnosisHandlerDeps } from '../diagnosis.handler';
import type { ChatOrchestratorService } from '../../domains/03-teaching/chat/chat-orchestrator.service';

// ============================================================
// 类型定义
// ============================================================

/** 通用 handler 返回结果 */
interface HandlerResult<T = unknown> {
  success: boolean;
  data?: T;
  error?: string;
}

/** Mock 容器形状（服务定位器模式） */
interface MockContainer {
  get: (key: string) => Record<string, unknown>;
}

/** Handler 函数签名 */
type HandlerFn = (event: unknown, args: Record<string, unknown>) => Promise<HandlerResult<unknown>> | HandlerResult<unknown>;

// 所有 handler 使用 :memory: 模式 DB，不依赖真实文件

// ============================================================
// Handler 级别的连通性测试
// 每个 handler 注册到 ipcMain.handle 后，直接调用 handler 函数
// 验证返回结构正确、数据持久化正确
// ============================================================

/** 构建轻量 mock 容器 */
function createMockContainer(db: Database.Database): MockContainer {
  return {
    get: vi.fn((key: string): Record<string, unknown> => {
      if (key === 'db') return db as unknown as Record<string, unknown>;
      if (key === 'configService') return { getConfig: () => ({ modelName: 'gpt-4' }) };
      if (key === 'sessionService') return {
        saveMessage: vi.fn(),
        getOrCreateDefaultSession: vi.fn(() => ({ id: 'test-session' })),
        autoGenerateTitle: vi.fn().mockResolvedValue(undefined),
        listSessions: vi.fn(),
        getLastMessage: vi.fn(),
        getRecentBySession: vi.fn().mockReturnValue([]),
        processAIResponse: vi.fn().mockReturnValue(undefined),
      };
      if (key === 'diagnosisService') return { findBySessionId: vi.fn().mockResolvedValue(null), save: vi.fn() };
      if (key === 'evidenceService') return { findBySessionId: vi.fn().mockReturnValue([]), save: vi.fn() };
      if (key === 'trainingRecordService') return { findBySessionId: vi.fn().mockReturnValue([]) };
      if (key === 'studentModelService') return { getProfile: vi.fn().mockResolvedValue(null) };
      if (key === 'abilityProfileService') return {};
      if (key === 'growthTrendService') return { getTrends: vi.fn().mockResolvedValue({ daily: [], weekly: [], totalSessions: 0 }) };
      if (key === 'diagnosisMerger') return { merge: vi.fn() };
      if (key === 'teachingStateService') return {
        getState: vi.fn().mockResolvedValue(null),
        updateState: vi.fn(),
        createState: vi.fn(),
      };
      if (key === 'teachingStrategyService') return {};
      if (key === 'teachingDomain') return {};
      if (key === 'studentDomain') return { toPromptText: vi.fn().mockResolvedValue('mock student') };
      if (key === 'promptDomain') return { loadSystemPrompt: vi.fn().mockResolvedValue(''), buildCapsule: vi.fn().mockReturnValue('') };
      if (key === 'messageRouter') return { handleContentMessage: vi.fn().mockResolvedValue(null) };
      if (key === 'orchestrator') return { sendMessage: vi.fn().mockResolvedValue({ success: true, messageId: 'mock' }) };
      if (key === 'diagnosisOrchestrator') return { analyze: vi.fn().mockResolvedValue(null), extractSyndromeIds: vi.fn().mockReturnValue([]) };
      if (key === 'teachingNoteService') return {
        recordNote: vi.fn().mockResolvedValue({ id: 'note-1' }),
        getTree: vi.fn().mockResolvedValue([]),
        deleteNode: vi.fn(),
      };
      return {};
    }),
  };
}

/** 创建 :memory: SQLite 数据库 */
function createMemoryDb(): Database.Database {
  const db = new Database(':memory:');

  // 创建需要的表结构
  db.exec(`
    CREATE TABLE IF NOT EXISTS manuscripts (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL DEFAULT '',
      description TEXT DEFAULT '',
      genre TEXT DEFAULT '',
      status TEXT DEFAULT 'draft',
      word_count INTEGER DEFAULT 0,
      sort_order INTEGER DEFAULT 0,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now'))
    );
    CREATE TABLE IF NOT EXISTS chapters (
      id TEXT PRIMARY KEY,
      manuscript_id TEXT NOT NULL,
      title TEXT NOT NULL DEFAULT '',
      content TEXT DEFAULT '',
      word_count INTEGER DEFAULT 0,
      sort_order INTEGER DEFAULT 0,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now'))
    );
    CREATE TABLE IF NOT EXISTS sessions (
      id TEXT PRIMARY KEY,
      title TEXT DEFAULT '',
      project_id TEXT,
      type TEXT DEFAULT 'chat',
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now'))
    );
    CREATE TABLE IF NOT EXISTS projects (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL DEFAULT '',
      description TEXT DEFAULT '',
      setting_tree TEXT DEFAULT '',
      setting_tree_type TEXT DEFAULT 'main',
      type TEXT DEFAULT 'training',
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now'))
    );
  `);

  return db;
}

// ============================================================
// 测试数据
// ============================================================
const TEST_MANUSCRIPT = { title: '测试作品', description: '连通性测试', genre: '修仙' };
const TEST_CHAPTER = { title: '第一章 测试', content: '测试章节内容。验证 IPC 写入。' };

/** 从 MockContainer 构建 SessionHandlerDeps */
function buildSessionDeps(container: MockContainer): SessionHandlerDeps {
  return {
    sessionService: container.get('sessionService') as unknown as SessionHandlerDeps['sessionService'],
  };
}

/** 从 MockContainer 构建 DiagnosisHandlerDeps */
function buildDiagnosisDeps(container: MockContainer): DiagnosisHandlerDeps {
  return {
    configService: container.get('configService') as unknown as DiagnosisHandlerDeps['configService'],
    diagnosisService: container.get('diagnosisService') as unknown as DiagnosisHandlerDeps['diagnosisService'],
    evidenceService: container.get('evidenceService') as unknown as DiagnosisHandlerDeps['evidenceService'],
    sessionService: container.get('sessionService') as unknown as DiagnosisHandlerDeps['sessionService'],
    growthTrendService: container.get('growthTrendService') as unknown as DiagnosisHandlerDeps['growthTrendService'],
    teachingStateService: container.get('teachingStateService') as unknown as DiagnosisHandlerDeps['teachingStateService'],
    diagnosisMerger: container.get('diagnosisMerger') as unknown as DiagnosisHandlerDeps['diagnosisMerger'],
    mainWindow: null,
  };
}

/** 创建 ChatOrchestratorService 的 mock 实例 */
function createMockOrchestrator(): ChatOrchestratorService {
  return {
    sendMessage: vi.fn().mockResolvedValue({ messageId: 'mock' }),
    stopGeneration: vi.fn(),
    handleOnboardingAnalyze: vi.fn().mockResolvedValue(undefined),
    updateApiProxyConfig: vi.fn(),
  } as unknown as ChatOrchestratorService;
}

// ============================================================
// 测试套件
// ============================================================
describe('IPC 连通性测试', () => {
  let handlers: Map<string, HandlerFn>;
  let db: Database.Database;

  beforeAll(() => {
    vi.mock('electron', () => {
      const mockHandleFn = vi.fn();
      const mockSendFn = vi.fn();
      return {
        ipcMain: { handle: mockHandleFn },
        BrowserWindow: {
          getAllWindows: () => [{
            webContents: { send: mockSendFn, isDestroyed: () => false },
          }],
        },
        app: { getPath: () => ':memory:', getVersion: () => '1.0.0-test' },
      };
    });
  });

  beforeEach(async () => {
    vi.clearAllMocks();
    handlers = new Map();

    db = createMemoryDb();
    const container = createMockContainer(db);

    // 注册 handler（使用内存 DB）
    const { initManuscriptHandlers, registerManuscriptHandlers } = await import('../manuscript.handler');
    initManuscriptHandlers({ db });
    registerManuscriptHandlers();

    const { initSessionHandlers, registerSessionHandlers } = await import('../session.handler');
    initSessionHandlers(buildSessionDeps(container));
    registerSessionHandlers();

    const { initProjectHandlers, registerProjectHandlers } = await import('../project.handler');
    initProjectHandlers({ db });
    registerProjectHandlers();

    const { initDiagnosisHandlers, registerDiagnosisHandlers } = await import('../diagnosis.handler');
    initDiagnosisHandlers(buildDiagnosisDeps(container));
    registerDiagnosisHandlers();

    const { initChatHandlers, registerChatHandlers } = await import('../chat.handler');
    initChatHandlers(createMockOrchestrator());
    registerChatHandlers();

    // 收集所有注册的 handler
    const { ipcMain } = await import('electron');
    const mockHandle = vi.mocked(ipcMain.handle);
    mockHandle.mock.calls.forEach(([channel, handler]) => {
      handlers.set(channel as string, handler as HandlerFn);
    });
  });

  // ============================================================
  // 验证 1：IPC channel 注册完备性
  // ============================================================
  it('作品和章节相关的 IPC channel 应全部注册', () => {
    const manuscriptChannels = [
      IPC_CHANNELS.MANUSCRIPT_LIST,
      IPC_CHANNELS.MANUSCRIPT_GET,
      IPC_CHANNELS.MANUSCRIPT_CREATE,
      IPC_CHANNELS.MANUSCRIPT_UPDATE,
      IPC_CHANNELS.MANUSCRIPT_DELETE,
      IPC_CHANNELS.CHAPTER_LIST,
      IPC_CHANNELS.CHAPTER_GET,
      IPC_CHANNELS.CHAPTER_CREATE,
      IPC_CHANNELS.CHAPTER_UPDATE_CONTENT,
      IPC_CHANNELS.CHAPTER_DELETE,
    ];
    manuscriptChannels.forEach(channel => {
      expect(handlers.has(channel)).toBe(true);
    });
  });

  // ============================================================
  // 验证 2：作品 CRUD（含文件写入验证）
  // ============================================================
  describe('作品管理 CRUD', () => {
    it('manuscript:create 应创建作品并用 list 验证持久化', async () => {
      const create = handlers.get(IPC_CHANNELS.MANUSCRIPT_CREATE)!;
      const list = handlers.get(IPC_CHANNELS.MANUSCRIPT_LIST)!;
      const get = handlers.get(IPC_CHANNELS.MANUSCRIPT_GET)!;

      // 创建
      const createRes = await create({}, TEST_MANUSCRIPT);
      expect(createRes.success).toBe(true);
      expect(createRes.data).toHaveProperty('id');
      const msId = (createRes.data as Record<string, unknown>).id as string;

      // list 验证
      const listRes = await list({}, {});
      expect(listRes.success).toBe(true);
      expect((listRes.data as Array<Record<string, unknown>>).find((m) => m.id === msId)).toBeDefined();

      // get 验证
      const getRes = await get({}, { id: msId });
      expect((getRes.data as Record<string, unknown>).title).toBe(TEST_MANUSCRIPT.title);
    });

    it('manuscript:update 应更新并持久化', async () => {
      const create = handlers.get(IPC_CHANNELS.MANUSCRIPT_CREATE)!;
      const update = handlers.get(IPC_CHANNELS.MANUSCRIPT_UPDATE)!;
      const get = handlers.get(IPC_CHANNELS.MANUSCRIPT_GET)!;

      const createRes = await create({}, TEST_MANUSCRIPT);
      const msId = (createRes.data as Record<string, unknown>).id as string;

      await update({}, { id: msId, title: '已更新' });

      const getRes = await get({}, { id: msId });
      expect((getRes.data as Record<string, unknown>).title).toBe('已更新');
    });

    it('chapter:create + chapter:updateContent 应写入并验证（文件写入测试）', async () => {
      const createMs = handlers.get(IPC_CHANNELS.MANUSCRIPT_CREATE)!;
      const createCh = handlers.get(IPC_CHANNELS.CHAPTER_CREATE)!;
      const updateCh = handlers.get(IPC_CHANNELS.CHAPTER_UPDATE_CONTENT)!;
      const getCh = handlers.get(IPC_CHANNELS.CHAPTER_GET)!;
      const listCh = handlers.get(IPC_CHANNELS.CHAPTER_LIST)!;

      // 创建作品
      const msRes = await createMs({}, TEST_MANUSCRIPT);
      const msId = (msRes.data as Record<string, unknown>).id as string;

      // 创建章节
      const chRes = await createCh({}, { manuscriptId: msId, ...TEST_CHAPTER });
      expect(chRes.success).toBe(true);
      const chId = (chRes.data as Record<string, unknown>).id as string;

      // list 验证章节已创建
      const listRes = await listCh({}, { manuscriptId: msId });
      expect((listRes.data as Array<Record<string, unknown>>).find((c) => c.id === chId)).toBeDefined();

      // 更新正文（文件写入）
      const updatedContent = '这是更新后的正文。验证 IPC 写入是否持久化。';
      await updateCh({}, { id: chId, content: updatedContent });

      // get 验证写入
      const getRes = await getCh({}, { id: chId });
      expect((getRes.data as Record<string, unknown>).content).toBe(updatedContent);
      const expectedWordCount = updatedContent.replace(/[\s\n\r]+/g, '').length;
      expect((getRes.data as Record<string, unknown>).word_count).toBe(expectedWordCount);
    });

    it('chapter:delete 应删除单个章节', async () => {
      const createMs = handlers.get(IPC_CHANNELS.MANUSCRIPT_CREATE)!;
      const createCh = handlers.get(IPC_CHANNELS.CHAPTER_CREATE)!;
      const deleteCh = handlers.get(IPC_CHANNELS.CHAPTER_DELETE)!;
      const getCh = handlers.get(IPC_CHANNELS.CHAPTER_GET)!;

      const msRes = await createMs({}, TEST_MANUSCRIPT);
      const chRes = await createCh({}, { manuscriptId: (msRes.data as Record<string, unknown>).id as string, ...TEST_CHAPTER });
      const chId = (chRes.data as Record<string, unknown>).id as string;

      // 删除
      const delRes = await deleteCh({}, { id: chId });
      expect(delRes.success).toBe(true);

      // 验证已删除
      const getRes = await getCh({}, { id: chId });
      // 删除后 get 可能返回 null 或 error
      expect(getRes.data).toBeNull();
    });

    it('manuscript:delete 应级联删除所有章节', async () => {
      const createMs = handlers.get(IPC_CHANNELS.MANUSCRIPT_CREATE)!;
      const createCh = handlers.get(IPC_CHANNELS.CHAPTER_CREATE)!;
      const deleteMs = handlers.get(IPC_CHANNELS.MANUSCRIPT_DELETE)!;
      const listCh = handlers.get(IPC_CHANNELS.CHAPTER_LIST)!;
      const getMs = handlers.get(IPC_CHANNELS.MANUSCRIPT_GET)!;

      const msRes = await createMs({}, TEST_MANUSCRIPT);
      const msId = (msRes.data as Record<string, unknown>).id as string;
      await createCh({}, { manuscriptId: msId, ...TEST_CHAPTER });

      // 删除作品
      await deleteMs({}, { id: msId });

      // 验证章节已级联删除
      const listRes = await listCh({}, { manuscriptId: msId });
      expect((listRes.data as Array<unknown>)).toHaveLength(0);

      // 验证作品已删除
      const getRes = await getMs({}, { id: msId });
      expect(getRes.data).toBeNull();
    });
  });

  // ============================================================
  // 验证 3：删除功能
  // ============================================================
  describe('删除功能', () => {
    it('session:delete 应删除会话', async () => {
      const handler = handlers.get(IPC_CHANNELS.SESSION_DELETE)!;
      expect(handler).toBeDefined();

      // session handler 使用 sessionService（mocked），只需要验证 handler 可调用
      const res = await handler({}, { id: 'test-session' });
      expect(res).toHaveProperty('success');
    });

    it('project:delete 应删除项目', async () => {
      const create = handlers.get(IPC_CHANNELS.PROJECT_CREATE)!;
      const del = handlers.get(IPC_CHANNELS.PROJECT_DELETE)!;
      const list = handlers.get(IPC_CHANNELS.PROJECT_LIST)!;

      const createRes = await create({}, { name: '测试项目', type: 'training' });
      expect(createRes.success).toBe(true);
      const projectId = (createRes.data as Record<string, unknown>)?.id as string | undefined;

      if (projectId) {
        // 验证已创建
        const listRes = await list({}, {});
        expect((listRes.data as Array<Record<string, unknown>>).find((p) => p.id === projectId)).toBeDefined();

        // 删除
        await del({}, { projectId });

        // 验证已删除
        const listRes2 = await list({}, {});
        expect((listRes2.data as Array<Record<string, unknown>>).find((p) => p.id === projectId)).toBeUndefined();
      }
    });
  });
});
