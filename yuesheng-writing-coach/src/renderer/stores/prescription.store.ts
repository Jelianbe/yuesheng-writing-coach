/**
 * prescription.store.ts — 学习阶段管理
 *
 * 职责:
 * - 拉取全部学习阶段列表 / 单个阶段 / 阶段进度
 *
 * 数据契约:src/shared/api-contracts/prescription.contract.ts
 *
 * Sprint 26 阶段 3.4 Z-1: fetchAllStages / fetchStageById 走双轨 service,
 * fetchStageProgress 仍走 IPC(依赖 DB mastery 数据,暂不直调)
 */

import { create } from 'zustand';
import { IPC_CHANNELS } from '../shared/constants';
import { typedInvoke } from '../services/ipc-client';
import { developmentPathService } from '../services/development-path.service';
import type {
  DevelopmentStageInfo,
  StageProgress,
} from '../../shared/types';
import type {
  PrescriptionGetStageProgressResponse,
} from '../../shared/api-contracts/prescription.contract';

interface PrescriptionState {
  allStages: DevelopmentStageInfo[];
  currentStage: DevelopmentStageInfo | null;
  stageProgress: StageProgress | null;
  loading: boolean;
  error: string | null;
}

interface PrescriptionActions {
  fetchAllStages: () => Promise<DevelopmentStageInfo[] | null>;
  fetchStageById: (stageId: string) => Promise<DevelopmentStageInfo | null>;
  fetchStageProgress: (sessionId: string) => Promise<PrescriptionGetStageProgressResponse | null>;
  reset: () => void;
}

export const usePrescriptionStore = create<PrescriptionState & PrescriptionActions>((set) => ({
  allStages: [],
  currentStage: null,
  stageProgress: null,
  loading: false,
  error: null,

  fetchAllStages: async () => {
    set({ loading: true, error: null });
    const stages = await developmentPathService.getAllStages();
    if (stages.length > 0) {
      set({ allStages: stages, loading: false });
      return stages;
    }
    set({ loading: false, error: '阶段列表为空' });
    return null;
  },

  fetchStageById: async (stageId) => {
    set({ loading: true, error: null });
    const stage = await developmentPathService.getStageById(stageId);
    if (stage) {
      set({ currentStage: stage, loading: false });
      return stage;
    }
    set({ loading: false, error: '阶段详情为空' });
    return null;
  },

  fetchStageProgress: async (sessionId) => {
    set({ loading: true, error: null });
    try {
      const res = await typedInvoke<{ sessionId: string }, PrescriptionGetStageProgressResponse>(
        IPC_CHANNELS.PRESCRIPTION_GET_STAGE_PROGRESS,
        { sessionId },
      );
      if (res.success && res.data) {
        set({
          currentStage: res.data.allStages?.find(s => s.stageId === res.data.currentStageId) ?? null,
          stageProgress: res.data.progress,
          allStages: res.data.allStages ?? [],
          loading: false,
        });
        return res.data;
      }
      set({ loading: false, error: !res.success ? res.error : '阶段进度为空' });
      return null;
    } catch (err) {
      set({ error: err instanceof Error ? err.message : '获取阶段进度异常', loading: false });
      return null;
    }
  },

  reset: () => set({ allStages: [], currentStage: null, stageProgress: null, error: null }),
}));
