/**
 * 诊断编排服务 — Sprint 20 B-2 降级(D-DEBT-34)
 *
 * 重要:本服务载荷包含完整诊断结果/改写评估/对比全文等敏感数据。
 * 降级策略:调用失败时 console.error + 返回 null/fallback,不再 throw,
 * 避免 UI 白屏(R-028 防御性编码 + R-027 门禁)。
 *
 * ─── Sprint 26 阶段 3.2 (双轨化决策) ───
 *
 * diagnosis 业务(诊断推理 + 改写评估 + 对比分析)全部在主进程 +
 * 依赖 AI 模型。shared 端**无等价 service**(无 types-diagnosis 之外的
 * service 实现)。因此本 service **不引入 runDualTrack**,而是:
 *   - 所有 invoke 方法保持 IPC-only
 *   - Capacitor 端 isCapacitor() 早返回 noop + warn
 *   - onDiagnosisUpdate 订阅在 Capacitor 端降级为 noop
 *   - 后续 diagnosis 业务下沉到 shared 时再统一迁移(待 S27+)
 *
 * Capacitor 端已知 trade-off:
 *   - query 降级:诊断面板不可用
 *   - submitRewrite 降级:改写评估不工作
 *   - getComparison 降级:历史对比不可用
 *   - onDiagnosisUpdate 降级:无事件推送
 *
 * 依据: dev-docs/tasks/sprint-26-phase-3-plan.md §3.2 / D-074
 */

import { typedInvoke, typedOn } from './ipc-client';
import { isCapacitor } from './_dual-track';
import { DiagnosisApi } from '../../shared/api-contracts/diagnosis.contract';
import type {
  DiagnosisQueryRequest,
  DiagnosisQueryResponse,
  DiagnosisSubmitRewriteRequest,
  DiagnosisRewriteEvaluation,
  DiagnosisGetComparisonRequest,
  DiagnosisUpdateEvent,
} from '../../shared/api-contracts/diagnosis.contract';

/** Capacitor 端无 IPC 通道,统一降级标识 */
function capacitorNoopDiagnosis<T>(methodName: string, fallback: T): T {
  console.warn(`[diagnosis] ${methodName}: not supported on Capacitor (诊断业务全在主进程), returning fallback`);
  return fallback;
}

export const diagnosisService = {
  /**
   * 查询诊断结果 — 失败时返回 null(降级)
   *
   * Capacitor 端:降级 noop(diagnosis 业务全在主进程,shared 端无等价实现)。
   */
  async query(params: DiagnosisQueryRequest): Promise<DiagnosisQueryResponse | null> {
    if (isCapacitor()) return capacitorNoopDiagnosis('query', null);
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

  /**
   * 提交改写评估 — 失败时返回 undefined(降级)
   *
   * Capacitor 端:降级 noop。
   */
  async submitRewrite(params: DiagnosisSubmitRewriteRequest): Promise<{ evaluation: DiagnosisRewriteEvaluation } | undefined> {
    if (isCapacitor()) return capacitorNoopDiagnosis('submitRewrite', undefined);
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

  /**
   * 获取诊断对比 — 失败时返回无历史标记(降级)
   *
   * Capacitor 端:降级 noop。
   */
  async getComparison(params: DiagnosisGetComparisonRequest): Promise<{ hasHistory: boolean; comparison?: string }> {
    if (isCapacitor()) return capacitorNoopDiagnosis('getComparison', { hasHistory: false });
    const result = await typedInvoke<DiagnosisGetComparisonRequest, { hasHistory: boolean; comparison?: string }>(
      DiagnosisApi.getComparison.channel,
      params,
    );
    if (!result.success) {
      console.error('[diagnosis] getComparison failed:', result.error);
      return { hasHistory: false };
    }
    return result.data ?? { hasHistory: false };
  },

  /**
   * 监听诊断更新推送 — 返回 cleanup 函数
   *
   * Capacitor 端:降级 noop(无事件推送通道)。
   */
  onDiagnosisUpdate(handler: (data: DiagnosisUpdateEvent) => void): () => void {
    if (isCapacitor()) {
      console.warn('[diagnosis] onDiagnosisUpdate: not supported on Capacitor, returning noop');
      return () => {};
    }
    return typedOn<DiagnosisUpdateEvent>(DiagnosisApi.updated.channel, handler);
  },
};
