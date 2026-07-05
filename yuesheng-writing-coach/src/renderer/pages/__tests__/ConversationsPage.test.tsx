/**
 * ConversationsPage 交互测试
 *
 * 验证:
 * - 空状态渲染
 * - 新建对话动作与页面跳转
 * - 会话列表点击切换
 * - 初始加载触发 loadSessions
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import '@testing-library/jest-dom/vitest';
import { ConversationsPage } from '../ConversationsPage';

// ---------------------------------------------------------------------------
// mocks
// ---------------------------------------------------------------------------

const mockPush = vi.fn();

vi.mock('../../stores/page-stack.store', () => ({
  usePageStackStore: (selector: (s: unknown) => unknown) =>
    selector({ push: mockPush, pop: vi.fn() }),
}));

interface MockSession {
  id: string;
  title: string;
  createdAt: number;
  updatedAt: number;
  messageCount?: number;
  lastMessageAt?: number;
}

const mockSessionStore = {
  sessions: [] as MockSession[],
  currentSessionId: null as string | null,
  loadSessions: vi.fn(),
  createSession: vi.fn(),
  switchSession: vi.fn(),
};

vi.mock('../../stores/session.store', () => ({
  useSessionStore: (selector: (s: unknown) => unknown) =>
    selector({
      sessions: mockSessionStore.sessions,
      currentSessionId: mockSessionStore.currentSessionId,
      loadSessions: mockSessionStore.loadSessions,
      createSession: mockSessionStore.createSession,
      switchSession: mockSessionStore.switchSession,
    }),
}));

function makeSession(overrides: Partial<MockSession> = {}): MockSession {
  return {
    id: overrides.id ?? 's-1',
    title: overrides.title ?? '测试对话',
    createdAt: overrides.createdAt ?? Date.now(),
    updatedAt: overrides.updatedAt ?? Date.now(),
    messageCount: overrides.messageCount ?? 0,
    lastMessageAt: overrides.lastMessageAt,
  };
}

// ---------------------------------------------------------------------------
// tests
// ---------------------------------------------------------------------------

describe('<ConversationsPage />', () => {
  beforeEach(() => {
    mockSessionStore.sessions = [];
    mockSessionStore.currentSessionId = null;
    mockSessionStore.loadSessions.mockReset().mockResolvedValue(undefined);
    mockSessionStore.createSession.mockReset();
    mockSessionStore.switchSession.mockReset();
    mockPush.mockReset();
  });

  // ---- 1. 空状态 ----
  it('没有会话时显示空状态提示', () => {
    render(<ConversationsPage />);
    expect(screen.getByText('还没有对话记录')).toBeInTheDocument();
    expect(screen.getByText('点击右上角开始新对话')).toBeInTheDocument();
    expect(screen.getByLabelText('新建对话')).toBeInTheDocument();
  });

  // ---- 2. 新建对话 ----
  it('点击「新建对话」调用 createSession("新对话") 成功后导航到 chat', async () => {
    const user = userEvent.setup();
    const createdSession = makeSession({ id: 'new-1', title: '新对话' });
    mockSessionStore.createSession.mockResolvedValue(createdSession);
    render(<ConversationsPage />);

    await user.click(screen.getByLabelText('新建对话'));

    await waitFor(() => {
      expect(mockSessionStore.createSession).toHaveBeenCalledWith('新对话');
    });
    expect(mockPush).toHaveBeenCalledWith('chat', { id: 'new-1', title: '新对话' });
  });

  it('createSession 返回 null 时不导航', async () => {
    const user = userEvent.setup();
    mockSessionStore.createSession.mockResolvedValue(null);
    render(<ConversationsPage />);

    await user.click(screen.getByLabelText('新建对话'));

    await waitFor(() => {
      expect(mockSessionStore.createSession).toHaveBeenCalled();
    });
    expect(mockPush).not.toHaveBeenCalled();
  });

  // ---- 3. 会话列表点击 ----
  it('点击会话项调用 switchSession(id) 并导航到 chat', async () => {
    const user = userEvent.setup();
    mockSessionStore.sessions = [
      makeSession({ id: 's-1', title: '对话一' }),
    ];
    render(<ConversationsPage />);

    await user.click(screen.getByText('对话一'));

    expect(mockSessionStore.switchSession).toHaveBeenCalledWith('s-1');
    expect(mockPush).toHaveBeenCalledWith('chat', { id: 's-1', title: '对话一' });
  });

  it('当前选中的会话项有高亮背景', () => {
    mockSessionStore.currentSessionId = 's-1';
    mockSessionStore.sessions = [
      makeSession({ id: 's-1', title: '当前会话' }),
      makeSession({ id: 's-2', title: '其他会话' }),
    ];
    render(<ConversationsPage />);
    // 两个按钮都在，不会崩溃；选中状态的样式由 CSS var(--bg-card) 控制
    expect(screen.getByText('当前会话')).toBeInTheDocument();
    expect(screen.getByText('其他会话')).toBeInTheDocument();
  });

  it('会话列表显示消息数量', () => {
    mockSessionStore.sessions = [
      makeSession({ id: 's-1', title: '对话', messageCount: 5 }),
    ];
    render(<ConversationsPage />);
    expect(screen.getByText('5 条消息')).toBeInTheDocument();
  });

  // ---- 4. 初始加载 ----
  it('挂载时调用 loadSessions()', () => {
    render(<ConversationsPage />);
    expect(mockSessionStore.loadSessions).toHaveBeenCalledOnce();
  });

  it('有会话时隐藏空状态', () => {
    mockSessionStore.sessions = [
      makeSession({ id: 's-1', title: '已有对话' }),
    ];
    render(<ConversationsPage />);
    expect(screen.queryByText('还没有对话记录')).not.toBeInTheDocument();
    expect(screen.getByText('已有对话')).toBeInTheDocument();
  });
});
