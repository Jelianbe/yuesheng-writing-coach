/**
 * retro.store.ts — 复盘数据管理
 *
 * 职责:
 * - service-bridge 单端点调用 retro:generate 拉取复盘摘要
 * - service-bridge 单端点调用 retro:save 持久化复盘
 *
 * 数据契约:src/shared/api-contracts/retro.contract.ts
 * Sprint 26 阶段 3.6: 调用方迁移到 service-bridge
 * D-DEBT-33:training.store.enterRetro 后续迁移到此处
 */

import { create } from 'zustand';
import { serviceBridge } from '../services/service-bridge';
import type {
  RetroGenerateResponse,
  RetroSaveRequest,
} from '../../shared/api-contracts/retro.contract';

interface RetroState {
  summary: RetroGenerateResponse | null;
  saving: boolean;
  loading: boolean;
  error: string | null;
}

interface RetroActions {
  generate: (sessionId: string) => Promise<RetroGenerateResponse | null>;
  save: (input: RetroSaveRequest) => Promise<boolean>;
  reset: () => void;
}

export const useRetroStore = create<RetroState & RetroActions>((set) => ({
  summary: null,
  saving: false,
  loading: false,
  error: null,

  generate: async (sessionId) => {
    set({ loading: true, error: null });
    const data = await serviceBridge.invoke<{ sessionId: string }, RetroGenerateResponse>(
      'retro:generate',
      { sessionId },
    );
    if (data) {
      set({ summary: data, loading: false });
      return data;
    }
    set({ loading: false, error: '复盘数据为空' });
    return null;
  },

  save: async (input) => {
    set({ saving: true, error: null });
    const data = await serviceBridge.invoke<RetroSaveRequest, { saved: boolean }>(
      'retro:save',
      input,
    );
    if (data?.saved) {
      set({ saving: false });
      return true;
    }
    set({ saving: false, error: '保存复盘失败' });
    return false;
  },

  reset: () => set({ summary: null, error: null }),
}));
