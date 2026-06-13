// 诊断状态管理
// ⚠️ 本文件 catch 块中的 console.error / console.warn 仅用于开发调试，
//    生产环境应通过构建工具（如 terser drop_console）自动移除。
// 负责：管理诊断数据的接收、存储和查询
// 依赖：zustand, DiagnosisEntry 类型
// 设计原则：
//   1. 状态与 UI 分离，通过订阅机制更新
//   2. 支持多会话诊断记录查询
//   3. 提供便捷的选择器方法

import { create } from 'zustand';
import { DiagnosisEntry, EvidenceRecord, SeverityLevel, SyndromeId } from '../shared/types';
import { getInvoke } from '../utils/ipc';
import { IPC_CHANNELS } from '../../shared/constants';

/**
 * 诊断状态接口
 * 包含当前诊断结果、历史诊断记录、加载状态等
 */
export interface DiagState {
  /** 当前轮次的诊断结果 */
  currentDiagnosis: DiagnosisEntry | null;
  /** 历史诊断记录（按会话ID分组） */
  history: Record<string, DiagnosisEntry[]>;
  /** 证据缓存（按 syndromeId 索引） */
  evidenceMap: Record<string, EvidenceRecord[]>;
  /** 是否正在加载诊断数据 */
  isLoading: boolean;
  /** 诊断错误信息 */
  error: string | null;

  /** 设置当前诊断结果 */
  setCurrentDiagnosis: (entry: DiagnosisEntry | null) => void;
  /** 添加诊断到历史记录 */
  addToHistory: (sessionId: string, entry: DiagnosisEntry) => void;
  /** 查询指定会话的诊断历史 */
  getHistoryBySession: (sessionId: string) => DiagnosisEntry[];
  /** 加载症候的原文证据（从 IPC 获取并缓存） */
  loadEvidence: (syndromeId: string, sessionId: string) => Promise<EvidenceRecord[]>;
  /** 获取缓存的证据数据 */
  getEvidence: (syndromeId: string) => EvidenceRecord[];
  /** 设置错误状态 */
  setError: (error: string | null) => void;
}

/**
 * 创建诊断 Zustand store
 * 使用持久化中间件可选，当前阶段不持久化（诊断数据由主进程推送）
 */
export const useDiagStore = create<DiagState>((set, get) => ({
  currentDiagnosis: null,
  history: {},
  evidenceMap: {},
  isLoading: false,
  error: null,

  setCurrentDiagnosis: (entry: DiagnosisEntry | null) => {
    set({ currentDiagnosis: entry, error: null });
  },

  addToHistory: (sessionId: string, entry: DiagnosisEntry) => {
    set((state) => {
      const sessionHistory = state.history[sessionId] || [];
      return {
        history: {
          ...state.history,
          [sessionId]: [...sessionHistory, entry],
        },
      };
    });
  },

  getHistoryBySession: (sessionId: string) => {
    return get().history[sessionId] || [];
  },

  loadEvidence: async (syndromeId: string, sessionId: string) => {
    // 已缓存则直接返回
    const cached = get().evidenceMap[syndromeId];
    if (cached && cached.length > 0) return cached;

    try {
      const result = await getInvoke()(IPC_CHANNELS.EVIDENCE_GET_BY_SYNDROME, {
        syndromeId,
        sessionId,
      }) as { success: boolean; data?: EvidenceRecord[]; error?: string };

      if (!result.success) {
        console.warn('[DiagStore] loadEvidence failed:', result.error || 'Unknown error');
        return [];
      }

      const records = result.data ?? [];
      set((state) => ({
        evidenceMap: { ...state.evidenceMap, [syndromeId]: records },
      }));
      return records;
    } catch (e) {
      console.warn('[DiagStore] loadEvidence failed:', e);
      return [];
    }
  },

  getEvidence: (syndromeId: string) => {
    return get().evidenceMap[syndromeId] ?? [];
  },

  clear: () => {
    set({
      currentDiagnosis: null,
      history: {},
      evidenceMap: {},
      error: null,
      isLoading: false,
    });
  },

  setError: (error: string | null) => {
    set({ error });
  },

  setLoading: (loading: boolean) => {
    set({ isLoading: loading });
  },
}));

/**
 * 便捷选择器：获取当前诊断的病症列表
 */
export const selectCurrentSyndromes = (state: DiagState) =>
  state.currentDiagnosis?.syndromes ?? [];

/**
 * 便捷选择器：获取当前诊断的建议动作列表
 */
export const selectCurrentActions = (state: DiagState) =>
  state.currentDiagnosis?.suggestedActions ?? [];

/**
 * 便捷选择器：获取当前诊断的置信度
 */
export const selectCurrentConfidence = (state: DiagState) =>
  state.currentDiagnosis?.confidence ?? 0;

/**
 * 便捷选择器：判断是否有诊断结果
 */
export const selectHasDiagnosis = (state: DiagState) =>
  state.currentDiagnosis !== null && state.currentDiagnosis.syndromes.length > 0;

/**
 * 便捷选择器：获取最高严重度的病症
 */
export const selectHighestSeveritySyndrome = (state: DiagState) => {
  const syndromes = state.currentDiagnosis?.syndromes ?? [];
  if (syndromes.length === 0) return null;

  const severityOrder: Record<SeverityLevel, number> = { L3: 3, L2: 2, L1: 1 };
  return syndromes.reduce((highest, current) =>
    severityOrder[current.severity] > severityOrder[highest.severity] ? current : highest
  );
};

/**
 * 便捷选择器：获取指定病症 ID 的诊断结果
 */
export const selectSyndromeById = (syndromeId: SyndromeId) => (state: DiagState) => {
  const syndromes = state.currentDiagnosis?.syndromes ?? [];
  return syndromes.find(s => s.id === syndromeId) ?? null;
};
