/**
 * typedInvoke 降级单元测试 (Sprint 20 B-2 / D-DEBT-34)
 *
 * 验证:Service 层 IPC 调用失败时,降级为 console.error + 返回 null/fallback,
 * 不再 throw,避免 UI 白屏(R-028 防御性编码 + R-027 门禁)。
 *
 * 覆盖服务:
 *  - student-context.service.ts (3 处)
 *  - diagnosis.service.ts (3 处)
 *  - training.service.ts (8 处)
 *  - teaching-state.service.ts (getPrompt 1 处)
 *  - chat.service.ts (send/stop 2 处)
 */

import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest';

// Mock typedInvoke
const mockTypedInvoke = vi.fn();
vi.mock('../ipc-client', () => ({
  typedInvoke: (...args: unknown[]) => mockTypedInvoke(...args),
  typedOn: vi.fn(() => () => {}),
}));

describe('typedInvoke 降级 — Sprint 20 B-2', () => {
  let origError: typeof console.error;
  let origWarn: typeof console.warn;
  let errorLogs: string[] = [];
  let warnLogs: string[] = [];

  beforeEach(() => {
    mockTypedInvoke.mockReset();
    origError = console.error;
    origWarn = console.warn;
    console.error = (...args: unknown[]) => {
      errorLogs.push(String(args[0]));
    };
    console.warn = (...args: unknown[]) => {
      warnLogs.push(String(args[0]));
    };
    errorLogs = [];
    warnLogs = [];
  });

  afterEach(() => {
    console.error = origError;
    console.warn = origWarn;
  });

  describe('student-context.service', () => {
    it('load() 失败时返回 null(不 throw)', async () => {
      mockTypedInvoke.mockResolvedValue({ success: false, error: 'IPC_FAIL' });
      const { studentContextService } = await import('../student-context.service');
      const result = await studentContextService.load();
      expect(result).toBeNull();
      expect(errorLogs.some(l => l.includes('student-context'))).toBe(true);
    });

    it('save() 失败时返回 false(不 throw)', async () => {
      mockTypedInvoke.mockResolvedValue({ success: false, error: 'IPC_FAIL' });
      const { studentContextService } = await import('../student-context.service');
      const result = await studentContextService.save({ test: 1 });
      expect(result).toBe(false);
    });

    it('toJSON() 失败时返回空串(不 throw)', async () => {
      mockTypedInvoke.mockResolvedValue({ success: false, error: 'IPC_FAIL' });
      const { studentContextService } = await import('../student-context.service');
      const result = await studentContextService.toJSON();
      expect(result).toBe('');
    });
  });

  describe('diagnosis.service', () => {
    it('query() 失败时返回 null(不 throw)', async () => {
      mockTypedInvoke.mockResolvedValue({ success: false, error: 'IPC_FAIL' });
      const { diagnosisService } = await import('../diagnosis.service');
      const result = await diagnosisService.query({ sessionId: 's1' });
      expect(result).toBeNull();
    });

    it('submitRewrite() 失败时返回 undefined(不 throw)', async () => {
      mockTypedInvoke.mockResolvedValue({ success: false, error: 'IPC_FAIL' });
      const { diagnosisService } = await import('../diagnosis.service');
      const result = await diagnosisService.submitRewrite({
        sessionId: 's1', syndromeId: 'P001', originalText: 'y', rewrittenText: 'x',
      });
      expect(result).toBeUndefined();
    });

    it('getComparison() 失败时返回 { hasHistory: false }(不 throw)', async () => {
      mockTypedInvoke.mockResolvedValue({ success: false, error: 'IPC_FAIL' });
      const { diagnosisService } = await import('../diagnosis.service');
      const result = await diagnosisService.getComparison({ sessionId: 's1', syndromeId: 'P001' });
      expect(result).toEqual({ hasHistory: false });
    });
  });

  describe('training.service (高敏感方法)', () => {
    it('submit() 失败时返回 null(不 throw)', async () => {
      mockTypedInvoke.mockResolvedValue({ success: false, error: 'IPC_FAIL' });
      const { trainingService } = await import('../training.service');
      const result = await trainingService.submit({ sessionId: 's1', recordId: 'r1', text: 'x' });
      expect(result).toBeNull();
    });

    it('evaluate() 失败时返回 null(不 throw)', async () => {
      mockTypedInvoke.mockResolvedValue({ success: false, error: 'IPC_FAIL' });
      const { trainingService } = await import('../training.service');
      const result = await trainingService.evaluate({
        sessionId: 's1', recordId: 'r1', syndromeId: 'P001', text: 'x', trainingType: 'T001',
      });
      expect(result).toBeNull();
    });

    it('deriveBehavior() 失败时返回 null(不 throw)', async () => {
      mockTypedInvoke.mockResolvedValue({ success: false, error: 'IPC_FAIL' });
      const { trainingService } = await import('../training.service');
      const result = await trainingService.deriveBehavior({ sessionId: 's1', text: 'scene' });
      expect(result).toBeNull();
    });
  });

  describe('training.service (其他方法降级)', () => {
    it('recommend() 失败时返回 null', async () => {
      mockTypedInvoke.mockResolvedValue({ success: false, error: 'IPC_FAIL' });
      const { trainingService } = await import('../training.service');
      const result = await trainingService.recommend({ sessionId: 's1' });
      expect(result).toBeNull();
    });

    it('history() 失败时返回 null', async () => {
      mockTypedInvoke.mockResolvedValue({ success: false, error: 'IPC_FAIL' });
      const { trainingService } = await import('../training.service');
      const result = await trainingService.history({ sessionId: 's1' });
      expect(result).toBeNull();
    });
  });

  describe('teaching-state.service (getPrompt 降级)', () => {
    it('getPrompt() 失败时返回 null(不 throw)', async () => {
      mockTypedInvoke.mockResolvedValue({ success: false, error: 'IPC_FAIL' });
      const { teachingStateService } = await import('../teaching-state.service');
      const result = await teachingStateService.getPrompt({ sessionId: 's1' });
      expect(result).toBeNull();
      expect(errorLogs.some(l => l.includes('teaching-state'))).toBe(true);
    });
  });

  describe('chat.service', () => {
    it('send() 已被 A-4 取代,失败时降级为 null + warn', async () => {
      mockTypedInvoke.mockResolvedValue({ success: false, error: 'IPC_FAIL' });
      const { chatService } = await import('../chat.service');
      const result = await chatService.send({
        message: 'x', sessionId: 's1', history: [], attitudeLevel: 'doubao', studentContext: '',
      });
      expect(result).toBeNull();
      expect(warnLogs.some(l => l.includes('已废弃'))).toBe(true);
    });

    it('stop(sessionId) 失败时降级为 { stopped: false }', async () => {
      mockTypedInvoke.mockResolvedValue({ success: false, error: 'IPC_FAIL' });
      const { chatService } = await import('../chat.service');
      const result = await chatService.stop('s1');
      expect(result).toEqual({ stopped: false });
    });

    it('stop() sessionId 不再传空字符串(载荷规范修正)', async () => {
      mockTypedInvoke.mockResolvedValue({ success: true, data: { stopped: true } });
      const { chatService } = await import('../chat.service');
      await chatService.stop('sess-42');
      expect(mockTypedInvoke).toHaveBeenCalledWith('chat:stop', { sessionId: 'sess-42' });
    });
  });
});
