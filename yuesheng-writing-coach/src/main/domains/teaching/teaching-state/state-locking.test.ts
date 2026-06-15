/**
 * 状态锁定机制单元测试
 * 测试覆盖：lockSyndromes / updateSyndromeStatus / unlockResolvedSyndromes / areAllSyndromesResolved
 */

import { describe, it, expect } from 'vitest';
import {
  lockSyndromes,
  updateSyndromeStatus,
  unlockResolvedSyndromes,
  areAllSyndromesResolved,
  autoLockConsistentSyndromes,
} from './teaching-state-machine';
import { TeachingState } from './teaching-state.types';
import type { ActiveProblem } from '../../../../shared/types/index';

function makeBaseState(overrides: Partial<TeachingState> = {}): TeachingState {
  return {
    sessionId: 'test-session',
    currentPhase: 'P2_PRACTICE_LOOP',
    currentSubphase: 'S2_IDENTIFY',
    completedActions: [],
    completedTasks: [],
    activeProblems: [],
    nextSuggestedActions: [],
    currentTaskId: null,
    diagnosisSummary: '',
    lastUserConfirmation: null,
    focusArea: null,
    transitionOffered: false,
    lockedSyndromes: [],
    updatedAt: new Date().toISOString(),
    ...overrides,
  };
}

// ===== lockSyndromes =====

describe('lockSyndromes', () => {
  it('应锁定新发现的症候', () => {
    const state = makeBaseState();
    const result = lockSyndromes(state, ['P001', 'P002']);
    expect(result.lockedSyndromes).toEqual(['P001', 'P002']);
  });

  it('不应重复锁定已有症候', () => {
    const state = makeBaseState({ lockedSyndromes: ['P001'] });
    const result = lockSyndromes(state, ['P001', 'P002']);
    expect(result.lockedSyndromes).toEqual(['P001', 'P002']);
    expect(result.lockedSyndromes.filter((id) => id === 'P001')).toHaveLength(1);
  });

  it('应保留已锁定症候并追加新症候', () => {
    const state = makeBaseState({ lockedSyndromes: ['P001', 'P003'] });
    const result = lockSyndromes(state, ['P002']);
    expect(result.lockedSyndromes).toHaveLength(3);
    expect(result.lockedSyndromes).toContain('P001');
    expect(result.lockedSyndromes).toContain('P002');
    expect(result.lockedSyndromes).toContain('P003');
  });

  it('空列表不应改变锁定状态', () => {
    const state = makeBaseState({ lockedSyndromes: ['P001'] });
    const result = lockSyndromes(state, []);
    expect(result.lockedSyndromes).toEqual(['P001']);
  });

  it('undefined lockedSyndromes 应初始化为空数组', () => {
    const state = makeBaseState({ lockedSyndromes: undefined as unknown as [] });
    const result = lockSyndromes(state, ['P001']);
    expect(result.lockedSyndromes).toEqual(['P001']);
  });
});

// ===== updateSyndromeStatus =====

