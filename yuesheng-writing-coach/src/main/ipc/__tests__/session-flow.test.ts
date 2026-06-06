/**
 * Session Handler 集成测试
 *
 * 测试目标：
 * 1. session:list / session:create / session:delete / session:rename 通道的正确性
 * 2. session:getMessages 消息查询
 * 3. 错误处理和边界条件
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { IPC_CHANNELS } from '../../../shared/constants';

// ===== Mock 依赖 =====
vi.mock('electron', () => ({
  ipcMain: { handle: vi.fn() },
}));

const mockSessionService = {
  listSessions: vi.fn(),
  createSession: vi.fn(),
  deleteSession: vi.fn(),
  renameSession: vi.fn(),
  getMessages: vi.fn(),
  getLastMessage: vi.fn(),
};

// ===== 导入被测试模块 =====
import { registerSessionHandlers, setSessionService } from '../session.handler';

describe('Session Handler', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    setSessionService(mockSessionService as any);
    registerSessionHandlers();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe('session:list', () => {
    it('返回会话列表', async () => {
      const now = new Date().toISOString();
      mockSessionService.listSessions.mockReturnValue([
        { id: 's1', title: '会话1', created_at: now, updated_at: now },
        { id: 's2', title: '会话2', created_at: now, updated_at: now },
      ]);
      mockSessionService.getLastMessage.mockReturnValueOnce({ content: '你好' });

      const { ipcMain } = await import('electron');
      const handleCalls = (ipcMain.handle as any).mock.calls;
      const handler = handleCalls.find((c: any[]) => c[0] === IPC_CHANNELS.SESSION_LIST);

      const result = await handler[1]();
      expect(result.data).toHaveLength(2);
      expect(result.data[0].id).toBe('s1');
      expect(result.data[0].lastMessage).toBe('你好');
    });

    it('无消息的会话 lastMessage 为 undefined', async () => {
      mockSessionService.listSessions.mockReturnValue([
        { id: 's1', title: '空会话', created_at: new Date().toISOString(), updated_at: new Date().toISOString() },
      ]);
      mockSessionService.getLastMessage.mockReturnValueOnce(undefined);

      const { ipcMain } = await import('electron');
      const handleCalls = (ipcMain.handle as any).mock.calls;
      const handler = handleCalls.find((c: any[]) => c[0] === IPC_CHANNELS.SESSION_LIST);

      const result = await handler[1]();
      expect(result.data).toHaveLength(1);
      expect(result.data[0].lastMessage).toBeUndefined();
    });
  });

  describe('session:create', () => {
    it('创建新会话并返回', async () => {
      const now = new Date().toISOString();
      mockSessionService.createSession.mockReturnValue({
        id: 'new-s1', title: '新会话', created_at: now, updated_at: now,
      });

      const { ipcMain } = await import('electron');
      const handleCalls = (ipcMain.handle as any).mock.calls;
      const handler = handleCalls.find((c: any[]) => c[0] === IPC_CHANNELS.SESSION_CREATE);

      const result = await handler[1]();
      expect(result.data.id).toBe('new-s1');
      expect(result.data.title).toBe('新会话');
    });
  });

  describe('session:delete', () => {
    it('删除指定会话', async () => {
      const { ipcMain } = await import('electron');
      const handleCalls = (ipcMain.handle as any).mock.calls;
      const handler = handleCalls.find((c: any[]) => c[0] === IPC_CHANNELS.SESSION_DELETE);

      await handler[1]({}, { sessionId: 's1' });
      expect(mockSessionService.deleteSession).toHaveBeenCalledWith('s1');
    });
  });

  describe('session:rename', () => {
    it('重命名会话', async () => {
      const { ipcMain } = await import('electron');
      const handleCalls = (ipcMain.handle as any).mock.calls;
      const handler = handleCalls.find((c: any[]) => c[0] === IPC_CHANNELS.SESSION_RENAME);

      await handler[1]({}, { sessionId: 's1', title: '新标题' });
      expect(mockSessionService.renameSession).toHaveBeenCalledWith('s1', '新标题');
    });
  });

  describe('session:getMessages', () => {
    it('返回会话消息', async () => {
      mockSessionService.getMessages.mockReturnValue([
        { id: 'm1', role: 'user', content: '你好' },
        { id: 'm2', role: 'assistant', content: '你好，我是月笙' },
      ]);

      const { ipcMain } = await import('electron');
      const handleCalls = (ipcMain.handle as any).mock.calls;
      const handler = handleCalls.find((c: any[]) => c[0] === IPC_CHANNELS.SESSION_GET_MESSAGES);

      const result = await handler[1]({}, { sessionId: 's1' });
      expect(result.data).toHaveLength(2);
      expect(result.data[0].content).toBe('你好');
    });
  });
});
