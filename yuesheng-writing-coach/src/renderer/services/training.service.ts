/**
 * 训练协调服务 — Sprint 20 B-2 降级(D-DEBT-34)
 *
 * 重要:本服务载荷包含 AI 评估/学生练习/角色行为推导等敏感数据。
 * 降级策略:调用失败时 console.error + 返回 null,不再 throw,
 * 避免 UI 白屏(R-028 防御性编码 + R-027 门禁)。
 */

import { typedInvoke } from './ipc-client';
import { TrainingApi } from '../../shared/api-contracts/training.contract';
import type {
  TrainingRecommendRequest,
  TrainingRecommendResponse,
  TrainingAssignRequest,
  TrainingAssignResponse,
  TrainingCompleteRequest,
  TrainingCompleteResponse,
  TrainingSkipRequest,
  TrainingHistoryRequest,
  TrainingHistoryResponse,
  TrainingSubmitRequest,
  TrainingSubmitResponse,
  TrainingEvaluateRequest,
  TrainingEvaluateResponse,
  TrainingDeriveBehaviorRequest,
  TrainingDeriveBehaviorResponse,
} from '../../shared/api-contracts/training.contract';

export const trainingService = {
  /** 获取推荐训练 — 失败时返回 null(降级) */
  async recommend(params: TrainingRecommendRequest): Promise<TrainingRecommendResponse | null> {
    const result = await typedInvoke<TrainingRecommendRequest, TrainingRecommendResponse>(
      TrainingApi.recommend.channel,
      params,
    );
    if (!result.success) {
      console.error('[training] recommend failed:', result.error);
      return null;
    }
    return result.data;
  },

  /** 分配训练任务 — 失败时返回 null(降级) */
  async assign(params: TrainingAssignRequest): Promise<TrainingAssignResponse | null> {
    const result = await typedInvoke<TrainingAssignRequest, TrainingAssignResponse>(
      TrainingApi.assign.channel,
      params,
    );
    if (!result.success) {
      console.error('[training] assign failed:', result.error);
      return null;
    }
    return result.data;
  },

  /** 完成训练 — 失败时返回 null(降级) */
  async complete(params: TrainingCompleteRequest): Promise<TrainingCompleteResponse | null> {
    const result = await typedInvoke<TrainingCompleteRequest, TrainingCompleteResponse>(
      TrainingApi.complete.channel,
      params,
    );
    if (!result.success) {
      console.error('[training] complete failed:', result.error);
      return null;
    }
    return result.data;
  },

  /** 跳过训练 — 失败时返回 null(降级,B-3 补齐) */
  async skip(params: TrainingSkipRequest): Promise<TrainingCompleteResponse | null> {
    const result = await typedInvoke<TrainingSkipRequest, TrainingCompleteResponse>(
      TrainingApi.skip.channel,
      params,
    );
    if (!result.success) {
      console.error('[training] skip failed:', result.error);
      return null;
    }
    return result.data;
  },

  /** 查询训练历史 — 失败时返回 null(降级) */
  async history(params: TrainingHistoryRequest): Promise<TrainingHistoryResponse | null> {
    const result = await typedInvoke<TrainingHistoryRequest, TrainingHistoryResponse>(
      TrainingApi.history.channel,
      params,
    );
    if (!result.success) {
      console.error('[training] history failed:', result.error);
      return null;
    }
    return result.data;
  },

  /** 提交训练 — 失败时返回 null(降级,涉及用户练习内容 + AI 评分) */
  async submit(params: TrainingSubmitRequest): Promise<TrainingSubmitResponse | null> {
    const result = await typedInvoke<TrainingSubmitRequest, TrainingSubmitResponse>(
      TrainingApi.submit.channel,
      params,
    );
    if (!result.success) {
      console.error('[training] submit failed:', result.error);
      return null;
    }
    return result.data;
  },

  /** 评估训练 — 失败时返回 null(降级,涉及 AI 评估全文) */
  async evaluate(params: TrainingEvaluateRequest): Promise<TrainingEvaluateResponse | null> {
    const result = await typedInvoke<TrainingEvaluateRequest, TrainingEvaluateResponse>(
      TrainingApi.evaluate.channel,
      params,
    );
    if (!result.success) {
      console.error('[training] evaluate failed:', result.error);
      return null;
    }
    return result.data;
  },

  /** 推导角色行为 — 失败时返回 null(降级,涉及角色心理分析) */
  async deriveBehavior(params: TrainingDeriveBehaviorRequest): Promise<TrainingDeriveBehaviorResponse | null> {
    const result = await typedInvoke<TrainingDeriveBehaviorRequest, TrainingDeriveBehaviorResponse>(
      TrainingApi.deriveBehavior.channel,
      params,
    );
    if (!result.success) {
      console.error('[training] deriveBehavior failed:', result.error);
      return null;
    }
    return result.data;
  },
};
