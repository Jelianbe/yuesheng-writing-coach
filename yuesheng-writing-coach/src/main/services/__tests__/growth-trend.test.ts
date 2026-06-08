import { describe, it, expect, vi } from 'vitest';
import { GrowthTrendService } from '../growth-trend.service';
import { StudentModelService } from '../student-model.service';

// Mock StudentModelService
function makeMockStudentModelService(profile: Record<string, any>) {
  return {
    getSyndromeProfile: vi.fn(() => profile),
  } as unknown as StudentModelService;
}

function makeSyndromeAggregation(overrides: Partial<any> = {}): any {
  return {
    occurrenceCount: 1,
    latestSeverity: 'L2' as const,
    severityHistory: ['L2' as const],
    trend: 'stable' as const,
    lastSeenAt: '2026-06-05T00:00:00.000Z',
    sessionIds: ['session-1'],
    ...overrides,
  };
}

describe('GrowthTrendService', () => {
  describe('getSyndromeTrends', () => {
    it('应返回空数组当无诊断数据', () => {
      const mock = makeMockStudentModelService({});
      const service = new GrowthTrendService(mock);
      const trends = service.getSyndromeTrends();
      expect(trends).toEqual([]);
    });

    it('应正确计算稳定症候的状态', () => {
      const profile = {
        P001: makeSyndromeAggregation({
          occurrenceCount: 2,
          latestSeverity: 'L2',
          severityHistory: ['L2', 'L2'],
          trend: 'stable',
        }),
      };
      const mock = makeMockStudentModelService(profile);
      const service = new GrowthTrendService(mock);
      const trends = service.getSyndromeTrends();

      expect(trends).toHaveLength(1);
      expect(trends[0].id).toBe('P001');
      expect(trends[0].status).toBe('stable');
      expect(trends[0].latestSeverity).toBe('L2');
    });

    it('应正确计算进步症候的状态', () => {
      const profile = {
        P001: makeSyndromeAggregation({
          occurrenceCount: 3,
          latestSeverity: 'L1',
          severityHistory: ['L3', 'L2', 'L1'],
          trend: 'improving',
        }),
      };
      const mock = makeMockStudentModelService(profile);
      const service = new GrowthTrendService(mock);
      const trends = service.getSyndromeTrends();

      expect(trends).toHaveLength(1);
      expect(trends[0].id).toBe('P001');
      expect(trends[0].status).toBe('mastered');
      expect(trends[0].description).toContain('已掌握');
    });

    it('应正确计算需关注症候的状态（worsening）', () => {
      const profile = {
        P001: makeSyndromeAggregation({
          occurrenceCount: 3,
          latestSeverity: 'L3',
          severityHistory: ['L1', 'L2', 'L3'],
          trend: 'worsening',
        }),
      };
      const mock = makeMockStudentModelService(profile);
      const service = new GrowthTrendService(mock);
      const trends = service.getSyndromeTrends();

      expect(trends).toHaveLength(1);
      expect(trends[0].id).toBe('P001');
      expect(trends[0].status).toBe('needsAttention');
      expect(trends[0].description).toContain('需关注');
    });

    it('应正确计算需关注症候的状态（stable 但 L3）', () => {
      const profile = {
        P001: makeSyndromeAggregation({
          occurrenceCount: 2,
          latestSeverity: 'L3',
          severityHistory: ['L3', 'L3'],
          trend: 'stable',
        }),
      };
      const mock = makeMockStudentModelService(profile);
      const service = new GrowthTrendService(mock);
      const trends = service.getSyndromeTrends();

      expect(trends[0].status).toBe('needsAttention');
      expect(trends[0].description).toContain('严重');
    });

    it('应使用自定义名称映射', () => {
      const profile = {
        P001: makeSyndromeAggregation({
          occurrenceCount: 1,
          latestSeverity: 'L2',
          severityHistory: ['L2'],
          trend: 'stable',
        }),
      };
      const mock = makeMockStudentModelService(profile);
      const service = new GrowthTrendService(mock);
      const trends = service.getSyndromeTrends(undefined, (id) => (id === 'P001' ? '世界观膨胀' : id));

      expect(trends[0].name).toBe('世界观膨胀');
    });

    it('应包含出现次数和之前严重度', () => {
      const profile = {
        P001: makeSyndromeAggregation({
          occurrenceCount: 4,
          latestSeverity: 'L1',
          severityHistory: ['L3', 'L2', 'L2', 'L1'],
          trend: 'improving',
        }),
      };
      const mock = makeMockStudentModelService(profile);
      const service = new GrowthTrendService(mock);
      const trends = service.getSyndromeTrends();

      expect(trends[0].occurrenceCount).toBe(4);
      expect(trends[0].previousSeverity).toBe('L2');
    });
  });

  describe('getGrowthSummary', () => {
    it('应正确统计各状态数量', () => {
      const profile = {
        P001: makeSyndromeAggregation({
          occurrenceCount: 3,
          latestSeverity: 'L1',
          severityHistory: ['L3', 'L2', 'L1'],
          trend: 'improving',
        }),
        P002: makeSyndromeAggregation({
          occurrenceCount: 2,
          latestSeverity: 'L3',
          severityHistory: ['L1', 'L3'],
          trend: 'worsening',
        }),
        P003: makeSyndromeAggregation({
          occurrenceCount: 1,
          latestSeverity: 'L2',
          severityHistory: ['L2'],
          trend: 'stable',
        }),
        // P004: improving 但还未到 L1，保持 improving 状态
        P004: makeSyndromeAggregation({
          occurrenceCount: 2,
          latestSeverity: 'L2',
          severityHistory: ['L3', 'L2'],
          trend: 'improving',
        }),
      };
      const mock = makeMockStudentModelService(profile);
      const service = new GrowthTrendService(mock);
      const summary = service.getGrowthSummary();

      expect(summary.masteredCount).toBe(1); // P001
      expect(summary.improvingCount).toBe(1); // P004
      expect(summary.needsAttentionCount).toBe(1); // P002
      expect(summary.trends).toHaveLength(4);
    });
  });

  describe('多症候混合场景', () => {
    it('应正确处理多种状态混合', () => {
      const profile = {
        P001: makeSyndromeAggregation({
          occurrenceCount: 3,
          latestSeverity: 'L1',
          severityHistory: ['L3', 'L2', 'L1'],
          trend: 'improving',
        }),
        P002: makeSyndromeAggregation({
          occurrenceCount: 2,
          latestSeverity: 'L2',
          severityHistory: ['L2', 'L2'],
          trend: 'stable',
        }),
        P003: makeSyndromeAggregation({
          occurrenceCount: 2,
          latestSeverity: 'L1',
          severityHistory: ['L1', 'L1'],
          trend: 'stable',
        }),
        P004: makeSyndromeAggregation({
          occurrenceCount: 3,
          latestSeverity: 'L3',
          severityHistory: ['L1', 'L2', 'L3'],
          trend: 'worsening',
        }),
      };
      const mock = makeMockStudentModelService(profile);
      const service = new GrowthTrendService(mock);
      const summary = service.getGrowthSummary();

      // P001: mastered (improving + L1 + history>=3)
      // P002: stable (stable + L2)
      // P003: stable (stable + L1)
      // P004: needsAttention (worsening)
      expect(summary.masteredCount).toBe(1);
      expect(summary.improvingCount).toBe(0); // improving 被归类为 mastered
      expect(summary.needsAttentionCount).toBe(1);
      expect(summary.trends.filter((t) => t.status === 'stable')).toHaveLength(2);
    });
  });
});
