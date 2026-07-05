/* eslint-disable @typescript-eslint/no-non-null-assertion */
/**
 * 教学状态机集成测试
 *
 * 纯函数集成测试，不依赖任何 mock，直接 import 导航/锁定/反射函数进行测试。
 * 覆盖：阶段转换链、子阶段序列、子阶段推进、状态转换、进度计算、
 *       锁定机制集成、反思门控集成、完整端到端流程。
 */

import { describe, it, expect } from 'vitest';
import { TeachingPhase, TeachingSubphase } from '../../../../../shared/constants';
import type { ActiveProblem } from '../../../../../shared/types/index';
import type { TeachingState } from '../teaching-state.types';
import {
  getNextPhase,
  getFirstSubphaseOf,
  getNextSubphase,
  confirmPhaseComplete,
  calculatePhaseProgress,
  lockSyndromes,
  updateSyndromeStatus,
  autoLockConsistentSyndromes,
  unlockResolvedSyndromes,
  areAllSyndromesResolved,
  shouldEnterReflection,
  enterReflectionIfTriggered,
  downgradeSyndromeSeverity,
} from '../teaching-state-machine';

// =============================================================================
// 工厂函数
// =============================================================================

/**
 * 创建测试用 TeachingState 实例
 * 导出供其他测试文件复用
 */