describe('updateSyndromeStatus', () => {
  it('应新增未存在的症候', () => {
    const state = makeBaseState({ activeProblems: [] });
    const result = updateSyndromeStatus(state, [
      { id: 'P001', name: '世界观膨胀', severity: 'L2', evidence: ['测试证据'], suggestedActions: ['A001'] },
    ]);
    expect(result.activeProblems).toHaveLength(1);
    expect(result.activeProblems[0].id).toBe('P001');
    expect(result.activeProblems[0].status).toBe('active');
    expect(result.activeProblems[0].severity).toBe('L2');
  });

  it('严重度降低应标记为 improving', () => {
    const state = makeBaseState({
      activeProblems: [
        {
          id: 'P001',
          name: '世界观膨胀',
          severity: 'L2',
          evidence: ['旧证据'],
          firstDetected: '2026-01-01T00:00:00.000Z',
          status: 'active',
          detectionCount: 1,
          missedCount: 0,
          suggestedActions: ['A001'],
        },
      ],
    });
    const result = updateSyndromeStatus(state, [
      { id: 'P001', name: '世界观膨胀', severity: 'L1', evidence: ['新证据'], suggestedActions: ['A001'] },
    ]);
    expect(result.activeProblems[0].severity).toBe('L1');
    expect(result.activeProblems[0].status).toBe('improving');
  });

  it('严重度升高应标记为 active（复发）', () => {
    const state = makeBaseState({
      activeProblems: [
        {
          id: 'P001',
          name: '世界观膨胀',
          severity: 'L1',
          evidence: ['旧证据'],
          firstDetected: '2026-01-01T00:00:00.000Z',
          status: 'improving',
          detectionCount: 1,
          missedCount: 0,
          suggestedActions: ['A001'],
        },
      ],
    });
    const result = updateSyndromeStatus(state, [
      { id: 'P001', name: '世界观膨胀', severity: 'L3', evidence: ['新证据'], suggestedActions: ['A001'] },
    ]);
    expect(result.activeProblems[0].severity).toBe('L3');
    expect(result.activeProblems[0].status).toBe('active');
  });

  it('严重度不变应保持原状态', () => {
    const state = makeBaseState({
      activeProblems: [
        {
          id: 'P001',
          name: '世界观膨胀',
          severity: 'L2',
          evidence: ['旧证据'],
          firstDetected: '2026-01-01T00:00:00.000Z',
          status: 'improving',
          detectionCount: 1,
          missedCount: 0,
          suggestedActions: ['A001'],
        },
      ],
    });
    const result = updateSyndromeStatus(state, [
      { id: 'P001', name: '世界观膨胀', severity: 'L2', evidence: ['新证据'], suggestedActions: ['A001'] },
    ]);
    expect(result.activeProblems[0].status).toBe('improving');
  });

  it('应同时处理新增和更新多个症候', () => {
    const state = makeBaseState({
      activeProblems: [
        {
          id: 'P001',
          name: '世界观膨胀',
          severity: 'L2',
          evidence: ['旧证据'],
          firstDetected: '2026-01-01T00:00:00.000Z',
          status: 'active',
          detectionCount: 2,
          missedCount: 0,
          suggestedActions: ['A001'],
        },
      ],
    });
    const result = updateSyndromeStatus(state, [
      { id: 'P001', name: '世界观膨胀', severity: 'L1', evidence: ['改善证据'], suggestedActions: ['A001'] },
      { id: 'P002', name: '角色工具人化', severity: 'L2', evidence: ['新证据'], suggestedActions: ['A004'] },
    ]);
    expect(result.activeProblems).toHaveLength(2);
    expect(result.activeProblems.find((p) => p.id === 'P001')!.status).toBe('improving');
    expect(result.activeProblems.find((p) => p.id === 'P002')!.status).toBe('active');
  });
});

// ===== P-06: detectionCount/missedCount 追踪 =====

