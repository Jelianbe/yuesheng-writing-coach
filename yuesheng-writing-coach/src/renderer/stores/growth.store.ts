/**
 * growth.store.ts — 成长趋势管理
 *
 * 职责:
 * - 通过 service-bridge 单端点调用 growth:getGlobalTrends 拉取能力趋势
 * - 缓存 trends 与 global 状态
 *
 * 数据契约:src/shared/api-contracts/growth.contract.ts
 * 调用:serviceBridge.invoke('growth:getGlobalTrends', {}) (Sprint 26 阶段 3.6)
 */

import { create } from 'zustand';
import { serviceBridge } from '../services/service-bridge';
import type {
  GrowthGetGlobalTrendsResponse,
  GrowthGlobalSyndromeTrend,
} from '../../shared/api-contracts/growth.contract';

interface GrowthState {
  trends: GrowthGlobalSyndromeTrend[];
  global: GrowthGetGlobalTrendsResponse['overall'] | null;
  loading: boolean;
  error: string | null;
}

interface GrowthActions {
  fetchGlobalTrends: () => Promise<GrowthGetGlobalTrendsResponse['overall'] | null>;
  reset: () => void;
}

export const useGrowthStore = create<GrowthState & GrowthActions>((set) => ({
  trends: [],
  global: null,
  loading: false,
  error: null,

  fetchGlobalTrends: async () => {
    set({ loading: true, error: null });
    const data = await serviceBridge.invoke<Record<string, never>, GrowthGetGlobalTrendsResponse>(
      'growth:getGlobalTrends',
      {},
    );
    if (data) {
      set({ global: data.overall, trends: data.trends, loading: false });
      return data.overall;
    }
    set({ loading: false });
    return null;
  },

  reset: () => set({ trends: [], global: null, error: null }),
}));
