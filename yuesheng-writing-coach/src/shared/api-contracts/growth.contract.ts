import type { ApiResponse } from './base';

// ─── 请求类型 ───

export interface GrowthGetTrendsRequest {
  sessionId: string;
  syndromeIds?: string[];
}

/** empty — 获取全局趋势 */
export type GrowthGetGlobalTrendsRequest = Record<string, never>;

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

/** 全局趋势的单条症候趋势项(Sprint 19 Issue 19-3) */
export interface GrowthGlobalSyndromeTrend {
  syndromeId: string;
  name: string;
  status: 'mastered' | 'improving' | 'stable' | 'needsAttention';
  latestSeverity: 'L1' | 'L2' | 'L3' | null;
  occurrenceCount: number;
  description: string;
}

export interface GrowthGetGlobalTrendsResponse {
  overall: {
    averageScore: number;
    totalInstances: number;
    topGainers: string[];
    topLosers: string[];
  };
  /** 全局趋势下每个症候的明细(用于雷达图与症候列表渲染) */
  trends: GrowthGlobalSyndromeTrend[];
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