describe('P-06 detectionCount 追踪', () => {
  it('重新检测到的症候应 increment detectionCount 并重置 missedCount', () => {
    const state = makeBaseState({
      activeProblems: [
        {
          id: 'P001', name: '世界观膨胀', severity: 'L2',
          evidence: ['旧证据'], firstDetected: '2026-01-01T00:00:00.000Z',
          status: 'active', detectionCount: 2, missedCount: 1,
          suggestedActions: ['A001'],
        },
      ],
    });
    const result = updateSyndromeStatus(state, [
      { id: 'P001', name: '世界观膨胀', severity: 'L2', evidence: ['新证据'], suggestedActions: ['A001'] },
    ]);
    expect(result.activeProblems[0].detectionCount).toBe(3);
    expect(result.activeProblems[0].missedCount).toBe(0);
  });

  it('本轮未检测到的症候应 increment missedCount 但 detectionCount 不变', () => {
    const state = makeBaseState({
      activeProblems: [
        {
          id: 'P001', name: '世界观膨胀', severity: 'L2',
          evidence: ['旧证据'], firstDetected: '2026-01-01T00:00:00.000Z',
          status: 'active', detectionCount: 2, missedCount: 0,
          suggestedActions: ['A001'],
        },
      ],
    });
    // 本轮只检测了 P002，P001 未被检测到
    const result = updateSyndromeStatus(state, [
      { id: 'P002', name: '角色工具人化', severity: 'L2', evidence: ['新证据'], suggestedActions: ['A004'] },
    ]);
    const p001 = result.activeProblems.find((p) => p.id === 'P001')!;
    expect(p001.detectionCount).toBe(2);   // 不变
    expect(p001.missedCount).toBe(1);       // +1
  });

  it('新增症候应初始化为 detectionCount=1, missedCount=0', () => {
    const state = makeBaseState({ activeProblems: [] });
    const result = updateSyndromeStatus(state, [
      { id: 'P001', name: '世界观膨胀', severity: 'L2', evidence: ['证据'], suggestedActions: ['A001'] },
    ]);
    expect(result.activeProblems[0].detectionCount).toBe(1);
    expect(result.activeProblems[0].missedCount).toBe(0);
  });

  it('多次跨轮次检测应累积 detectionCount', () => {
    let activeProblems: ActiveProblem[] = [];

    // 第 1 轮：首次检测到 P001
    let result = updateSyndromeStatus(
      makeBaseState({ activeProblems }),
      [{ id: 'P001', name: '世界观膨胀', severity: 'L2', evidence: ['证据1'], suggestedActions: ['A001'] }],
    );
    activeProblems = result.activeProblems;
    expect(activeProblems[0].detectionCount).toBe(1);

    // 第 2 轮：再次检测到 P001
    result = updateSyndromeStatus(
      makeBaseState({ activeProblems }),
      [{ id: 'P001', name: '世界观膨胀', severity: 'L2', evidence: ['证据2'], suggestedActions: ['A001'] }],
    );
    activeProblems = result.activeProblems;
    expect(activeProblems[0].detectionCount).toBe(2);

    // 第 3 轮：再次检测到 P001
    result = updateSyndromeStatus(
      makeBaseState({ activeProblems }),
      [{ id: 'P001', name: '世界观膨胀', severity: 'L2', evidence: ['证据3'], suggestedActions: ['A001'] }],
    );
    activeProblems = result.activeProblems;
    expect(activeProblems[0].detectionCount).toBe(3);
  });

  it('检测→消失→再检测 时 missedCount 应先增后重置', () => {
    let activeProblems: ActiveProblem[] = [];

    // 第 1 轮：检测到 P001
    let result = updateSyndromeStatus(
      makeBaseState({ activeProblems }),
      [{ id: 'P001', name: '世界观膨胀', severity: 'L2', evidence: ['证据1'], suggestedActions: ['A001'] }],
    );
    activeProblems = result.activeProblems;

    // 第 2 轮：P001 未被检测到（只检测了 P002）
    result = updateSyndromeStatus(
      makeBaseState({ activeProblems }),
      [{ id: 'P002', name: '角色工具人化', severity: 'L2', evidence: ['证据2'], suggestedActions: ['A004'] }],
    );
    activeProblems = result.activeProblems;
    expect(activeProblems.find((p) => p.id === 'P001')!.missedCount).toBe(1);

    // 第 3 轮：P001 再次被检测到
    result = updateSyndromeStatus(
      makeBaseState({ activeProblems }),
      [
        { id: 'P001', name: '世界观膨胀', severity: 'L2', evidence: ['证据3'], suggestedActions: ['A001'] },
        { id: 'P002', name: '角色工具人化', severity: 'L2', evidence: ['证据3'], suggestedActions: ['A004'] },
      ],
    );
    activeProblems = result.activeProblems;
    const p001 = activeProblems.find((p) => p.id === 'P001')!;
    expect(p001.missedCount).toBe(0);   // 重置
    expect(p001.detectionCount).toBe(2); // +1
  });
});

// ===== autoLockConsistentSyndromes (P-06) =====

