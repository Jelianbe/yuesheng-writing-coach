/**
 * TrainingRecommendation Service 单元测试
 *
 * T15-C.5 覆盖：
 * - relatedTrainIds 字段补全
 * - abilityNodeIds / prerequisites / 难度 字段
 * - 去重 + 排序 + 至少 3 条 fallback 逻辑
 * - 阅读推荐（A3 链路）
 * - 阶段感知过滤（S8）
 */

import { describe, it, expect } from 'vitest';
import {
  generateRecommendations,
  getSyndromeType,
  getChallengeTemplate,
  getAllChallengeTemplates,
  getReadingRecommendations,
  shouldRecommendReading,
  filterRecommendationsByStage,
  getAllowedSyndromeIds,
  READING_RECOMMENDATION_THRESHOLD,
} from '../training-recommendation.service';
import type { ActiveProblem, DevelopmentStageInfo } from '../../../../../shared/types/index';

/** T15-C.5 stub 工厂：补齐 ActiveProblem 必需字段（避免因后续类型扩展反复改测试） */
function prob(id: string, severity: 'L1' | 'L2' | 'L3', name = id): ActiveProblem {
  return {
    id,
    name,
    severity,
    evidence: [],
    firstDetected: '2026-06-23T00:00:00.000Z',
    status: 'active',
    detectionCount: 1,
    missedCount: 0,
    suggestedActions: [],
  };
}

describe('getSyndromeType', () => {
  it('P001 属于 motivation_deficit', () => {
    expect(getSyndromeType('P001')).toBe('motivation_deficit');
  });

  it('P003 属于 expressive_deficit', () => {
    expect(getSyndromeType('P003')).toBe('expressive_deficit');
  });

  it('P005 属于 structural_disorder', () => {
    expect(getSyndromeType('P005')).toBe('structural_disorder');
  });

  it('不存在的症候应返回 null', () => {
    expect(getSyndromeType('P999')).toBeNull();
  });
});

describe('getChallengeTemplate / getAllChallengeTemplates', () => {
  it('getAllChallengeTemplates 应返回 31 条模板', () => {
    expect(getAllChallengeTemplates()).toHaveLength(31);
  });

  it('getChallengeTemplate 应能查到 CH-P001-001', () => {
    const tpl = getChallengeTemplate('CH-P001-001');
    expect(tpl?.id).toBe('CH-P001-001');
    expect(tpl?.syndromeId).toBe('P001');
  });

  it('不存在的挑战应返回 null', () => {
    expect(getChallengeTemplate('CH-XXX-999')).toBeNull();
  });
});

describe('generateRecommendations - 基础', () => {
  it('空 activeProblems 应返回空数组', () => {
    expect(generateRecommendations([])).toEqual([]);
  });

  it('L1 症候应被过滤（L1 不训练）', () => {
    const problems: ActiveProblem[] = [
      prob('P001', 'L1', '世界观膨胀'),
    ];
    expect(generateRecommendations(problems)).toEqual([]);
  });

  it('L2 症候应生成 1 条推荐', () => {
    const problems: ActiveProblem[] = [
      prob('P001', 'L2', '世界观膨胀'),
    ];
    const recs = generateRecommendations(problems);
    expect(recs).toHaveLength(1);
    expect(recs[0].syndromeId).toBe('P001');
    expect(recs[0].severity).toBe('L2');
  });
});

describe('generateRecommendations - T15-C.5: relatedTrainIds 字段', () => {
  it('P001 推荐应包含 relatedTrainIds（TRAIN-P001-001 等）', () => {
    const problems: ActiveProblem[] = [
      prob('P001', 'L2', '世界观膨胀'),
    ];
    const recs = generateRecommendations(problems);
    expect(recs[0].relatedTrainIds).toBeDefined();
    expect(recs[0].relatedTrainIds).toContain('TRAIN-P001-001');
  });

  it('P003 推荐应包含 relatedTrainIds（TRAIN-P003-001 等）', () => {
    const problems: ActiveProblem[] = [
      prob('P003', 'L2', '情绪标签化'),
    ];
    const recs = generateRecommendations(problems);
    expect(recs[0].relatedTrainIds).toContain('TRAIN-P003-001');
  });

  it('P004 推荐应包含 relatedTrainIds', () => {
    const problems: ActiveProblem[] = [
      prob('P004', 'L2', '信息硬塞'),
    ];
    const recs = generateRecommendations(problems);
    expect(recs[0].relatedTrainIds).toContain('TRAIN-P004-001');
  });

  it('fallback 推荐（无匹配模板）应有 relatedTrainIds: undefined', () => {
    const problems: ActiveProblem[] = [
      // 使用一个映射中无对应的 challenge
      prob('P999', 'L2', '未知症候'),
    ];
    const recs = generateRecommendations(problems);
    // P999 无匹配模板，应使用 fallback
    expect(recs[0].challengeId).toBe('CH-FALLBACK');
    expect(recs[0].relatedTrainIds).toBeUndefined();
  });
});

