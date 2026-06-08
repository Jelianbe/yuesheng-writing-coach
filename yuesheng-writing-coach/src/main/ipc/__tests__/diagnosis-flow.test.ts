/**
 * IPC Handler 集成测试 — 诊断 → 修改 → 评估 → 成长 完整流程
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { IPC_CHANNELS } from '../../../shared/constants';

vi.mock('electron', () => ({
  ipcMain: { handle: vi.fn() },
  BrowserWindow: vi.fn().mockImplementation(() => ({
    webContents: { send: vi.fn(), on: vi.fn() },
    on: vi.fn(), loadURL: vi.fn(), close: vi.fn(),
  })),
}));

vi.mock('../../api-proxy', () => ({
  ApiProxy: class {
    evaluateRewrite = vi.fn().mockResolvedValue({
      improvement: '明显改善',
      analysis: '你的修改用动作替代了旁白说明。',
      suggestion: '继续——下一步是加一个环境细节。',
    });
    chatStream = vi.fn();
    testConnection = vi.fn();
    updateConfig = vi.fn();
  },
}));

const mockSessionService = {
  saveMessage: vi.fn().mockReturnValue(true),
  listSessions: vi.fn().mockReturnValue([]),
  getLastMessage: vi.fn(),
  createSession: vi.fn(),
  deleteSession: vi.fn(),
  renameSession: vi.fn(),
  getMessages: vi.fn(),
  getById: vi.fn(),
};

vi.mock('../../services/diagnosis-parser', () => ({
  parseDiagnosisFromAIResponse: vi.fn(() => ({
    cleanResponse: '回复文本',
    diagnosis: {
      sessionId: 'test-session',
      messageId: 'test-msg',
      syndromes: [
        { id: 'P004', name: '信息硬塞', severity: 'L2', evidence: ['他资质平平'], score: 0.75, suggestedActions: [] },
        { id: 'P002', name: '角色工具化', severity: 'L3', evidence: ['散修是最底层'], score: 0.82, suggestedActions: [] },
      ],
      suggestedActions: [],
      confidence: 0.85,
    },
  })),
}));

import { registerDiagnosisHandlers, initDiagnosisHandlers, processDiagnosisFromAI, DiagnosisHandlerDeps } from '../diagnosis.handler';

describe('诊断 Handler 集成测试', () => {
  let mockDiagnosisService: any;
  let mockEvidenceService: any;
  let mockWindow: any;
  let mockMerger: any;
  let mockConfigService: any;
  let mockGrowthTrendService: any;
  let mockTeachingStateGetter: ReturnType<typeof vi.fn>;
  let getTeachingStateBySession: (sessionId: string) => { activeProblems: unknown[] } | null;
  let handlerDeps: DiagnosisHandlerDeps;

  beforeEach(() => {
    vi.clearAllMocks();

    mockDiagnosisService = {
      getRecentBySession: vi.fn(),
      save: vi.fn(),
      saveAnalysis: vi.fn(),
      getBySession: vi.fn(),
    };

    mockEvidenceService = {
      save: vi.fn(),
      linkToDiagnosis: vi.fn(),
      getByDisease: vi.fn(),
      getByAbility: vi.fn(),
      getChainForDiagnosis: vi.fn(),
    };

    mockWindow = { webContents: { send: vi.fn() }, on: vi.fn() };
    mockMerger = { merge: vi.fn() };

    mockConfigService = {
      getConfig: vi.fn(() => ({ apiKey: 'test-key', baseUrl: 'https://test.com' })),
      setConfigKey: vi.fn(),
      testConnection: vi.fn(),
    };

    mockGrowthTrendService = { getGrowthSummary: vi.fn() };
    mockTeachingStateGetter = vi.fn();
    getTeachingStateBySession = ((sessionId: string) => {
      return (mockTeachingStateGetter as any)(sessionId);
    }) as (sessionId: string) => { activeProblems: unknown[] } | null;

    handlerDeps = {
      configService: mockConfigService,
      diagnosisService: mockDiagnosisService,
      evidenceService: mockEvidenceService,
      sessionService: mockSessionService as any,
      growthTrendService: mockGrowthTrendService,
      getTeachingStateBySession,
      diagnosisMerger: mockMerger,
      mainWindow: mockWindow,
    };

    initDiagnosisHandlers(handlerDeps);
    registerDiagnosisHandlers();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe('diagnosis:query', () => {
    it('会话存在时返回活跃问题列表', async () => {
      mockTeachingStateGetter.mockReturnValue({
        activeProblems: [{
          id: 'P004', name: '信息硬塞', severity: 'L2',
          evidence: ['他资质平平'], score: 0.75,
          firstDetected: new Date().toISOString(),
          status: 'active', suggestedActions: [],
        }],
      });

      const { ipcMain } = await import('electron');
      const handleCalls = (ipcMain.handle as any).mock.calls;
      const queryHandler = handleCalls.find((c: any[]) => c[0] === IPC_CHANNELS.DIAGNOSIS_QUERY);

      const result = await queryHandler[1]({}, { sessionId: 'test-session' });
      expect(result.data).toHaveLength(1);
      expect(result.data[0].id).toBe('P004');
    });

    it('会话不存在时返回 null', async () => {
      mockTeachingStateGetter.mockReturnValue(null);

      const { ipcMain } = await import('electron');
      const handleCalls = (ipcMain.handle as any).mock.calls;
      const queryHandler = handleCalls.find((c: any[]) => c[0] === IPC_CHANNELS.DIAGNOSIS_QUERY);

      const result = await queryHandler[1]({}, { sessionId: 'non-existent' });
      expect(result.data).toBeNull();
    });
  });

  describe('diagnosis:getComparison', () => {
    it('有两次诊断时返回对比数据', async () => {
      mockDiagnosisService.getRecentBySession.mockReturnValue([
        { sessionId: 'test-session', syndromes: [{ id: 'P004', name: '信息硬塞', score: 3 }] },
        { sessionId: 'test-session', syndromes: [{ id: 'P004', name: '信息硬塞', score: 1.5 }] },
      ]);

      const { ipcMain } = await import('electron');
      const handleCalls = (ipcMain.handle as any).mock.calls;
      const handler = handleCalls.find((c: any[]) => c[0] === IPC_CHANNELS.DIAGNOSIS_GET_COMPARISON);

      const result = await handler[1]({}, { sessionId: 'test-session' });
      expect(result.data.hasHistory).toBe(true);
      expect(result.data.comparison).toContain('信息硬塞');
    });

    it('仅有一次诊断时返回 hasHistory=false', async () => {
      mockDiagnosisService.getRecentBySession.mockReturnValue([
        { sessionId: 'test-session', syndromes: [{ id: 'P004', name: '信息硬塞' }] },
      ]);

      const { ipcMain } = await import('electron');
      const handleCalls = (ipcMain.handle as any).mock.calls;
      const handler = handleCalls.find((c: any[]) => c[0] === IPC_CHANNELS.DIAGNOSIS_GET_COMPARISON);

      const result = await handler[1]({}, { sessionId: 'test-session' });
      expect(result.data.hasHistory).toBe(false);
    });
  });

  describe('diagnosis:submitRewrite', () => {
    it('成功提交修改并返回评估', async () => {
      const { ipcMain } = await import('electron');
      const handleCalls = (ipcMain.handle as any).mock.calls;
      const handler = handleCalls.find((c: any[]) => c[0] === IPC_CHANNELS.DIAGNOSIS_SUBMIT_REWRITE);

      const result = await handler[1]({}, {
        sessionId: 'test-session', messageId: 'msg-1',
        syndromeId: 'P004',
        originalText: '他资质平平，只是一个普通的散修。',
        rewrittenText: '他盘坐在硬板床上吐纳了三息便散去。',
        syndromeName: '信息硬塞',
      });

      expect(result.success).toBe(true);
      expect(mockSessionService.saveMessage).toHaveBeenCalled();
      expect(result.data.evaluation).toBeDefined();
      expect(result.data.evaluation!.improvement).toBe('明显改善');
    });

    it('缺少 syndromeName 时仍能处理', async () => {
      const { ipcMain } = await import('electron');
      const handleCalls = (ipcMain.handle as any).mock.calls;
      const handler = handleCalls.find((c: any[]) => c[0] === IPC_CHANNELS.DIAGNOSIS_SUBMIT_REWRITE);

      const result = await handler[1]({}, {
        sessionId: 'test-session', messageId: 'msg-1',
        syndromeId: 'P004',
        originalText: '他资质平平',
        rewrittenText: '他摸了摸腰间仅剩的两张匿气符',
      });

      expect(result.success).toBe(true);
      expect(mockSessionService.saveMessage).toHaveBeenCalled();
      expect(result.data.evaluation).toBeDefined();
    });
  });

  describe('processDiagnosisFromAI 流程', () => {
    it('从 AI 回复中解析诊断并推送', async () => {
      processDiagnosisFromAI('模拟 AI 回复', 'test-session', 'test-msg');

      expect(mockDiagnosisService.save).toHaveBeenCalled();
      expect(mockWindow.webContents.send).toHaveBeenCalledWith(
        IPC_CHANNELS.DIAGNOSIS_UPDATE,
        expect.objectContaining({
          sessionId: 'test-session',
          syndromes: expect.arrayContaining([
            expect.objectContaining({ id: 'P004' }),
          ]),
        })
      );
    });

    it('解析无诊断结果时不触发流程', async () => {
      const parser = await import('../../services/diagnosis-parser');
      (parser.parseDiagnosisFromAIResponse as ReturnType<typeof vi.fn>).mockReturnValueOnce({
        cleanResponse: '回复文本',
        diagnosis: null,
      });

      processDiagnosisFromAI('普通回复', 'test-session', 'test-msg');

      expect(mockDiagnosisService.save).not.toHaveBeenCalled();
      expect(mockWindow.webContents.send).not.toHaveBeenCalled();
    });

    it('合并诊断结果到 TeachingState', async () => {
      processDiagnosisFromAI('模拟 AI 回复', 'test-session', 'test-msg');

      expect(mockMerger.merge).toHaveBeenCalled();
      expect(mockMerger.merge).toHaveBeenCalledWith(
        expect.objectContaining({
          sessionId: 'test-session',
          syndromes: expect.arrayContaining([
            expect.objectContaining({ id: 'P004' }),
          ]),
        })
      );
    });
  });
});
