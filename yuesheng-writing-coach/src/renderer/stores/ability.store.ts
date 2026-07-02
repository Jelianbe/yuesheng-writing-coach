/**
 * ability.store.ts — 用户能力画像管理
 *
 * 职责:
 * - 通过 ability:getProfile 通道拉取用户能力画像(按 sessionId)
 * - 缓存最近一次拉取的 profile
 * - 提供 selector 供 UI 消费
 *
 * 数据契约:src/shared/api-contracts/ability.contract.ts
 * 通道:IPC_CHANNELS.ABILITY_GET_PROFILE ('ability:getProfile')
 */

import { create } from 'zustand';
import { IPC_CHANNELS } from '../shared/constants';
import { typedInvoke } from '../services/ipc-client';
import type {
  AbilityGetProfileRequest,
  AbilityGetProfileResponse,
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
    try {
      const payload: AbilityGetProfileRequest = { sessionId };
      const res = await typedInvoke<AbilityGetProfileRequest, AbilityGetProfileResponse>(
        IPC_CHANNELS.ABILITY_GET_PROFILE,
        payload,
      );
      if (res.success && res.data) {
        set({ profile: res.data.profile, loading: false });
        return res.data.profile;
      }
      set({ profile: null, error: !res.success ? res.error : '画像为空', loading: false });
      return null;
    } catch (err) {
      set({ error: err instanceof Error ? err.message : '获取能力画像异常', loading: false });
      return null;
    }
  },

  reset: () => set({ profile: null, error: null }),
}));
