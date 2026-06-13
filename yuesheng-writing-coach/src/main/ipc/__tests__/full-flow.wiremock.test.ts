/**
 * 全链路 Wire Mock 端到端测试
 *
 * 核心理念：在 HTTP 网络边界拦截 fetch 请求，用预准备的 LLM 响应数据替代云端数据流。
 * 这样测试的是完整的真实处理管线（ApiProxy → chat.handler → diagnosis.handler），
 * 而非 mock 模块函数。
 *
 * 数据流：
 *   CHAT_SEND → callDiagnosisAgent() → [wire mock fetch] → DiagnosisAnalysis
 *             → loadSystemPrompt() + chatStream → [wire mock fetch] → Teaching Response
 *             → processDiagnosisFromAI() → [diagnosis-parser] → DiagnosisEntry
 *             → chat:stream:end
 *
 * 模拟数据基于：
 *   C:\Users\月笙如歌\Desktop\修仙传(1).txt
 *   该小说第1-2章展示了多种写作症候（P004信息硬塞、P003情绪标签化、P002角色工具化）
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { IPC_CHANNELS } from '../../../shared/constants';
import { createSSEResponse, createJSONResponse } from '../../../test/wire-mock/sse-helper';
import {
  DIAGNOSIS_AGENT_JSON,
  TEACHING_AGENT_FULL_RESPONSE,
  REWRITE_EVAL_JSON,
} from '../../../test/fixtures/llm-responses';

// ===== Mock 依赖 =====
vi.mock('electron', () => ({
  ipcMain: { handle: vi.fn() },
  BrowserWindow: vi.fn(() => ({
    webContents: { send: vi.fn() },
    on: vi.fn(),
    loadURL: vi.fn(),
    close: vi.fn(),
  })),
}));

// ===== 注入 ConfigService mock（替代静态 getInstance 调用） =====
const mockConfigService = {
  getConfig: vi.fn(() => ({
    apiKey: 'wire-mock-key',
    baseUrl: 'https://api.wiremock.com',
    modelName: 'gpt-4',
    attitudeLevel: 'gentle',
    temperature: 0.7,
    maxTokens: 8192,
  })),
  setConfigKey: vi.fn(),
};

// 模拟 SessionService（顶层常量，不受 vi.clearAllMocks 影响）
const mockSessionService = {
  saveMessage: vi.fn(),
  getOrCreateDefaultSession: vi.fn(() => ({ id: 'wiremock-session-1' })),
  autoGenerateTitle: vi.fn(),
  listSessions: vi.fn(),
  getLastMessage: vi.fn(),
  createSession: vi.fn(),
  deleteSession: vi.fn(),
  renameSession: vi.fn(),
  getMessages: vi.fn(),
};

// ===== 被测试模块导入 =====
import { ChatOrchestratorService } from '../../services/chat-orchestrator.service';
import { initChatHandlers, registerChatHandlers } from '../chat.handler';
import { initDiagnosisHandlers, registerDiagnosisHandlers } from '../diagnosis.handler';

// ===== 修仙传测试文本（第1章精华片段） =====
const XIUXIAN_TEXT = `午阳山的山风吹在身上，带着一股硫磺与草木腐烂混合的独特气味。孙项明站在蜿蜒的队伍中，心中那份穿越者的傲气早已被现实磨砺得只剩下冰冷的棱角。

筑基中期。普通散修资质。金丹便是终点。

这几个词像烙印一样刻在他的神魂深处。百余年后的枯骨，秘境里的无名炮灰——这便是"命运"为他勾勒的、清晰得令人绝望的轨迹。

"不甘心啊……"他低声自语，指节捏得发白。与其在末流的挣扎中耗尽寿元，不如趁着这百十年"壮年"，去搏那一线并非注定的生机！

前方传来管事刻板的声音："孙项明！"
孙项明立刻收敛心神，迈步上前。

负责发放物资的是仓央洲林家的管事，一个面无表情的中年修士。递过来的东西是一个粗糙玉瓶，装着几粒气味刺鼻的低阶回春丹；两张边缘微微磨损的土黄色遁地符；两张绘制着淡薄云纹的匿气符。

"规矩都懂。出来之后，七成收获上交，林家自有灵晶丹药补偿。"管事眼皮都没抬。

"明白。"孙项明接过东西，熟练地检查符箓的灵光是否稳定，丹药是否有异样。这是他数次进入秘境养成的本能——散修的命，得靠自己小心。`;

const SHORT_MESSAGE = '你好月笙，今天天气真好。';

const COLLABORATION_TEXT = `我想练习一下你说的"用动作代替情绪标签"这个技巧。我试着改写了这段：

原文：他不甘心，心中充满了愤怒。
改写：他的指节捏得发白，桌上的茶杯在掌中微微颤抖。

你觉得怎么样？有什么需要改进的地方吗？`;

// ============================================================
// 测试套件
// ============================================================
describe('全链路 Wire Mock 测试（基于《修仙传》）', () => {
  let invokeHandler: Function;
  let sendMock: ReturnType<typeof vi.fn>;

  beforeEach(async () => {
    vi.clearAllMocks();

    // === 设置 electron mock ===
    const { ipcMain, BrowserWindow } = await import('electron');
    const mockWindow = (BrowserWindow as any)();
    sendMock = mockWindow.webContents.send;

    // === 设置 diagnosis.handler DI ===
    const mockDiagService = {
      getRecentBySession: vi.fn().mockReturnValue([]),
      save: vi.fn(),
      saveAnalysis: vi.fn(),
      getBySession: vi.fn(),
    };
    const mockEvidService = {
      save: vi.fn(), linkToDiagnosis: vi.fn(), getByDisease: vi.fn(),
      getByAbility: vi.fn(), getChainForDiagnosis: vi.fn(),
    };

    const mockDiagnosisMerger = { merge: vi.fn() } as any;

    // === 设置 PromptLoader 和 MessageRouter mock ===
    const mockPromptLoader = {
      loadSystemPrompt: vi.fn((_attitude, diagnosisAnalysis, _diagnosisHistory, _studentContext, _sessionId) => {
        if (diagnosisAnalysis) return 'Teaching Agent Prompt';
        return 'Yuesheng Prompt';
      }),
    } as any;
    const mockMessageRouter = {
      shouldRunDiagnosis: () => true,
    } as any;

    // === 初始化 Chat Handlers ===
    const mockDisputeTracker = {
      checkMessage: vi.fn().mockReturnValue({ hasDispute: false }),
      getEffectiveAttitude: vi.fn().mockReturnValue('gentle'),
    };
    const mockReflectionGate = {
      shouldEnterReflection: vi.fn().mockReturnValue(false),
      shouldTriggerReflection: vi.fn().mockReturnValue(false),
    };

    const mockStudentModelService = {
      toPromptText: vi.fn().mockReturnValue(''),
      inferProficiency: vi.fn().mockReturnValue(0.5),
      inferCognitiveStyle: vi.fn().mockReturnValue('unknown'),
    };
    const mockTeachingStrategyService = {
      decide: vi.fn().mockReturnValue({ strategy: 'diagnosis', rationale: 'test' }),
    };
    const mockProblemPrioritizer = {
      prioritize: vi.fn().mockReturnValue([]),
    };

    const mockStrategyInstructionBuilder = {
      build: vi.fn().mockReturnValue(null),
    };

    // === 创建 ChatOrchestratorService ===
    const orchestrator = new ChatOrchestratorService({
      configService: mockConfigService as any,
      sessionService: mockSessionService as any,
      diagnosisService: mockDiagService as any,
      promptLoader: mockPromptLoader,
      messageRouter: mockMessageRouter,
      studentModelService: mockStudentModelService as any,
      teachingStrategyService: mockTeachingStrategyService as any,
      problemPrioritizer: mockProblemPrioritizer as any,
      disputeTracker: mockDisputeTracker as any,
      reflectionGate: mockReflectionGate as any,
      strategyInstructionBuilder: mockStrategyInstructionBuilder as any,
      mainWindow: mockWindow,
      db: { prepare: vi.fn().mockReturnValue({ get: vi.fn().mockReturnValue(null) }) } as any,
    });

    initChatHandlers(orchestrator);

    // === 初始化 Diagnosis Handlers ===
    const mockTeachingStateService = {
      getBySession: vi.fn().mockReturnValue({ activeProblems: [] }),
    };

    initDiagnosisHandlers({
      configService: mockConfigService as any,
      diagnosisService: mockDiagService as any,
      evidenceService: mockEvidService as any,
      sessionService: mockSessionService as any,
      growthTrendService: {} as any,
      teachingStateService: mockTeachingStateService as any,
      diagnosisMerger: mockDiagnosisMerger,
      mainWindow: mockWindow,
    });

    // === 注册 handler ===
    registerChatHandlers();
    registerDiagnosisHandlers();

    const handleCalls = (ipcMain.handle as any).mock.calls;
    const chatHandler = handleCalls.find((c: any[]) => c[0] === IPC_CHANNELS.CHAT_SEND);
    invokeHandler = chatHandler[1];
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  // ============================================================
  // 场景1：完整诊断 + 教学流程
  // ============================================================
  describe('场景1：提交长文本 → 诊断分析 → 教学回复', () => {
    it('带诊断分析的完整流程', async () => {
      let fetchCallCount = 0;
      vi.stubGlobal('fetch', vi.fn().mockImplementation(async () => {
        fetchCallCount++;
        if (fetchCallCount === 1) {
          return createSSEResponse(JSON.stringify(DIAGNOSIS_AGENT_JSON), 100);
        }
        return createSSEResponse(TEACHING_AGENT_FULL_RESPONSE, 100);
      }));

      const result = await invokeHandler({}, {
        message: XIUXIAN_TEXT,
        sessionId: 'wiremock-session-1',
        attitudeLevel: 'doubao',
      });

      expect(result.success).toBe(true);
      expect(result.data.messageId).toBeDefined();

      expect(mockSessionService.saveMessage).toHaveBeenCalledWith(
        'wiremock-session-1', 'user', expect.stringContaining('午阳山的山风吹在身上'),
      );
      expect(mockSessionService.saveMessage).toHaveBeenCalledWith(
        'wiremock-session-1', 'assistant', expect.stringContaining('硫磺与草木腐烂的气味'),
      );
      expect(mockSessionService.autoGenerateTitle).toHaveBeenCalledWith('wiremock-session-1');
      expect(fetchCallCount).toBe(2);
    });

    it('诊断分析结果通过 diagnosis:update 推送到前端', async () => {
      let callCount = 0;
      vi.stubGlobal('fetch', vi.fn().mockImplementation(async () => {
        callCount++;
        if (callCount === 1) {
          return createSSEResponse(JSON.stringify(DIAGNOSIS_AGENT_JSON), 100);
        }
        return createSSEResponse(TEACHING_AGENT_FULL_RESPONSE, 100);
      }));

      await invokeHandler({}, {
        message: XIUXIAN_TEXT,
        sessionId: 'wiremock-session-1',
      });

      // RP-02 去重：同一 sessionId 仅 Pipe1 推送一次
      const updateCalls = sendMock.mock.calls.filter(
        (c: any[]) => c[0] === IPC_CHANNELS.DIAGNOSIS_UPDATE
      );
      expect(updateCalls).toHaveLength(1);

      // 验证推送内容包含正确的 sessionId 和三个症候
      const onlyUpdate = updateCalls[0];
      expect(onlyUpdate[1]).toMatchObject({
        sessionId: 'wiremock-session-1',
        syndromes: expect.arrayContaining([
          expect.objectContaining({ id: 'P004', name: '信息硬塞' }),
          expect.objectContaining({ id: 'P003', name: '情绪标签化' }),
          expect.objectContaining({ id: 'P002' }),
        ]),
      });

    });

    it('完整诊断数据结构和内容正确', async () => {
      let callCount = 0;
      vi.stubGlobal('fetch', vi.fn().mockImplementation(async () => {
        callCount++;
        if (callCount === 1) {
          return createSSEResponse(JSON.stringify(DIAGNOSIS_AGENT_JSON), 100);
        }
        return createSSEResponse(TEACHING_AGENT_FULL_RESPONSE, 100);
      }));

      await invokeHandler({}, {
        message: XIUXIAN_TEXT,
        sessionId: 'wiremock-session-1',
      });

      const updateCall = sendMock.mock.calls.find(
        (c: any[]) => c[0] === IPC_CHANNELS.DIAGNOSIS_UPDATE
      );
      expect(updateCall).toBeDefined();

      const [entry] = (updateCall || []).slice(1);
      expect(entry.syndromes).toHaveLength(3);

      // 验证严重程度排序 L3 > L2 > L1
      expect(entry.syndromes[0].id).toBe('P002');
      expect(entry.syndromes[1].severity).toBe('L2');
      expect(entry.syndromes[2].severity).toBe('L2');

      // 验证证据文本来自修仙传
      const infoDump = entry.syndromes.find((s: any) => s.id === 'P004');
      expect(infoDump.evidence).toContain('筑基中期。普通散修资质。金丹便是终点。');
    });

    it('流式数据通过 chat:stream:data 转发', async () => {
      let callCount = 0;
      vi.stubGlobal('fetch', vi.fn().mockImplementation(async () => {
        callCount++;
        if (callCount === 1) {
          return createSSEResponse(JSON.stringify(DIAGNOSIS_AGENT_JSON), 100);
        }
        return createSSEResponse(TEACHING_AGENT_FULL_RESPONSE, 50);
      }));

      await invokeHandler({}, {
        message: XIUXIAN_TEXT,
        sessionId: 'wiremock-session-1',
      });

      const streamDataCall = sendMock.mock.calls.find(
        (c: any[]) => c[0] === IPC_CHANNELS.CHAT_STREAM_DATA
      );
      expect(streamDataCall).toBeDefined();
      expect(streamDataCall![1]).toMatchObject({
        sessionId: 'wiremock-session-1',
        chunk: expect.any(String),
      });
      expect((streamDataCall![1] as { chunk: string }).chunk.length).toBeGreaterThan(0);

      const streamCalls = sendMock.mock.calls.filter(
        (c: any[]) => c[0] === IPC_CHANNELS.CHAT_STREAM_DATA
      );
      expect(streamCalls.length).toBeGreaterThan(1);
    });

    it('chat:stream:end 在流结束后发送', async () => {
      let callCount = 0;
      vi.stubGlobal('fetch', vi.fn().mockImplementation(async () => {
        callCount++;
        if (callCount === 1) {
          return createSSEResponse(JSON.stringify(DIAGNOSIS_AGENT_JSON), 200);
        }
        return createSSEResponse(TEACHING_AGENT_FULL_RESPONSE, 200);
      }));

      await invokeHandler({}, {
        message: XIUXIAN_TEXT,
        sessionId: 'wiremock-session-1',
      });

      expect(sendMock).toHaveBeenCalledWith(
        IPC_CHANNELS.CHAT_STREAM_END,
        expect.objectContaining({
          sessionId: 'wiremock-session-1',
          fullResponse: expect.any(String),
          messageId: expect.any(String),
        }),
      );
    });
  });

  // ============================================================
  // 场景2：旧路径诊断标记处理
  // ============================================================
  describe('场景2：旧格式诊断标记（---DIAGNOSIS_START---）的兼容处理', () => {
    it('Teaching Agent 回复中的诊断标记被 processDiagnosisFromAI 解析', async () => {
      let callCount = 0;
      vi.stubGlobal('fetch', vi.fn().mockImplementation(async () => {
        callCount++;
        if (callCount === 1) {
          return createSSEResponse(JSON.stringify(DIAGNOSIS_AGENT_JSON), 200);
        }
        return createSSEResponse(TEACHING_AGENT_FULL_RESPONSE, 200);
      }));

      sendMock.mockClear();

      await invokeHandler({}, {
        message: XIUXIAN_TEXT,
        sessionId: 'wiremock-session-1',
      });

      // RP-02 去重：Pipe1 已推送，Pipe2 被跳过，仅推送 1 次
      const updateCalls = sendMock.mock.calls.filter(
        (c: any[]) => c[0] === IPC_CHANNELS.DIAGNOSIS_UPDATE
      );
      expect(updateCalls).toHaveLength(1);

      // 验证这唯一的推送来自 Pipe1，包含正确的诊断数据
      const onlyUpdate = updateCalls[0];
      expect(onlyUpdate[1].syndromes).toBeDefined();
      expect(onlyUpdate[1].syndromes.length).toBeGreaterThan(0);
    });
  });

  // ============================================================
  // 场景3：短文本 — 不触发诊断分析
  // ============================================================
  describe('场景3：短文本不触发诊断分析', () => {
    it('短文本依然调用 DiagnosisAgent 做内容分类，但 AI 返回 non-narrative，不生成诊断', async () => {
      const NON_NARRATIVE_RESPONSE = JSON.stringify({
        contentType: 'non-narrative',
        rootCause: '',
        intentPhase: 0,
        syndromeRef: [],
        techniquePool: [],
        keyPassages: [],
        confidence: 0,
      });

      let callCount = 0;
      const fetchMock = vi.fn().mockImplementation(async () => {
        callCount++;
        if (callCount === 1) {
          // 第一次调用：DiagnosisAgent → non-narrative
          return createSSEResponse(NON_NARRATIVE_RESPONSE, 100);
        }
        // 第二次调用：TeachingAgent
        return createSSEResponse('你好！有什么我可以帮你的吗？', 200);
      });
      vi.stubGlobal('fetch', fetchMock);

      await invokeHandler({}, {
        message: SHORT_MESSAGE,
        sessionId: 'wiremock-session-1',
      });

      const diagUpdates = sendMock.mock.calls.filter(
        (c: any[]) => c[0] === IPC_CHANNELS.DIAGNOSIS_UPDATE
      );
      expect(diagUpdates).toHaveLength(0);
      expect(fetchMock).toHaveBeenCalledTimes(2);
    });
  });

  // ============================================================
  // 场景4：API 错误处理
  // ============================================================
  describe('场景4：错误处理', () => {
    it('API 失败时返回错误且不崩溃', async () => {
      vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new Error('Network error')));

      const result = await invokeHandler({}, {
        message: XIUXIAN_TEXT, sessionId: 'wiremock-session-1',
      });

      expect(result.success).toBe(false);
      expect(result.error).toBeDefined();
    });

    it('非 200 响应时返回错误', async () => {
      vi.stubGlobal('fetch', vi.fn().mockResolvedValue(
        new Response('Unauthorized', { status: 401 })
      ));

      const result = await invokeHandler({}, {
        message: XIUXIAN_TEXT, sessionId: 'wiremock-session-1',
      });

      expect(result.success).toBe(false);
      expect(result.error).toContain('401');
    });
  });

  // ============================================================
  // 场景5：修改原文 + 评估
  // ============================================================
  describe('场景5：修改原文 → 评估流程', () => {
    it('原文修改通过 wire mock 调用评估 API', async () => {
      vi.stubGlobal('fetch', vi.fn().mockImplementation(async (_url: string, options: any) => {
        const body = JSON.parse(options.body);
        if (body.stream === false || body.stream === undefined) {
          return createJSONResponse(REWRITE_EVAL_JSON);
        }
        return createSSEResponse(JSON.stringify(DIAGNOSIS_AGENT_JSON), 200);
      }));

      const { ipcMain } = await import('electron');
      const handleCalls = (ipcMain.handle as any).mock.calls;
      const submitHandler = handleCalls.find(
        (c: any[]) => c[0] === IPC_CHANNELS.DIAGNOSIS_SUBMIT_REWRITE
      );

      const result = await submitHandler[1]({}, {
        sessionId: 'wiremock-session-1', messageId: 'msg-1', syndromeId: 'P004',
        originalText: '筑基中期。普通散修资质。金丹便是终点。',
        rewrittenText: '孙项明摸了摸袖口仅剩的两张匿气符，符纸边缘已经磨得起毛。筑基中期的修为在这秘境里不上不下——金丹是奢望，眼下只想活着带一株地火苔回去换几块灵晶。',
        syndromeName: '信息硬塞',
      });

      expect(result.success).toBe(true);
      expect(result.data.evaluation).toBeDefined();
      expect(result.data.evaluation!.improvement).toBe('明显改善');
    });
  });

  // ============================================================
  // 场景6：训练计划关联
  // ============================================================
  describe('场景6：训练计划关联', () => {
    it('诊断症候映射到正确技法', async () => {
      const p004 = DIAGNOSIS_AGENT_JSON.techniquePool.find(t => t.name.includes('设定'));
      expect(p004).toBeDefined();
      expect(p004!.difficulty).toBe('中级');

      const p003 = DIAGNOSIS_AGENT_JSON.techniquePool.find(t => t.name.includes('情绪'));
      expect(p003).toBeDefined();
      expect(p003!.difficulty).toBe('初级');
    });
  });

  // ============================================================
  // 场景7：多轮对话
  // ============================================================
  describe('场景7：多轮对话（协作式）', () => {
    it('用户在诊断后提交改写练习，系统继续教学', async () => {
      // 改写练习是非叙事内容，DiagnosisAgent 返回 non-narrative
      const NON_NARRATIVE_RESPONSE = JSON.stringify({
        contentType: 'non-narrative',
        rootCause: '',
        intentPhase: 0,
        syndromeRef: [],
        techniquePool: [],
        keyPassages: [],
        confidence: 0,
      });

      let callCount = 0;
      vi.stubGlobal('fetch', vi.fn().mockImplementation(async () => {
        callCount++;
        if (callCount === 1) {
          // 第一次调用：DiagnosisAgent → non-narrative
          return createSSEResponse(NON_NARRATIVE_RESPONSE, 100);
        }
        // 第二次调用：TeachingAgent
        return createSSEResponse(TEACHING_AGENT_FULL_RESPONSE, 100);
      }));

      const result = await invokeHandler({}, {
        message: COLLABORATION_TEXT,
        sessionId: 'wiremock-session-1',
        history: [{ role: 'assistant', content: '你这段文字设定以旁白形式告知了读者...' }],
      });

      expect(result.success).toBe(true);

      // 保存了助手回复
      expect(mockSessionService.saveMessage).toHaveBeenCalledWith(
        'wiremock-session-1', 'assistant', expect.any(String)
      );
    });
  });
});
