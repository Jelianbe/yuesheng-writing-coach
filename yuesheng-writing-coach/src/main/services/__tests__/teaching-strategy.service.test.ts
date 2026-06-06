/**
 * TeachingStrategyService 单元测试
 *
 * 测试覆盖：
 * 1. 教学模式决策规则
 * 2. 语气决策逻辑
 * 3. 配置加载和降级
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';

import * as path from 'path';

import { TeachingStrategyService, StrategyInput } from '../teaching-strategy.service';

const RESOURCES_ROOT = path.join(process.cwd(), 'resources');

describe('TeachingStrategyService', () => {
  let service: TeachingStrategyService;

  beforeEach(() => {
    service = new TeachingStrategyService(RESOURCES_ROOT);
    service.clearCache();
  });

  describe('decideMode', () => {
    const makeInput = (overrides: Partial<StrategyInput> = {}): StrategyInput => ({
      proficiency: 'intermediate',
      cognitiveStyle: 'mixed',
      topSyndromeCount: 1,
      frustrationIndex: 0,
      ...overrides,
    });

    it('should return scaffolding for frustrated users (frustrationIndex >= 0.6)', () => {
      const result = service.decide(makeInput({ frustrationIndex: 0.7 }));
      expect(result.mode).toBe('scaffolding');
    });

    it('should return scaffolding for repeated failures (topSyndromeCount >= 3)', () => {
      const result = service.decide(makeInput({ topSyndromeCount: 4 }));
      expect(result.mode).toBe('scaffolding');
    });

    it('should return scaffolding for beginners', () => {
      const result = service.decide(makeInput({ proficiency: 'beginner' }));
      expect(result.mode).toBe('scaffolding');
    });

    it('should return guiding for intermediate users by default', () => {
      const result = service.decide(makeInput({ proficiency: 'intermediate' }));
      expect(result.mode).toBe('guiding');
    });

    it('should return challenging for advanced users', () => {
      const result = service.decide(makeInput({ proficiency: 'advanced' }));
      expect(result.mode).toBe('challenging');
    });

    it('should prioritize frustration over other rules', () => {
      // Advanced user but highly frustrated → should still get scaffolding
      const result = service.decide(makeInput({
        proficiency: 'advanced',
        frustrationIndex: 0.8,
      }));
      expect(result.mode).toBe('scaffolding');
    });
  });

  describe('decideTone', () => {
    const makeInput = (overrides: Partial<StrategyInput> = {}): StrategyInput => ({
      proficiency: 'intermediate',
      cognitiveStyle: 'mixed',
      topSyndromeCount: 1,
      frustrationIndex: 0,
      ...overrides,
    });

    it('should return encouraging tone for beginners', () => {
      const result = service.decide(makeInput({ proficiency: 'beginner' }));
      expect(result.tone).toBe('encouraging');
    });

    it('should return direct tone for advanced users', () => {
      const result = service.decide(makeInput({ proficiency: 'advanced' }));
      expect(result.tone).toBe('direct');
    });

    it('should return logical tone for analytical style', () => {
      const result = service.decide(makeInput({ cognitiveStyle: 'analytical' }));
      expect(result.tone).toBe('logical');
    });

    it('should return resonant tone for emotional style', () => {
      const result = service.decide(makeInput({ cognitiveStyle: 'emotional' }));
      expect(result.tone).toBe('resonant');
    });
  });

  describe('decideFormat', () => {
    const makeInput = (overrides: Partial<StrategyInput> = {}): StrategyInput => ({
      proficiency: 'intermediate',
      cognitiveStyle: 'mixed',
      topSyndromeCount: 1,
      frustrationIndex: 0,
      ...overrides,
    });

    it('should return problem→cause→evidence→solution for analytical style', () => {
      const result = service.decide(makeInput({ cognitiveStyle: 'analytical' }));
      expect(result.format).toBe('problem→cause→evidence→solution');
    });

    it('should return example→feeling→demonstration for emotional style', () => {
      const result = service.decide(makeInput({ cognitiveStyle: 'emotional' }));
      expect(result.format).toBe('example→feeling→demonstration');
    });

    it('should return undefined for mixed style', () => {
      const result = service.decide(makeInput({ cognitiveStyle: 'mixed' }));
      expect(result.format).toBeUndefined();
    });
  });
});
