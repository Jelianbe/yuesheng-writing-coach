/**
 * PromptBuilder 单元测试
 *
 * 测试覆盖：
 * 1. 基础教学进度构建（无策略决策）
 * 2. 策略决策注入（模式、语气、格式）
 * 3. 优先级问题注入
 * 4. 聚焦方向指令
 * 5. 组合场景（策略 + 优先级问题 + 聚焦方向）
 */

import { describe, it, expect, beforeEach } from 'vitest';
import { PromptBuilder, StrategyPromptOptions } from '../prompt-builder';
import { TeachingState } from '../teaching-state.types';
import type { TeachingStrategyDecision } from '../teaching-strategy.service';
import type { PrioritizedProblem } from '../problem-prioritizer.service';

describe('PromptBuilder', () => {
  let builder: PromptBuilder;

  const makeState = (overrides: Partial<TeachingState> = {}): TeachingState => ({
    sessionId: 'test-session',
    currentPhase: 'P1_WORLD',
    currentSubphase: 'S1_1_INIT',
    completedActions: ['A001'],
    completedTasks: [],
    activeProblems: [
      { id: 'P001', name: '世界观膨胀', severity: 'L2', evidence: ['test'], firstDetected: '2026-01-01', status: 'active', detectionCount: 1, missedCount: 0, suggestedActions: [] },
    ],
    nextSuggestedActions: ['A002'],
    currentTaskId: null,
    diagnosisSummary: '',
    lastUserConfirmation: null,
    focusArea: 'general',
    transitionOffered: false,
    lockedSyndromes: [],
    updatedAt: '2026-01-01',
    ...overrides,
  });

  const makeStrategyDecision = (overrides: Partial<TeachingStrategyDecision> = {}): TeachingStrategyDecision => ({
    mode: 'scaffolding',
    tone: 'encouraging',
    ...overrides,
  });

  const makePrioritizedProblems = (): PrioritizedProblem[] => [
    {
      syndromeId: 'P009',
      name: '角色动机缺失',
      tier: 'fatal',
      action: 'must_fix',
      tierLabel: '致命伤',
      occurrenceCount: 1,
      severityHistory: ['L3'],
    },
  ];

  beforeEach(() => {
    builder = new PromptBuilder();
  });

  describe('buildSystemPrompt — basic (no strategy)', () => {
    it('should build system prompt with teaching progress', () => {
      const result = builder.buildSystemPrompt(
        makeState(),
        (id) => id,
        (id) => `goal-${id}`,
        (id) => id,
      );

      expect(result).toContain('【当前教学进度】');
      expect(result).toContain('世界观搭建');
    });

    it('should include completed actions', () => {
      const result = builder.buildSystemPrompt(
        makeState(),
        (id) => id,
        (id) => `goal-${id}`,
        (id) => id,
      );

      expect(result).toContain('A001');
      expect(result).toContain('goal-A001');
    });

    it('should include active problems', () => {
      const result = builder.buildSystemPrompt(
        makeState(),
        (id) => id,
        (id) => `goal-${id}`,
        (id) => id,
      );

      expect(result).toContain('P001');
      expect(result).toContain('活跃');
    });

    it('should include next suggested actions', () => {
      const result = builder.buildSystemPrompt(
        makeState(),
        (id) => id,
        (id) => `goal-${id}`,
        (id) => id,
      );

      expect(result).toContain('A002');
    });
  });

  describe('buildSystemPrompt — with strategy decision', () => {
    it('should include strategy section when strategyDecision is provided', () => {
      const options: StrategyPromptOptions = {
        strategyDecision: makeStrategyDecision(),
      };

      const result = builder.buildSystemPrompt(
        makeState(),
        (id) => id,
        (id) => `goal-${id}`,
        (id) => id,
        options,
      );

      expect(result).toContain('【教学策略指令】');
      expect(result).toContain('支架模式');
      expect(result).toContain('鼓励的语气');
    });

    it('should include guiding mode instruction', () => {
      const options: StrategyPromptOptions = {
        strategyDecision: makeStrategyDecision({ mode: 'guiding', tone: 'direct' }),
      };

      const result = builder.buildSystemPrompt(
        makeState(),
        (id) => id,
        (id) => `goal-${id}`,
        (id) => id,
        options,
      );

      expect(result).toContain('引导模式');
      expect(result).toContain('直接简洁的语气');
    });

    it('should include challenging mode instruction', () => {
      const options: StrategyPromptOptions = {
        strategyDecision: makeStrategyDecision({ mode: 'challenging', tone: 'logical' }),
      };

      const result = builder.buildSystemPrompt(
        makeState(),
        (id) => id,
        (id) => `goal-${id}`,
        (id) => id,
        options,
      );

      expect(result).toContain('挑战模式');
      expect(result).toContain('逻辑化的语气');
    });

    it('should include format instruction when provided', () => {
      const options: StrategyPromptOptions = {
        strategyDecision: makeStrategyDecision({
          mode: 'scaffolding',
          tone: 'direct',
          format: 'problem→cause→evidence→solution',
        }),
      };

      const result = builder.buildSystemPrompt(
        makeState(),
        (id) => id,
        (id) => `goal-${id}`,
        (id) => id,
        options,
      );

      expect(result).toContain('问题→原因→证据→解决方案');
    });

    it('should include resonant tone and example format for emotional style', () => {
      const options: StrategyPromptOptions = {
        strategyDecision: makeStrategyDecision({
          mode: 'guiding',
          tone: 'resonant',
          format: 'example→feeling→demonstration',
        }),
      };

      const result = builder.buildSystemPrompt(
        makeState(),
        (id) => id,
        (id) => `goal-${id}`,
        (id) => id,
        options,
      );

      expect(result).toContain('共鸣的语气');
      expect(result).toContain('案例→感受→示范');
    });
  });

  describe('buildSystemPrompt — with prioritized problems', () => {
    it('should include highest priority problem', () => {
      const options: StrategyPromptOptions = {
        strategyDecision: makeStrategyDecision(),
        prioritizedProblems: makePrioritizedProblems(),
      };

      const result = builder.buildSystemPrompt(
        makeState(),
        (id) => id,
        (id) => `goal-${id}`,
        (id) => id,
        options,
      );

      expect(result).toContain('当前最高优先级问题');
      expect(result).toContain('致命伤');
      expect(result).toContain('P009');
      expect(result).toContain('角色动机缺失');
      expect(result).toContain('必须先修复');
    });

    it('should not include priority section when no problems provided', () => {
      const options: StrategyPromptOptions = {
        strategyDecision: makeStrategyDecision(),
      };

      const result = builder.buildSystemPrompt(
        makeState(),
        (id) => id,
        (id) => `goal-${id}`,
        (id) => id,
        options,
      );

      expect(result).not.toContain('当前最高优先级问题');
    });
  });

  describe('buildSystemPrompt — combined scenario', () => {
    it('should include all sections: strategy + problems + focus area', () => {
      const options: StrategyPromptOptions = {
        strategyDecision: makeStrategyDecision({
          mode: 'scaffolding',
          tone: 'encouraging',
          format: 'example→feeling→demonstration',
        }),
        prioritizedProblems: makePrioritizedProblems(),
      };

      const result = builder.buildSystemPrompt(
        makeState({ focusArea: 'worldbuilding' }),
        (id) => id,
        (id) => `goal-${id}`,
        (id) => id,
        options,
      );

      // Strategy section
      expect(result).toContain('【教学策略指令】');
      expect(result).toContain('支架模式');
      expect(result).toContain('鼓励的语气');
      expect(result).toContain('案例→感受→示范');

      // Priority problem
      expect(result).toContain('当前最高优先级问题');
      expect(result).toContain('致命伤');

      // Focus area
      expect(result).toContain('世界观构建');
    });
  });

  describe('buildSystemPrompt — backward compatibility', () => {
    it('should work without options parameter', () => {
      const result = builder.buildSystemPrompt(
        makeState(),
        (id) => id,
        (id) => `goal-${id}`,
        (id) => id,
      );

      expect(result).toContain('【当前教学进度】');
      expect(result).not.toContain('【教学策略指令】');
    });

    it('should work with empty options', () => {
      const result = builder.buildSystemPrompt(
        makeState(),
        (id) => id,
        (id) => `goal-${id}`,
        (id) => id,
        {},
      );

      expect(result).toContain('【当前教学进度】');
      expect(result).not.toContain('【教学策略指令】');
    });
  });
});
