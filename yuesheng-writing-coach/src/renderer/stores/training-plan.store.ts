/**
 * TrainingPlanStore — 自定义训练计划状态管理
 *
 * Sprint 38: 管理 training_plans 和 training_plan_items 的前端状态。
 * IPC 通道: plan:* (shared/constants.ts)
 */
import { create } from 'zustand';
import { serviceBridge } from '../services/service-bridge';
import type {
  TrainingPlanDTO,
  TrainingPlanWithItemsDTO,
  TrainingPlanItemDTO,
  AvailableChallengeDTO,
} from '../../shared/api-contracts/training-plan.contract';

interface TrainingPlanStoreState {
  // 数据
  plans: TrainingPlanDTO[];
  currentPlan: TrainingPlanWithItemsDTO | null;
  availableChallenges: AvailableChallengeDTO[];
  loading: boolean;
  error: string | null;

  // Actions
  fetchPlans: () => Promise<void>;
  fetchPlan: (planId: string) => Promise<void>;
  createPlan: (name: string, description?: string) => Promise<string | null>;
  deletePlan: (planId: string) => Promise<void>;
  addItem: (planId: string, challengeId: string) => Promise<void>;
  removeItem: (planId: string, itemId: string) => Promise<void>;
  updateItemStatus: (itemId: string, status: 'pending' | 'in_progress' | 'completed') => Promise<void>;
  fetchAvailableChallenges: () => Promise<void>;
  clearError: () => void;
}

export const useTrainingPlanStore = create<TrainingPlanStoreState>((set, get) => ({
  plans: [],
  currentPlan: null,
  availableChallenges: [],
  loading: false,
  error: null,

  fetchPlans: async () => {
    set({ loading: true, error: null });
    try {
      const data = await serviceBridge.invoke<Record<string, never>, TrainingPlanDTO[]>('plan:list', {});
      set({ plans: data ?? [], loading: false });
    } catch (err) {
      set({ error: String(err), loading: false });
    }
  },

  fetchPlan: async (planId: string) => {
    set({ loading: true, error: null });
    try {
      const data = await serviceBridge.invoke<{ planId: string }, TrainingPlanWithItemsDTO | null>('plan:get', { planId });
      set({ currentPlan: data, loading: false });
    } catch (err) {
      set({ error: String(err), loading: false });
    }
  },

  createPlan: async (name: string, description?: string) => {
    set({ loading: true, error: null });
    try {
      const data = await serviceBridge.invoke<{ name: string; description?: string }, { id: string }>(
        'plan:create', { name, description },
      );
      if (data?.id) {
        await get().fetchPlans();
        set({ loading: false });
        return data.id;
      }
      set({ loading: false });
      return null;
    } catch (err) {
      set({ error: String(err), loading: false });
      return null;
    }
  },

  deletePlan: async (planId: string) => {
    set({ loading: true, error: null });
    try {
      await serviceBridge.invoke<{ planId: string }, { success: boolean }>('plan:delete', { planId });
      set({ loading: false });
      await get().fetchPlans();
    } catch (err) {
      set({ error: String(err), loading: false });
    }
  },

  addItem: async (planId: string, challengeId: string) => {
    set({ error: null });
    try {
      await serviceBridge.invoke<{ planId: string; challengeId: string }, TrainingPlanItemDTO>(
        'plan:addItem', { planId, challengeId },
      );
      // 刷新当前计划
      await get().fetchPlan(planId);
    } catch (err) {
      set({ error: String(err) });
    }
  },

  removeItem: async (planId: string, itemId: string) => {
    set({ error: null });
    try {
      await serviceBridge.invoke<{ planId: string; itemId: string }, { success: boolean }>(
        'plan:removeItem', { planId, itemId },
      );
      await get().fetchPlan(planId);
    } catch (err) {
      set({ error: String(err) });
    }
  },

  updateItemStatus: async (itemId: string, status: 'pending' | 'in_progress' | 'completed') => {
    set({ error: null });
    try {
      await serviceBridge.invoke<{ itemId: string; status: string }, { success: boolean }>(
        'plan:updateItemStatus', { itemId, status },
      );
      const { currentPlan } = get();
      if (currentPlan) {
        await get().fetchPlan(currentPlan.id);
      }
    } catch (err) {
      set({ error: String(err) });
    }
  },

  fetchAvailableChallenges: async () => {
    try {
      const data = await serviceBridge.invoke<Record<string, never>, AvailableChallengeDTO[]>(
        'plan:getAvailableChallenges', {},
      );
      set({ availableChallenges: data ?? [] });
    } catch (err) {
      set({ error: String(err) });
    }
  },

  clearError: () => set({ error: null }),
}));
