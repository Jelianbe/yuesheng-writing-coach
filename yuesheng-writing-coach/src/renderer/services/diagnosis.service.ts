/**
 * 诊断编排服务
 *
 * 封装所有 diagnosis 域 IPC 通信。
 */

import { typedInvoke, typedOn } from './ipc-client';
import { DiagnosisApi } from '../../shared/api-contracts/diagnosis.contract';
import type {
  DiagnosisQueryRequest,
  DiagnosisQueryResponse,
  DiagnosisSubmitRewriteRequest,
  DiagnosisRewriteEvaluation,
  DiagnosisGetComparisonRequest,
  DiagnosisUpdateEvent,
} from '../../shared/api-contracts/diagnosis.contract';

export const diagnosisService = {
  /** 查询诊断结果 */
  async query(params: DiagnosisQueryRequest): Promise<DiagnosisQueryResponse | null> {
    const result = await typedInvoke<DiagnosisQueryRequest, DiagnosisQueryResponse>(
      DiagnosisApi.query.channel,
      params,
    );
    if (!result.success) {
      throw new Error(result.error);
    }
    return result.data;
  },

  /** 提交改写评估 */
  async submitRewrite(params: DiagnosisSubmitRewriteRequest): Promise<{ evaluation: DiagnosisRewriteEvaluation } | undefined> {
    const result = await typedInvoke<DiagnosisSubmitRewriteRequest, { evaluation: DiagnosisRewriteEvaluation }>(
      DiagnosisApi.submitRewrite.channel,
      params,
    );
    if (!result.success) {
      throw new Error(result.error);
    }
    return result.data;
  },

  /** 获取诊断对比 */
  async getComparison(params: DiagnosisGetComparisonRequest): Promise<{ hasHistory: boolean; comparison?: string }> {
    const result = await typedInvoke<DiagnosisGetComparisonRequest, { hasHistory: boolean; comparison?: string }>(
      DiagnosisApi.getComparison.channel,
      params,
    );
    if (!result.success) {
      throw new Error(result.error);
    }
    return result.data!;
  },

  /** 监听诊断更新推送 — 返回 cleanup 函数 */
  onDiagnosisUpdate(handler: (data: DiagnosisUpdateEvent) => void): () => void {
    return typedOn<DiagnosisUpdateEvent>(DiagnosisApi.updated.channel, handler);
  },
};
