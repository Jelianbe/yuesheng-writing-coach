/**
 * ability.store.ts — 用户能力画像管理
 *
 * 职责:
 * - 通过 serviceBridge 拉取用户能力画像(按 sessionId)
 * - 缓存最近一次拉取的 profile
 * - 提供 selector 供 UI 消费
 *
 * 数据契约:src/shared/api-contracts/ability.contract.ts
 * 调用:`serviceBridge.invoke('ability:getProfile', { sessionId })` (Sprint 26 阶段 3.5 方案 4a)
 */

import { create } from 'zustand';
import { serviceBridge } from '../services/service-bridge';
import type {
  AbilityProfile,
} from '../../shared/api-contracts/ability.contract';

interface AbilityState {
  profile: AbilityProfile | null;
  loading: boolean;
  error: string | null;
}

interface AbilityActions {
  /** 拉取指定 session 的能力画像 */
  fetchProfile: (sessionId: string) => Promise<AbilityProfile | null>;
  /** 清空画像(切换 session 时调用) */
  reset: () => void;
}

export const useAbilityStore = create<AbilityState & AbilityActions>((set) => ({
  profile: null,
  loading: false,
  error: null,

  fetchProfile: async (sessionId: string) => {
    set({ loading: true, error: null });
    // Sprint 26 阶段 3.5 方案 4a: 走单端点 bridge,不用 per-channel IPC
    const result = await serviceBridge.invoke<{ sessionId: string }, { profile: AbilityProfile | null }>(
      'ability:getProfile',
      { sessionId },
    );
    if (result?.profile) {
      set({ profile: result.profile, loading: false });
      return result.profile;
    }
    set({ profile: null, loading: false });
    return null;
  },

  reset: () => set({ profile: null, error: null }),
}));