describe('autoLockConsistentSyndromes', () => {
  it('detectionCount >= 2 的症候应自动锁定', () => {
    const state = makeBaseState({
      lockedSyndromes: [],
      activeProblems: [
        { ...makeProblem('P001', 'L2', 'active'), detectionCount: 2 },
        { ...makeProblem('P002', 'L2', 'active'), detectionCount: 1 },
      ],
    });
    const result = autoLockConsistentSyndromes(state);
    expect(result.lockedSyndromes).toContain('P001');
    expect(result.lockedSyndromes).not.toContain('P002');
  });

  it('已锁定的症候不应重复锁定', () => {
    const state = makeBaseState({
      lockedSyndromes: ['P001'],
      activeProblems: [
        { ...makeProblem('P001', 'L2', 'active'), detectionCount: 3 },
      ],
    });
    const result = autoLockConsistentSyndromes(state);
    expect(result.lockedSyndromes).toEqual(['P001']);
  });

  it('detectionCount < 2 的症候不应锁定', () => {
    const state = makeBaseState({
      lockedSyndromes: [],
      activeProblems: [
        { ...makeProblem('P001', 'L2', 'active'), detectionCount: 1 },
        { ...makeProblem('P002', 'L2', 'active'), detectionCount: 1 },
      ],
    });
    const result = autoLockConsistentSyndromes(state);
    expect(result.lockedSyndromes).toEqual([]);
  });

  it('空 activeProblems 应返回空锁定列表', () => {
    const state = makeBaseState({ activeProblems: [] });
    const result = autoLockConsistentSyndromes(state);
    expect(result.lockedSyndromes).toEqual([]);
  });

  it('应与 updateSyndromeStatus 配合实现 P-06 完整流程', () => {
    // 模拟：P001 连续 2 轮被检测到 → 自动锁定
    let activeProblems: ActiveProblem[] = [];

    // 第 1 轮：检测到 P001
    let result = updateSyndromeStatus(
      makeBaseState({ activeProblems }),
      [{ id: 'P001', name: '世界观膨胀', severity: 'L2', evidence: ['证据1'], suggestedActions: ['A001'] }],
    );

    // 第 2 轮：再次检测到 P001 → detectionCount = 2
    result = updateSyndromeStatus(
      makeBaseState({ activeProblems: result.activeProblems }),
      [{ id: 'P001', name: '世界观膨胀', severity: 'L2', evidence: ['证据2'], suggestedActions: ['A001'] }],
    );

    const state2 = makeBaseState({ activeProblems: result.activeProblems });
    const lockResult = autoLockConsistentSyndromes(state2);
    expect(lockResult.lockedSyndromes).toContain('P001');
  });
});

// ===== unlockResolvedSyndromes =====

describe('unlockResolvedSyndromes', () => {
  it('应移除已解决症候的锁定', () => {
    const state = makeBaseState({
      lockedSyndromes: ['P001', 'P002', 'P003'],
      activeProblems: [
        makeProblem('P001', 'L1', 'resolved'),
        makeProblem('P002', 'L2', 'improving'),
        makeProblem('P003', 'L1', 'active'),
      ],
    });
    const result = unlockResolvedSyndromes(state);
    expect(result.lockedSyndromes).toEqual(['P002', 'P003']);
    expect(result.activeProblems).toHaveLength(2);
    expect(result.activeProblems.find((p) => p.id === 'P001')).toBeUndefined();
  });

  it('无 resolved 症候应保持不变', () => {
    const state = makeBaseState({
      lockedSyndromes: ['P001', 'P002'],
      activeProblems: [
        makeProblem('P001', 'L1', 'active'),
        makeProblem('P002', 'L2', 'improving'),
      ],
    });
    const result = unlockResolvedSyndromes(state);
    expect(result.lockedSyndromes).toEqual(['P001', 'P002']);
    expect(result.activeProblems).toHaveLength(2);
  });

  it('应清理不在 lockedSyndromes 中的 resolved 症候', () => {
    const state = makeBaseState({
      lockedSyndromes: ['P001'],
      activeProblems: [
        makeProblem('P001', 'L1', 'resolved'),
        makeProblem('P002', 'L2', 'resolved'), // 未锁定但也 resolved
      ],
    });
    const result = unlockResolvedSyndromes(state);
    expect(result.lockedSyndromes).toEqual([]);
    expect(result.activeProblems).toHaveLength(0);
  });
});

// ===== areAllSyndromesResolved =====

