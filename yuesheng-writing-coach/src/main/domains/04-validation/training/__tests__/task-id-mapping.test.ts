/**
 * Task ID Mapping Loader 单元测试
 *
 * T15-B.5 覆盖：
 * - T0XX ↔ TRAIN-PXXX 双向查询
 * - TRAIN-PXXX ↔ CH-PXXX 多向查询
 * - PRAC-XXX → 症候查询
 * - 孤儿项追踪
 * - 完整性校验
 */

import { describe, it, expect, beforeEach } from 'vitest';
import {
  t0xxToTrain,
  t0xxToTrainDetail,
  trainToT0xx,
  trainToChallenges,
  challengeToTrains,
  getSyndromeMapping,
  pracToSyndrome,
  getOrphanT0XX,
  getOrphanTRAIN,
  getOrphanChallenges,
  getOrphanSyndromes,
  validateMappingIntegrity,
  getStatistics,
  reload,
  isLoaded,
} from '../task-id-mapping.loader';

beforeEach(() => {
  reload();
});

describe('Loader 初始化', () => {
  it('isLoaded 在 reload 后应为 false', () => {
    expect(isLoaded()).toBe(false);
  });
});

describe('T0XX → TRAIN-PXXX 映射', () => {
  it('T001（情绪描写 d=1）应映射到 TRAIN-P003-001', () => {
    expect(t0xxToTrain('T001')).toBe('TRAIN-P003-001');
  });

  it('T011（缩小练习）应映射到 TRAIN-P001-001', () => {
    expect(t0xxToTrain('T011')).toBe('TRAIN-P001-001');
  });

  it('T016 应返回 null（孤儿 T0XX，TBD）', () => {
    expect(t0xxToTrain('T016')).toBeNull();
  });

  it('T016 的 isTBD 应为 true', () => {
    const detail = t0xxToTrainDetail('T016');
    expect(detail?.isTBD).toBe(true);
  });

  it('不存在的 T0XX 应返回 null', () => {
    expect(t0xxToTrain('T999')).toBeNull();
  });

  it('rationale 字段应包含同症候标记', () => {
    const detail = t0xxToTrainDetail('T011');
    expect(detail?.rationale).toContain('P001');
  });
});

describe('TRAIN-PXXX → T0XX 反向映射', () => {
  it('TRAIN-P001-001 应映射到 T011', () => {
    expect(trainToT0xx('TRAIN-P001-001')).toBe('T011');
  });

  it('TRAIN-P002-003 应返回 null（无对应 T0XX，孤儿）', () => {
    expect(trainToT0xx('TRAIN-P002-003')).toBeNull();
  });

  it('TRAIN-P003-001 应映射到 T001', () => {
    expect(trainToT0xx('TRAIN-P003-001')).toBe('T001');
  });
});

describe('TRAIN-PXXX → CH-PXXX 映射', () => {
  it('TRAIN-P001-001 应关联 CH-P001-001 和 CH-P001-003', () => {
    const chs = trainToChallenges('TRAIN-P001-001');
    expect(chs).toContain('CH-P001-001');
    expect(chs).toContain('CH-P001-003');
  });

  it('TRAIN-P002-001 应精确匹配 CH-P002-001', () => {
    const chs = trainToChallenges('TRAIN-P002-001');
    expect(chs).toEqual(['CH-P002-001']);
  });

  it('TRAIN-P001-002 应只关联 CH-P001-002', () => {
    const chs = trainToChallenges('TRAIN-P001-002');
    expect(chs).toEqual(['CH-P001-002']);
  });

  it('不存在的 TRAIN 应返回空数组', () => {
    expect(trainToChallenges('TRAIN-P999-999')).toEqual([]);
  });
});

describe('CH-PXXX → TRAIN-PXXX 反向映射', () => {
  it('CH-P001-001 应映射到 TRAIN-P001-001', () => {
    expect(challengeToTrains('CH-P001-001')).toContain('TRAIN-P001-001');
  });

  it('CH-P001-003 应映射到 TRAIN-P001-001（共享一个训练任务）', () => {
    expect(challengeToTrains('CH-P001-003')).toContain('TRAIN-P001-001');
  });

  it('CH-P008-001 应返回空数组（P008 孤儿）', () => {
    expect(challengeToTrains('CH-P008-001')).toEqual([]);
  });
});

