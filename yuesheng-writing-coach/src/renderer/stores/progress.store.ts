/**
 * 教学进度 Store(RWR-P0-2)
 *
 * 类型与常量 → src/shared/types/types-teaching.ts(SessionProgress)
 * 设计依据:
 *   - TASK-DETAILS RWR-P0-2 DoD(类型骨架)
 *   - spec §9.1(appendIssues / markRelapsed / setDisplayStatus)
 *   - spec §4.2(分阶段分组 phaseGroup + 分子分母只增不减)
 *
 * 持久化:localStorage,key = 'yuesheng-progress'
 *   - partialize 只持久化 progressMap(数据真源)
 *   - currentProgress / isLoading / error 不持久化(从 progressMap 派生或临时状态)
 *
 * 依赖:zustand + persist middleware
 * 真源:教学状态机(teaching-state.store)的诊断结果驱动更新
 */

import { create } from 'zustand';
import { persist } from 'zustand/middleware';
import type {
  SessionProgress,
  ProgressIssue,
  DisplayStatus,
} from '../shared/types';

// ===== 常量 =====

/** localStorage 持久化 key(便于多窗口/多标签页共享) */
const PERSIST_NAME = 'yuesheng-progress';
/** 每批问题分组阈值(超过此数则切换到下一 phaseGroup) */
const BATCH_SIZE = 5;

// ===== 类型定义 =====

/** 教学进度 Store 状态 */
export interface ProgressState {
  /** 当前会话的进度(从 progressMap 派生) */
  currentProgress: SessionProgress | null;
  /** 按会话 ID 索引(真源,持久化) */
  progressMap: Record<string, SessionProgress>;
  /** 加载中(预留:RWR-P1-6 接入 IPC 时使用) */
  isLoading: boolean;
  /** 错误信息(预留) */
  error: string | null;
}

/** 教学进度 Store Actions */
export interface ProgressActions {
  /**
   * 初始化/完整替换会话进度
   * 用于:诊断完成时首次初始化、批量更新
   */
  setProgress: (progress: SessionProgress) => void;

  /**
   * 分子 +1(教学完成 + 精通确认)
   * 同时将对应 issue 状态置为 'mastered'
   */
  updateResolved: (sessionId: string, syndromeId: string) => void;

  /**
   * 标记会话完成(等价于 updateResolved + displayStatus='completed')
   * 用于:整个会话教学收尾时
   */
  markCompleted: (sessionId: string) => void;

  /**
   * 重置会话进度(分子清零,但 issues 数组保留,displayStatus 回到 idle)
   * 用于:用户主动"重新开始"某会话
   */
  resetProgress: (sessionId: string) => void;

  /**
   * 追加新问题(分阶段分组)
   * spec §4.2 "追加新问题时不累积到同一个分母,改为分阶段显示"
   * 自动去重:已存在的 syndromeId 不会重复添加
   */
  appendIssues: (
    sessionId: string,
    newIssues: Array<{ syndromeId: string; label: string }>
  ) => void;

  /**
   * 标记复发
   * spec §9.1:isRelapse + relapseCount 由学生画像层追踪,store 层只置 status='relapsed'
   */
  markRelapsed: (sessionId: string, syndromeId: string) => void;

  /**
   * 更新展示状态(右侧栏状态指示器)
   */
  setDisplayStatus: (sessionId: string, status: DisplayStatus) => void;

  /**
   * 切换 currentProgress(会话切换时)
   */
  setCurrentProgress: (sessionId: string) => void;
}

// ===== 工具函数 =====

/**
 * 构造 ISO 8601 时间戳(便于测试时 mock)
 */
function nowISO(): string {
  return new Date().toISOString();
}

/**
 * 根据 totalIssues 计算 phaseGroup
 * 每 BATCH_SIZE 个问题切换到下一批次(spec §4.2 "第一批 3/3 ✓ → 第二批 0/4")
 */
function computePhaseGroup(totalIssues: number): string {
  const batchIndex = Math.floor((totalIssues - 1) / BATCH_SIZE) + 1;
  return `batch-${batchIndex}`;
}

/**
 * 构造 SessionProgress 对象的工厂(保证 updatedAt 一致性)
 */
function withUpdatedAt(progress: SessionProgress): SessionProgress {
  return { ...progress, updatedAt: nowISO() };
}

// ===== Store =====

