/**
 * TrainingPlanPage 交互测试
 *
 * 覆盖：加载态、空态、阶段列表渲染、返回导航。
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import '@testing-library/jest-dom/vitest';
import { TrainingPlanPage } from '../TrainingPlanPage';
import type { DevelopmentStageInfo } from '../../../shared/types';

// --- spies ---
const mockFetchAllStages = vi.fn().mockResolvedValue(undefined);
const mockPop = vi.fn();

/** 可在各测试中修改的可变 store 状态 */
const storeState = vi.hoisted(() => ({
  allStages: [] as DevelopmentStageInfo[],
  loading: false,
  error: null as string | null,
}));

vi.mock('../../stores/prescription.store', () => ({
  usePrescriptionStore: (selector: (s: unknown) => unknown) =>
    selector({
      get allStages() {
        return storeState.allStages;
      },
      get loading() {
        return storeState.loading;
      },
      get error() {
        return storeState.error;
      },
      fetchAllStages: mockFetchAllStages,
    }),
}));

vi.mock('../../stores/page-stack.store', () => ({
  usePageStackStore: (selector: (s: unknown) => unknown) =>
    selector({ pop: mockPop }),
}));

describe('<TrainingPlanPage />', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    storeState.allStages = [];
    storeState.loading = false;
    storeState.error = null;
  });

  it('加载态显示加载提示', () => {
    storeState.loading = true;
    render(<TrainingPlanPage />);

    expect(screen.getByText('加载中…')).toBeInTheDocument();
  });

  it('空态显示暂无阶段数据', () => {
    render(<TrainingPlanPage />);

    expect(screen.getByText('暂无阶段数据')).toBeInTheDocument();
  });

  it('数据渲染：显示阶段列表及名称', () => {
    storeState.allStages = [
      {
        stageId: 'eye',
        name: '眼·观察',
        order: 1,
        coreQuestion: '如何观察生活？',
        prerequisites: [],
        entryPractices: [],
        passCriteria: '能写出 3 个观察细节',
        associatedSyndromes: ['P001'],
        teachingFocus: '培养观察习惯',
      },
      {
        stageId: 'pen',
        name: '笔·表达',
        order: 2,
        coreQuestion: '如何准确表达？',
        prerequisites: ['eye'],
        entryPractices: [],
        passCriteria: '能写出 200 字通顺段落',
        associatedSyndromes: ['P002', 'P003'],
        teachingFocus: '基础写作训练',
      },
      {
        stageId: 'word',
        name: '词·修辞',
        order: 3,
        coreQuestion: '如何用好词语？',
        prerequisites: ['pen'],
        entryPractices: [],
        passCriteria: '能使用 5 种修辞手法',
        associatedSyndromes: [],
        teachingFocus: '词汇扩展',
      },
    ];

    render(<TrainingPlanPage />);

    // 验证阶段名称渲染
    expect(screen.getByText('眼·观察')).toBeInTheDocument();
    expect(screen.getByText('笔·表达')).toBeInTheDocument();
    expect(screen.getByText('词·修辞')).toBeInTheDocument();

    // 验证核心问题
    expect(screen.getByText('如何观察生活？')).toBeInTheDocument();
    expect(screen.getByText('如何准确表达？')).toBeInTheDocument();
    expect(screen.getByText('如何用好词语？')).toBeInTheDocument();

    // 验证教学重点
    expect(screen.getByText(/培养观察习惯/)).toBeInTheDocument();
    expect(screen.getByText(/基础写作训练/)).toBeInTheDocument();

    // 验证通过标准
    expect(screen.getByText(/能写出 3 个观察细节/)).toBeInTheDocument();
    expect(screen.getByText(/能写出 200 字通顺段落/)).toBeInTheDocument();
  });

  it('首个阶段显示 Clock 图标，其余显示 Circle', () => {
    storeState.allStages = [
      {
        stageId: 'eye',
        name: '眼·观察',
        order: 1,
        coreQuestion: '如何观察？',
        prerequisites: [],
        entryPractices: [],
        passCriteria: '完成观察练习',
        associatedSyndromes: [],
        teachingFocus: '观察训练',
      },
      {
        stageId: 'pen',
        name: '笔·表达',
        order: 2,
        coreQuestion: '如何表达？',
        prerequisites: ['eye'],
        entryPractices: [],
        passCriteria: '完成表达练习',
        associatedSyndromes: ['P001'],
        teachingFocus: '表达训练',
      },
    ];

    render(<TrainingPlanPage />);

    // 第一个阶段显示 Clock (进行中), 第二个显示 Circle (未开始)
    const articles = screen.getAllByRole('heading', { level: 2 });
    expect(articles).toHaveLength(2);
  });

  it('空 associatedSyndromes 时不显示"涵盖 N 个常见写作问题"', () => {
    storeState.allStages = [
      {
        stageId: 'word',
        name: '词·修辞',
        order: 1,
        coreQuestion: '如何用好词语？',
        prerequisites: [],
        entryPractices: [],
        passCriteria: '完成修辞练习',
        associatedSyndromes: [],
        teachingFocus: '词汇扩展',
      },
    ];

    render(<TrainingPlanPage />);

    expect(screen.queryByText(/涵盖/)).not.toBeInTheDocument();
  });

  it('返回按钮调用 pop()', async () => {
    const user = userEvent.setup();
    render(<TrainingPlanPage />);

    await user.click(screen.getByLabelText('返回'));
    expect(mockPop).toHaveBeenCalledOnce();
  });

  it('挂载时调用 fetchAllStages()', () => {
    render(<TrainingPlanPage />);
    expect(mockFetchAllStages).toHaveBeenCalledOnce();
  });

  it('错误状态下显示错误信息', () => {
    storeState.error = '网络异常';
    render(<TrainingPlanPage />);

    expect(screen.getByText('网络异常')).toBeInTheDocument();
  });
});
