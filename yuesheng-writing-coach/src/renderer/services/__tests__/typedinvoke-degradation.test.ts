/**
 * typedInvoke 降级单元测试 (Sprint 20 B-2 / D-DEBT-34)
 *
 * 验证:Service 层 IPC 调用失败时,降级为 console.error + 返回 null/fallback,
 * 不再 throw,避免 UI 白屏(R-028 防御性编码 + R-027 门禁)。
 *
 * 覆盖服务:
 *  - student-context.service.ts (3 处)
 *  - diagnosis.service.ts (3 处)
 *  - training.service.ts (旧方法已移除,更新为现有方法的降级测试)
 *  - teaching-state.service.ts (getPrompt/update/getState/confirmPhase/updateSummary)
 *  - chat.service.ts (send/stop 2 处)
 *
 * Sprint 32: 方法签名已更新,测试同步对齐
 */

import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest';
import type { TeachingState } from '../../../shared/types/types-teaching';

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
    it('get() 失败时返回 null(不 throw)', async () => {
      mockTypedInvoke.mockResolvedValue({ success: false, error: 'IPC_FAIL' });
      const { studentContextService } = await import('../student-context.service');
      const result = await studentContextService.get('user-1');
      expect(result).toBeNull();
      expect(errorLogs.some(l => l.includes('[invoke]'))).toBe(true);
    });

    it('update() 失败时返回 null(不 throw)', async () => {
      mockTypedInvoke.mockResolvedValue({ success: false, error: 'IPC_FAIL' });
      const { studentContextService } = await import('../student-context.service');
      const result = await studentContextService.update('user-1', { test: 1 });
      expect(result).toBeNull();
    });

    it('getNote() 失败时返回 null(不 throw)', async () => {
      mockTypedInvoke.mockResolvedValue({ success: false, error: 'IPC_FAIL' });
      const { studentContextService } = await import('../student-context.service');
      const result = await studentContextService.getNote('user-1');
      expect(result).toBeNull();
    });
  });

  describe('diagnosis.service', () => {
    it('query() 失败时返回 null(不 throw)', async () => {
      mockTypedInvoke.mockResolvedValue({ success: false, error: 'IPC_FAIL' });
      const { diagnosisService } = await import('../diagnosis.service');
      const result = await diagnosisService.query('analyze this text');
      expect(result).toBeNull();
    });

    it('submitRewrite() 失败时返回 null(不 throw)', async () => {
      mockTypedInvoke.mockResolvedValue({ success: false, error: 'IPC_FAIL' });
      const { diagnosisService } = await import('../diagnosis.service');
      const result = await diagnosisService.submitRewrite('s1', 'original', 'rewritten');
      expect(result).toBeNull();
    });

    it('getComparison() 失败时返回 null(不 throw)', async () => {
      mockTypedInvoke.mockResolvedValue({ success: false, error: 'IPC_FAIL' });
      const { diagnosisService } = await import('../diagnosis.service');
      const result = await diagnosisService.getComparison('s1');
      expect(result).toBeNull();
    });
  });

  describe('training.service (现有方法降级)', () => {
    it('createObjective() 失败时返回 null(不 throw)', async () => {
      mockTypedInvoke.mockResolvedValue({ success: false, error: 'IPC_FAIL' });
      const { trainingService } = await import('../training.service');
      const result = await trainingService.createObjective({ sessionId: 's1', title: 'objective' });
      expect(result).toBeNull();
    });

    it('getObjectives() 失败时返回 [](不 throw)', async () => {
      mockTypedInvoke.mockResolvedValue({ success: false, error: 'IPC_FAIL' });
      const { trainingService } = await import('../training.service');
      const result = await trainingService.getObjectives('s1');
      expect(result).toEqual([]);
    });

    it('getHistory() 失败时返回 [](不 throw)', async () => {
      mockTypedInvoke.mockResolvedValue({ success: false, error: 'IPC_FAIL' });
      const { trainingService } = await import('../training.service');
      const result = await trainingService.getHistory('s1');
      expect(result).toEqual([]);
    });

    it('remove() 失败时返回 false(不 throw)', async () => {
      mockTypedInvoke.mockResolvedValue({ success: false, error: 'IPC_FAIL' });
      const { trainingService } = await import('../training.service');
      const result = await trainingService.remove('r1');
      expect(result).toBe(false);
    });
  });

  describe('teaching-state.service (降级)', () => {
    it('getPrompt() 失败时返回 null(不 throw)', async () => {
      mockTypedInvoke.mockResolvedValue({ success: false, error: 'IPC_FAIL' });
      const { teachingStateService } = await import('../teaching-state.service');
      const result = await teachingStateService.getPrompt('s1');
      expect(result).toBeNull();
      expect(errorLogs.some(l => l.includes('[invoke]'))).toBe(true);
    });

    it('getState() 失败时返回 null(不 throw)', async () => {
      mockTypedInvoke.mockResolvedValue({ success: false, error: 'IPC_FAIL' });
      const { teachingStateService } = await import('../teaching-state.service');
      const result = await teachingStateService.getState('s1');
      expect(result).toBeNull();
    });

    it('update() 失败时返回 null(不 throw)', async () => {
      mockTypedInvoke.mockResolvedValue({ success: false, error: 'IPC_FAIL' });
      const { teachingStateService } = await import('../teaching-state.service');
      const result = await teachingStateService.update('s1', { currentPhase: 'P1_WORLD' } as Partial<TeachingState>);
      expect(result).toBeNull();
    });

    it('confirmPhase() 失败时返回 null(不 throw)', async () => {
      mockTypedInvoke.mockResolvedValue({ success: false, error: 'IPC_FAIL' });
      const { teachingStateService } = await import('../teaching-state.service');
      const result = await teachingStateService.confirmPhase('s1', 'P1_WORLD');
      expect(result).toBeNull();
    });

    it('updateSummary() 失败时返回 null(不 throw)', async () => {
      mockTypedInvoke.mockResolvedValue({ success: false, error: 'IPC_FAIL' });
      const { teachingStateService } = await import('../teaching-state.service');
      const result = await teachingStateService.updateSummary('s1', 'summary');
      expect(result).toBeNull();
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

  describe('session.service — B-3 降级补齐', () => {
    it('list() 失败时返回 []', async () => {
      mockTypedInvoke.mockResolvedValue({ success: false, error: 'IPC_FAIL' });
      const { sessionService } = await import('../session.service');
      const result = await sessionService.list();
      expect(result).toEqual([]);
    });

    it('create() 失败时返回 null', async () => {
      mockTypedInvoke.mockResolvedValue({ success: false, error: 'IPC_FAIL' });
      const { sessionService } = await import('../session.service');
      const result = await sessionService.create('title');
      expect(result).toBeNull();
    });

    it('delete() 失败时返回 false', async () => {
      mockTypedInvoke.mockResolvedValue({ success: false, error: 'IPC_FAIL' });
      const { sessionService } = await import('../session.service');
      const result = await sessionService.delete('s1');
      expect(result).toBe(false);
    });

    it('rename() 失败时返回 false', async () => {
      mockTypedInvoke.mockResolvedValue({ success: false, error: 'IPC_FAIL' });
      const { sessionService } = await import('../session.service');
      const result = await sessionService.rename('s1', 'new');
      expect(result).toBe(false);
    });

    it('getMessagesPaged() 失败时返回空页', async () => {
      mockTypedInvoke.mockResolvedValue({ success: false, error: 'IPC_FAIL' });
      const { sessionService } = await import('../session.service');
      const result = await sessionService.getMessagesPaged('s1', 0, 20);
      expect(result).toEqual({ messages: [], hasMore: false });
    });

    it('listWithMeta() 失败时返回 []', async () => {
      mockTypedInvoke.mockResolvedValue({ success: false, error: 'IPC_FAIL' });
      const { sessionService } = await import('../session.service');
      const result = await sessionService.listWithMeta();
      expect(result).toEqual([]);
    });

    it('updateTitle() 失败时返回 false', async () => {
      mockTypedInvoke.mockResolvedValue({ success: false, error: 'IPC_FAIL' });
      const { sessionService } = await import('../session.service');
      const result = await sessionService.updateTitle('s1', 'new');
      expect(result).toBe(false);
    });

    it('searchMessages() 失败时返回 []', async () => {
      mockTypedInvoke.mockResolvedValue({ success: false, error: 'IPC_FAIL' });
      const { sessionService } = await import('../session.service');
      const result = await sessionService.searchMessages('s1', 'q');
      expect(result).toEqual([]);
    });
  });
});
