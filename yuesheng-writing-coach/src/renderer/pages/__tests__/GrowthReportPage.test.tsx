/**
 * GrowthReportPage 交互测试
 *
 * 覆盖：加载态、空态、数据渲染、返回导航。
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import '@testing-library/jest-dom/vitest';
import { GrowthReportPage } from '../GrowthReportPage';
import type { GrowthGlobalSyndromeTrend } from '../../../shared/api-contracts/growth.contract';

// --- spies ---
const mockFetchGlobalTrends = vi.fn().mockResolvedValue(undefined);
const mockPop = vi.fn();

/** 可在各测试中修改的可变 store 状态 */
const storeState = vi.hoisted(() => ({
  trends: [] as GrowthGlobalSyndromeTrend[],
  global: null as { averageScore: number; totalInstances: number; topGainers: string[]; topLosers: string[] } | null,
  loading: false,
  error: null as string | null,
}));

vi.mock('../../stores/growth.store', () => ({
  useGrowthStore: (selector: (s: unknown) => unknown) =>
    selector({
      get trends() {
        return storeState.trends;
      },
      get global() {
        return storeState.global;
      },
      get loading() {
        return storeState.loading;
      },
      get error() {
        return storeState.error;
      },
      fetchGlobalTrends: mockFetchGlobalTrends,
    }),
}));

vi.mock('../../stores/page-stack.store', () => ({
  usePageStackStore: (selector: (s: unknown) => unknown) =>
    selector({ pop: mockPop }),
}));

describe('<GrowthReportPage />', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    storeState.trends = [];
    storeState.global = null;
    storeState.loading = false;
    storeState.error = null;
  });

  it('加载态显示加载提示', () => {
    storeState.loading = true;
    render(<GrowthReportPage />);

    expect(screen.getByTestId('growth-loading')).toBeInTheDocument();
    expect(screen.getByText('数据加载中…')).toBeInTheDocument();
  });

  it('空态显示引导文案', () => {
    storeState.loading = false;
    render(<GrowthReportPage />);

    expect(screen.getByTestId('growth-empty')).toBeInTheDocument();
    expect(screen.getByText(/先去对话中发起几次诊断/)).toBeInTheDocument();
  });

  it('数据渲染：显示趋势总览、状态卡片、雷达图、症候列表', () => {
    storeState.trends = [
      {
        syndromeId: 'P001',
        name: '世界观模糊',
        status: 'improving',
        latestSeverity: 'L2',
        occurrenceCount: 3,
        description: '世界观设定不够清晰',
      },
      {
        syndromeId: 'P002',
        name: '角色扁平',
        status: 'mastered',
        latestSeverity: 'L1',
        occurrenceCount: 1,
        description: '角色缺乏深度',
      },
      {
        syndromeId: 'P003',
        name: '语言贫乏',
        status: 'needsAttention',
        latestSeverity: 'L3',
        occurrenceCount: 5,
        description: '词汇量不足',
      },
    ];
    storeState.global = {
      averageScore: 65,
      totalInstances: 9,
      topGainers: ['角色塑造'],
      topLosers: ['语言表达'],
    };

    render(<GrowthReportPage />);

    // 趋势总览
    expect(screen.getByTestId('growth-trend-summary')).toBeInTheDocument();
    expect(screen.getByText('趋势总览')).toBeInTheDocument();
    expect(screen.getByText('优势方向')).toBeInTheDocument();
    expect(screen.getByText('需要关注')).toBeInTheDocument();

    // 状态卡片
    expect(screen.getByTestId('growth-status-cards')).toBeInTheDocument();

    // 雷达图
    expect(screen.getByTestId('growth-radar-section')).toBeInTheDocument();
    expect(screen.getByTestId('growth-radar')).toBeInTheDocument();

    // 症候列表
    expect(screen.getByTestId('growth-syndrome-list')).toBeInTheDocument();
    expect(screen.getByText('世界观模糊')).toBeInTheDocument();
    expect(screen.getByText('角色扁平')).toBeInTheDocument();
    expect(screen.getByText('语言贫乏')).toBeInTheDocument();
  });

  it('返回按钮调用 pop()', async () => {
    const user = userEvent.setup();
    render(<GrowthReportPage />);

    await user.click(screen.getByLabelText('返回'));
    expect(mockPop).toHaveBeenCalledOnce();
  });

  it('挂载时调用 fetchGlobalTrends()', () => {
    render(<GrowthReportPage />);
    expect(mockFetchGlobalTrends).toHaveBeenCalledOnce();
  });

  it('错误状态下显示错误信息', () => {
    storeState.error = '网络异常，请稍后重试';
    render(<GrowthReportPage />);

    expect(screen.getByText('网络异常，请稍后重试')).toBeInTheDocument();
  });
});
