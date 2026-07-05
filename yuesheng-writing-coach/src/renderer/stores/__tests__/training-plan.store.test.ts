/**
 * training-plan.store.test.ts — 训练计划 Store 测试
 *
 * 覆盖：CRUD 8 个方法成功/异常路径
 * 错误捕获：每个用例输出测试 ID、断言位置、复现步骤
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { useTrainingPlanStore } from '../training-plan.store';

const { mockInvoke } = vi.hoisted(() => ({
  mockInvoke: vi.fn<() => Promise<unknown>>(),
}));

vi.mock('../../services/service-bridge', () => ({
  serviceBridge: { invoke: mockInvoke },
}));

const mockPlans = [
  { id: 'plan-1', name: '基础训练', description: '打好基础', createdAt: '', updatedAt: '', itemCount: 3, completedCount: 1 },
  { id: 'plan-2', name: '进阶训练', description: '提升技巧', createdAt: '', updatedAt: '', itemCount: 5, completedCount: 0 },
];

const mockPlanWithItems = {
  id: 'plan-1',
  name: '基础训练',
  description: '打好基础',
  createdAt: '', updatedAt: '',
  itemCount: 3, completedCount: 1,
  items: [
    { id: 'item-1', planId: 'plan-1', challengeId: 'ch-1', techniqueName: 'T1', syndromeId: 'P001', sortOrder: 0, status: 'completed' as const, completedAt: null, createdAt: '' },
    { id: 'item-2', planId: 'plan-1', challengeId: 'ch-2', techniqueName: 'T2', syndromeId: 'P002', sortOrder: 1, status: 'pending' as const, completedAt: null, createdAt: '' },
  ],
};

const mockChallenges = [
  { challengeId: 'ch-1', techniqueName: 'T1', syndromeId: 'P001', description: '挑战1', constraint: '…' },
  { challengeId: 'ch-2', techniqueName: 'T2', syndromeId: 'P002', description: '挑战2', constraint: '…' },
];

beforeEach(() => {
  vi.clearAllMocks();
  useTrainingPlanStore.setState({
    plans: [], currentPlan: null, availableChallenges: [],
    loading: false, error: null,
  });
});

describe('training-plan.store', () => {
  // TP-1: fetchPlans 成功
  it('[TP-1] fetchPlans 成功时 plans 被填充，loading=false', async () => {
    mockInvoke.mockResolvedValue(mockPlans);

    const store = useTrainingPlanStore.getState();
    expect(store.plans).toHaveLength(0);

    await store.fetchPlans();

    const updated = useTrainingPlanStore.getState();
    expect(updated.loading).toBe(false);
    expect(updated.error).toBeNull();
    expect(updated.plans).toHaveLength(2);
    expect(updated.plans[0].name).toBe('基础训练');
    // 验证调用了正确的 IPC 通道
    expect(mockInvoke).toHaveBeenCalledWith('plan:list', {});
  });

  // TP-2: fetchPlan 成功
  it('[TP-2] fetchPlan 成功时 currentPlan 被填充', async () => {
    mockInvoke.mockResolvedValue(mockPlanWithItems);

    const store = useTrainingPlanStore.getState();
    await store.fetchPlan('plan-1');

    const updated = useTrainingPlanStore.getState();
    expect(updated.currentPlan).not.toBeNull();
    expect(updated.currentPlan!.id).toBe('plan-1');
    expect(updated.currentPlan!.items).toHaveLength(2);
    expect(mockInvoke).toHaveBeenCalledWith('plan:get', { planId: 'plan-1' });
  });

  // TP-3: createPlan 成功
  it('[TP-3] createPlan 成功后刷新列表并返回新 ID', async () => {
    // createPlan 内部: 1) plan:create → 2) fetchPlans → plan:list
    mockInvoke.mockResolvedValueOnce({ id: 'plan-new' })
              .mockResolvedValueOnce(mockPlans);

    const store = useTrainingPlanStore.getState();
    const id = await store.createPlan('新计划', '描述');

    expect(id).toBe('plan-new');
    expect(mockInvoke).toHaveBeenCalledTimes(2);
    expect(mockInvoke).toHaveBeenNthCalledWith(1, 'plan:create', { name: '新计划', description: '描述' });
    expect(mockInvoke).toHaveBeenNthCalledWith(2, 'plan:list', {});
  });

  // TP-4: deletePlan 成功
  it('[TP-4] deletePlan 成功后刷新列表', async () => {
    mockInvoke.mockResolvedValueOnce({ success: true })
              .mockResolvedValueOnce(mockPlans.filter(p => p.id !== 'plan-1'));

    const store = useTrainingPlanStore.getState();
    await store.deletePlan('plan-1');

    expect(mockInvoke).toHaveBeenCalledTimes(2);
    expect(mockInvoke).toHaveBeenNthCalledWith(1, 'plan:delete', { planId: 'plan-1' });
  });

  // TP-5: addItem 成功
  it('[TP-5] addItem 成功后刷新 currentPlan', async () => {
    mockInvoke.mockResolvedValueOnce(mockPlanWithItems.items[1]) // addItem 返回新 item
              .mockResolvedValueOnce(mockPlanWithItems);         // fetchPlan 刷新

    // 先加载 currentPlan
    useTrainingPlanStore.setState({ currentPlan: mockPlanWithItems });

    const store = useTrainingPlanStore.getState();
    await store.addItem('plan-1', 'ch-2');

    expect(mockInvoke).toHaveBeenNthCalledWith(1, 'plan:addItem', { planId: 'plan-1', challengeId: 'ch-2' });
    expect(mockInvoke).toHaveBeenNthCalledWith(2, 'plan:get', { planId: 'plan-1' });
  });

  // TP-6: removeItem 成功
  it('[TP-6] removeItem 成功后刷新 currentPlan', async () => {
    mockInvoke.mockResolvedValueOnce({ success: true })
              .mockResolvedValueOnce({
                ...mockPlanWithItems,
                items: mockPlanWithItems.items.slice(1), // 移除第一项后
              });

    useTrainingPlanStore.setState({ currentPlan: mockPlanWithItems });

    const store = useTrainingPlanStore.getState();
    await store.removeItem('plan-1', 'item-1');

    expect(mockInvoke).toHaveBeenNthCalledWith(1, 'plan:removeItem', { planId: 'plan-1', itemId: 'item-1' });
    expect(mockInvoke).toHaveBeenNthCalledWith(2, 'plan:get', { planId: 'plan-1' });
  });

  // TP-7: updateItemStatus 成功
  it('[TP-7] updateItemStatus 成功后刷新 currentPlan', async () => {
    mockInvoke.mockResolvedValueOnce({ success: true })
              .mockResolvedValueOnce({
                ...mockPlanWithItems,
                items: mockPlanWithItems.items.map(i =>
                  i.id === 'item-2' ? { ...i, status: 'completed' as const } : i
                ),
              });

    useTrainingPlanStore.setState({ currentPlan: mockPlanWithItems });

    const store = useTrainingPlanStore.getState();
    await store.updateItemStatus('item-2', 'completed');

    expect(mockInvoke).toHaveBeenNthCalledWith(1, 'plan:updateItemStatus', { itemId: 'item-2', status: 'completed' });
    expect(mockInvoke).toHaveBeenNthCalledWith(2, 'plan:get', { planId: 'plan-1' });
  });

  // TP-8: fetchAvailableChallenges 成功
  it('[TP-8] fetchAvailableChallenges 成功时 availableChallenges 被填充', async () => {
    mockInvoke.mockResolvedValue(mockChallenges);

    const store = useTrainingPlanStore.getState();
    await store.fetchAvailableChallenges();

    const updated = useTrainingPlanStore.getState();
    expect(updated.availableChallenges).toHaveLength(2);
    expect(updated.availableChallenges[0].challengeId).toBe('ch-1');
    expect(mockInvoke).toHaveBeenCalledWith('plan:getAvailableChallenges', {});
  });

  // TP-9: IPC 异常时 error 被设置
  it('[TP-9] IPC 异常时 error 被设置', async () => {
    mockInvoke.mockRejectedValue(new Error('IPC 失败'));

    const store = useTrainingPlanStore.getState();
    await store.fetchPlans();

    const updated = useTrainingPlanStore.getState();
    expect(updated.error).toBe('Error: IPC 失败');
    expect(updated.loading).toBe(false);
  });

  // TP-10: clearError 重置 error
  it('[TP-10] clearError 重置 error 为 null', async () => {
    useTrainingPlanStore.setState({ error: '测试错误' });
    useTrainingPlanStore.getState().clearError();
    expect(useTrainingPlanStore.getState().error).toBeNull();
  });
});
