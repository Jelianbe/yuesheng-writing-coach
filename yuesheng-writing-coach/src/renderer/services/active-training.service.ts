/**
 * ActiveTraining 渲染端服务 — Sprint 24 A-3 / A-4
 *
 * 职责: 封装 ActiveTraining IPC 边界,提供降级语义
 *
 * 降级策略(D-DEBT-34):
 *   - 调用失败时 console.error + 返回 null,不再 throw
 *   - 避免 UI 白屏(R-028 防御性编码)
 *
 * 重要:
 *   - updateDraft 是高频操作(用户每次按键都可能触发)
 *   - 调用方应自行防抖(典型 500ms)以减少 IPC 压力
 *   - 本服务不做防抖 — 防抖属于 UI 策略层
 *
 * Sprint 24 A-4 增强:
 *   - 添加 subscribe() 接口,订阅主进程状态变更推送
 *   - 通道: activeTraining:updated
 *   - 用途: renderer store 接收主进程推送并更新本地状态
 *
 * 依据: dev-docs/tasks/sprint-24-plan.md §A-3, §A-4
 */

import { typedInvoke } from './ipc-client';
import { ActiveTrainingApi } from '../../shared/api-contracts/active-training.contract';
import type {
  ActiveTrainingUpdateDraftRequest,
  ActiveTrainingUpdateDraftResponse,
  ActiveTrainingGetRequest,
  ActiveTrainingGetResponse,
  ActiveTrainingUpdatedEvent,
} from '../../shared/api-contracts/active-training.contract';

/** 从 window 获取 preload 暴露的 electronAPI(带类型守卫) */
function getAPI(): Window['electronAPI'] | null {
  if (typeof window === 'undefined') return null;
  return window.electronAPI ?? null;
}

export const activeTrainingService = {
  /**
   * 草稿保存 — 失败时返回 null
   * 调用方应在用户停止输入 500ms 后再调用
   */
  async updateDraft(
    params: ActiveTrainingUpdateDraftRequest,
  ): Promise<ActiveTrainingUpdateDraftResponse | null> {
    const result = await typedInvoke<
      ActiveTrainingUpdateDraftRequest,
      ActiveTrainingUpdateDraftResponse
    >(ActiveTrainingApi.updateDraft.channel, params);
    if (!result.success) {
      console.error('[activeTraining] updateDraft failed:', result.error);
      return null;
    }
    return result.data;
  },

  /**
   * 查询当前 session 的 in_progress 训练 — 失败时返回 null
   * 用途: 冷启动恢复 / 跨页签同步
   */
  async get(
    params: ActiveTrainingGetRequest,
  ): Promise<ActiveTrainingGetResponse | null> {
    const result = await typedInvoke<ActiveTrainingGetRequest, ActiveTrainingGetResponse | null>(
      ActiveTrainingApi.get.channel,
      params,
    );
    if (!result.success) {
      console.error('[activeTraining] get failed:', result.error);
      return null;
    }
    return result.data;
  },

  /**
   * Sprint 24 A-4: 订阅主进程状态变更推送
   *
   * 工作流:
   *   1. 通过 preload 暴露的 electronAPI.on() 监听 activeTraining:updated
   *   2. 收到事件后调用 callback(event)
   *   3. 返回的 unsubscribe 函数用于清理(组件 unmount)
   *
   * 降级:
   *   - electronAPI 不可用(非 Electron 环境)时静默返回 noop unsubscribe
   *   - 调用方应自行检查 callback 是否被调用
   *
   * @param callback 状态变更事件回调
   * @returns 取消订阅函数
   */
  subscribe(callback: (event: ActiveTrainingUpdatedEvent) => void): () => void {
    const api = getAPI();
    if (!api?.on) {
      console.warn('[activeTraining] subscribe: electronAPI not available');
      return () => {};
    }
    try {
      return api.on(ActiveTrainingApi.updated.channel, (data) => {
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

