import { useState, useCallback } from 'react';
import { serviceBridge } from '../services/service-bridge';
import type { RewriteEvaluation } from '../shared/types';

interface EditingSyndrome {
  id: string;
  evidence: string[];
  /** 症候名称，用于传递给后端评估 */
  name: string;
  /** 症候描述/严重程度，用于传递给后端评估 */
  severity: string;
}

interface DiagnosisFlowState {
  /** 当前正在编辑的综合征 */
  editingSyndrome: EditingSyndrome | null;
  /** 是否正在提交修改 */
  isSubmitting: boolean;
  /** 最近的评估结果 */
  lastEvaluation: RewriteEvaluation | null;
  /** 最近一次提交的修改文本（EvaluationCard 对比展示用） */
  lastRewrittenText: string | null;
  /** 最近一次编辑的原文（EvaluationCard 对比展示用） */
  lastOriginalText: string | null;
  /** 成长记录加载状态 */
  growthLoading: boolean;
  /** 成长记录 */
  growthSummary: string | null;
  /** 是否有历史数据 */
  hasHistory: boolean;
}

/**
 * useDiagnosisFlow — 诊断→修改→评估 流程 hook
 *
 * 管理整个诊断流程的状态：
 * 1. 用户点击"定位根因"展开诊断详情
 * 2. 用户点击"尝试修改"展开编辑面板
 * 3. 用户提交修改触发评估
 * 4. 评估完成后显示成长记录
 *
 * Sprint 26 阶段 3.6: 改走 service-bridge 单端点
 */
export function useDiagnosisFlow(sessionId: string | null) {
  const [state, setState] = useState<DiagnosisFlowState>({
    editingSyndrome: null,
    isSubmitting: false,
    lastEvaluation: null,
    lastRewrittenText: null,
    lastOriginalText: null,
    growthLoading: false,
    growthSummary: null,
    hasHistory: false,
  });

  /** 开始编辑指定的综合征 */
  const startEditing = useCallback((syndromeId: string, evidence: string[], name?: string, severity?: string) => {
    setState((prev) => ({
      ...prev,
      editingSyndrome: { id: syndromeId, evidence, name: name || syndromeId, severity: severity || '' },
    }));
  }, []);

  /** 取消编辑 */
  const cancelEditing = useCallback(() => {
    setState((prev) => ({
      ...prev,
      editingSyndrome: null,
    }));
  }, []);

  /** 提交修改 */
  const submitRewrite = useCallback(
    async (rewrittenText: string) => {
      if (!sessionId || !state.editingSyndrome) return;

      setState((prev) => ({ ...prev, isSubmitting: true }));

      const data = await serviceBridge.invoke<
        {
          sessionId: string;
          syndromeId: string;
          originalText: string;
          rewrittenText: string;
          syndromeName: string;
          syndromeDesc: string;
        },
        { evaluation: RewriteEvaluation } | undefined
      >('diagnosis:submitRewrite', {
        sessionId,
        syndromeId: state.editingSyndrome.id,
        originalText: state.editingSyndrome.evidence.join('\n'),
        rewrittenText,
        syndromeName: state.editingSyndrome.name,
        syndromeDesc: state.editingSyndrome.severity,
      });

      if (data?.evaluation) {
        setState((prev) => ({
          ...prev,
          isSubmitting: false,
          editingSyndrome: null,
          lastEvaluation: data.evaluation,
          lastRewrittenText: rewrittenText,
          lastOriginalText: prev.editingSyndrome?.evidence.join('\n') ?? null,
        }));
      } else {
        setState((prev) => ({
          ...prev,
          isSubmitting: false,
          editingSyndrome: null,
        }));
      }
    },
    [sessionId, state.editingSyndrome],
  );

  /** 获取成长记录 */
  const fetchGrowthSummary = useCallback(async () => {
    if (!sessionId) return;

    setState((prev) => ({ ...prev, growthLoading: true }));

    const data = await serviceBridge.invoke<
      { sessionId: string },
      { hasHistory: boolean; comparison?: string }
    >('diagnosis:getComparison', { sessionId });

    if (data) {
      setState((prev) => ({
        ...prev,
        hasHistory: data.hasHistory,
        growthSummary: data.comparison ?? null,
        growthLoading: false,
      }));
    } else {
      setState((prev) => ({ ...prev, growthLoading: false }));
    }
  }, [sessionId]);

  /** 重置流程状态 */
  const reset = useCallback(() => {
    setState({
      editingSyndrome: null,
      isSubmitting: false,
      lastEvaluation: null,
      lastRewrittenText: null,
      lastOriginalText: null,
      growthLoading: false,
      growthSummary: null,
      hasHistory: false,
    });
  }, []);

  return {
    ...state,
    startEditing,
    cancelEditing,
    submitRewrite,
    fetchGrowthSummary,
    reset,
  };
}
