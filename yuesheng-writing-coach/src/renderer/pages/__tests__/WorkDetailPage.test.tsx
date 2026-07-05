/**
 * WorkDetailPage.test.tsx — 作品详情页测试（Sprint 39）
 *
 * 覆盖: 空 id / 加载态 / 作品不存在 / 元数据渲染 / 统计卡片 / 章节列表
 *       新增章节 / 删除章节 / 编辑弹窗 / 返回
 *
 * 依据: qa-baseline.md §3.4
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import '@testing-library/jest-dom/vitest';
import { WorkDetailPage } from '../WorkDetailPage';

// ---- hoisted mocks (must be before vi.mock) ----
const {
  mockPush, mockPop, mockUpdate, mockCreateChapter,
  mockDeleteChapter, mockInvoke,
  mockManuscriptState, mockChapterState,
} = vi.hoisted(() => {
  const push = vi.fn();
  const pop = vi.fn();
  const update = vi.fn();
  const createChapter = vi.fn();
  const deleteChapter = vi.fn();
  const fetchByWork = vi.fn();
  const invoke = vi.fn();

  const manuscript = {
    id: 'manu-1',
    title: '测试小说',
    genre: '玄幻',
    description: '一本用于测试的小说作品',
    status: 'active',
    sortOrder: 0,
    createdAt: Date.now() / 1000,
    updatedAt: Date.now() / 1000,
    projectId: undefined,
  };

  return {
    mockPush: push,
    mockPop: pop,
    mockUpdate: update,
    mockCreateChapter: createChapter,
    mockDeleteChapter: deleteChapter,
    fetchByWork,
    mockInvoke: invoke,
    mockManuscriptState: { manuscripts: [manuscript], update },
    mockChapterState: {
      chapters: [] as Array<Record<string, unknown>>,
      fetchByWork,
      createChapter,
      deleteChapter,
    },
  };
});

// ---- mock stores ----
vi.mock('../../stores/page-stack.store', () => ({
  usePageStackStore: (selector: (s: unknown) => unknown) =>
    selector({ push: mockPush, pop: mockPop }),
}));

vi.mock('../../stores/manuscript.store', () => ({
  useManuscriptStore: (selector: (s: unknown) => unknown) =>
    selector(mockManuscriptState),
}));

vi.mock('../../stores/chapter.store', () => ({
  useChapterStore: (selector: (s: unknown) => unknown) =>
    selector(mockChapterState),
}));

vi.mock('../../services/service-bridge', () => ({
  serviceBridge: { invoke: mockInvoke },
}));

// ---- tests ----
beforeEach(() => {
  vi.clearAllMocks();
  mockChapterState.chapters = [];
  mockManuscriptState.manuscripts = [{
    id: 'manu-1', title: '测试小说', genre: '玄幻',
    description: '一本用于测试的小说作品', status: 'active',
    sortOrder: 0, createdAt: Date.now() / 1000, updatedAt: Date.now() / 1000, projectId: undefined,
  }];
  mockInvoke.mockResolvedValue({ chapterCount: 2, totalWordCount: 3500, sessionCount: 5, trainingCount: 8 });
  (globalThis as unknown as Record<string, unknown>).confirm = vi.fn(() => true);
});

describe('<WorkDetailPage />', () => {
  it('[WD-1] 未指定 id 时显示提示', () => {
    render(<WorkDetailPage />);
    expect(screen.getByText('未指定作品')).toBeInTheDocument();
    expect(screen.queryByText('加载中…')).not.toBeInTheDocument();
  });

  it('[WD-2] 作品不存在时显示提示', async () => {
    mockManuscriptState.manuscripts = [];
    render(<WorkDetailPage params={{ id: 'nonexistent' }} />);
    await waitFor(() => {
      expect(screen.getByText('作品不存在')).toBeInTheDocument();
    });
  });

  it('[WD-3] 加载中显示加载提示', () => {
    mockInvoke.mockReturnValue(new Promise(() => {}));
    render(<WorkDetailPage params={{ id: 'manu-1' }} />);
    expect(screen.getByText('加载中…')).toBeInTheDocument();
  });

  it('[WD-4] 渲染作品名称、类型、描述', async () => {
    render(<WorkDetailPage params={{ id: 'manu-1' }} />);
    await waitFor(() => {
      expect(screen.getByText('测试小说')).toBeInTheDocument();
    });
    expect(screen.getByText('玄幻')).toBeInTheDocument();
    expect(screen.getByText('一本用于测试的小说作品')).toBeInTheDocument();
  });

  it('[WD-5] 显示 4 个统计卡片', async () => {
    render(<WorkDetailPage params={{ id: 'manu-1' }} />);
    await waitFor(() => {
      expect(screen.getByText('2')).toBeInTheDocument();
    });
    expect(screen.getByText('3,500')).toBeInTheDocument();
    expect(screen.getByText('5')).toBeInTheDocument();
    expect(screen.getByText('8')).toBeInTheDocument();
  });

  it('[WD-6] 章节列表为空时显示提示', async () => {
    mockChapterState.chapters = [];
    render(<WorkDetailPage params={{ id: 'manu-1' }} />);
    await waitFor(() => {
      expect(screen.getByText('暂无章节，在上方添加')).toBeInTheDocument();
    });
  });

  it('[WD-7] 显示章节名称和字数', async () => {
    mockChapterState.chapters = [
      { id: 'ch-1', manuscriptId: 'manu-1', title: '第一章', content: '', wordCount: 1500, sortOrder: 0, status: 'draft', createdAt: Date.now() / 1000, updatedAt: Date.now() / 1000 },
      { id: 'ch-2', manuscriptId: 'manu-1', title: '第二章', content: '', wordCount: 2000, sortOrder: 1, status: 'draft', createdAt: Date.now() / 1000, updatedAt: Date.now() / 1000 },
    ];
    render(<WorkDetailPage params={{ id: 'manu-1' }} />);
    await waitFor(() => {
      expect(screen.getByText('第一章')).toBeInTheDocument();
      expect(screen.getByText('第二章')).toBeInTheDocument();
    });
    expect(screen.getByText('1,500')).toBeInTheDocument();
    expect(screen.getByText('2,000')).toBeInTheDocument();
  });

  it('[WD-8] 输入名称点击添加后调用 createChapter', async () => {
    const user = userEvent.setup();
    render(<WorkDetailPage params={{ id: 'manu-1' }} />);
    await waitFor(() => {
      expect(screen.getByText('测试小说')).toBeInTheDocument();
    });
    const input = screen.getByPlaceholderText('章节名称…');
    await user.type(input, '第三章');
    await user.click(screen.getByRole('button', { name: /添加章节/i }));
    expect(mockCreateChapter).toHaveBeenCalledWith('manu-1', '第三章');
  });

  it('[WD-8b] 回车触发创建', async () => {
    const user = userEvent.setup();
    render(<WorkDetailPage params={{ id: 'manu-1' }} />);
    await waitFor(() => {
      expect(screen.getByText('测试小说')).toBeInTheDocument();
    });
    const input = screen.getByPlaceholderText('章节名称…');
    await user.type(input, '第四章{Enter}');
    expect(mockCreateChapter).toHaveBeenCalledWith('manu-1', '第四章');
  });

  it('[WD-9] 点击删除后调用 deleteChapter', async () => {
    mockChapterState.chapters = [
      { id: 'ch-1', manuscriptId: 'manu-1', title: '第一章', content: '', wordCount: 1500, sortOrder: 0, status: 'draft', createdAt: Date.now() / 1000, updatedAt: Date.now() / 1000 },
    ];
    const confirmMock = vi.fn(() => true);
    (globalThis as unknown as Record<string, unknown>).confirm = confirmMock;

    const user = userEvent.setup();
    render(<WorkDetailPage params={{ id: 'manu-1' }} />);
    await waitFor(() => {
      expect(screen.getByText('第一章')).toBeInTheDocument();
    });

    // 查找删除按钮 — 章节项中 label 包含"删除"的按钮
    const deleteBtn = screen.getByLabelText(/删除.*章节/i);
    await user.click(deleteBtn);

    expect(confirmMock).toHaveBeenCalled();
    expect(mockDeleteChapter).toHaveBeenCalledWith('ch-1', 'manu-1');
  });

  it('[WD-10] 点击编辑按钮后显示编辑弹窗', async () => {
    const user = userEvent.setup();
    render(<WorkDetailPage params={{ id: 'manu-1' }} />);
    await waitFor(() => {
      expect(screen.getByText('测试小说')).toBeInTheDocument();
    });
    await user.click(screen.getByLabelText('编辑作品'));
    expect(screen.getByDisplayValue('测试小说')).toBeInTheDocument();
    expect(screen.getByDisplayValue('玄幻')).toBeInTheDocument();
    expect(screen.getByDisplayValue('一本用于测试的小说作品')).toBeInTheDocument();
  });

  it('[WD-10b] 编辑弹窗保存后调用 update', async () => {
    const user = userEvent.setup();
    render(<WorkDetailPage params={{ id: 'manu-1' }} />);
    await waitFor(() => {
      expect(screen.getByText('测试小说')).toBeInTheDocument();
    });
    await user.click(screen.getByLabelText('编辑作品'));
    const nameInput = screen.getByDisplayValue('测试小说');
    await user.clear(nameInput);
    await user.type(nameInput, '修改后的小说');
    await user.click(screen.getByRole('button', { name: /保存/i }));
    expect(mockUpdate).toHaveBeenCalledWith('manu-1', { title: '修改后的小说', genre: '玄幻', description: '一本用于测试的小说作品' });
  });

  it('[WD-10c] 点击返回按钮调用 pop()', async () => {
    const user = userEvent.setup();
    render(<WorkDetailPage params={{ id: 'manu-1' }} />);
    await waitFor(() => {
      expect(screen.getByText('测试小说')).toBeInTheDocument();
    });
    await user.click(screen.getByLabelText('返回'));
    expect(mockPop).toHaveBeenCalled();
  });
});
