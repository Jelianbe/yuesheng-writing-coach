/* eslint-disable @typescript-eslint/no-non-null-assertion */
/**
 * DevelopmentPathService 单元测试
 *
 * 覆盖：
 * - 阶段查询（全部/按 ID/按症候）
 * - MasteryGate 阶段通过判定
 * - 当前阶段计算
 * - 阶段解锁检查
 * - 阶段进度计算
 */

import { describe, it, expect, beforeEach } from 'vitest';
import {
  getAllStages,
  getStageById,
  getStageForSyndrome,
  getCurrentStage,
  checkStageUnlock,
  calculateStageProgress,
  getMasteryThreshold,
  reload,
  isLoaded,
} from '../development-path.service';
import type { UserMasteryData } from '../../../../../shared/types/index';

beforeEach(() => {
  reload();
});

describe('基础查询', () => {
  it('getAllStages 应返回 7 个阶段', () => {
    const stages = getAllStages();
    expect(stages).toHaveLength(7);
    expect(stages[0].stageId).toBe('eye');
    expect(stages[6].stageId).toBe('taste');
  });

  it('getStageById 应返回正确阶段', () => {
    const stage = getStageById('word');
    expect(stage).toBeDefined();
    expect(stage!.name).toBe('练字');
    expect(stage!.order).toBe(3);
    expect(stage!.prerequisites).toEqual(['pen']);
  });

  it('getStageById 未知 ID 应返回 undefined', () => {
    const stage = getStageById('unknown');
    expect(stage).toBeUndefined();
  });

  it('getStageForSyndrome 应返回症候所属阶段', () => {
    const stage = getStageForSyndrome('P003');
    expect(stage).toBeDefined();
    expect(stage!.stageId).toBe('word');
  });

  it('getStageForSyndrome 未知症候应返回 undefined', () => {
    const stage = getStageForSyndrome('P099');
    expect(stage).toBeUndefined();
  });

  it('getMasteryThreshold 应返回 8', () => {
    expect(getMasteryThreshold()).toBe(8);
  });
});

describe('阶段进度计算', () => {
  const highMastery: UserMasteryData[] = [
    { syndromeId: 'P001', averageScore: 9, trainingCount: 5 },
    { syndromeId: 'P006', averageScore: 8.5, trainingCount: 3 },
  ];

  it('有关联症候的阶段进度应正确计算', () => {
    const eyeStage = getStageById('pen')!;
    const progress = calculateStageProgress(eyeStage, [
      { syndromeId: 'P001', averageScore: 6, trainingCount: 2 },
    ]);
    expect(progress).toBe(75); // 6/8*100 = 75
  });

  it('无关联症候的阶段进度应为 100', () => {
    const eyeStage = getStageById('eye')!;
    const progress = calculateStageProgress(eyeStage, []);
    expect(progress).toBe(100);
  });

  it('满进度应不超过 100', () => {
    const structureStage = getStageById('structure')!;
    const progress = calculateStageProgress(structureStage, highMastery);
    expect(progress).toBeLessThanOrEqual(100);
  });
});

describe('当前阶段判定', () => {
  it('无掌握度数据时应在第二阶段（eye 自动通过后指向 pen）', () => {
    const progress = getCurrentStage([]);
    expect(progress.currentStage.stageId).toBe('pen');
    expect(progress.progress).toBe(0); // pen 有 P001 但无评分
    expect(progress.nextStage).toBeDefined();
    expect(progress.nextStage!.stageId).toBe('word');
  });

  it('第一阶段通过后应指向第二阶段', () => {
    const progress = getCurrentStage([]);
    expect(progress.currentStage.stageId).toBe('pen');
    expect(progress.stageUnlocked).toBe(true);
  });

  it('所有阶段通过时应指向最后阶段并标记完成', () => {
    // 为所有关联症候准备高分
    const allMastery: UserMasteryData[] = [
      { syndromeId: 'P001', averageScore: 9, trainingCount: 3 },
      { syndromeId: 'P002', averageScore: 8.5, trainingCount: 4 },
      { syndromeId: 'P003', averageScore: 9, trainingCount: 5 },
      { syndromeId: 'P004', averageScore: 8.5, trainingCount: 3 },
      { syndromeId: 'P005', averageScore: 9, trainingCount: 2 },
      { syndromeId: 'P006', averageScore: 8, trainingCount: 4 },
      { syndromeId: 'P007', averageScore: 8.5, trainingCount: 3 },
      { syndromeId: 'P009', averageScore: 9, trainingCount: 5 },
      { syndromeId: 'P010', averageScore: 8, trainingCount: 4 },
    ];

    const progress = getCurrentStage(allMastery);
    expect(progress.currentStage.stageId).toBe('taste');
    expect(progress.nextStage).toBeUndefined();
    expect(progress.stageUnlocked).toBe(true);
  });

  it('部分症候未达标时应在对应阶段', () => {
    const partialMastery: UserMasteryData[] = [
      { syndromeId: 'P001', averageScore: 9, trainingCount: 3 },
      { syndromeId: 'P006', averageScore: 5, trainingCount: 2 }, // P006 未达标
    ];

    const progress = getCurrentStage(partialMastery);
    // eye 无症候 → auto pass → pen (P001 达标) → auto pass → word (P002/P003 无数据)
    expect(progress.currentStage.stageId).toBe('word');
    // word 的 P002, P003 都没有 mastery 数据
    expect(progress.blockingSyndromes).toContain('P002');
    expect(progress.blockingSyndromes).toContain('P003');
    expect(progress.nextStage).toBeDefined();
    expect(progress.nextStage!.stageId).toBe('person');
  });
});

describe('阶段解锁检查', () => {
  it('第一阶段应无条件解锁', () => {
    expect(checkStageUnlock('eye', [])).toBe(true);
  });

  it('第二阶段需要第一阶段通过', () => {
    // eye 无关联症候 → 自动通过
    expect(checkStageUnlock('pen', [])).toBe(true);
  });

  it('未知阶段应返回 false', () => {
    expect(checkStageUnlock('unknown', [])).toBe(false);
  });

  it('前置阶段未通过时应返回 false', () => {
    // structure 需要 person 通过，但 person 需要 word 通过
    // word 有关联症候 P002, P003 — 模拟未达标
    const lowMastery: UserMasteryData[] = [
      { syndromeId: 'P002', averageScore: 3, trainingCount: 1 },
      { syndromeId: 'P003', averageScore: 4, trainingCount: 1 },
    ];
    // word 前置是 pen，pen 前置是 eye（自动通过）
    // word 未通过 → control 前置 structure 不可达
    const controlUnlock = checkStageUnlock('control', lowMastery);
    expect(controlUnlock).toBe(false);
  });
});

describe('Loader 状态管理', () => {
  it('reload 后查询应正常', () => {
    reload();
    const stages = getAllStages();
    expect(stages).toHaveLength(7);
    expect(isLoaded()).toBe(true);
  });
});
