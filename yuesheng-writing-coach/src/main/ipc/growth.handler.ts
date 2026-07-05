/**
 * 成长趋势 — Sprint 26 阶段 3.5 方案 4a bridge 注册
 *
 * 原 IPC handler 已废弃,改为 registerMethod 走单端点 bridge:invoke。
 * 调用方:`serviceBridge.invoke('growth:getTrends' | 'growth:getGlobalTrends', ...)`
 *
 * 依赖: GrowthTrendService (DI 注入)
 */

import type { GrowthGlobalSyndromeTrend } from '../../shared/api-contracts/growth.contract';
import { validatePayload } from './utils/validate-payload';
import { registerMethod } from '../core/service-bridge';
import type { GrowthTrendService } from '../domains/02-prescription/student/growth-trend.service';

let growthTrendService: GrowthTrendService | null = null;

export function initGrowthHandlers(d: { growthTrendService: GrowthTrendService }): void {
  growthTrendService = d.growthTrendService;
}

export function registerGrowthHandlers(): void {
  registerMethod('growth:getTrends', async (args) => {
    const validation = validatePayload<{ sessionId?: string }>(args, {
      types: { sessionId: 'string' },
    });
    if (!validation.valid) {
      throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    }

    if (!growthTrendService) {
      throw new Error('GrowthTrendService not initialized');
    }
    return growthTrendService.getGrowthSummary(validation.data.sessionId);
  });

  registerMethod('growth:getGlobalTrends', async (_args) => {
    if (!growthTrendService) {
      throw new Error('GrowthTrendService not initialized');
    }
    const summary = growthTrendService.getGrowthSummary();
    const trends: GrowthGlobalSyndromeTrend[] = summary.trends.map(t => ({
      syndromeId: t.id,
      name: t.name,
      status: t.status,
      latestSeverity: t.latestSeverity,
      occurrenceCount: t.occurrenceCount,
      description: t.description,
    }));
    return {
      overall: {
        averageScore: summary.masteredCount > 0 ? Math.round((summary.masteredCount / (summary.trends.length || 1)) * 100) / 100 : 0,
        totalInstances: summary.trends.length,
        topGainers: summary.trends.filter(t => t.status === 'mastered').map(t => t.name),
        topLosers: summary.trends.filter(t => t.status === 'needsAttention').map(t => t.name),
      },
      trends,
    };
  });
}
