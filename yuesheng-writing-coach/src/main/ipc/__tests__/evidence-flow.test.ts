/**
 * Evidence Handler 集成测试
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { IPC_CHANNELS } from '../../../shared/constants';

vi.mock('electron', () => ({
  ipcMain: { handle: vi.fn() },
}));

const mockEvidenceService = {
  getByDisease: vi.fn(),
  getByAbility: vi.fn(),
  getChainForDiagnosis: vi.fn(),
  save: vi.fn(),
};

import { registerEvidenceHandlers, initEvidenceHandlers } from '../evidence.handler';

describe('Evidence Handler', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    initEvidenceHandlers({ evidenceService: mockEvidenceService as any });
    registerEvidenceHandlers();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe('evidence:getByDisease', () => {
    it('按症候查询证据', async () => {
      mockEvidenceService.getByDisease.mockReturnValue([
        { evidenceId: 'evd1', contentJson: '{"text":"证据1"}' },
      ]);

      const { ipcMain } = await import('electron');
      const handleCalls = (ipcMain.handle as any).mock.calls;
      const handler = handleCalls.find((c: any[]) => c[0] === IPC_CHANNELS.EVIDENCE_GET_BY_DISEASE);

      const result = await handler[1]({}, { diseaseId: 'P004', novelId: 'session-1', minLevel: 1 });
      expect(result.success).toBe(true);
      expect(result.data).toHaveLength(1);
      expect(mockEvidenceService.getByDisease).toHaveBeenCalledWith('P004', 'session-1', 1);
    });
  });

  describe('evidence:getByAbility', () => {
    it('按能力查询证据', async () => {
      mockEvidenceService.getByAbility.mockReturnValue([
        { evidenceId: 'evd2', contentJson: '{"text":"证据2"}' },
      ]);

      const { ipcMain } = await import('electron');
      const handleCalls = (ipcMain.handle as any).mock.calls;
      const handler = handleCalls.find((c: any[]) => c[0] === IPC_CHANNELS.EVIDENCE_GET_BY_ABILITY);

      const result = await handler[1]({}, { abilityId: 'A001', authorId: 'author-1' });
      expect(result.success).toBe(true);
      expect(result.data).toHaveLength(1);
    });
  });

  describe('evidence:getChain', () => {
    it('返回诊断证据链', async () => {
      mockEvidenceService.getChainForDiagnosis.mockReturnValue({
        diagnosisId: 'diag-1',
        evidence: [],
      });

      const { ipcMain } = await import('electron');
      const handleCalls = (ipcMain.handle as any).mock.calls;
      const handler = handleCalls.find((c: any[]) => c[0] === IPC_CHANNELS.EVIDENCE_GET_CHAIN);

      const result = await handler[1]({}, { diagnosisId: 'diag-1' });
      expect(result.success).toBe(true);
      expect(result.data.diagnosisId).toBe('diag-1');
    });
  });

  describe('evidence:create', () => {
    it('创建证据成功返回', async () => {
      const { ipcMain } = await import('electron');
      const handleCalls = (ipcMain.handle as any).mock.calls;
      const handler = handleCalls.find((c: any[]) => c[0] === IPC_CHANNELS.EVIDENCE_CREATE);

      const result = await handler[1]({}, {
        evidence: {
          type: 'text',
          level: 1,
          novelId: 'session-1',
          contentJson: { text: '新证据' },
          relatedDisease: 'P004',
          relatedAbility: 'A001',
          extractedBy: 'test',
        },
      });

      expect(result.success).toBe(true);
      expect(result.data.evidenceId).toBeDefined();
      expect(mockEvidenceService.save).toHaveBeenCalled();
    });
  });
});
