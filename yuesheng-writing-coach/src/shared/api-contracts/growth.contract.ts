import type { ApiResponse } from './base';

// ─── 请求类型 ───

export interface GrowthGetTrendsRequest {
  sessionId: string;
  syndromeIds?: string[];
}

export interface GrowthGetGlobalTrendsRequest {
  /** empty — 获取全局趋势 */
}

// ─── 响应类型 ───

export interface GrowthTrendPoint {
  date: number;
  score: number;
  instances: number;
}

export interface GrowthTrend {
  syndromeId: string;
  points: GrowthTrendPoint[];
  direction: 'up' | 'down' | 'stable';
}

export interface GrowthGetTrendsResponse {
  trends: GrowthTrend[];
}

export interface GrowthGetGlobalTrendsResponse {
  overall: {
    averageScore: number;
    totalInstances: number;
    topGainers: string[];
    topLosers: string[];
  };
}

// ─── API 接口定义 ───

export const GrowthApi = {
  getTrends: {
    channel: 'growth:getTrends' as const,
    request: {} as GrowthGetTrendsRequest,
    response: {} as ApiResponse<GrowthGetTrendsResponse>,
  },

  getGlobalTrends: {
    channel: 'growth:getGlobalTrends' as const,
    request: {} as GrowthGetGlobalTrendsRequest,
    response: {} as ApiResponse<GrowthGetGlobalTrendsResponse>,
  },
} as const;

export type GrowthInvokeChannels =
  | typeof GrowthApi.getTrends.channel
  | typeof GrowthApi.getGlobalTrends.channel;
