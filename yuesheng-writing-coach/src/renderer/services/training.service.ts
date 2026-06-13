/**
 * 训练协调服务
 *
 * 封装所有 training 域 IPC 通信。
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
  /** 获取推荐训练 */
  async recommend(params: TrainingRecommendRequest): Promise<TrainingRecommendResponse | null> {
    const result = await typedInvoke<TrainingRecommendRequest, TrainingRecommendResponse>(
      TrainingApi.recommend.channel,
      params,
    );
    if (!result.success) {
      throw new Error(result.error);
    }
    return result.data;
  },

  /** 分配训练任务 */
  async assign(params: TrainingAssignRequest): Promise<TrainingAssignResponse | null> {
    const result = await typedInvoke<TrainingAssignRequest, TrainingAssignResponse>(
      TrainingApi.assign.channel,
      params,
    );
    if (!result.success) {
      throw new Error(result.error);
    }
    return result.data;
  },

  /** 完成训练 */
  async complete(params: TrainingCompleteRequest): Promise<TrainingCompleteResponse | null> {
    const result = await typedInvoke<TrainingCompleteRequest, TrainingCompleteResponse>(
      TrainingApi.complete.channel,
      params,
    );
    if (!result.success) {
      throw new Error(result.error);
    }
    return result.data;
  },

  /** 跳过训练 */
  async skip(params: TrainingSkipRequest): Promise<TrainingCompleteResponse | null> {
    const result = await typedInvoke<TrainingSkipRequest, TrainingCompleteResponse>(
      TrainingApi.skip.channel,
      params,
    );
    if (!result.success) {
      throw new Error(result.error);
    }
    return result.data;
  },

  /** 查询训练历史 */
  async history(params: TrainingHistoryRequest): Promise<TrainingHistoryResponse | null> {
    const result = await typedInvoke<TrainingHistoryRequest, TrainingHistoryResponse>(
      TrainingApi.history.channel,
      params,
    );
    if (!result.success) {
      throw new Error(result.error);
    }
    return result.data;
  },

  /** 提交训练 */
  async submit(params: TrainingSubmitRequest): Promise<TrainingSubmitResponse | null> {
    const result = await typedInvoke<TrainingSubmitRequest, TrainingSubmitResponse>(
      TrainingApi.submit.channel,
      params,
    );
    if (!result.success) {
      throw new Error(result.error);
    }
    return result.data;
  },

  /** 评估训练 */
  async evaluate(params: TrainingEvaluateRequest): Promise<TrainingEvaluateResponse | null> {
    const result = await typedInvoke<TrainingEvaluateRequest, TrainingEvaluateResponse>(
      TrainingApi.evaluate.channel,
      params,
    );
    if (!result.success) {
      throw new Error(result.error);
    }
    return result.data;
  },

  /** 推导角色行为 */
  async deriveBehavior(params: TrainingDeriveBehaviorRequest): Promise<TrainingDeriveBehaviorResponse | null> {
    const result = await typedInvoke<TrainingDeriveBehaviorRequest, TrainingDeriveBehaviorResponse>(
      TrainingApi.deriveBehavior.channel,
      params,
    );
    if (!result.success) {
      throw new Error(result.error);
    }
    return result.data;
  },
};