describe('症候级映射', () => {
  it('P001 应有 2 个 T0XX + 2 个 TRAIN + 3 个 CH', () => {
    const m = getSyndromeMapping('P001');
    expect(m?.T0XX).toHaveLength(2);
    expect(m?.TRAIN_PXXX).toHaveLength(2);
    expect(m?.CH_PXXX).toHaveLength(3);
  });

  it('P008 应是孤儿症候（无 T0XX/TRAIN，仅有 CH）', () => {
    const m = getSyndromeMapping('P008');
    expect(m?.T0XX).toEqual([]);
    expect(m?.TRAIN_PXXX).toEqual([]);
    expect(m?.CH_PXXX).toHaveLength(4);
    expect(m?.note).toContain('孤儿');
  });

  it('不存在的症候应返回 null', () => {
    expect(getSyndromeMapping('P999')).toBeNull();
  });
});

describe('PRAC-XXX 通用任务', () => {
  it('PRAC-WORD-001 应关联 P003（精准表达）', () => {
    expect(pracToSyndrome('PRAC-WORD-001')).toBe('P003');
  });

  it('PRAC-EYE-001 应关联 P007（阅读素养）', () => {
    expect(pracToSyndrome('PRAC-EYE-001')).toBe('P007');
  });

  it('PRAC-STRUCT-001 应关联 P006（结构控制）', () => {
    expect(pracToSyndrome('PRAC-STRUCT-001')).toBe('P006');
  });

  it('不存在的 PRAC 应返回 null', () => {
    expect(pracToSyndrome('PRAC-999-999')).toBeNull();
  });
});

describe('孤儿项追踪', () => {
  it('应识别 T016 为孤儿 T0XX', () => {
    const orphans = getOrphanT0XX();
    expect(orphans.find(o => o.id === 'T016')).toBeDefined();
  });

  it('应识别 TRAIN-P002-003 和 TRAIN-P003-003 为孤儿 TRAIN', () => {
    const orphans = getOrphanTRAIN();
    const ids = orphans.map(o => o.id);
    expect(ids).toContain('TRAIN-P002-003');
    expect(ids).toContain('TRAIN-P003-003');
  });

  it('应识别 CH-P008-* 为孤儿 CH', () => {
    const orphans = getOrphanChallenges();
    expect(orphans.length).toBeGreaterThanOrEqual(4);
    orphans.forEach(o => expect(o.id).toMatch(/^CH-P008-/));
  });

  it('应识别 P008 为孤儿症候', () => {
    const orphans = getOrphanSyndromes();
    expect(orphans[0]?.id).toBe('P008');
    expect(orphans[0]?.presentIn.CH_PXXX).toBe(true);
    expect(orphans[0]?.presentIn.T0XX).toBe(false);
    expect(orphans[0]?.presentIn.TRAIN_PXXX).toBe(false);
  });
});

describe('映射完整性校验', () => {
  it('validateMappingIntegrity 应通过', () => {
    const result = validateMappingIntegrity();
    expect(result.isComplete).toBe(true);
    expect(result.issues).toEqual([]);
  });
});

describe('统计信息', () => {
  it('T0XX 应为 20 条', () => {
    expect(getStatistics().T0XX).toBe(20);
  });

  it('TRAIN_PXXX 应为 21 条', () => {
    expect(getStatistics().TRAIN_PXXX).toBe(21);
  });

  it('CH_PXXX 应为 31 条', () => {
    expect(getStatistics().CH_PXXX).toBe(31);
  });

  it('应有 10 个症候覆盖 + 1 个孤儿症候', () => {
    const stats = getStatistics();
    expect(stats.syndromesCovered).toBe(10);
    expect(stats.orphanSyndromes).toBe(1);
  });
});

describe('T0XX → TRAIN 单向一致性（每个 T0XX 最多对应 1 个 TRAIN）', () => {
  it('所有 20 条 T0XX 映射合计应有 19 个非 TBD 映射', () => {
    const data = [
      'T001', 'T002', 'T003', 'T004', 'T005', 'T006', 'T007', 'T008',
      'T009', 'T010', 'T011', 'T012', 'T013', 'T014', 'T015', 'T016',
      'T017', 'T018', 'T019', 'T020',
    ];
    let mapped = 0;
    for (const t of data) {
      if (t0xxToTrain(t) !== null) mapped++;
    }
    expect(mapped).toBe(19); // T016 是 TBD
  });
});
