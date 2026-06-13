/**
 * 教学状态协调服务
 *
 * 封装所有 teaching-state 域 IPC 通信。
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
} from '../../shared/api-contracts/teaching-state.contract';

export const teachingStateService = {
  /** 获取教学状态 */
  async get(params: TeachingStateGetRequest): Promise<TeachingStateGetResponse | null> {
    const result = await typedInvoke<TeachingStateGetRequest, TeachingStateGetResponse>(
      TeachingStateApi.get.channel,
      params,
    );
    if (!result.success) {
      throw new Error(result.error);
    }
    return result.data;
  },

  /** 更新教学状态 */
  async update(params: TeachingStateUpdateRequest): Promise<unknown> {
    const result = await typedInvoke<TeachingStateUpdateRequest, unknown>(
      TeachingStateApi.update.channel,
      params,
    );
    if (!result.success) {
      throw new Error(result.error);
    }
    return result.data;
  },

  /** 确认阶段完成 */
  async confirm(params: TeachingStateConfirmRequest): Promise<TeachingStateConfirmResponse | null> {
    const result = await typedInvoke<TeachingStateConfirmRequest, TeachingStateConfirmResponse>(
      TeachingStateApi.confirm.channel,
      params,
    );
    if (!result.success) {
      throw new Error(result.error);
    }
    return result.data;
  },

  /** 获取 Prompt 注入内容 */
  async getPrompt(params: TeachingStateGetPromptRequest): Promise<string | null> {
    const result = await typedInvoke<TeachingStateGetPromptRequest, TeachingStateGetPromptResponse>(
      TeachingStateApi.getPrompt.channel,
      params,
    );
    if (!result.success) {
      throw new Error(result.error);
    }
    return result.data.promptContent;
  },

  /** 更新诊断摘要 */
  async updateSummary(params: TeachingStateUpdateSummaryRequest): Promise<unknown> {
    const result = await typedInvoke<TeachingStateUpdateSummaryRequest, unknown>(
      TeachingStateApi.updateSummary.channel,
      params,
    );
    if (!result.success) {
      throw new Error(result.error);
    }
    return result.data;
  },

  /** 监听教学状态更新推送 — 返回 cleanup 函数 */
  onUpdated(handler: (data: TeachingStateUpdatedEvent) => void): () => void {
    return typedOn<TeachingStateUpdatedEvent>(TeachingStateApi.updated.channel, handler);
  },
};
