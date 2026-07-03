/**
 * 诊断编排服务 — Sprint 20 B-2 降级(D-DEBT-34)
 *
 * 重要:本服务载荷包含完整诊断结果/改写评估/对比全文等敏感数据。
 * 降级策略:调用失败时 console.error + 返回 null/fallback,不再 throw,
 * 避免 UI 白屏(R-028 防御性编码 + R-027 门禁)。
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
  /** 查询诊断结果 — 失败时返回 null(降级) */
  async query(params: DiagnosisQueryRequest): Promise<DiagnosisQueryResponse | null> {
    const result = await typedInvoke<DiagnosisQueryRequest, DiagnosisQueryResponse>(
      DiagnosisApi.query.channel,
      params,
    );
    if (!result.success) {
      console.error('[diagnosis] query failed:', result.error);
      return null;
    }
    return result.data;
  },

  /** 提交改写评估 — 失败时返回 undefined(降级) */
  async submitRewrite(params: DiagnosisSubmitRewriteRequest): Promise<{ evaluation: DiagnosisRewriteEvaluation } | undefined> {
    const result = await typedInvoke<DiagnosisSubmitRewriteRequest, { evaluation: DiagnosisRewriteEvaluation }>(
      DiagnosisApi.submitRewrite.channel,
      params,
    );
    if (!result.success) {
      console.error('[diagnosis] submitRewrite failed:', result.error);
      return undefined;
    }
    return result.data;
  },

  /** 获取诊断对比 — 失败时返回无历史标记(降级) */
  async getComparison(params: DiagnosisGetComparisonRequest): Promise<{ hasHistory: boolean; comparison?: string }> {
    const result = await typedInvoke<DiagnosisGetComparisonRequest, { hasHistory: boolean; comparison?: string }>(
      DiagnosisApi.getComparison.channel,
      params,
    );
    if (!result.success) {
      console.error('[diagnosis] getComparison failed:', result.error);
      return { hasHistory: false };
    }
    return result.data!;
  },

  /** 监听诊断更新推送 — 返回 cleanup 函数 */
  onDiagnosisUpdate(handler: (data: DiagnosisUpdateEvent) => void): () => void {
    return typedOn<DiagnosisUpdateEvent>(DiagnosisApi.updated.channel, handler);
  },
};