export function createTestState(overrides: Partial<TeachingState> = {}): TeachingState {
  return {
    sessionId: 'integration-test-session',
    currentPhase: TeachingPhase.INIT,
    currentSubphase: '',
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

/** 快捷创建 ActiveProblem */
function makeProblem(
  id: string,
  severity: 'L1' | 'L2' | 'L3',
  status: 'active' | 'improving' | 'resolved',
  overrides: Partial<ActiveProblem> = {},
): ActiveProblem {
  return {
    id: id as ActiveProblem['id'],
    name: id,
    severity,
    evidence: ['证据片段'],
    firstDetected: '2026-01-01T00:00:00.000Z',
    status,
    detectionCount: 1,
    missedCount: 0,
    suggestedActions: ['A001'] as ActiveProblem['suggestedActions'],
    ...overrides,
  };
}

// =============================================================================
// 1. 阶段转换链
// =============================================================================

describe('阶段转换链 (getNextPhase)', () => {
  it('INIT → ENGAGE', () => {
    expect(getNextPhase(TeachingPhase.INIT)).toBe(TeachingPhase.ENGAGE);
  });

  it('ENGAGE → WORLD', () => {
    expect(getNextPhase(TeachingPhase.ENGAGE)).toBe(TeachingPhase.WORLD);
  });

  it('WORLD → PRACTICE_LOOP', () => {
    expect(getNextPhase(TeachingPhase.WORLD)).toBe(TeachingPhase.PRACTICE_LOOP);
  });

  it('PRACTICE_LOOP 自循环（不会自动离开）', () => {
    expect(getNextPhase(TeachingPhase.PRACTICE_LOOP)).toBe(TeachingPhase.PRACTICE_LOOP);
  });

  it('REVIEW → PRACTICE_LOOP（复盘后回到循环）', () => {
    expect(getNextPhase(TeachingPhase.REVIEW)).toBe(TeachingPhase.PRACTICE_LOOP);
  });
});

// =============================================================================
// 2. 子阶段序列
// =============================================================================

describe('子阶段序列 (getFirstSubphaseOf)', () => {
  it('ENGAGE 返回 S0_CONFIRM', () => {
    expect(getFirstSubphaseOf(TeachingPhase.ENGAGE)).toBe(TeachingSubphase.ENGAGE_CONFIRM);
  });

  it('WORLD 返回 S1_NATURAL_LAW', () => {
    expect(getFirstSubphaseOf(TeachingPhase.WORLD)).toBe(TeachingSubphase.WORLD_NATURAL_LAW);
  });

  it('PRACTICE_LOOP 返回 S2_IDENTIFY', () => {
    expect(getFirstSubphaseOf(TeachingPhase.PRACTICE_LOOP)).toBe(TeachingSubphase.PRACTICE_IDENTIFY);
  });

  it('REVIEW 返回 S4_SUMMARY', () => {
    expect(getFirstSubphaseOf(TeachingPhase.REVIEW)).toBe(TeachingSubphase.REVIEW_SUMMARY);
  });

  it('INIT 无子阶段应抛错', () => {
    expect(() => getFirstSubphaseOf(TeachingPhase.INIT)).toThrow('has no subphases');
  });
});

// =============================================================================
// 3. 子阶段推进
// =============================================================================

describe('子阶段推进 (getNextSubphase)', () => {
  describe('WORLD 下自然顺序推进', () => {
    const worldSubphases = [
      TeachingSubphase.WORLD_NATURAL_LAW,
      TeachingSubphase.WORLD_PROTAGONIST,
      TeachingSubphase.WORLD_SOCIAL_STRUCT,
      TeachingSubphase.WORLD_FIRST_SCENE,
      TeachingSubphase.WORLD_DAILY_DETAIL,
    ];

    it('5 个子阶段走完后返回 null', () => {
      for (let i = 0; i < worldSubphases.length - 1; i++) {
        const next = getNextSubphase(TeachingPhase.WORLD, worldSubphases[i]);
        expect(next).toBe(worldSubphases[i + 1]);
      }
      const last = getNextSubphase(TeachingPhase.WORLD, worldSubphases[worldSubphases.length - 1]);
      expect(last).toBeNull();
    });
  });

  describe('PRACTICE_LOOP 下推进', () => {
    const loopSubphases = [
      TeachingSubphase.PRACTICE_IDENTIFY,
      TeachingSubphase.PRACTICE_GUIDE,
      TeachingSubphase.PRACTICE_REFLECTION,
      TeachingSubphase.PRACTICE_TEACHING,
      TeachingSubphase.PRACTICE_ASSIGN,
      TeachingSubphase.PRACTICE_REVIEW,
    ];

    it('6 个子阶段 + S2_GUIDE 顺序推进，末尾返回 null', () => {
      for (let i = 0; i < loopSubphases.length - 1; i++) {
        const next = getNextSubphase(TeachingPhase.PRACTICE_LOOP, loopSubphases[i]);
        expect(next).toBe(loopSubphases[i + 1]);
      }
      const last = getNextSubphase(TeachingPhase.PRACTICE_LOOP, loopSubphases[loopSubphases.length - 1]);
      expect(last).toBeNull();
    });
  });

  describe('character focusArea 只走主角子阶段', () => {
    it('WORLD 下 character 聚焦应跳过自然法则', () => {
      const next = getNextSubphase(TeachingPhase.WORLD, TeachingSubphase.WORLD_PROTAGONIST, 'character');
      expect(next).toBeNull();
    });

    it('general 聚焦走完整序列', () => {
      const next = getNextSubphase(TeachingPhase.WORLD, TeachingSubphase.WORLD_NATURAL_LAW, 'general');
      expect(next).toBe(TeachingSubphase.WORLD_PROTAGONIST);
    });
  });
});

// =============================================================================
// 4. confirmPhaseComplete 完整状态转换
// =============================================================================

describe('confirmPhaseComplete 完整状态转换', () => {
  it('子阶段内推进：currentSubphase 更新，completedActions 追加', () => {
    const state = createTestState({
      currentPhase: TeachingPhase.WORLD,
      currentSubphase: TeachingSubphase.WORLD_NATURAL_LAW,
      nextSuggestedActions: ['A001' as TeachingState['nextSuggestedActions'][number]],
    });
    const result = confirmPhaseComplete(state);
    expect(result.currentSubphase).toBe(TeachingSubphase.WORLD_PROTAGONIST);
    expect(result.completedActions).toContain('A001');
    expect(result.lastUserConfirmation).not.toBeNull();
  });

  it('阶段推进：currentPhase 更新为下一阶段，subphase 重置为第一个子阶段', () => {
    const state = createTestState({
      currentPhase: TeachingPhase.WORLD,
      currentSubphase: TeachingSubphase.WORLD_DAILY_DETAIL,
    });
    const result = confirmPhaseComplete(state);
    expect(result.currentPhase).toBe(TeachingPhase.PRACTICE_LOOP);
    expect(result.currentSubphase).toBe(TeachingSubphase.PRACTICE_IDENTIFY);
  });

  it('ENGAGE 阶段完成后应推进到 WORLD', () => {
    const state = createTestState({
      currentPhase: TeachingPhase.ENGAGE,
      currentSubphase: TeachingSubphase.ENGAGE_CONFIRM,
    });
    const result = confirmPhaseComplete(state);
    expect(result.currentPhase).toBe(TeachingPhase.WORLD);
    expect(result.currentSubphase).toBe(TeachingSubphase.WORLD_NATURAL_LAW);
  });

  it('INIT 阶段完成后应推进到 ENGAGE', () => {
    const state = createTestState({
      currentPhase: TeachingPhase.INIT,
      currentSubphase: '',
    });
    const result = confirmPhaseComplete(state);
    expect(result.currentPhase).toBe(TeachingPhase.ENGAGE);
    expect(result.currentSubphase).toBe(TeachingSubphase.ENGAGE_CONFIRM);
  });

  it('循环阶段（PRACTICE_LOOP）：回到第一个子阶段', () => {
    const state = createTestState({
      currentPhase: TeachingPhase.PRACTICE_LOOP,
      currentSubphase: TeachingSubphase.PRACTICE_REVIEW,
    });
    const result = confirmPhaseComplete(state);
    expect(result.currentPhase).toBe(TeachingPhase.PRACTICE_LOOP);
    expect(result.currentSubphase).toBe(TeachingSubphase.PRACTICE_IDENTIFY);
  });

  it('复盘完成后（REVIEW → PRACTICE_LOOP）应重置子阶段', () => {
    const state = createTestState({
      currentPhase: TeachingPhase.REVIEW,
      currentSubphase: TeachingSubphase.REVIEW_SUMMARY,
    });
    const result = confirmPhaseComplete(state);
    expect(result.currentPhase).toBe(TeachingPhase.PRACTICE_LOOP);
    expect(result.currentSubphase).toBe(TeachingSubphase.PRACTICE_IDENTIFY);
  });
});

// =============================================================================
// 5. 进度计算
// =============================================================================

describe('calculatePhaseProgress', () => {
  it('第一子阶段 = 1/N', () => {
    // WORLD 有 5 个子阶段
    const progress = calculatePhaseProgress(TeachingPhase.WORLD, TeachingSubphase.WORLD_NATURAL_LAW);
    expect(progress).toBeCloseTo(1 / 5);
  });

  it('最后子阶段 = 1.0', () => {
    const progress = calculatePhaseProgress(TeachingPhase.WORLD, TeachingSubphase.WORLD_DAILY_DETAIL);
    expect(progress).toBe(1.0);
  });

  it('中间子阶段进度正确', () => {
    // WORLD: 第 3 个子阶段（SOCIAL_STRUCT）进度 = 3/5
    const progress = calculatePhaseProgress(TeachingPhase.WORLD, TeachingSubphase.WORLD_SOCIAL_STRUCT);
    expect(progress).toBeCloseTo(3 / 5);
  });

  it('INIT 无子阶段返回 1', () => {
    const progress = calculatePhaseProgress(TeachingPhase.INIT, '');
    expect(progress).toBe(1);
  });

  it('PRACTICE_LOOP 第 1 子阶段 = 1/6', () => {
    const progress = calculatePhaseProgress(TeachingPhase.PRACTICE_LOOP, TeachingSubphase.PRACTICE_IDENTIFY);
    expect(progress).toBeCloseTo(1 / 6);
  });

  it('PRACTICE_LOOP 最后子阶段 = 1.0', () => {
    const progress = calculatePhaseProgress(TeachingPhase.PRACTICE_LOOP, TeachingSubphase.PRACTICE_REVIEW);
    expect(progress).toBe(1.0);
  });
});

// =============================================================================
// 6. 锁定机制集成
// =============================================================================

describe('锁定机制集成', () => {
  it('lockSyndromes 新锁定 + 去重', () => {
    const state = createTestState({ lockedSyndromes: ['P001'] });
    const result = lockSyndromes(state, ['P001', 'P002', 'P003']);
    expect(result.lockedSyndromes).toEqual(['P001', 'P002', 'P003']);
    // P001 不应出现两次
    expect(result.lockedSyndromes.filter((id) => id === 'P001')).toHaveLength(1);
  });

  it('updateSyndromeStatus 新增 + improving + 复发', () => {
    const state = createTestState({
      activeProblems: [
        makeProblem('P001', 'L2', 'active', { detectionCount: 2 }),
      ],
    });
    // 新增 P002，同时 P001 降低严重度
    const result = updateSyndromeStatus(state, [
      { id: 'P001', name: '世界观膨胀', severity: 'L1', evidence: ['改善'], suggestedActions: ['A001'] },
      { id: 'P002', name: '角色工具人化', severity: 'L2', evidence: ['新发现'], suggestedActions: ['A004'] },
    ]);
    expect(result.activeProblems).toHaveLength(2);
    expect(result.activeProblems.find((p) => p.id === 'P001')!.status).toBe('improving');
    expect(result.activeProblems.find((p) => p.id === 'P002')!.status).toBe('active');
  });

  it('autoLockConsistentSyndromes 2 次自动锁定', () => {
    const state = createTestState({
      lockedSyndromes: ['P001'], // 已手动锁定
      activeProblems: [
        makeProblem('P001', 'L2', 'active', { detectionCount: 3 }),
        makeProblem('P002', 'L2', 'active', { detectionCount: 2 }),
        makeProblem('P003', 'L2', 'active', { detectionCount: 1 }),
      ],
    });
    const result = autoLockConsistentSyndromes(state);
    // P001 已锁定，P002 连续 2 次自动锁定，P003 不足 2 次不锁定
    expect(result.lockedSyndromes).toContain('P001');
    expect(result.lockedSyndromes).toContain('P002');
    expect(result.lockedSyndromes).not.toContain('P003');
  });

  it('unlockResolvedSyndromes 清除已解决', () => {
    const state = createTestState({
      lockedSyndromes: ['P001', 'P002', 'P003'],
      activeProblems: [
        makeProblem('P001', 'L1', 'resolved'),
        makeProblem('P002', 'L2', 'active'),
        makeProblem('P003', 'L1', 'improving'),
      ],
    });
    const result = unlockResolvedSyndromes(state);
    expect(result.lockedSyndromes).toEqual(['P002', 'P003']);
    expect(result.activeProblems).toHaveLength(2);
    expect(result.activeProblems.find((p) => p.id === 'P001')).toBeUndefined();
  });

  it('areAllSyndromesResolved 判断', () => {
    const resolvedState = createTestState({
      lockedSyndromes: ['P001', 'P002'],
      activeProblems: [
        makeProblem('P001', 'L1', 'resolved'),
        makeProblem('P002', 'L1', 'resolved'),
      ],
    });
    expect(areAllSyndromesResolved(resolvedState)).toBe(true);

    const unresolvedState = createTestState({
      lockedSyndromes: ['P001'],
      activeProblems: [makeProblem('P001', 'L2', 'active')],
    });
    expect(areAllSyndromesResolved(unresolvedState)).toBe(false);
  });
});

// =============================================================================
// 7. 反思门控集成
// =============================================================================

describe('反思门控集成', () => {
  it('L2+ 症候存在时 shouldEnterReflection 返回 true', () => {
    const state = createTestState({
      currentPhase: TeachingPhase.PRACTICE_LOOP,
      currentSubphase: TeachingSubphase.PRACTICE_IDENTIFY,
      activeProblems: [makeProblem('P001', 'L2', 'active')],
    });
    expect(shouldEnterReflection(state)).toBe(true);
  });

  it('L1 仅症候时返回 false', () => {
    const state = createTestState({
      currentPhase: TeachingPhase.PRACTICE_LOOP,
      currentSubphase: TeachingSubphase.PRACTICE_IDENTIFY,
      activeProblems: [makeProblem('P001', 'L1', 'active')],
    });
    expect(shouldEnterReflection(state)).toBe(false);
  });

  it('enterReflectionIfTriggered 强制进入 REFLECTION', () => {
    const state = createTestState({
      currentPhase: TeachingPhase.PRACTICE_LOOP,
      currentSubphase: TeachingSubphase.PRACTICE_IDENTIFY,
      activeProblems: [makeProblem('P001', 'L3', 'active')],
    });
    const result = enterReflectionIfTriggered(state);
    expect(result.currentSubphase).toBe(TeachingSubphase.PRACTICE_REFLECTION);
  });

  it('已在 REFLECTION 后不重复触发', () => {
    const state = createTestState({
      currentPhase: TeachingPhase.PRACTICE_LOOP,
      currentSubphase: TeachingSubphase.PRACTICE_REFLECTION,
      activeProblems: [makeProblem('P001', 'L2', 'active')],
    });
    expect(shouldEnterReflection(state)).toBe(false);
    const result = enterReflectionIfTriggered(state);
    // 未触发，返回原状态
    expect(result.currentSubphase).toBe(TeachingSubphase.PRACTICE_REFLECTION);
  });

  it('downgradeSyndromeSeverity 评分 >= 7 降级', () => {
    const state = createTestState({
      activeProblems: [makeProblem('P001', 'L3', 'active')],
    });
    const result = downgradeSyndromeSeverity(state, 'P001', 8);
    const p001 = result.activeProblems.find((p) => p.id === 'P001')!;
    expect(p001.severity).toBe('L2');
    expect(p001.status).toBe('improving');
  });

  it('评分 < 7 不降级', () => {
    const state = createTestState({
      activeProblems: [makeProblem('P001', 'L3', 'active')],
    });
    const result = downgradeSyndromeSeverity(state, 'P001', 5);
    const p001 = result.activeProblems.find((p) => p.id === 'P001')!;
    expect(p001.severity).toBe('L3');
    expect(p001.status).toBe('active');
  });

  it('L2 降级到 L1', () => {
    const state = createTestState({
      activeProblems: [makeProblem('P001', 'L2', 'active')],
    });
    const result = downgradeSyndromeSeverity(state, 'P001', 9);
    const p001 = result.activeProblems.find((p) => p.id === 'P001')!;
    expect(p001.severity).toBe('L1');
    expect(p001.status).toBe('improving');
  });

  it('L1 不降级（已经是最低）', () => {
    const state = createTestState({
      activeProblems: [makeProblem('P001', 'L1', 'active')],
    });
    const result = downgradeSyndromeSeverity(state, 'P001', 10);
    const p001 = result.activeProblems.find((p) => p.id === 'P001')!;
    expect(p001.severity).toBe('L1');
    expect(p001.status).toBe('active');
  });
});

// =============================================================================
// 8. 完整流程端到端
// =============================================================================

describe('完整流程端到端', () => {
  it('模拟完整教学流程：初始状态 → ENGAGE → WORLD → PRACTICE_LOOP → 诊断锁定 → 反思门控 → 训练降级 → 症候解决', () => {
    // ===== 1. 创建初始状态 =====
    let state = createTestState();

    expect(state.currentPhase).toBe(TeachingPhase.INIT);
    expect(state.currentSubphase).toBe('');

    // ===== 2. INIT → ENGAGE =====
    state = confirmPhaseComplete(state);
    expect(state.currentPhase).toBe(TeachingPhase.ENGAGE);
    expect(state.currentSubphase).toBe(TeachingSubphase.ENGAGE_CONFIRM);

    // ===== 3. ENGAGE → WORLD =====
    state = confirmPhaseComplete(state);
    expect(state.currentPhase).toBe(TeachingPhase.WORLD);
    expect(state.currentSubphase).toBe(TeachingSubphase.WORLD_NATURAL_LAW);

    // ===== 4. 遍历 WORLD 的 5 个子阶段 =====
    const worldSubphases = [
      TeachingSubphase.WORLD_NATURAL_LAW,
      TeachingSubphase.WORLD_PROTAGONIST,
      TeachingSubphase.WORLD_SOCIAL_STRUCT,
      TeachingSubphase.WORLD_FIRST_SCENE,
      TeachingSubphase.WORLD_DAILY_DETAIL,
    ];

    for (let i = 0; i < worldSubphases.length - 1; i++) {
      expect(state.currentSubphase).toBe(worldSubphases[i]);
      state = confirmPhaseComplete(state);
    }
    // 最后一次推进到 PRACTICE_LOOP
    state = confirmPhaseComplete(state);
    expect(state.currentPhase).toBe(TeachingPhase.PRACTICE_LOOP);
    expect(state.currentSubphase).toBe(TeachingSubphase.PRACTICE_IDENTIFY);

    // ===== 5. 诊断合并锁定症候 =====
    // 模拟诊断发现了 P001(L3) 和 P002(L2)
    const lockResult = lockSyndromes(state, ['P001', 'P002']);
    state = { ...state, ...lockResult };
    expect(state.lockedSyndromes).toEqual(['P001', 'P002']);

    // 更新 activeProblems
    const updateResult = updateSyndromeStatus(state, [
      { id: 'P001', name: '世界观膨胀', severity: 'L3', evidence: ['大量背景设定'], suggestedActions: ['A001'] },
      { id: 'P002', name: '角色工具人化', severity: 'L2', evidence: ['角色缺乏动机'], suggestedActions: ['A004'] },
    ]);
    state = { ...state, ...updateResult };
    expect(state.activeProblems).toHaveLength(2);
    expect(state.activeProblems.every((p) => p.status === 'active')).toBe(true);

    // 第 2 轮：再次诊断到相同症候 → detectionCount=2 → 自动锁定（但已锁定）
    const updateResult2 = updateSyndromeStatus(state, [
      { id: 'P001', name: '世界观膨胀', severity: 'L3', evidence: ['仍然过多'], suggestedActions: ['A001'] },
      { id: 'P002', name: '角色工具人化', severity: 'L2', evidence: ['仍然工具'], suggestedActions: ['A004'] },
    ]);
    state = { ...state, ...updateResult2 };
    const autoLockResult = autoLockConsistentSyndromes(state);
    state = { ...state, ...autoLockResult };

    // ===== 6. 反思门控触发 =====
    // 推进到 IDENTIFY 之后，因为存在 L2+ 症候，应触发反思
    // 先推进到 GUIDE
    state = confirmPhaseComplete(state);
    expect(state.currentSubphase).toBe(TeachingSubphase.PRACTICE_GUIDE);

    // 触发反思门控
    expect(shouldEnterReflection(state)).toBe(true);
    state = enterReflectionIfTriggered(state);
    expect(state.currentSubphase).toBe(TeachingSubphase.PRACTICE_REFLECTION);

    // 推进到 TEACHING
    state = confirmPhaseComplete(state);
    expect(state.currentSubphase).toBe(TeachingSubphase.PRACTICE_TEACHING);

    // ===== 7. 训练完成降级 =====
    // 模拟 P001 训练评分 8 → 降级
    const downgradeResult = downgradeSyndromeSeverity(state, 'P001', 8);
    state = { ...state, ...downgradeResult };
    const p001 = state.activeProblems.find((p) => p.id === 'P001')!;
    expect(p001.severity).toBe('L2');
    expect(p001.status).toBe('improving');

    // 模拟 P002 训练评分 9 → 降级
    const downgradeResult2 = downgradeSyndromeSeverity(state, 'P002', 9);
    state = { ...state, ...downgradeResult2 };
    const p002 = state.activeProblems.find((p) => p.id === 'P002')!;
    expect(p002.severity).toBe('L1');
    expect(p002.status).toBe('improving');

    // ===== 8. 症候全部解决 =====
    // 手动标记为 resolved
    state.activeProblems = state.activeProblems.map((p) => ({ ...p, status: 'resolved' as const }));
    state = { ...state, ...unlockResolvedSyndromes(state) };

    expect(state.lockedSyndromes).toEqual([]);
    expect(state.activeProblems).toHaveLength(0);
  });
});
