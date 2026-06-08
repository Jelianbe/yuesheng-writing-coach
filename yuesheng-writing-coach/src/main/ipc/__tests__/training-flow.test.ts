/**
 * Training IPC Handler 集成测试
 * 覆盖：recommend / assign / complete / skip / history / submit 六个通道
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { IPC_CHANNELS } from '../../../shared/constants';

// ===== Mocks =====

vi.mock('electron', () => ({
  ipcMain: { handle: vi.fn() },
  BrowserWindow: vi.fn().mockImplementation(() => ({
    webContents: { send: vi.fn(), on: vi.fn() },
    on: vi.fn(), loadURL: vi.fn(), close: vi.fn(),
  })),
}));

const mockApiProxyInstance = {
  chatStream: vi.fn(),
  testConnection: vi.fn(),
  updateConfig: vi.fn(),
};

vi.mock('../../api-proxy', () => ({
  ApiProxy: class {
    chatStream = mockApiProxyInstance.chatStream;
    testConnection = vi.fn();
    updateConfig = vi.fn();
  },
}));

const mockGenerateRecommendations = vi.fn();
const mockGetChallengeTemplate = vi.fn();

vi.mock('../../services/training-recommendation.service', () => ({
  generateRecommendations: (...args: unknown[]) => mockGenerateRecommendations(...args),
  getChallengeTemplate: (...args: unknown[]) => mockGetChallengeTemplate(...args),
  getAllChallengeTemplates: vi.fn(),
}));

const mockAssign = vi.fn();
const mockComplete = vi.fn();
const mockSkip = vi.fn();
const mockGetBySession = vi.fn();
const mockGetSyndromeProfile = vi.fn();

vi.mock('../../services/training-record.service', () => ({
  TrainingRecordService: class {
    assign = mockAssign;
    complete = mockComplete;
    skip = mockSkip;
    getBySession = mockGetBySession;
  },
}));

vi.mock('../../services/student-model.service', () => ({
  StudentModelService: class {
    getSyndromeProfile = mockGetSyndromeProfile;
  },
}));

vi.mock('../../services/config.service', () => ({
  ConfigService: class {
    getConfig = vi.fn(() => ({ apiKey: 'test-key', baseUrl: 'https://test.com' }));
    setConfigKey = vi.fn();
    testConnection = vi.fn();
  },
}));

// ===== 导入被测试模块 =====

import { initTrainingHandlers, registerTrainingHandlers } from '../training.handler';

describe('Training Handler 集成测试', () => {
  beforeEach(() => {
    vi.clearAllMocks();

    initTrainingHandlers({
      configService: { getConfig: vi.fn(() => ({ apiKey: 'test-key', baseUrl: 'https://test.com' })) } as any,
      trainingRecordService: {
        assign: mockAssign,
        complete: mockComplete,
        skip: mockSkip,
        getBySession: mockGetBySession,
      } as any,
      studentModelService: {
        getSyndromeProfile: mockGetSyndromeProfile,
      } as any,
    });
    registerTrainingHandlers();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  /** 辅助：获取已注册的 IPC handler */
  async function getHandler(channel: string): Promise<Function> {
    const { ipcMain } = await import('electron');
    const calls = (ipcMain.handle as any).mock.calls;
    const entry = calls.find((c: any[]) => c[0] === channel);
    if (!entry) throw new Error(`Handler not found for channel: ${channel}`);
    return entry[1];
  }

  // ===== recommend =====

  describe('training:recommend', () => {
    it('有活跃症候时生成推荐列表', async () => {
      mockGetSyndromeProfile.mockResolvedValue({
        P004: {
          latestSeverity: 'L2',
          trend: 'stable',
          lastSeenAt: new Date().toISOString(),
        },
        P002: {
          latestSeverity: 'L3',
          trend: 'worsening',
          lastSeenAt: new Date().toISOString(),
        },
      });

      mockGenerateRecommendations.mockReturnValue([
        { challengeId: 'CH-001', challengeName: '信息硬塞', syndromeId: 'P004', severity: 'L2', tier: 'structural', mode: 'generic' },
        { challengeId: 'CH-002', challengeName: '角色工具化', syndromeId: 'P002', severity: 'L3', tier: 'structural', mode: 'generic' },
      ]);

      const handler = await getHandler(IPC_CHANNELS.TRAINING_RECOMMEND);
      const result = await handler({}, { sessionId: 'test-session' });

      expect(result.success).toBe(true);
      expect(result.data.recommendations).toHaveLength(2);
      expect(result.data.recommendations[0].syndromeId).toBe('P004');
      expect(mockGetSyndromeProfile).toHaveBeenCalledWith('test-session');
    });

    it('无活跃症候时返回空列表', async () => {
      mockGetSyndromeProfile.mockResolvedValue({});

      const handler = await getHandler(IPC_CHANNELS.TRAINING_RECOMMEND);
      const result = await handler({}, { sessionId: 'test-session' });

      expect(result.success).toBe(true);
      expect(result.data.recommendations).toEqual([]);
    });

    it('profile 为 null 时返回空列表', async () => {
      mockGetSyndromeProfile.mockResolvedValue(null);

      const handler = await getHandler(IPC_CHANNELS.TRAINING_RECOMMEND);
      const result = await handler({}, { sessionId: 'test-session' });

      expect(result.success).toBe(true);
      expect(result.data.recommendations).toEqual([]);
    });
  });

  // ===== assign =====

  describe('training:assign', () => {
    it('分配挑战成功', async () => {
      mockGetChallengeTemplate.mockReturnValue({
        id: 'CH-001',
        syndromeId: 'P004',
        syndromeName: '信息硬塞',
        challenge: '请改写这段文字',
        mode: 'generic',
        tier: 'structural',
        constraint: '不直接交代信息',
        expectedOutcome: '改善设定释放方式',
      });

      mockAssign.mockReturnValue({ id: 'rec-001', status: 'assigned' });

      const handler = await getHandler(IPC_CHANNELS.TRAINING_ASSIGN);
      const result = await handler({}, { sessionId: 'test-session', challengeId: 'CH-001' });

      expect(result.success).toBe(true);
      expect(result.data.record.id).toBe('rec-001');
      expect(mockAssign).toHaveBeenCalledWith(expect.objectContaining({
        sessionId: 'test-session',
        taskId: 'CH-001',
        syndromeId: 'P004',
      }));
    });

    it('挑战模板不存在时返回错误', async () => {
      mockGetChallengeTemplate.mockReturnValue(null);

      const handler = await getHandler(IPC_CHANNELS.TRAINING_ASSIGN);
      const result = await handler({}, { sessionId: 'test-session', challengeId: 'INVALID' });

      expect(result.success).toBe(false);
      expect(result.error).toContain('not found');
    });
  });

  // ===== complete =====

  describe('training:complete', () => {
    it('完成训练成功', async () => {
      mockComplete.mockReturnValue({ id: 'rec-001', status: 'completed' });

      const handler = await getHandler(IPC_CHANNELS.TRAINING_COMPLETE);
      const result = await handler({}, {
        recordId: 'rec-001',
        userResponse: '改写稿内容',
        aiFeedback: '改得不错',
        effectiveness: 0.85,
      });

      expect(result.success).toBe(true);
      expect(mockComplete).toHaveBeenCalledWith('rec-001', {
        userResponse: '改写稿内容',
        aiFeedback: '改得不错',
        effectiveness: 0.85,
      });
    });

    it('记录不存在时返回错误', async () => {
      mockComplete.mockReturnValue(null);

      const handler = await getHandler(IPC_CHANNELS.TRAINING_COMPLETE);
      const result = await handler({}, { recordId: 'non-existent', userResponse: '' });

      expect(result.success).toBe(false);
      expect(result.error).toContain('not found');
    });
  });

  // ===== skip =====

  describe('training:skip', () => {
    it('跳过训练成功', async () => {
      mockSkip.mockReturnValue({ id: 'rec-001', status: 'skipped' });

      const handler = await getHandler(IPC_CHANNELS.TRAINING_SKIP);
      const result = await handler({}, { recordId: 'rec-001' });

      expect(result.success).toBe(true);
      expect(result.data.record.status).toBe('skipped');
    });

    it('记录不存在时返回错误', async () => {
      mockSkip.mockReturnValue(null);

      const handler = await getHandler(IPC_CHANNELS.TRAINING_SKIP);
      const result = await handler({}, { recordId: 'non-existent' });

      expect(result.success).toBe(false);
      expect(result.error).toContain('not found');
    });
  });

  // ===== history =====

  describe('training:history', () => {
    it('返回历史记录列表', async () => {
      mockGetBySession.mockReturnValue([
        { id: 'r1', taskId: 'CH-001', status: 'completed' },
        { id: 'r2', taskId: 'CH-002', status: 'skipped' },
      ]);

      const handler = await getHandler(IPC_CHANNELS.TRAINING_HISTORY);
      const result = await handler({}, { sessionId: 'test-session' });

      expect(result.success).toBe(true);
      expect(result.data.records).toHaveLength(2);
      expect(result.data.records[0].id).toBe('r1');
    });

    it('无历史记录时返回空数组', async () => {
      mockGetBySession.mockReturnValue([]);

      const handler = await getHandler(IPC_CHANNELS.TRAINING_HISTORY);
      const result = await handler({}, { sessionId: 'empty-session' });

      expect(result.success).toBe(true);
      expect(result.data.records).toEqual([]);
    });
  });

  // ===== submit =====

  describe('training:submit', () => {
    it('提交评估并返回结果', async () => {
      const mockStream = vi.fn().mockImplementation(async function* () {
        yield '{"score": 8, "feedback": "改写很好，完全符合约束。", "improved": true, "nextStep": "继续练习"}';
      });
      mockApiProxyInstance.chatStream.mockReturnValue(mockStream());

      const handler = await getHandler(IPC_CHANNELS.TRAINING_SUBMIT);
      const result = await handler({}, {
        challengeDescription: '请改写这段文字',
        constraint: '不直接交代信息',
        originalQuote: '他资质平平，只是一个普通的散修。',
        userDraft: '他盘坐在硬板床上吐纳了三息便散去。',
      });

      expect(result.success).toBe(true);
      expect(result.data.passed).toBe(true);
      expect(result.data.feedback).toBeTruthy();
    });

    it('评估不通过时返回 passed=false', async () => {
      const mockStream = vi.fn().mockImplementation(async function* () {
        yield '{"score": 3, "feedback": "改写还不够，尝试用动作替代旁白。", "improved": false, "nextStep": "重新练习"}';
      });
      mockApiProxyInstance.chatStream.mockReturnValue(mockStream());

      const handler = await getHandler(IPC_CHANNELS.TRAINING_SUBMIT);
      const result = await handler({}, {
        challengeDescription: '请改写这段文字',
        constraint: '不直接交代信息',
        originalQuote: '他资质平平',
        userDraft: '资质平平的散修',
      });

      expect(result.success).toBe(true);
      expect(result.data.passed).toBe(false);
      expect(result.data.feedback).toContain('改写还不够');
    });

    it('AI 返回非 JSON 时返回错误', async () => {
      const mockStream = vi.fn().mockImplementation(async function* () {
        yield '抱歉，我现在无法评估。请稍后重试。';
      });
      mockApiProxyInstance.chatStream.mockReturnValue(mockStream());

      const handler = await getHandler(IPC_CHANNELS.TRAINING_SUBMIT);
      const result = await handler({}, {
        challengeDescription: 'desc',
        constraint: 'constraint',
        originalQuote: 'text',
        userDraft: 'draft',
      });

      expect(result.success).toBe(false);
      expect(result.error).toBeTruthy();
    });
  });
});
