/**
 * TrainingRecommendationService 单元测试
 *
 * 验证：
 * 1. 只推荐 L2+ 症候
 * 2. 按严重度排序
 * 3. 症候与挑战模板正确匹配
 * 4. 无匹配模板时使用 fallback
 */

import { describe, it, expect } from 'vitest';
import { generateRecommendations, getChallengeTemplate, getAllChallengeTemplates } from '../training-recommendation.service';
import type { ActiveProblem } from '../../../renderer/shared/types';

// === 测试数据 ===

function makeProblem(
  id: string,
  severity: 'L1' | 'L2' | 'L3',
  name: string,
): ActiveProblem {
  return {
    id,
    name,
    severity,
    evidence: [],
    firstDetected: '2026-01-01',
    status: 'active',
    detectionCount: 1,
    missedCount: 0,
    suggestedActions: [],
  };
}

// === generateRecommendations 测试 ===

describe('generateRecommendations', () => {
  it('should only recommend L2+ syndromes', () => {
    const problems: ActiveProblem[] = [
      makeProblem('P001', 'L1', '世界观膨胀'), // 已改善，不推荐
      makeProblem('P002', 'L2', '角色工具人化'),
      makeProblem('P003', 'L3', '情绪标签化'),
    ];

    const recommendations = generateRecommendations(problems);

    expect(recommendations).toHaveLength(2);
    expect(recommendations[0].syndromeId).toBe('P003'); // L3 优先
    expect(recommendations[1].syndromeId).toBe('P002'); // L2
  });

  it('should return empty array when no eligible syndromes', () => {
    const problems: ActiveProblem[] = [
      makeProblem('P001', 'L1', '世界观膨胀'),
      makeProblem('P002', 'L1', '角色工具人化'),
    ];

    const recommendations = generateRecommendations(problems);

    expect(recommendations).toHaveLength(0);
  });

  it('should sort by severity (L3 > L2) and then by syndromeId', () => {
    const problems: ActiveProblem[] = [
      makeProblem('P005', 'L2', '视角漂移'),
      makeProblem('P001', 'L3', '世界观膨胀'),
      makeProblem('P003', 'L2', '情绪标签化'),
      makeProblem('P002', 'L3', '角色工具人化'),
    ];

    const recommendations = generateRecommendations(problems);

    // L3 在前，同严重度按 ID 排序
    expect(recommendations[0].syndromeId).toBe('P001'); // L3
    expect(recommendations[1].syndromeId).toBe('P002'); // L3
    expect(recommendations[2].syndromeId).toBe('P003'); // L2
    expect(recommendations[3].syndromeId).toBe('P005'); // L2
  });

  it('should match syndrome to correct challenge template', () => {
    const problems: ActiveProblem[] = [
      makeProblem('P001', 'L2', '世界观膨胀'),
    ];

    const recommendations = generateRecommendations(problems);

    expect(recommendations).toHaveLength(1);
    expect(recommendations[0].challengeId).toBe('CH-P001-001');
    expect(recommendations[0].mode).toBe('narrow_focus');
    expect(recommendations[0].tier).toBe('structural');
    expect(recommendations[0].constraint).toContain('只能保留一个具体场景');
  });

  it('should use fallback challenge when no matching template', () => {
    const problems: ActiveProblem[] = [
      makeProblem('P999', 'L2', '未知症候'),
    ];

    const recommendations = generateRecommendations(problems);

    expect(recommendations).toHaveLength(1);
    expect(recommendations[0].challengeId).toBe('CH-FALLBACK');
    expect(recommendations[0].mode).toBe('generic');
    expect(recommendations[0].syndromeId).toBe('P999');
  });

  it('should include all required fields in recommendation', () => {
    const problems: ActiveProblem[] = [
      makeProblem('P001', 'L2', '世界观膨胀'),
    ];

    const recommendations = generateRecommendations(problems);
    const rec = recommendations[0];

    expect(rec).toHaveProperty('challengeId');
    expect(rec).toHaveProperty('challengeName');
    expect(rec).toHaveProperty('description');
    expect(rec).toHaveProperty('syndromeId');
    expect(rec).toHaveProperty('severity');
    expect(rec).toHaveProperty('tier');
    expect(rec).toHaveProperty('constraint');
    expect(rec).toHaveProperty('expectedOutcome');
    expect(rec).toHaveProperty('mode');
  });

  it('should handle empty input', () => {
    const recommendations = generateRecommendations([]);
    expect(recommendations).toHaveLength(0);
  });
});

// === getChallengeTemplate 测试 ===

describe('getChallengeTemplate', () => {
  it('should return template by challengeId', () => {
    const template = getChallengeTemplate('CH-P001-001');
    expect(template).not.toBeNull();
    expect(template!.syndromeId).toBe('P001');
    expect(template!.mode).toBe('narrow_focus');
  });

  it('should return null for unknown challengeId', () => {
    const template = getChallengeTemplate('CH-UNKNOWN');
    expect(template).toBeNull();
  });
});

// === getAllChallengeTemplates 测试 ===

describe('getAllChallengeTemplates', () => {
  it('should return all templates', () => {
    const templates = getAllChallengeTemplates();
    expect(templates.length).toBeGreaterThanOrEqual(9);
  });

  it('should not return a mutable reference', () => {
    const t1 = getAllChallengeTemplates();
    const t2 = getAllChallengeTemplates();
    expect(t1).not.toBe(t2);
  });
});