describe('generateRecommendations - S7: abilityNodeIds / prerequisites', () => {
  it('P001 推荐应包含 ABL-001（结构控制）和 ABL-005（世界观工程）', () => {
    const problems: ActiveProblem[] = [
      prob('P001', 'L2', '世界观膨胀'),
    ];
    const recs = generateRecommendations(problems);
    expect(recs[0].abilityNodeIds).toContain('ABL-001');
    expect(recs[0].abilityNodeIds).toContain('ABL-005');
  });

  it('P002 推荐应包含 ABL-003 / ABL-004', () => {
    const problems: ActiveProblem[] = [
      prob('P002', 'L2', '角色工具人化'),
    ];
    const recs = generateRecommendations(problems);
    expect(recs[0].abilityNodeIds).toContain('ABL-003');
  });

  it('ABL-001 应有前置能力 ABL-002', () => {
    const problems: ActiveProblem[] = [
      prob('P001', 'L2', '世界观膨胀'),
    ];
    const recs = generateRecommendations(problems);
    expect(recs[0].prerequisites).toContain('ABL-002');
  });
});

describe('generateRecommendations - 排序', () => {
  it('L3 应排在 L2 之前', () => {
    const problems: ActiveProblem[] = [
      prob('P002', 'L2', '角色工具人化'),
      prob('P003', 'L3', '情绪标签化'),
    ];
    const recs = generateRecommendations(problems);
    expect(recs[0].severity).toBe('L3');
    expect(recs[1].severity).toBe('L2');
  });

  it('同严重度按症候 ID 排序', () => {
    const problems: ActiveProblem[] = [
      prob('P003', 'L2', '情绪标签化'),
      prob('P001', 'L2', '世界观膨胀'),
    ];
    const recs = generateRecommendations(problems);
    expect(recs[0].syndromeId).toBe('P001');
    expect(recs[1].syndromeId).toBe('P003');
  });
});

describe('generateRecommendations - 去重', () => {
  it('重复 challengeId 应被去重', () => {
    const problems: ActiveProblem[] = [
      prob('P001', 'L2', '世界观膨胀'),
      prob('P001', 'L2', '世界观膨胀'),
    ];
    const recs = generateRecommendations(problems);
    // 应去重为 1 条
    const p001Recs = recs.filter(r => r.syndromeId === 'P001');
    expect(p001Recs).toHaveLength(1);
  });
});

describe('A3 阅读推荐', () => {
  it('getReadingRecommendations(P003) 应返回阅读列表', () => {
    const recs = getReadingRecommendations('P003');
    expect(Array.isArray(recs)).toBe(true);
  });

  it('READING_RECOMMENDATION_THRESHOLD 应为 7', () => {
    expect(READING_RECOMMENDATION_THRESHOLD).toBe(7);
  });

  it('shouldRecommendReading: score 8 应返回 true', () => {
    expect(shouldRecommendReading(8)).toBe(true);
  });

  it('shouldRecommendReading: score 5 应返回 false', () => {
    expect(shouldRecommendReading(5)).toBe(false);
  });

  it('shouldRecommendReading: score undefined 应返回 false', () => {
    expect(shouldRecommendReading(undefined)).toBe(false);
  });
});

describe('S8 阶段感知过滤', () => {
  it('空 allowedSyndromeIds 应返回原列表', () => {
    const recs = generateRecommendations([
      prob('P001', 'L2', '世界观膨胀'),
    ]);
    expect(filterRecommendationsByStage(recs, [])).toEqual(recs);
  });

  it('allowedSyndromeIds 应过滤推荐', () => {
    const recs = generateRecommendations([
      prob('P001', 'L2', '世界观膨胀'),
      prob('P003', 'L2', '情绪标签化'),
    ]);
    const filtered = filterRecommendationsByStage(recs, ['P001']);
    expect(filtered).toHaveLength(1);
    expect(filtered[0].syndromeId).toBe('P001');
  });

  it('getAllowedSyndromeIds 应返回 associatedSyndromes 数组', () => {
    const stage: DevelopmentStageInfo = {
      stageId: 'word',
      name: '表达阶段',
      order: 1,
      coreQuestion: '如何清晰表达',
      prerequisites: [],
      entryPractices: ['日记 200 字'],
      passCriteria: '连续 7 篇结构清晰',
      associatedSyndromes: ['P003', 'P010'],
      teachingFocus: '用动作和细节替代情绪标签',
    };
    const allowed = getAllowedSyndromeIds(stage);
    expect(allowed).toContain('P003');
    expect(allowed).toContain('P010');
  });
});

describe('T15-C.5 三向打通验证', () => {
  it('P002 推荐应同时包含 CH-PXXX / TRAIN-PXXX / ABL-XXX', () => {
    const problems: ActiveProblem[] = [
      prob('P002', 'L2', '角色工具人化'),
    ];
    const recs = generateRecommendations(problems);
    const r = recs[0];

    // 挑战层 (CH-PXXX)
    expect(r.challengeId).toMatch(/^CH-P\d{3}-\d{3}$/);

    // 任务层 (TRAIN-PXXX)
    expect(r.relatedTrainIds).toBeDefined();
    expect(r.relatedTrainIds?.every(id => /^TRAIN-P\d{3}-\d{3}$/.test(id))).toBe(true);

    // 能力层 (ABL-XXX)
    expect(r.abilityNodeIds).toBeDefined();
    expect(r.abilityNodeIds?.every(id => /^ABL-\d{3}$/.test(id))).toBe(true);
  });
});