export const useProgressStore = create<ProgressState & ProgressActions>()(
  persist(
    (set, _get) => ({
      currentProgress: null,
      progressMap: {},
      isLoading: false,
      error: null,

      setProgress: (progress) => {
        const updated = withUpdatedAt(progress);
        set((state) => ({
          progressMap: { ...state.progressMap, [progress.sessionId]: updated },
          currentProgress: updated,
        }));
      },

      updateResolved: (sessionId, syndromeId) => {
        set((state) => {
          const existing = state.progressMap[sessionId];
          if (!existing) return {};
          const updated: SessionProgress = {
            ...existing,
            resolvedIssues: existing.resolvedIssues + 1,
            issues: existing.issues.map((i) =>
              i.syndromeId === syndromeId
                ? { ...i, status: 'mastered' as const }
                : i
            ),
            updatedAt: nowISO(),
          };
          return {
            progressMap: { ...state.progressMap, [sessionId]: updated },
            currentProgress:
              state.currentProgress?.sessionId === sessionId
                ? updated
                : state.currentProgress,
          };
        });
      },

      markCompleted: (sessionId) => {
        set((state) => {
          const existing = state.progressMap[sessionId];
          if (!existing) return {};
          const updated: SessionProgress = withUpdatedAt({
            ...existing,
            displayStatus: 'completed',
          });
          return {
            progressMap: { ...state.progressMap, [sessionId]: updated },
            currentProgress:
              state.currentProgress?.sessionId === sessionId
                ? updated
                : state.currentProgress,
          };
        });
      },

      resetProgress: (sessionId) => {
        set((state) => {
          const existing = state.progressMap[sessionId];
          if (!existing) return {};
          const updated: SessionProgress = withUpdatedAt({
            ...existing,
            resolvedIssues: 0,
            displayStatus: 'idle',
          });
          return {
            progressMap: { ...state.progressMap, [sessionId]: updated },
            currentProgress:
              state.currentProgress?.sessionId === sessionId
                ? updated
                : state.currentProgress,
          };
        });
      },

      appendIssues: (sessionId, newIssues) => {
        set((state) => {
          const existing = state.progressMap[sessionId];
          if (!existing) return {};
          // 去重:已存在的 syndromeId 跳过
          const existingIds = new Set(existing.issues.map((i) => i.syndromeId));
          const filtered = newIssues.filter((ni) => !existingIds.has(ni.syndromeId));
          if (filtered.length === 0) return {};
          const newTotal = existing.totalIssues + filtered.length;
          const appendedIssues: ProgressIssue[] = filtered.map((ni) => ({
            syndromeId: ni.syndromeId,
            status: 'identified' as const,
            label: ni.label,
          }));
          const updated: SessionProgress = {
            ...existing,
            totalIssues: newTotal,
            phaseGroup: computePhaseGroup(newTotal),
            issues: [...existing.issues, ...appendedIssues],
            updatedAt: nowISO(),
          };
          return {
            progressMap: { ...state.progressMap, [sessionId]: updated },
            currentProgress:
              state.currentProgress?.sessionId === sessionId
                ? updated
                : state.currentProgress,
          };
        });
      },

      markRelapsed: (sessionId, syndromeId) => {
        set((state) => {
          const existing = state.progressMap[sessionId];
          if (!existing) return {};
          const updated: SessionProgress = withUpdatedAt({
            ...existing,
            issues: existing.issues.map((i) =>
              i.syndromeId === syndromeId
                ? { ...i, status: 'relapsed' as const }
                : i
            ),
          });
          return {
            progressMap: { ...state.progressMap, [sessionId]: updated },
            currentProgress:
              state.currentProgress?.sessionId === sessionId
                ? updated
                : state.currentProgress,
          };
        });
      },

      setDisplayStatus: (sessionId, status) => {
        set((state) => {
          const existing = state.progressMap[sessionId];
          if (!existing) return {};
          const updated: SessionProgress = withUpdatedAt({
            ...existing,
            displayStatus: status,
          });
          return {
            progressMap: { ...state.progressMap, [sessionId]: updated },
            currentProgress:
              state.currentProgress?.sessionId === sessionId
                ? updated
                : state.currentProgress,
          };
        });
      },

      setCurrentProgress: (sessionId) => {
        set((state) => ({
          currentProgress: state.progressMap[sessionId] ?? null,
        }));
      },
    }),
    {
      name: PERSIST_NAME,
      // 只持久化数据真源(progressMap);currentProgress / isLoading / error 不持久化
      partialize: (state) => ({
        progressMap: state.progressMap,
      }),
    }
  )
);

// ===== 选择器(供组件使用) =====

/** 获取当前会话进度 */
export const selectCurrentProgress = (state: ProgressState): SessionProgress | null =>
  state.currentProgress;

/** 获取完整 progressMap(供调试或会话切换) */
export const selectProgressMap = (
  state: ProgressState
): Record<string, SessionProgress> => state.progressMap;

/** 获取指定会话的 0/N 比值(0-1) */
export const selectResolvedRatio = (sessionId: string) => (
  state: ProgressState
): { resolved: number; total: number; ratio: number } => {
  const p = state.progressMap[sessionId];
  if (!p) return { resolved: 0, total: 0, ratio: 0 };
  return {
    resolved: p.resolvedIssues,
    total: p.totalIssues,
    ratio: p.totalIssues > 0 ? p.resolvedIssues / p.totalIssues : 0,
  };
};
