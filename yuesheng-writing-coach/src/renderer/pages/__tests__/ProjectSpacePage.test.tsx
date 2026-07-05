/**
 * ProjectSpacePage 交互测试
 *
 * 验证:
 * - 渲染: 项目名称、返回按钮、统计卡片、雷达图、空状态信息
 * - MoreMenu: 打开菜单,显示选项
 * - 项目设置选项: disabled 状态
 * - 开始新的学习 CTA → 调用 push('chat', ...)
 * - 返回按钮 → 调用 pop()
 * - 加载/错误状态: 页面当前不消费 loading/error 字段,见下方说明
 *
 * C-2 (Sprint 33): mock 数据替换为空状态
 * - 统计卡片显示 '0' 而非 '—'
 * - 最近记录/章节显示空状态提示
 * - 雷达图显示"暂无能力数据"
 * - useAbilityStore 已 mock
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

const mockAbilityState: {
  profile: unknown;
  loading: boolean;
  error: string | null;
  fetchProfile: ReturnType<typeof vi.fn>;
} = {
  profile: null,
  loading: false,
  error: null,
  fetchProfile: vi.fn(),
};

vi.mock('../../stores/ability.store', () => ({
  useAbilityStore: (selector: (s: unknown) => unknown) =>
    selector(mockAbilityState),
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
    mockAbilityState.profile = null;
    mockAbilityState.loading = false;
    mockAbilityState.error = null;
  });

  // ---- 1. 渲染 ----

  it('显示项目名称（来自 currentProject）', () => {
    mockProjectState.projects = [{ id: 'p1', name: '我的小说' }];

    render(<ProjectSpacePage params={{ id: 'p1', title: '项目' }} />);

    expect(screen.getByText('我的小说')).toBeInTheDocument();
  });

  it('currentProject 不存在时回退到 params.title', () => {
    render(<ProjectSpacePage params={{ id: 'p1', title: '测试项目' }} />);

    expect(screen.getByText('测试项目')).toBeInTheDocument();
  });

  it('显示返回按钮', () => {
    render(<ProjectSpacePage params={{ id: 'p1' }} />);

    expect(screen.getByLabelText('返回')).toBeInTheDocument();
  });

  it('渲染统计卡片和空状态等静态内容', () => {
    render(<ProjectSpacePage params={{ id: 'p1' }} />);

    // 统计卡片（Sprint 34: 第三列改为"症候"）
    expect(screen.getByText('诊断')).toBeInTheDocument();
    expect(screen.getByText('训练')).toBeInTheDocument();
    expect(screen.getByText('症候')).toBeInTheDocument();
    // 统计卡片显示 0
    const zeros = screen.getAllByText('0');
    expect(zeros.length).toBeGreaterThanOrEqual(3);

    // 空状态
    expect(screen.getByText('最近学习')).toBeInTheDocument();
    expect(screen.getByText('暂无学习记录')).toBeInTheDocument();
    expect(screen.getByText('作品章节')).toBeInTheDocument();
    expect(screen.getByText('暂无章节')).toBeInTheDocument();
  });

  it('未传入 sessionId 时显示"暂无能力数据"', () => {
    render(<ProjectSpacePage params={{ id: 'p1' }} />);

    expect(screen.getByText('暂无能力数据')).toBeInTheDocument();
  });

  // ---- 2. MoreMenu ----

  it('MoreMenu 点击展开显示选项', async () => {
    const user = userEvent.setup();
    render(<ProjectSpacePage params={{ id: 'p1' }} />);

    expect(screen.queryByRole('menu')).not.toBeInTheDocument();

    await user.click(screen.getByLabelText('更多操作'));

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
    expect(settingItem).toBeDisabled();
  });

  it('点击禁用的「项目设置」不会关闭菜单或触发操作', async () => {
    const user = userEvent.setup();
    render(<ProjectSpacePage params={{ id: 'p1' }} />);

    await user.click(screen.getByLabelText('更多操作'));
    expect(screen.getByRole('menu')).toBeInTheDocument();

    const settingItem = screen.getByRole('menuitem', { name: '项目设置' });
    await user.click(settingItem);

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
    render(<ProjectSpacePage params={{ id: 'p1' }} />);

    expect(mockProjectState.fetchById).toHaveBeenCalledWith('p1');
  });

  it('currentProject 已存在时不重复 fetchById', () => {
    mockProjectState.projects = [{ id: 'p1', name: '已有项目' }];

    render(<ProjectSpacePage params={{ id: 'p1' }} />);

    expect(mockProjectState.fetchById).not.toHaveBeenCalled();
  });

  it('projects 非空时不调用 fetchList', () => {
    mockProjectState.projects = [{ id: 'p1', name: '已有项目' }];

    render(<ProjectSpacePage params={{ id: 'p1' }} />);

    expect(mockProjectState.fetchList).not.toHaveBeenCalled();
  });

  // ---- 7. ability store 集成 ----

  it('传入 sessionId 时调用 fetchProfile', () => {
    render(<ProjectSpacePage params={{ id: 'p1', sessionId: 's1' }} />);

    expect(mockAbilityState.fetchProfile).toHaveBeenCalledWith('s1');
  });

  it('ability loading 时显示加载中', () => {
    mockAbilityState.loading = true;

    render(<ProjectSpacePage params={{ id: 'p1', sessionId: 's1' }} />);

    expect(screen.getByText('加载中…')).toBeInTheDocument();
  });

  // ---- Sprint 37: 能力数据集成 ----

  it('能力数据存在时显示雷达图能力值', () => {
    mockAbilityState.profile = {
      abilities: [
        { abilityName: '情节架构', score: 75 },
        { abilityName: '人物塑造', score: 60 },
        { abilityName: '文笔表达', score: 80 },
      ],
      trainingStats: { totalCompleted: 5 },
      diagnosisTrend: { totalDiagnoses: 12 },
    };

    const { container } = render(<ProjectSpacePage params={{ id: 'p1', sessionId: 's1' }} />);

    // 雷达图数据多边形渲染（能力值 > 0 时 polygon 存在）
    const polygons = container.querySelectorAll('svg polygon');
    // grid polygons (5) + data polygon (1) = 6
    expect(polygons.length).toBe(6);

    // 暂无能力数据 不应出现
    expect(screen.queryByText('暂无能力数据')).not.toBeInTheDocument();
  });

  it('能力数据中的统计卡片显示真实数值', () => {
    mockAbilityState.profile = {
      abilities: [],
      trainingStats: { totalCompleted: 5 },
      diagnosisTrend: { totalDiagnoses: 12 },
      syndromeFrequency: { P001: 3, P002: 1 },
    };

    render(<ProjectSpacePage params={{ id: 'p1', sessionId: 's1' }} />);

    // 诊断数显示 12
    expect(screen.getByText('12')).toBeInTheDocument();
    // 训练完成数显示 5
    expect(screen.getByText('5')).toBeInTheDocument();
  });

  it('能力数据无 abilities 时仍显示"暂无能力数据"', () => {
    mockAbilityState.profile = {
      trainingStats: { totalCompleted: 0 },
      diagnosisTrend: { totalDiagnoses: 0 },
    };

    render(<ProjectSpacePage params={{ id: 'p1', sessionId: 's1' }} />);

    // 没有abilities时显示空状态
    expect(screen.getByText('暂无能力数据')).toBeInTheDocument();
  });
});
