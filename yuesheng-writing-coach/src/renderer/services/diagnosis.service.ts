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
 * service 实现)。
 *
 * ─── Sprint 32 (Android Diagnosis 激活) ───
 *
 * Capacitor 端从 noop 升级为真实实现(通过 capacitor-diagnosis 模块):
 *   - query: 从 localStorage 读取缓存的诊断结果
 *   - submitRewrite: 直调 LLM API 评估改写
 *   - getComparison: 保持 noop(需要 diagnosis_records 表,未迁移)
 *   - onDiagnosisUpdate: 内存事件总线
 *
 * 依据: dev-docs/decision-log.md D-081 未做事项 §1
 */

import { typedOn } from './ipc-client';
import { serviceBridge } from './service-bridge';
import { isCapacitor } from './_dual-track';
import {
  capacitorDiagnosisQuery,
  capacitorDiagnosisSubmitRewrite,
  capacitorDiagnosisGetComparison,
  capacitorOnDiagnosisUpdate,
} from './capacitor-diagnosis';
import type {
  DiagnosisQueryRequest,
  DiagnosisQueryResponse,
  DiagnosisSubmitRewriteRequest,
  DiagnosisRewriteEvaluation,
  DiagnosisGetComparisonRequest,
  DiagnosisUpdateEvent,
} from '../../shared/api-contracts/diagnosis.contract';

export const diagnosisService = {
  /**
   * 查询诊断结果 — 失败时返回 null(降级)
   *
   * Capacitor 端:降级 noop(diagnosis 业务全在主进程,shared 端无等价实现)。
   */
  async query(params: DiagnosisQueryRequest): Promise<DiagnosisQueryResponse | null> {
    if (isCapacitor()) return capacitorDiagnosisQuery(params);
    const result = await serviceBridge.invoke<DiagnosisQueryRequest, DiagnosisQueryResponse>('diagnosis:query', params);
    if (!result) {
      console.error('[diagnosis] query failed');
      return null;
    }
    return result;
  },

  /**
   * 提交改写评估 — 失败时返回 undefined(降级)
   *
   * Capacitor 端:降级 noop。
   */
  async submitRewrite(params: DiagnosisSubmitRewriteRequest): Promise<{ evaluation: DiagnosisRewriteEvaluation } | undefined> {
    if (isCapacitor()) return capacitorDiagnosisSubmitRewrite(params);
    const result = await serviceBridge.invoke<DiagnosisSubmitRewriteRequest, { evaluation: DiagnosisRewriteEvaluation }>('diagnosis:submitRewrite', params);
    if (!result) {
      console.error('[diagnosis] submitRewrite failed');
      return undefined;
    }
    return result;
  },

  /**
   * 获取诊断对比 — 失败时返回无历史标记(降级)
   *
   * Capacitor 端:降级 noop。
   */
  async getComparison(params: DiagnosisGetComparisonRequest): Promise<{ hasHistory: boolean; comparison?: string }> {
    if (isCapacitor()) return capacitorDiagnosisGetComparison(params);
    const result = await serviceBridge.invoke<DiagnosisGetComparisonRequest, { hasHistory: boolean; comparison?: string }>('diagnosis:getComparison', params);
    if (!result) {
      console.error('[diagnosis] getComparison failed');
      return { hasHistory: false };
    }
    return result;
  },

  /**
   * 监听诊断更新推送 — 返回 cleanup 函数
   *
   * Capacitor 端:降级 noop(无事件推送通道)。
   */
  onDiagnosisUpdate(handler: (data: DiagnosisUpdateEvent) => void): () => void {
    if (isCapacitor()) return capacitorOnDiagnosisUpdate(handler);
    return typedOn<DiagnosisUpdateEvent>('diagnosis:updated', handler);
  },
};