describe('areAllSyndromesResolved', () => {
  it('所有锁定症候都已 resolved 应返回 true', () => {
    const state = makeBaseState({
      lockedSyndromes: ['P001', 'P002'],
      activeProblems: [
        makeProblem('P001', 'L1', 'resolved'),
        makeProblem('P002', 'L1', 'resolved'),
      ],
    });
    expect(areAllSyndromesResolved(state)).toBe(true);
  });

  it('有未解决的锁定症候应返回 false', () => {
    const state = makeBaseState({
      lockedSyndromes: ['P001', 'P002'],
      activeProblems: [
        makeProblem('P001', 'L1', 'resolved'),
        makeProblem('P002', 'L2', 'active'),
      ],
    });
    expect(areAllSyndromesResolved(state)).toBe(false);
  });

  it('没有锁定症候应返回 false', () => {
    const state = makeBaseState({
      lockedSyndromes: [],
      activeProblems: [],
    });
    expect(areAllSyndromesResolved(state)).toBe(false);
  });

  it('锁定症候不在 activeProblems 中应视为已解决', () => {
    // 这种情况可能发生在用户手动清除问题后
    const state = makeBaseState({
      lockedSyndromes: ['P001', 'P002'],
      activeProblems: [],
    });
    expect(areAllSyndromesResolved(state)).toBe(true);
  });

  it('improving 状态的锁定症候不算 resolved', () => {
    const state = makeBaseState({
      lockedSyndromes: ['P001'],
      activeProblems: [makeProblem('P001', 'L1', 'improving')],
    });
    expect(areAllSyndromesResolved(state)).toBe(false);
  });
});

// ===== 完整锁定→解锁流程 =====

describe('完整锁定→解锁流程', () => {
  it('应完成 诊断→锁定→改善→解锁 的完整循环', () => {
    // 1. 初始状态
    let state = makeBaseState();

    // 2. 首次诊断，发现两个症候
    const lockResult = lockSyndromes(state, ['P001', 'P002']);
    state = { ...state, ...lockResult };
    state.activeProblems = [
      makeProblem('P001', 'L2', 'active'),
      makeProblem('P002', 'L3', 'active'),
    ];

    expect(state.lockedSyndromes).toHaveLength(2);
    expect(areAllSyndromesResolved(state)).toBe(false);

    // 3. 重新诊断，P001 改善
    const updateResult = updateSyndromeStatus(state, [
      { id: 'P001', name: '世界观膨胀', severity: 'L1', evidence: ['改善'], suggestedActions: ['A001'] },
      { id: 'P002', name: '角色工具人化', severity: 'L3', evidence: ['无变化'], suggestedActions: ['A004'] },
    ]);
    state = { ...state, ...updateResult };

    expect(state.activeProblems.find((p) => p.id === 'P001')!.status).toBe('improving');
    expect(state.activeProblems.find((p) => p.id === 'P002')!.status).toBe('active');
    expect(areAllSyndromesResolved(state)).toBe(false);

    // 4. P001 被标记为 resolved
    state.activeProblems = state.activeProblems.map((p) =>
      p.id === 'P001' ? { ...p, status: 'resolved' as const } : p,
    );

    // 5. 解锁已解决的症候
    const unlockResult = unlockResolvedSyndromes(state);
    state = { ...state, ...unlockResult };

    expect(state.lockedSyndromes).toEqual(['P002']);
    expect(state.activeProblems).toHaveLength(1);
    expect(state.activeProblems[0].id).toBe('P002');
    expect(areAllSyndromesResolved(state)).toBe(false);

    // 6. P002 最终也 resolved
    state.activeProblems = state.activeProblems.map((p) =>
      p.id === 'P002' ? { ...p, status: 'resolved' as const } : p,
    );

    // 7. 再次解锁
    const finalUnlock = unlockResolvedSyndromes(state);
    state = { ...state, ...finalUnlock };

    expect(state.lockedSyndromes).toEqual([]);
    expect(state.activeProblems).toHaveLength(0);
    // 注意：没有锁定症候时 areAllSyndromesResolved 返回 false（因为无从判断）
    // 但此时可以安全地认为训练完成
  });
});

function makeProblem(id: string, severity: 'L1' | 'L2' | 'L3', status: 'active' | 'improving' | 'resolved'): ActiveProblem {
  return {
    id: id as ActiveProblem['id'],
    name: id,
    severity,
    evidence: ['证据片段'],
    firstDetected: '2026-01-01T00:00:00.000Z',
    status,
    detectionCount: 1, // 默认已检测 1 轮
    missedCount: 0,
    suggestedActions: ['A001'] as ActiveProblem['suggestedActions'],
  };
}
