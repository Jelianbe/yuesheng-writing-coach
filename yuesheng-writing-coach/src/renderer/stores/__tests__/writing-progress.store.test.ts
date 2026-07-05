/**
 * writing-progress.store.test.ts — 写作进度追踪 Store 测试
 *
 * 覆盖：fetchOverview 成功/异常/空数据/loading 状态/连续请求
 * 错误捕获：每个用例输出测试 ID、断言位置、复现步骤
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { useWritingProgressStore } from '../writing-progress.store';

const mockOverview = {
  todayWordCount: 500,
  weeklyWordCount: 3500,
  monthlyWordCount: 12000,
  totalWordCount: 50000,
  writingStreak: 3,
  totalTraining: 20,
  completedTraining: 15,
  averageScore: 7.5,
  totalSessions: 10,
  weeklySessions: 3,
  dailyWordCounts: [
    { date: '2026-07-01', count: 500 },
    { date: '2026-07-02', count: 800 },
  ],
  dailyTrainingCounts: [
    { date: '2026-07-01', total: 2, completed: 1 },
  ],
};

const { mockInvoke } = vi.hoisted(() => ({
  mockInvoke: vi.fn<() => Promise<unknown>>(),
}));

vi.mock('../../services/service-bridge', () => ({
  serviceBridge: { invoke: mockInvoke },
}));

beforeEach(() => {
  vi.clearAllMocks();
  useWritingProgressStore.setState({ overview: null, loading: false, error: null });
});

describe('writing-progress.store', () => {
  // WP-1: fetchOverview 成功
  it('[WP-1] fetchOverview 成功后 overview 被填充，loading=false', async () => {
    mockInvoke.mockResolvedValue(mockOverview);

    const store = useWritingProgressStore.getState();
    expect(store.overview).toBeNull();

    const promise = store.fetchOverview();
    // loading 中
    expect(useWritingProgressStore.getState().loading).toBe(true);

    await promise;

    const updated = useWritingProgressStore.getState();
    expect(updated.loading).toBe(false);
    expect(updated.error).toBeNull();
    expect(updated.overview).toEqual(mockOverview);
    expect(updated.overview!.todayWordCount).toBe(500);
    expect(updated.overview!.writingStreak).toBe(3);
    expect(updated.overview!.dailyWordCounts).toHaveLength(2);
  });

  // WP-2: fetchOverview 异常
  it('[WP-2] fetchOverview 异常时 error 被设置，overview=null', async () => {
    const testError = new Error('IPC 连接失败');
    mockInvoke.mockRejectedValue(testError);

    const store = useWritingProgressStore.getState();
    await store.fetchOverview();

    const updated = useWritingProgressStore.getState();
    expect(updated.overview).toBeNull();
    expect(updated.error).toBe('Error: IPC 连接失败');
    expect(updated.loading).toBe(false);
  });

  // WP-3: fetchOverview 空数据
  it('[WP-3] fetchOverview 返回空数据时 dailyWordCounts 为空数组', async () => {
    const emptyOverview = {
      todayWordCount: 0,
      weeklyWordCount: 0,
      monthlyWordCount: 0,
      totalWordCount: 0,
      writingStreak: 0,
      totalTraining: 0,
      completedTraining: 0,
      averageScore: null,
      totalSessions: 0,
      weeklySessions: 0,
      dailyWordCounts: [],
      dailyTrainingCounts: [],
    };
    mockInvoke.mockResolvedValue(emptyOverview);

    const store = useWritingProgressStore.getState();
    await store.fetchOverview();

    const updated = useWritingProgressStore.getState();
    expect(updated.overview).toEqual(emptyOverview);
    expect(updated.overview!.dailyWordCounts).toHaveLength(0);
    expect(updated.overview!.averageScore).toBeNull();
  });

  // WP-4: loading 状态
  it('[WP-4] 请求期间 loading=true', async () => {
    let resolvePromise!: (v: typeof mockOverview) => void;
    mockInvoke.mockReturnValue(new Promise<typeof mockOverview>(resolve => {
      resolvePromise = resolve;
    }));

    const store = useWritingProgressStore.getState();
    const promise = store.fetchOverview();

    expect(useWritingProgressStore.getState().loading).toBe(true);

    resolvePromise(mockOverview);
    await promise;

    expect(useWritingProgressStore.getState().loading).toBe(false);
  });

  // WP-5: 连续两次 fetch
  it('[WP-5] 连续两次 fetch，第二次发起时 loading 再次为 true', async () => {
    mockInvoke.mockResolvedValue(mockOverview);

    const store = useWritingProgressStore.getState();
    await store.fetchOverview();
    expect(useWritingProgressStore.getState().loading).toBe(false);

    const promise = store.fetchOverview();
    expect(useWritingProgressStore.getState().loading).toBe(true);
    await promise;
    expect(useWritingProgressStore.getState().loading).toBe(false);
  });
});
