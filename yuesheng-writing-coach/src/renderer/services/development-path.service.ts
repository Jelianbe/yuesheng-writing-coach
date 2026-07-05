/**
 * 发展路径服务 — Sprint 32 (移除 serviceBridge/dual-track)
 *
 * 双轨迁移:
 * - Electron 端: typedInvoke → main handler
 * - Android 端: 暂不支持(无 shared 实现)
 *
 * 依据: dev-docs/tasks/sprint-32-plan.md
 */
import { invoke } from './_invoke';
import { isCapacitor } from './_platform';
import type { DevelopmentStageInfo } from '../../shared/api-contracts/prescription.contract';

export const developmentPathService = {
  /** 获取发展路径 — 失败时返回 null */
  async get(userId: string): Promise<Record<string, unknown> | null> {
    if (isCapacitor()) {
      console.warn('[dev-path] get: not supported on Capacitor');
      return null;
    }
    return invoke<Record<string, unknown>>('developmentPath:get', { userId }) ?? null;
  },

  /** 更新发展路径 — 失败时返回 null */
  async update(userId: string, data: Record<string, unknown>): Promise<Record<string, unknown> | null> {
    if (isCapacitor()) {
      console.warn('[dev-path] update: not supported on Capacitor');
      return null;
    }
    return invoke<Record<string, unknown>>('developmentPath:update', { userId, ...data }) ?? null;
  },

  /** 获取全部学习阶段 — 失败时返回 [] */
  async getAllStages(): Promise<DevelopmentStageInfo[]> {
    if (isCapacitor()) {
      console.warn('[dev-path] getAllStages: not supported on Capacitor');
      return [];
    }
    return (await invoke<DevelopmentStageInfo[]>('prescription:getAllStages', {})) ?? [];
  },

  /** 按 ID 获取学习阶段 — 失败时返回 null */
  async getStageById(stageId: string): Promise<DevelopmentStageInfo | null> {
    if (isCapacitor()) {
      console.warn('[dev-path] getStageById: not supported on Capacitor');
      return null;
    }
    return (await invoke<DevelopmentStageInfo>('prescription:getStageById', { stageId })) ?? null;
  },
};
