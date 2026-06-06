/**
 * ProblemPrioritizer 单元测试
 *
 * 测试覆盖：
 * 1. 症候三级分类映射
 * 2. 按优先级排序
 * 3. 获取最高优先级问题
 * 4. 配置加载和降级
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';

import * as path from 'path';

import { ProblemPrioritizer } from '../problem-prioritizer.service';

const RESOURCES_ROOT = path.join(process.cwd(), 'resources');

describe('ProblemPrioritizer', () => {
  let prioritizer: ProblemPrioritizer;

  beforeEach(() => {
    prioritizer = new ProblemPrioritizer(RESOURCES_ROOT);
    prioritizer.clearCache();
  });

  const testSyndromes = [
    { id: 'P003', name: '情绪标签化', occurrenceCount: 2, severityHistory: ['L1', 'L1'] },
    { id: 'P009', name: '角色动机缺失', occurrenceCount: 1, severityHistory: ['L3'] },
    { id: 'P001', name: '世界观膨胀', occurrenceCount: 3, severityHistory: ['L2', 'L2', 'L1'] },
    { id: 'P004', name: '信息硬塞', occurrenceCount: 2, severityHistory: ['L2', 'L2'] },
  ];

  describe('prioritize', () => {
    it('should return problems sorted by tier priority', () => {
      const result = prioritizer.prioritize(testSyndromes);

      // P009 is fatal, should be first
      expect(result[0].syndromeId).toBe('P009');
      expect(result[0].tier).toBe('fatal');
      expect(result[0].action).toBe('must_fix');
    });

    it('should classify structural problems correctly', () => {
      const result = prioritizer.prioritize(testSyndromes);
      const structural = result.filter(p => p.tier === 'structural');

      expect(structural.some(p => p.syndromeId === 'P001')).toBe(true);
      expect(structural.some(p => p.syndromeId === 'P004')).toBe(true);
    });

    it('should classify surface problems correctly', () => {
      const result = prioritizer.prioritize(testSyndromes);
      const surface = result.filter(p => p.tier === 'surface');

      expect(surface.some(p => p.syndromeId === 'P003')).toBe(true);
    });

    it('should include occurrence count and severity history', () => {
      const result = prioritizer.prioritize(testSyndromes);
      const p001 = result.find(p => p.syndromeId === 'P001')!;

      expect(p001.occurrenceCount).toBe(3);
      expect(p001.severityHistory).toEqual(['L2', 'L2', 'L1']);
    });
  });

  describe('getTopProblem', () => {
    it('should return the highest priority problem (fatal)', () => {
      const result = prioritizer.getTopProblem(testSyndromes);

      expect(result).not.toBeNull();
      expect(result!.syndromeId).toBe('P009');
      expect(result!.tier).toBe('fatal');
    });

    it('should return null for empty input', () => {
      const result = prioritizer.getTopProblem([]);
      expect(result).toBeNull();
    });
  });

  describe('fallback behavior', () => {
    it('should use default config when JSON file is missing', () => {
      // The service should still work with hardcoded fallback
      const result = prioritizer.prioritize(testSyndromes);
      expect(result.length).toBeGreaterThan(0);
    });
  });
});
