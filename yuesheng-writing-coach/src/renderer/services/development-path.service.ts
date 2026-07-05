/**
 * DevelopmentPath 双轨服务 — Sprint 26 阶段 3.4 Z-1
 *
 * 双轨实现(用 _dual-track.ts helper 统一调度):
 * - Android 端: 静态 import shared service,直接读 development-path.json
 * - Electron 端: 走 typedInvoke → main 进程 → 主进程 fs 版 service
 *
 * 失败处理: console.error + 返回 caller 提供的 fallback([]/null)
 *
 * 覆盖方法: getAllStages / getStageById (不覆盖 getCurrentStage 等依赖 DB 的方法)
 *
 * 依据: dev-docs/tasks/sprint-26-phase-3-plan.md §3.4 Z-1
 */
import { typedInvoke } from './ipc-client';
import { PrescriptionApi } from '../../shared/api-contracts/prescription.contract';
import type { DevelopmentStageInfo } from '../../shared/types/index';
import { developmentPathService as directService } from '../../shared/services/development-path.service';
import { isCapacitor, runDualTrack } from './_dual-track';

export const developmentPathService = {
  /** 获取所有发展阶段 — 失败时返回 [] */
  async getAllStages(): Promise<DevelopmentStageInfo[]> {
    if (isCapacitor()) {
      try {
        return directService.getAllStages();
      } catch (err) {
        console.error('[development-path] getAllStages failed (direct):', err);
        return [];
      }
    }
    return runDualTrack(undefined, {
      direct: async () => directService.getAllStages(),
      electron: async () => {
        const result = await typedInvoke<Record<string, never>, DevelopmentStageInfo[]>(
          PrescriptionApi.getAllStages,
          {},
        );
        if (!result.success) {
          console.error('[development-path] getAllStages failed:', result.error);
          return [];
        }
        return result.data;
      },
    });
  },

  /** 按 ID 查询阶段 — 失败时返回 null */
  async getStageById(stageId: string): Promise<DevelopmentStageInfo | null> {
    if (isCapacitor()) {
      try {
        return directService.getStageById(stageId);
      } catch (err) {
        console.error('[development-path] getStageById failed (direct):', err);
        return null;
      }
    }
    return runDualTrack({ stageId }, {
      direct: async (args) => directService.getStageById(args.stageId),
      electron: async (args) => {
        const result = await typedInvoke<
          { stageId: string },
          DevelopmentStageInfo
        >(PrescriptionApi.getStageById, { stageId: args.stageId });
        if (!result.success) {
          console.error('[development-path] getStageById failed:', result.error);
          return null;
        }
        return result.data;
      },
    });
  },
};
