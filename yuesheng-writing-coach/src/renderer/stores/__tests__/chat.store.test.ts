// @vitest-environment jsdom
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { useChatStore } from '../chat.store';
import { useConfigStore } from '../config.store';
import { useSessionStore } from '../session.store';
import { IPC_CHANNELS } from '../../shared/constants';

function mockElectronAPI(success = true) {
  window.electronAPI = {
    invoke: vi.fn().mockResolvedValue({ success, messageId: 'mock-msg-id' }) as (...args: unknown[]) => Promise<unknown>,
    on: vi.fn() as (channel: string, callback: (...args: unknown[]) => void) => () => void,
  };
}

function clearMock() {
  delete window.electronAPI;
}

describe('ChatStore', () => {
  beforeEach(() => {
    useChatStore.setState({
      messages: [],
      currentSessionId: 'test-session',
      isLoading: false,
      error: null,
    });
    useSessionStore.setState({
      sessions: [],
      currentSessionId: 'test-session',
    });
    clearMock();
    vi.restoreAllMocks();
  });

  describe('基础状态', () => {
    it('初始状态为空', () => {
      const state = useChatStore.getState();
      expect(state.messages).toEqual([]);
      expect(state.isLoading).toBe(false);
      expect(state.error).toBeNull();
    });
  });

  describe('addMessage', () => {
    it('添加消息到列表', () => {
      useChatStore.getState().addMessage({
        id: 'msg-1',
        role: 'user',
        content: '测试消息',
        timestamp: Date.now(),
      });

      expect(useChatStore.getState().messages).toHaveLength(1);
      expect(useChatStore.getState().messages[0].role).toBe('user');
      expect(useChatStore.getState().messages[0].content).toBe('测试消息');
    });
  });

  describe('appendToLastAssistant', () => {
    it('追加内容到最后一条 assistant 消息', () => {
      useChatStore.setState({
        messages: [
          { id: 'm1', role: 'user', content: 'hi', timestamp: 100 },
          { id: 'm2', role: 'assistant', content: '你', timestamp: 200 },
        ],
      });

      useChatStore.getState().appendToLastAssistant('好');

      const msgs = useChatStore.getState().messages;
      expect(msgs).toHaveLength(2);
      expect(msgs[1].content).toBe('你好');
    });

    it('多条 assistant 消息时追加到最后一条', () => {
      useChatStore.setState({
        messages: [
          { id: 'm1', role: 'user', content: 'a', timestamp: 100 },
          { id: 'm2', role: 'assistant', content: '第', timestamp: 200 },
          { id: 'm3', role: 'user', content: 'b', timestamp: 300 },
          { id: 'm4', role: 'assistant', content: '第', timestamp: 400 },
        ],
      });

      useChatStore.getState().appendToLastAssistant('二');

      const msgs = useChatStore.getState().messages;
      expect(msgs[1].content).toBe('第');
      expect(msgs[3].content).toBe('第二');
    });
  });

  describe('sendMessage', () => {
    it('发送消息创建 user + assistant 两条消息', async () => {
      mockElectronAPI(true);

      await useChatStore.getState().sendMessage('你好');

      const msgs = useChatStore.getState().messages;
      expect(msgs).toHaveLength(2);
      expect(msgs[0].role).toBe('user');
      expect(msgs[0].content).toBe('你好');
      expect(msgs[1].role).toBe('assistant');
      expect(msgs[1].content).toBe('');
    });

    it('发送时设置 isLoading = true', async () => {
      mockElectronAPI(true);
      let loadingStarted = false;

      // 拦截 setState 以在发送过程中检查 loading 状态
      window.electronAPI!.invoke = vi.fn().mockImplementation(async () => {
        loadingStarted = useChatStore.getState().isLoading;
        return { success: true, messageId: 'mock-id' };
      });

      await useChatStore.getState().sendMessage('hi');

      expect(loadingStarted).toBe(true);
    });

    it('发送完成后 isLoading 保持 true（由 stream end 事件处理）', async () => {
      mockElectronAPI(true);

      await useChatStore.getState().sendMessage('hi');

      // isLoading 由 store 设为 true，stream end 事件从 App 层重置
      expect(useChatStore.getState().isLoading).toBe(true);
    });

    it('发送时调用 IPC invoke 传递正确参数', async () => {
      const invoke = vi.fn().mockResolvedValue({ success: true, messageId: 'mock-id' });
      window.electronAPI = { invoke: invoke as (...args: unknown[]) => Promise<unknown>, on: vi.fn() as (...args: unknown[]) => () => void };

      await useChatStore.getState().sendMessage('测试消息');

      expect(invoke).toHaveBeenCalledWith(
        IPC_CHANNELS.CHAT_SEND,
        expect.objectContaining({
          message: '测试消息',
          sessionId: 'test-session',
        }),
      );
    });

    it('发送时传递当前 attitudeLevel', async () => {
      useConfigStore.setState({ attitudeLevel: 'doubao' });
      const invoke = vi.fn().mockResolvedValue({ success: true, messageId: 'mock-id' });
      window.electronAPI = { invoke: invoke as (...args: unknown[]) => Promise<unknown>, on: vi.fn() as (...args: unknown[]) => () => void };

      await useChatStore.getState().sendMessage('切换态度');

      expect(invoke).toHaveBeenCalledWith(
        IPC_CHANNELS.CHAT_SEND,
        expect.objectContaining({ attitudeLevel: 'doubao' }),
      );
    });

    it('attitudeLevel 默认值为 yuesheng', async () => {
      useConfigStore.setState({ attitudeLevel: 'yuesheng' });
      const invoke = vi.fn().mockResolvedValue({ success: true, messageId: 'mock-id' });
      window.electronAPI = { invoke: invoke as (...args: unknown[]) => Promise<unknown>, on: vi.fn() as (...args: unknown[]) => () => void };

      await useChatStore.getState().sendMessage('默认态度');

      expect(invoke).toHaveBeenCalledWith(
        IPC_CHANNELS.CHAT_SEND,
        expect.objectContaining({ attitudeLevel: 'yuesheng' }),
      );
    });

    it('IPC 返回失败时移除空的 assistant 消息但保留 user 消息并设置错误', async () => {
      mockElectronAPI(false);

      await useChatStore.getState().sendMessage('hi');

      const state = useChatStore.getState();
      expect(state.messages).toHaveLength(1);
      expect(state.messages[0].role).toBe('user');
      expect(state.error).toBe('发送失败');
      expect(state.isLoading).toBe(false);
    });

    it('IPC 抛出异常时移除空的 assistant 消息但保留 user 消息并设置错误', async () => {
      window.electronAPI = {
        invoke: vi.fn().mockRejectedValue(new Error('Network error')) as (...args: unknown[]) => Promise<unknown>,
        on: vi.fn() as (...args: unknown[]) => () => void,
      };

      await useChatStore.getState().sendMessage('hi');

      const state = useChatStore.getState();
      expect(state.messages).toHaveLength(1);
      expect(state.messages[0].role).toBe('user');
      expect(state.error).toBe('Network error');
      expect(state.isLoading).toBe(false);
    });

    it('空消息不发送', async () => {
      const invoke = vi.fn();
      window.electronAPI = { invoke: invoke as (...args: unknown[]) => Promise<unknown>, on: vi.fn() as (...args: unknown[]) => () => void };

      await useChatStore.getState().sendMessage('');

      expect(invoke).not.toHaveBeenCalled();
      expect(useChatStore.getState().messages).toHaveLength(0);
    });

    it('空格消息不发送', async () => {
      const invoke = vi.fn();
      window.electronAPI = { invoke: invoke as (...args: unknown[]) => Promise<unknown>, on: vi.fn() as (...args: unknown[]) => () => void };

      await useChatStore.getState().sendMessage('   ');

      expect(invoke).not.toHaveBeenCalled();
    });

    it('loading 状态下不发送新消息', async () => {
      useChatStore.setState({ isLoading: true });
      const invoke = vi.fn();
      window.electronAPI = { invoke: invoke as (...args: unknown[]) => Promise<unknown>, on: vi.fn() as (...args: unknown[]) => () => void };

      await useChatStore.getState().sendMessage('新消息');

      expect(invoke).not.toHaveBeenCalled();
    });

    it('发送时传递历史消息（不包括刚添加的新消息）', async () => {
      useChatStore.setState({
        messages: [
          { id: 'm1', role: 'user', content: '之前的问题', timestamp: 100 },
          { id: 'm2', role: 'assistant', content: '之前的回答', timestamp: 200 },
        ],
      });
      const invoke = vi.fn().mockResolvedValue({ success: true, messageId: 'mock-id' });
      window.electronAPI = { invoke: invoke as (...args: unknown[]) => Promise<unknown>, on: vi.fn() as (...args: unknown[]) => () => void };

      await useChatStore.getState().sendMessage('新问题');

      expect(invoke).toHaveBeenCalledWith(
        IPC_CHANNELS.CHAT_SEND,
        expect.objectContaining({
          message: '新问题',
          sessionId: 'test-session',
          history: [
            { role: 'user', content: '之前的问题' },
            { role: 'assistant', content: '之前的回答' },
          ],
        }),
      );
    });
  });

  describe('getHistory', () => {
    it('只返回 user 和 assistant 消息', () => {
      useChatStore.setState({
        messages: [
          { id: 'm1', role: 'user', content: 'a', timestamp: 100 },
          { id: 'm2', role: 'assistant', content: 'b', timestamp: 200 },
          { id: 'm3', role: 'system', content: '指令', timestamp: 300 },
        ],
      });

      const history = useChatStore.getState().getHistory();

      expect(history).toHaveLength(2);
      expect(history[0]).toEqual({ role: 'user', content: 'a' });
      expect(history[1]).toEqual({ role: 'assistant', content: 'b' });
    });

    it('超过 20 条消息时截断', () => {
      const msgs = Array.from({ length: 25 }, (_, i) => ({
        id: `m${i}`,
        role: (i % 2 === 0 ? 'user' : 'assistant') as 'user' | 'assistant',
        content: `msg-${i}`,
        timestamp: i,
      }));
      useChatStore.setState({ messages: msgs });

      const history = useChatStore.getState().getHistory();

      expect(history).toHaveLength(20);
      expect(history[0].content).toBe('msg-5');
    });
  });

  describe('clearMessages', () => {
    it('清空消息和错误', () => {
      useChatStore.setState({
        messages: [{ id: 'm1', role: 'user', content: 'hi', timestamp: 100 }],
        error: '之前的错误',
      });

      useChatStore.getState().clearMessages();

      expect(useChatStore.getState().messages).toHaveLength(0);
      expect(useChatStore.getState().error).toBeNull();
    });
  });

  describe('setLoading / setError', () => {
    it('设置加载状态', () => {
      useChatStore.getState().setLoading(true);
      expect(useChatStore.getState().isLoading).toBe(true);

      useChatStore.getState().setLoading(false);
      expect(useChatStore.getState().isLoading).toBe(false);
    });

    it('设置错误信息', () => {
      useChatStore.getState().setError('出错了');
      expect(useChatStore.getState().error).toBe('出错了');

      useChatStore.getState().setError(null);
      expect(useChatStore.getState().error).toBeNull();
    });
  });
});
