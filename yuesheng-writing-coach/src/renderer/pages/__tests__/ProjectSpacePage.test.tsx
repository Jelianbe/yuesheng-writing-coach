/**
 * ProjectSpacePage 交互测试
 *
 * 验证:
 * - 渲染: 项目名称、返回按钮、统计卡片、雷达图、最近记录、章节
 * - MoreMenu: 打开菜单,显示选项
 * - 项目设置选项: disabled 状态
 * - 开始新的学习 CTA → 调用 push('chat', ...)
 * - 返回按钮 → 调用 pop()
 * - 加载/错误状态: 页面当前不消费 loading/error 字段,见下方说明
 *
 * 注意: ProjectSpacePage 的 useShallow selector 只选取了 projects/fetchList/
 * fetchById/currentProject,未选取 loading/error。因此 loading/error 状态
 * 在页面上无对应渲染,相关测试暂跳过。
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import '@testing-library/jest-dom/vitest';
import { ProjectSpacePage } from '../ProjectSpacePage';

// ---------------------------------------------------------------------------
// mocks
// ---------------------------------------------------------------------------

const mockPush = vi.fn();
const mockPop = vi.fn();

vi.mock('../../stores/page-stack.store', () => ({
  usePageStackStore: (selector: (s: unknown) => unknown) =>
    selector({ push: mockPush, pop: mockPop }),
}));

const mockProjectState: {
  projects: Array<{ id: string; name: string }>;
  loading: boolean;
  error: string | null;
  fetchList: ReturnType<typeof vi.fn>;
  fetchById: ReturnType<typeof vi.fn>;
} = {
  projects: [],
  loading: false,
  error: null,
  fetchList: vi.fn(),
  fetchById: vi.fn(),
};

vi.mock('../../stores/project.store', () => ({
  useProjectStore: (selector: (s: unknown) => unknown) =>
    selector(mockProjectState),
}));

// ---------------------------------------------------------------------------
// tests
// ---------------------------------------------------------------------------

describe('<ProjectSpacePage />', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    // 重置 mock 状态到默认值
    mockProjectState.projects = [];
    mockProjectState.loading = false;
    mockProjectState.error = null;
  });

  // ---- 1. 渲染 ----

  it('显示项目名称（来自 currentProject）', () => {
    mockProjectState.projects = [{ id: 'p1', name: '我的小说' }];

    render(<ProjectSpacePage params={{ id: 'p1', title: '项目' }} />);

    expect(screen.getByText('我的小说')).toBeInTheDocument();
  });

  it('currentProject 不存在时回退到 params.title', () => {
    // projects 为空,currentProject 是 undefined
    render(<ProjectSpacePage params={{ id: 'p1', title: '测试项目' }} />);

    expect(screen.getByText('测试项目')).toBeInTheDocument();
  });

  it('显示返回按钮', () => {
    render(<ProjectSpacePage params={{ id: 'p1' }} />);

    expect(screen.getByLabelText('返回')).toBeInTheDocument();
  });

  it('渲染统计卡片、雷达图、最近记录和章节等静态内容', () => {
    render(<ProjectSpacePage params={{ id: 'p1' }} />);

    // 统计卡片（"诊断"和"训练"在统计卡片和最近记录各出现一次）
    expect(screen.getAllByText('诊断').length).toBe(2);
    expect(screen.getAllByText('训练').length).toBe(2);
    expect(screen.getByText('学习天')).toBeInTheDocument();

    // 最近记录
    expect(screen.getByText('最近学习')).toBeInTheDocument();
    expect(screen.getByText('人物动机分析')).toBeInTheDocument();

    // 章节
    expect(screen.getByText('作品章节')).toBeInTheDocument();
    expect(screen.getByText('第一章：初遇')).toBeInTheDocument();
    expect(screen.getByText('第二章：暗流')).toBeInTheDocument();
    expect(screen.getByText('第三章：抉择')).toBeInTheDocument();
  });

  // ---- 2. MoreMenu ----

  it('MoreMenu 点击展开显示选项', async () => {
    const user = userEvent.setup();
    render(<ProjectSpacePage params={{ id: 'p1' }} />);

    // 菜单初始关闭
    expect(screen.queryByRole('menu')).not.toBeInTheDocument();

    // 点击 ⋮ 按钮
    await user.click(screen.getByLabelText('更多操作'));

    // 菜单出现
    expect(screen.getByRole('menu')).toBeInTheDocument();
    expect(screen.getByRole('menuitem', { name: '新建对话' })).toBeInTheDocument();
    expect(screen.getByRole('menuitem', { name: '项目设置' })).toBeInTheDocument();
  });

  // ---- 3. 项目设置 disabled ----

  it('「项目设置」菜单项处于禁用状态', async () => {
    const user = userEvent.setup();
    render(<ProjectSpacePage params={{ id: 'p1' }} />);

    await user.click(screen.getByLabelText('更多操作'));

    const settingItem = screen.getByRole('menuitem', { name: '项目设置' });
    // disabled 属性阻止点击
    expect(settingItem).toBeDisabled();
  });

  it('点击禁用的「项目设置」不会关闭菜单或触发操作', async () => {
    const user = userEvent.setup();
    render(<ProjectSpacePage params={{ id: 'p1' }} />);

    await user.click(screen.getByLabelText('更多操作'));
    expect(screen.getByRole('menu')).toBeInTheDocument();

    // 尝试点击禁用项——disabled button 在 userEvent 下不会触发 onClick
    const settingItem = screen.getByRole('menuitem', { name: '项目设置' });
    await user.click(settingItem);

    // 菜单仍保持打开（disabled 阻止了 onClick 内的 setOpen(false)）
    expect(screen.getByRole('menu')).toBeInTheDocument();
  });

  // ---- 4. CTA 按钮 ----

  it('「开始新的学习」CTA → 调用 push("chat", { projectId, title })', async () => {
    const user = userEvent.setup();
    render(<ProjectSpacePage params={{ id: 'p1', title: '我的小说' }} />);

    await user.click(screen.getByText('开始新的学习'));

    expect(mockPush).toHaveBeenCalledWith('chat', { projectId: 'p1', title: '我的小说' });
  });

  it('CTA 传入空字符串 projectId 当 params.id 为空', async () => {
    const user = userEvent.setup();
    render(<ProjectSpacePage params={{ title: '未命名' }} />);

    await user.click(screen.getByText('开始新的学习'));

    expect(mockPush).toHaveBeenCalledWith('chat', { projectId: '', title: '未命名' });
  });

  // ---- 5. 返回按钮 ----

  it('点击返回按钮调用 pop()', async () => {
    const user = userEvent.setup();
    render(<ProjectSpacePage params={{ id: 'p1' }} />);

    await user.click(screen.getByLabelText('返回'));

    expect(mockPop).toHaveBeenCalledOnce();
  });

  // ---- 6. useEffect 数据拉取 ----

  it('挂载时 projects 为空则调用 fetchList', () => {
    render(<ProjectSpacePage params={{ id: 'p1' }} />);

    expect(mockProjectState.fetchList).toHaveBeenCalledOnce();
  });

  it('挂载时有 params.id 且无 currentProject 则调用 fetchById', () => {
    // projects 为空 → currentProject undefined
    render(<ProjectSpacePage params={{ id: 'p1' }} />);

    expect(mockProjectState.fetchById).toHaveBeenCalledWith('p1');
  });

  it('currentProject 已存在时不重复 fetchById', () => {
    mockProjectState.projects = [{ id: 'p1', name: '已有项目' }];

    render(<ProjectSpacePage params={{ id: 'p1' }} />);

    // fetchList 可能仍会被调用(projects 非空时不会),但 fetchById 不应重复调用
    expect(mockProjectState.fetchById).not.toHaveBeenCalled();
  });

  it('projects 非空时不调用 fetchList', () => {
    mockProjectState.projects = [{ id: 'p1', name: '已有项目' }];

    render(<ProjectSpacePage params={{ id: 'p1' }} />);

    expect(mockProjectState.fetchList).not.toHaveBeenCalled();
  });
});
