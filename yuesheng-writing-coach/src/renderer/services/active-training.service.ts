/**
 * ActiveTraining 渲染端服务 — Sprint 26 阶段 3.2 (双轨版)
 *
 * 继承自 Sprint 24 A-3/A-4:
 *   - updateDraft (高频) / get (冷启动恢复) / submitStep (5 步分步提交)
 *   - subscribe (主进程推送订阅)
 *
 * 3.2 双轨改造:
 *   - 3 个 invoke 方法 (updateDraft/get/submitStep) 走 runDualTrack
 *   - subscribe 保持 IPC-only (Capacitor 端无事件推送,降级为 noop + warn)
 *   - Android 端直接 import shared/services/active-training.service.ts
 *
 * 依据: dev-docs/tasks/sprint-26-phase-3-plan.md §3.2 / D-074
 */
import { serviceBridge } from './service-bridge';
import { runDualTrack, isCapacitor } from './_dual-track';
import { createStorageAdapter } from '../../shared/storage';
import { ActiveTrainingService as DirectActiveTrainingService } from '../../shared/services/active-training.service';
import type {
  ActiveTrainingUpdateDraftRequest,
  ActiveTrainingUpdateDraftResponse,
  ActiveTrainingGetRequest,
  ActiveTrainingGetResponse,
  ActiveTrainingSubmitStepRequest,
  ActiveTrainingSubmitStepResponse,
  ActiveTrainingUpdatedEvent,
} from '../../shared/api-contracts/active-training.contract';

/** 从 window 获取 preload 暴露的 electronAPI(带类型守卫) */
function getAPI(): Window['electronAPI'] | null {
  if (typeof window === 'undefined') return null;
  return window.electronAPI ?? null;
}

/** Android 端: 延迟初始化 adapter + direct service(单例) */
let _directService: DirectActiveTrainingService | null = null;

async function getDirectService(): Promise<DirectActiveTrainingService | null> {
  if (!isCapacitor()) return null;
  if (_directService) return _directService;

  const adapter = createStorageAdapter({ type: 'capacitor-sqlite', dbName: 'yuesheng.db', version: 1 });
  await adapter.initialize();
  _directService = new DirectActiveTrainingService(adapter);
  return _directService;
}

export const activeTrainingService = {
  /**
   * 草稿保存 — 失败时返回 null
   * 调用方应在用户停止输入 500ms 后再调用
   */
  async updateDraft(
    params: ActiveTrainingUpdateDraftRequest,
  ): Promise<ActiveTrainingUpdateDraftResponse | null> {
    return runDualTrack(params, {
      direct: async (p) => {
        const svc = await getDirectService();
        if (!svc) return null;
        const updated = await svc.update(p.sessionId, { userDraft: p.content });
        if (!updated) return null;
        return {
          success: true,
          length: p.content.length,
          persistedAt: updated.updatedAt,
          status: updated.status,
        } as ActiveTrainingUpdateDraftResponse;
      },
      electron: async (p) => {
        const result = await serviceBridge.invoke<ActiveTrainingUpdateDraftRequest, ActiveTrainingUpdateDraftResponse>('activeTraining:updateDraft', p);
        if (!result) {
          console.error('[activeTraining] updateDraft failed');
          return null;
        }
        return result;
      },
    });
  },

  /**
   * 查询当前 session 的最新训练记录 — 失败时返回 null
   * 用途: 冷启动恢复 / 跨页签同步
   */
  async get(
    params: ActiveTrainingGetRequest,
  ): Promise<ActiveTrainingGetResponse | null> {
    return runDualTrack(params, {
      direct: async (p) => {
        const svc = await getDirectService();
        if (!svc) return null;
        return svc.getBySession(p.sessionId);
      },
      electron: async (p) => {
        const result = await serviceBridge.invoke<ActiveTrainingGetRequest, ActiveTrainingGetResponse>('activeTraining:get', p);
        if (!result) {
          console.error('[activeTraining] get failed');
          return null;
        }
        return result;
      },
    });
  },

  /**
   * Sprint 25 BL-01 C-4: 5 步分步提交
   * - V6.2 FlowPanel 在每步"下一步"时调用
   * - 失败时返回 null(降级模式,UI 不阻塞)
   */
  async submitStep(
    params: ActiveTrainingSubmitStepRequest,
  ): Promise<ActiveTrainingSubmitStepResponse | null> {
    return runDualTrack(params, {
      direct: async (p) => {
        const svc = await getDirectService();
        if (!svc) return null;
        // shared 端 updateStepResponses 整数组替换,需 caller 负责合并
        // 此处直接提交单步,符合 submitStep 语义(每次只提交一个 stepId)
        const now = new Date().toISOString();
        const updated = await svc.updateStepResponses(p.sessionId, [
          {
            stepId: p.stepId,
            content: p.content,
            submittedAt: now,
          },
        ]);
        if (!updated) return null;
        return {
          success: true,
          submittedCount: updated.stepResponses.length,
          submittedAt: now,
          status: updated.status,
        } as ActiveTrainingSubmitStepResponse;
      },
      electron: async (p) => {
        const result = await serviceBridge.invoke<ActiveTrainingSubmitStepRequest, ActiveTrainingSubmitStepResponse>('activeTraining:submitStep', p);
        if (!result) {
          console.error('[activeTraining] submitStep failed');
          return null;
        }
        return result;
      },
    });
  },

  /**
   * Sprint 24 A-4: 订阅主进程状态变更推送
   *
   * 双轨语义:
   *   - Electron 端: 通过 IPC 订阅 activeTraining:updated
   *   - Capacitor 端: 无 IPC 推送通道,降级为 noop + warn
   *     (调用方应改用 store polling 或等待后续 Capacitor EventTarget 实现)
   */
  subscribe(callback: (event: ActiveTrainingUpdatedEvent) => void): () => void {
    if (isCapacitor()) {
      console.warn('[activeTraining] subscribe: not supported on Capacitor, use store polling instead');
      return () => {};
    }

    const api = getAPI();
    if (!api?.on) {
      console.warn('[activeTraining] subscribe: electronAPI not available');
      return () => {};
    }
    try {
      return api.on('activeTraining:updated', (data) => {
        try {
          callback(data as ActiveTrainingUpdatedEvent);
        } catch (err) {
          console.error('[activeTraining] subscribe callback error:', err);
        }
      });
    } catch (err) {
      console.error('[activeTraining] subscribe failed:', err);
      return () => {};
    }
  },
};
