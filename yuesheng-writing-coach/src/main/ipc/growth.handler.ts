/**
 * 成长趋势 IPC 处理器
 * 负责：前端学习日志工具查询症候成长趋势
 * 依赖：GrowthTrendService
 */

import { IPC_CHANNELS } from '../../shared/constants';
import type { GrowthTrendService } from '../domains/02-prescription/student/growth-trend.service';
import { createHandler } from './utils/create-handler';

export interface GrowthHandlerDeps {
  growthTrendService: GrowthTrendService;
}

let deps: GrowthHandlerDeps | null = null;

export function initGrowthHandlers(d: GrowthHandlerDeps): void {
  deps = d;
}

/**
 * 注册成长趋势相关的 IPC 处理器
 */
export function registerGrowthHandlers(): void {
  createHandler(IPC_CHANNELS.GROWTH_GET_TRENDS, async (_event, args: { sessionId?: string }) => {
    if (!deps) {
      console.warn('[GrowthHandler] Deps not initialized');
      throw new Error('GrowthHandler deps not initialized');
    }
    const summary = deps.growthTrendService.getGrowthSummary(args.sessionId);
    return summary;
  });

  createHandler(IPC_CHANNELS.GROWTH_GET_GLOBAL_TRENDS, async () => {
    if (!deps) {
      console.warn('[GrowthHandler] Deps not initialized');
      throw new Error('GrowthHandler deps not initialized');
    }
    const summary = deps.growthTrendService.getGrowthSummary();
    return {
      overall: {
        averageScore: summary.masteredCount > 0 ? Math.round((summary.masteredCount / (summary.trends.length || 1)) * 100) / 100 : 0,
        totalInstances: summary.trends.length,
        topGainers: summary.trends.filter(t => t.status === 'mastered').map(t => t.name),
        topLosers: summary.trends.filter(t => t.status === 'needsAttention').map(t => t.name),
      },
    };
  });
}
