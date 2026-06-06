/**
 * AbilityProfile Handler 集成测试
 *
 * 测试目标：
 * 1. ability:getProfile 通道的正确性
 * 2. 服务未初始化时的错误处理
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { IPC_CHANNELS } from '../../../shared/constants';

// ===== Mock 依赖 =====
vi.mock('electron', () => ({
  ipcMain: { handle: vi.fn() },
}));

const mockProfileService = {
  computeProfile: vi.fn(),
};

// ===== 导入被测试模块 =====
import { registerAbilityProfileHandlers, setAbilityProfileService, setMainWindow } from '../ability-profile.handler';

describe('AbilityProfile Handler', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    setMainWindow({ webContents: { send: vi.fn() } } as any);
    setAbilityProfileService(mockProfileService as any);
    registerAbilityProfileHandlers();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe('ability:getProfile', () => {
    it('返回能力画像', async () => {
      mockProfileService.computeProfile.mockReturnValue({
        sessionId: 'session-1',
        abilities: [
          { abilityId: 'A001', score: 0.75, trend: 'up' },
          { abilityId: 'A002', score: 0.5, trend: 'stable' },
        ],
      });

      const { ipcMain } = await import('electron');
      const handleCalls = (ipcMain.handle as any).mock.calls;
      const handler = handleCalls.find((c: any[]) => c[0] === IPC_CHANNELS.ABILITY_GET_PROFILE);

      const result = await handler[1]({}, { sessionId: 'session-1' });
      expect(result.data.sessionId).toBe('session-1');
      expect(result.data.abilities).toHaveLength(2);
      expect(mockProfileService.computeProfile).toHaveBeenCalledWith('session-1');
    });

    it('服务未初始化时返回 null', async () => {
      setAbilityProfileService(null as any);
      registerAbilityProfileHandlers();

      const { ipcMain } = await import('electron');
      const handleCalls = (ipcMain.handle as any).mock.calls;
      const handler = handleCalls.find((c: any[]) => c[0] === IPC_CHANNELS.ABILITY_GET_PROFILE);

      const result = await handler[1]({}, { sessionId: 'session-1' });
      expect(result.success).toBe(false);
    });
  });
});
