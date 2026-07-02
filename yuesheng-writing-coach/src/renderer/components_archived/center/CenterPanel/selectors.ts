/**
 * CenterPanel Zustand 订阅拆分（T17-7）
 *
 * 背景：原 CenterPanel 用了
 *  - `useSessionStore()` 无 selector → 全 store 订阅
 *  - `useTrainingStore((s) => ({...14 fields}))` → 每次创建新对象，聚合订阅
 * 训练流 stream 高频更新（activeTraining/isLoading）时，会触发 CenterPanel
 * 整体 re-render，进而带动 ChatView/TrainingWorkshop 全部刷新。
 *
 * 重构：按使用场景拆为独立 selector，actions 用 getState() 调取
 * （R-021 禁止直接拿整个 store 后取 action）。
 *
 * 原则：
 *  - 引用稳定性：selector 返回相同字段值时，React 不会触发 re-render
 *  - actions 不进订阅：use useStore.getState().xxx() 调用
 *  - 聚合 selector 用 useShallow：内部用 Object.is 比较，字段值不变返回旧引用
 */

import { useShallow } from 'zustand/react/shallow';
import { useSessionStore } from '../../../stores/session.store';
import { useTrainingStore } from '../../../stores/training.store';
import type { TrainingState } from '../../../stores/training.types';

// ===== Session selectors =====

/** 当前会话 ID（高频字段，会话切换时变化） */
export const useCenterSessionId = (): string | null =>
  useSessionStore((s) => s.currentSessionId);

/** 会话列表（低频字段，只在 loadSessions 后变化） */
export const useCenterSessionList = () =>
  useSessionStore((s) => s.sessions);

// ===== Training selectors（按使用场景分组）=====

/**
 * 训练工坊 props（11 字段）
 * 包含训练流程的完整数据，由 TrainingWorkshop 直接消费。
 * 训练流 stream 时 activeTraining/submissionResult/evaluationResult 频繁变化。
 * useShallow 保证内部任一字段值不变时返回旧引用，避免不必要 re-render。
 */
export const useTrainingWorkshopState = () =>
  useTrainingStore(
    useShallow((s: TrainingState) => ({
      errorCards: s.errorCards,
      recommendations: s.recommendations,
      readingDecision: s.readingDecision,
      readingComplete: s.readingComplete,
      activeTraining: s.activeTraining,
      history: s.history,
      submissionResult: s.submissionResult,
      evaluationResult: s.evaluationResult,
      isLoading: s.isLoading,
      error: s.error ?? null,
      lastEvaluationScore: s.lastEvaluationScore,
      lastSyndromeId: s.lastSyndromeId,
    })),
  );

/** 桥接卡片（ChatView 消费，低频字段） */
export const useBridgeState = () =>
  useTrainingStore((s: TrainingState) => s.bridgeRecommendation);

/** 复盘视图（RetroSummaryView 消费，低频字段） */
export const useRetroState = () =>
  useTrainingStore(
    useShallow((s: TrainingState) => ({
      retroSummary: s.retroSummary,
      retroLoading: s.retroLoading,
    })),
  );
