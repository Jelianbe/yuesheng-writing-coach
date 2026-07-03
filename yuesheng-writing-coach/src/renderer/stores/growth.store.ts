/**
 * growth.store.ts — 成长趋势管理
 *
 * 职责:
 * - 通过 growth:getTrends / growth:getGlobalTrends 拉取能力趋势
 * - 缓存 trends 与 global 状态
 *
 * 数据契约:src/shared/api-contracts/growth.contract.ts
 */

import { create } from 'zustand';
import { IPC_CHANNELS } from '../shared/constants';
import { typedInvoke } from '../services/ipc-client';
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
    try {
      const res = await typedInvoke<Record<string, never>, GrowthGetGlobalTrendsResponse>(
        IPC_CHANNELS.GROWTH_GET_GLOBAL_TRENDS,
        {},
      );
      if (res.success && res.data) {
        set({ global: res.data.overall, trends: res.data.trends, loading: false });
        return res.data.overall;
      }
      set({ loading: false, error: !res.success ? res.error : '全局趋势为空' });
      return null;
    } catch (err) {
      set({ error: err instanceof Error ? err.message : '获取全局趋势异常', loading: false });
      return null;
    }
  },

  reset: () => set({ trends: [], global: null, error: null }),
}));
