/**
 * AbilityProfile Handler 集成测试
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { IPC_CHANNELS } from '../../../shared/constants';

vi.mock('electron', () => ({
  ipcMain: { handle: vi.fn() },
}));

const mockProfileService = {
  computeProfile: vi.fn(),
};

import { registerAbilityProfileHandlers, initAbilityProfileHandlers } from '../ability-profile.handler';

describe('AbilityProfile Handler', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    initAbilityProfileHandlers({ abilityProfileService: mockProfileService as any });
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
  });
});
