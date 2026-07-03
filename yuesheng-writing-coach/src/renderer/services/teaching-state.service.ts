/**
 * 教学状态协调服务 — Sprint 20 B-3 降级(D-DEBT-34)
 *
 * 降级策略:调用失败时 console.error + 返回 fallback,不再 throw。
 * getPrompt 已在 B-2 降级,其余 4 处(强载荷)统一对齐。
 */

import { typedInvoke, typedOn } from './ipc-client';
import { TeachingStateApi } from '../../shared/api-contracts/teaching-state.contract';
import type {
  TeachingStateGetRequest,
  TeachingStateGetResponse,
  TeachingStateUpdateRequest,
  TeachingStateConfirmRequest,
  TeachingStateConfirmResponse,
  TeachingStateGetPromptRequest,
  TeachingStateGetPromptResponse,
  TeachingStateUpdateSummaryRequest,
  TeachingStateUpdatedEvent,
  TeachingStateMasteryEvent,
  TeachingState,
} from '../../shared/api-contracts/teaching-state.contract';

export const teachingStateService = {
  /** 获取教学状态 — 失败时返回 null(降级) */
  async get(params: TeachingStateGetRequest): Promise<TeachingStateGetResponse | null> {
    const result = await typedInvoke<TeachingStateGetRequest, TeachingStateGetResponse>(
      TeachingStateApi.get.channel,
      params,
    );
    if (!result.success) {
      console.error('[teaching-state] get failed:', result.error);
      return null;
    }
    return result.data;
  },

  /** 更新教学状态 — 失败时返回 null(降级) */
  async update(params: TeachingStateUpdateRequest): Promise<TeachingState | null> {
    const result = await typedInvoke<TeachingStateUpdateRequest, TeachingState>(
      TeachingStateApi.update.channel,
      params,
    );
    if (!result.success) {
      console.error('[teaching-state] update failed:', result.error);
      return null;
    }
    return result.data;
  },

  /** 确认阶段完成 — 失败时返回 null(降级) */
  async confirm(params: TeachingStateConfirmRequest): Promise<TeachingStateConfirmResponse | null> {
    const result = await typedInvoke<TeachingStateConfirmRequest, TeachingStateConfirmResponse>(
      TeachingStateApi.confirm.channel,
      params,
    );
    if (!result.success) {
      console.error('[teaching-state] confirm failed:', result.error);
      return null;
    }
    return result.data;
  },

  /** 获取 Prompt 注入内容 — 失败时返回 null(降级,涉及系统 prompt 全文) */
  async getPrompt(params: TeachingStateGetPromptRequest): Promise<string | null> {
    const result = await typedInvoke<TeachingStateGetPromptRequest, TeachingStateGetPromptResponse>(
      TeachingStateApi.getPrompt.channel,
      params,
    );
    if (!result.success) {
      console.error('[teaching-state] getPrompt failed:', result.error);
      return null;
    }
    return result.data.promptContent;
  },

  /** 更新诊断摘要 — 失败时返回 null(降级) */
  async updateSummary(params: TeachingStateUpdateSummaryRequest): Promise<TeachingState | null> {
    const result = await typedInvoke<TeachingStateUpdateSummaryRequest, TeachingState>(
      TeachingStateApi.updateSummary.channel,
      params,
    );
    if (!result.success) {
      console.error('[teaching-state] updateSummary failed:', result.error);
      return null;
    }
    return result.data;
  },

  /** 监听教学状态更新推送 — 返回 cleanup 函数 */
  onUpdated(handler: (data: TeachingStateUpdatedEvent) => void): () => void {
    return typedOn<TeachingStateUpdatedEvent>(TeachingStateApi.updated.channel, handler);
  },

  /**
   * 监听精通门控达成事件(RWR-P1-10 / C-4)
   *
   * 主进程 training.handler.ts 在 resolvedIssues / totalIssues >= 0.8
   * 时 emit,渲染端消费后写入 store。
   * payload 不含 syndromeId,消费方需查 progress.store 拿全量 mastered 症候。
   */
  onMastery(handler: (data: TeachingStateMasteryEvent) => void): () => void {
    return typedOn<TeachingStateMasteryEvent>(TeachingStateApi.mastery.channel, handler);
  },
};
