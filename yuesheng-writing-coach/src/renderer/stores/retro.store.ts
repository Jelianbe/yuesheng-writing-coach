/**
 * retro.store.ts — 复盘数据管理
 *
 * 职责:
 * - retro:generate 拉取复盘摘要
 * - retro:save 持久化复盘
 *
 * 数据契约:src/shared/api-contracts/retro.contract.ts
 * D-DEBT-33:training.store.enterRetro 后续迁移到此处
 */

import { create } from 'zustand';
import { IPC_CHANNELS } from '../shared/constants';
import { typedInvoke } from '../services/ipc-client';
import type {
  RetroGenerateRequest,
  RetroGenerateResponse,
  RetroSaveRequest,
  RetroSaveResponse,
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
    try {
      const payload: RetroGenerateRequest = { sessionId };
      const res = await typedInvoke<RetroGenerateRequest, RetroGenerateResponse>(
        IPC_CHANNELS.RETRO_GENERATE,
        payload,
      );
      if (res.success && res.data) {
        set({ summary: res.data, loading: false });
        return res.data;
      }
      set({ loading: false, error: !res.success ? res.error : '复盘数据为空' });
      return null;
    } catch (err) {
      set({ error: err instanceof Error ? err.message : '生成复盘异常', loading: false });
      return null;
    }
  },

  save: async (input) => {
    set({ saving: true, error: null });
    try {
      const res = await typedInvoke<RetroSaveRequest, RetroSaveResponse>(
        IPC_CHANNELS.RETRO_SAVE,
        input,
      );
      if (res.success) {
        set({ saving: false });
        return true;
      }
      set({ saving: false, error: res.error || '保存复盘失败' });
      return false;
    } catch (err) {
      set({ error: err instanceof Error ? err.message : '保存复盘异常', saving: false });
      return false;
    }
  },

  reset: () => set({ summary: null, error: null }),
}));
