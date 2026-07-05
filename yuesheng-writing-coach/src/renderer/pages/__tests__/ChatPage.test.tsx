/**
 * ChatPage 交互测试
 *
 * 验证:
 * - 无消息时渲染欢迎引导区和返回按钮
 * - 发送消息动作
 * - 空输入保护
 * - ActionSheet 开关与动作
 * - MoreMenu 跳转
 * - 返回按钮
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import '@testing-library/jest-dom/vitest';
import { ChatPage } from '../ChatPage';

// ---------------------------------------------------------------------------
// mocks
// ---------------------------------------------------------------------------

const mockPush = vi.fn();
const mockPop = vi.fn();

vi.mock('../../stores/page-stack.store', () => ({
  usePageStackStore: (selector: (s: unknown) => unknown) =>
    selector({ push: mockPush, pop: mockPop }),
}));

const mockSessionStore = {
  currentSessionId: 'session-1',
  sessions: [] as Array<{ id: string; title: string }>,
  loadMessages: vi.fn(),
  switchSession: vi.fn(),
};

vi.mock('../../stores/session.store', () => ({
  useSessionStore: (selector: (s: unknown) => unknown) =>
    selector(mockSessionStore),
}));

const mockSend = vi.fn();
const mockSubscribe = vi.fn(() => () => {});
const mockFinishStream = vi.fn();

vi.mock('../../hooks/useOrchestrator', () => ({
  useOrchestrator: () => ({
    send: mockSend,
    subscribe: mockSubscribe,
    finishStream: mockFinishStream,
    streaming: false,
  }),
  isTokenEvent: (e: { type: string }) => e.type === 'token',
  isErrorEvent: (e: { type: string }) => e.type === 'error',
  isDoneEvent: (e: { type: string }) => e.type === 'done',
}));

// ---------------------------------------------------------------------------
// tests
// ---------------------------------------------------------------------------

describe('<ChatPage />', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockSessionStore.currentSessionId = 'session-1';
    mockSessionStore.sessions = [];
    mockSessionStore.loadMessages.mockResolvedValue([]);
    mockSessionStore.switchSession.mockReset();
  });

  // ---- 1. 渲染 ----
  it('无消息时显示欢迎引导区和返回按钮', async () => {
    render(<ChatPage />);

    // 返回按钮始终存在
    expect(screen.getByLabelText('返回')).toBeInTheDocument();

    // 等待 loadMessages 完成后显示欢迎引导区
    await waitFor(() => {
      expect(screen.getByText('嘿,今天想从哪里开始?')).toBeInTheDocument();
    });
    expect(screen.getByText('分析一下作品')).toBeInTheDocument();
    expect(screen.getByText('学点描写技法')).toBeInTheDocument();
    expect(screen.getByText('出个题目练练')).toBeInTheDocument();
  });

  // ---- 2. 发送消息 ----
  it('输入文本后点击发送按钮调用 orchestrator.send', async () => {
    const user = userEvent.setup();
    render(<ChatPage />);

    // 等待欢迎引导区加载完毕
    await waitFor(() => {
      expect(screen.getByText('分析一下作品')).toBeInTheDocument();
    });

    const input = screen.getByPlaceholderText('输入你的问题和作品…');
    await user.type(input, '如何提升文笔');

    await user.click(screen.getByLabelText('发送'));

    await waitFor(() => {
      expect(mockSend).toHaveBeenCalledWith({
        userMessage: '如何提升文笔',
        sessionId: 'session-1',
        phase: 'requirement',
      });
    });
  });

  // ---- 3. 空输入保护 ----
  it('输入为空时发送按钮禁用,点击不触发 send', async () => {
    const user = userEvent.setup();
    render(<ChatPage />);

    await waitFor(() => {
      expect(screen.getByText('分析一下作品')).toBeInTheDocument();
    });

    const sendBtn = screen.getByLabelText('发送');
    // 空输入时按钮应为 disabled
    expect(sendBtn).toBeDisabled();

    await user.click(sendBtn);
    expect(mockSend).not.toHaveBeenCalled();
  });

  // ---- 4. ActionSheet 开关 ----
  it('点击「+」按钮切换 ActionSheet 可见性', async () => {
    const user = userEvent.setup();
    render(<ChatPage />);

    await waitFor(() => {
      expect(screen.getByText('分析一下作品')).toBeInTheDocument();
    });

    // 初始: ActionSheet 隐藏
    expect(screen.queryByRole('dialog', { name: '工具' })).not.toBeInTheDocument();

    // 点击「+」按钮 → 显示
    await user.click(screen.getByLabelText('添加工具'));
    expect(screen.getByRole('dialog', { name: '工具' })).toBeInTheDocument();

    // 点击「纯文字」选项(handleClick 会调用 onClose) → 隐藏
    await user.click(screen.getByText('纯文字'));
    expect(screen.queryByRole('dialog', { name: '工具' })).not.toBeInTheDocument();
  });

  // ---- 5. ActionSheet: "设定" → 跳转设置 ----
  it('ActionSheet 中点击「设定」导航到 settings 页面', async () => {
    const user = userEvent.setup();
    render(<ChatPage />);

    await waitFor(() => {
      expect(screen.getByText('分析一下作品')).toBeInTheDocument();
    });

    await user.click(screen.getByLabelText('添加工具'));
    await user.click(screen.getByText('设定'));

    expect(mockPush).toHaveBeenCalledWith('settings', { label: '对话配置' });
  });

  // ---- 6. ActionSheet: "图片/文档" → 显示错误 ----
  it('ActionSheet 中点击「图片」显示暂不支持提示', async () => {
    const user = userEvent.setup();
    render(<ChatPage />);

    await waitFor(() => {
      expect(screen.getByText('分析一下作品')).toBeInTheDocument();
    });

    await user.click(screen.getByLabelText('添加工具'));
    await user.click(screen.getByText('图片'));

    expect(screen.getByRole('alert')).toHaveTextContent('暂不支持文件上传');
  });

  it('ActionSheet 中点击「文档」同样显示暂不支持提示', async () => {
    const user = userEvent.setup();
    render(<ChatPage />);

    await waitFor(() => {
      expect(screen.getByText('分析一下作品')).toBeInTheDocument();
    });

    await user.click(screen.getByLabelText('添加工具'));
    await user.click(screen.getByText('文档'));

    expect(screen.getByRole('alert')).toHaveTextContent('暂不支持文件上传');
  });

  // ---- 7. MoreMenu: "对话配置" → 跳转设置 ----
  it('MoreMenu 中点击「对话配置」导航到 settings 页面', async () => {
    const user = userEvent.setup();
    render(<ChatPage />);

    await waitFor(() => {
      expect(screen.getByText('分析一下作品')).toBeInTheDocument();
    });

    // 打开 MoreMenu
    await user.click(screen.getByLabelText('更多操作'));

    // 点击「对话配置」
    const configItem = screen.getByRole('menuitem', { name: '对话配置' });
    await user.click(configItem);

    expect(mockPush).toHaveBeenCalledWith('settings', { label: '对话配置' });
  });

  // ---- 8. 返回按钮 ----
  it('点击返回按钮调用 pop()', async () => {
    const user = userEvent.setup();
    render(<ChatPage />);

    await waitFor(() => {
      expect(screen.getByText('分析一下作品')).toBeInTheDocument();
    });

    await user.click(screen.getByLabelText('返回'));
    expect(mockPop).toHaveBeenCalledOnce();
  });
});
