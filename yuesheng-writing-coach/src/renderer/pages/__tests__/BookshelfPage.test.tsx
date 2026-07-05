/**
 * BookshelfPage 交互测试
 *
 * 验证:
 * - 空状态 / 加载 / 错误渲染
 * - 搜索栏开关与过滤
 * - 新建作品动作
 * - 书卡点击跳转
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import '@testing-library/jest-dom/vitest';
import { BookshelfPage } from '../BookshelfPage';

// ---------------------------------------------------------------------------
// mocks
// ---------------------------------------------------------------------------

const mockPush = vi.fn();

vi.mock('../../stores/page-stack.store', () => ({
  usePageStackStore: (selector: (s: unknown) => unknown) =>
    selector({ push: mockPush, pop: vi.fn() }),
}));

const mockManuscriptStore = {
  manuscripts: [] as Array<{
    id: string;
    title: string;
    genre: string;
    description: string;
    status: 'active' | 'archived';
    created_at: number;
    updated_at: number;
    sort_order: number;
  }>,
  loading: false,
  error: null as string | null,
  fetchList: vi.fn(),
  create: vi.fn(),
};

vi.mock('../../stores/manuscript.store', () => ({
  useManuscriptStore: (selector: (s: unknown) => unknown) =>
    selector({
      manuscripts: mockManuscriptStore.manuscripts,
      loading: mockManuscriptStore.loading,
      error: mockManuscriptStore.error,
      fetchList: mockManuscriptStore.fetchList,
      create: mockManuscriptStore.create,
    }),
}));

function makeManuscript(overrides: Partial<{
  id: string;
  title: string;
  genre: string;
}> = {}): {
  id: string;
  title: string;
  genre: string;
  description: string;
  status: 'active' | 'archived';
  created_at: number;
  updated_at: number;
  sort_order: number;
} {
  return {
    id: overrides.id ?? 'm-1',
    title: overrides.title ?? '测试作品',
    genre: overrides.genre ?? '小说',
    description: '',
    status: 'active' as const,
    created_at: Date.now(),
    updated_at: Date.now(),
    sort_order: 0,
  };
}

// ---------------------------------------------------------------------------
// tests
// ---------------------------------------------------------------------------

describe('<BookshelfPage />', () => {
  beforeEach(() => {
    mockManuscriptStore.manuscripts = [];
    mockManuscriptStore.loading = false;
    mockManuscriptStore.error = null;
    mockManuscriptStore.fetchList.mockReset();
    mockManuscriptStore.create.mockReset().mockResolvedValue(makeManuscript());
    mockPush.mockReset();
  });

  // ---- 1. 空状态 ----
  it('空状态时显示提示文案和新建按钮', () => {
    render(<BookshelfPage />);
    expect(screen.getByText('暂无作品,点击右上角 + 创建')).toBeInTheDocument();
    // header 中的➕按钮
    expect(screen.getByLabelText('新建作品')).toBeInTheDocument();
  });

  // ---- 2. 新建作品 ----
  it('点击「新建作品」按钮打开弹窗，填入名称后创建', async () => {
    const user = userEvent.setup();
    render(<BookshelfPage />);

    // 打开弹窗
    await user.click(screen.getByLabelText('新建作品'));
    expect(screen.getByText('新建作品')).toBeInTheDocument();

    // 填入名称
    const nameInput = screen.getByPlaceholderText('作品名称 *');
    await user.type(nameInput, '我的新作');

    // 点击创建
    const createBtn = screen.getByRole('button', { name: /创建/i });
    await user.click(createBtn);

    await waitFor(() => {
      expect(mockManuscriptStore.create).toHaveBeenCalledWith('我的新作', '', undefined);
    });
  });

  // ---- 3. 搜索栏开关 ----
  it('点击搜索按钮切换搜索栏可见性', async () => {
    const user = userEvent.setup();
    render(<BookshelfPage />);

    // 初始隐藏
    expect(screen.queryByPlaceholderText('搜索作品名或类型…')).not.toBeInTheDocument();

    // 点击搜索按钮 → 显示
    await user.click(screen.getByLabelText('搜索'));
    expect(screen.getByPlaceholderText('搜索作品名或类型…')).toBeInTheDocument();

    // 再次点击搜索按钮 → 隐藏
    await user.click(screen.getByLabelText('搜索'));
    expect(screen.queryByPlaceholderText('搜索作品名或类型…')).not.toBeInTheDocument();
  });

  // ---- 4. 搜索过滤 ----
  it('搜索输入框按标题过滤已显示的作品', async () => {
    const user = userEvent.setup();
    mockManuscriptStore.manuscripts = [
      makeManuscript({ id: '1', title: '三体', genre: '科幻' }),
      makeManuscript({ id: '2', title: '活着', genre: '小说' }),
      makeManuscript({ id: '3', title: '三体X', genre: '科幻' }),
    ];
    render(<BookshelfPage />);

    // 先打开搜索
    await user.click(screen.getByLabelText('搜索'));
    const input = screen.getByPlaceholderText('搜索作品名或类型…');

    // 输入"三体" → 只显示匹配的作品
    await user.type(input, '三体');
    expect(screen.getByText('三体')).toBeInTheDocument();
    expect(screen.getByText('三体X')).toBeInTheDocument();
    expect(screen.queryByText('活着')).not.toBeInTheDocument();
  });

  it('搜索无匹配时显示未找到提示', async () => {
    const user = userEvent.setup();
    mockManuscriptStore.manuscripts = [
      makeManuscript({ id: '1', title: '三体' }),
    ];
    render(<BookshelfPage />);

    await user.click(screen.getByLabelText('搜索'));
    await user.type(screen.getByPlaceholderText('搜索作品名或类型…'), '不存在的作品');

    expect(screen.getByText(/未找到匹配/)).toBeInTheDocument();
  });

  it('清除按钮清空搜索并恢复完整列表', async () => {
    const user = userEvent.setup();
    mockManuscriptStore.manuscripts = [
      makeManuscript({ id: '1', title: '三体' }),
      makeManuscript({ id: '2', title: '活着' }),
    ];
    render(<BookshelfPage />);

    await user.click(screen.getByLabelText('搜索'));
    await user.type(screen.getByPlaceholderText('搜索作品名或类型…'), '三体');
    expect(screen.queryByText('活着')).not.toBeInTheDocument();

    // 点击清除按钮
    await user.click(screen.getByLabelText('清除'));
    expect(screen.getByText('活着')).toBeInTheDocument();
    expect(screen.getByText('三体')).toBeInTheDocument();
  });

  // ---- 5. 书卡点击跳转 ----
  it('点击作品卡片调用 push("project-space", { id, title })', async () => {
    const user = userEvent.setup();
    mockManuscriptStore.manuscripts = [
      makeManuscript({ id: 'b-42', title: '我的作品' }),
    ];
    render(<BookshelfPage />);

    await user.click(screen.getByText('我的作品'));

    expect(mockPush).toHaveBeenCalledWith('project-space', { id: 'b-42', title: '我的作品' });
  });

  // ---- 6. 加载 / 错误状态 ----
  it('加载中时显示"加载中…"', () => {
    mockManuscriptStore.loading = true;
    mockManuscriptStore.manuscripts = [];
    render(<BookshelfPage />);
    expect(screen.getByText('加载中…')).toBeInTheDocument();
  });

  it('有错误时显示错误提示', () => {
    mockManuscriptStore.error = '网络错误';
    render(<BookshelfPage />);
    expect(screen.getByText('网络错误')).toBeInTheDocument();
  });
});
