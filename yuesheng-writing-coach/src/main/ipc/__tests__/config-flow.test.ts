/**
 * Config Handler 集成测试
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

vi.mock('electron', () => ({
  ipcMain: { handle: vi.fn() },
}));

const mockConfig = {
  apiKey: 'test-key',
  baseUrl: 'https://api.test.com',
  model: 'gpt-4',
  attitudeLevel: 'gentle',
  maxTokens: 2048,
};

import { registerConfigHandlers, initConfigHandlers } from '../config.handler';

const mockConfigService = {
  getConfig: vi.fn().mockReturnValue(mockConfig),
  setConfigKey: vi.fn(),
  testConnection: vi.fn().mockResolvedValue({ success: true }),
};

describe('Config Handler', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    initConfigHandlers({ configService: mockConfigService as any });
    registerConfigHandlers();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe('config:get', () => {
    it('返回指定配置键的值', async () => {
      const { ipcMain } = await import('electron');
      const handleCalls = (ipcMain.handle as any).mock.calls;
      const handler = handleCalls.find((c: any[]) => c[0] === 'config:get');

      const result = await handler[1]({}, { key: 'apiKey' });
      expect(result.data).toBe('test-key');
      expect(mockConfigService.getConfig).toHaveBeenCalled();
    });

    it('返回模型配置值', async () => {
      const { ipcMain } = await import('electron');
      const handleCalls = (ipcMain.handle as any).mock.calls;
      const handler = handleCalls.find((c: any[]) => c[0] === 'config:get');

      const result = await handler[1]({}, { key: 'model' });
      expect(result.data).toBe('gpt-4');
    });
  });

  describe('config:set', () => {
    it('设置配置值', async () => {
      const { ipcMain } = await import('electron');
      const handleCalls = (ipcMain.handle as any).mock.calls;
      const handler = handleCalls.find((c: any[]) => c[0] === 'config:set');

      await handler[1]({}, { key: 'apiKey', value: 'new-key' });
      expect(mockConfigService.setConfigKey).toHaveBeenCalledWith('apiKey', 'new-key');
    });
  });

  describe('config:testConnection', () => {
    it('测试 API 连接', async () => {
      const { ipcMain } = await import('electron');
      const handleCalls = (ipcMain.handle as any).mock.calls;
      const handler = handleCalls.find((c: any[]) => c[0] === 'config:testConnection');

      const result = await handler[1]({}, { apiKey: 'test-key', baseUrl: 'https://api.test.com' });
      expect(result.success).toBe(true);
      expect(result.data?.success).toBe(true);
      expect(mockConfigService.testConnection).toHaveBeenCalledWith('test-key', 'https://api.test.com');
    });
  });
});
