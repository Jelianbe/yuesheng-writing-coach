/**
 * 教学状态管理
 * 负责：管理教学状态数据的接收、存储和查询
 * 依赖：zustand, TeachingState 类型
 * 设计原则：
 *   1. 状态与 UI 分离，通过订阅机制更新
 *   2. 支持多会话教学状态查询
 *   3. 提供便捷的选择器方法
 */

import { create } from 'zustand';
import { TeachingState, TeachingProgressDisplay } from '../shared/types';
import { ACTION_NAMES } from '../../shared/mappings';

/**
 * 教学状态接口
 *
 * RWR-P1-10 / C-4 增加 masteredSyndromeIds:
 *   当前 session 中已精通的症候 ID 列表。
 *   数据源:teachingState:mastery 事件触发后,consume 端查
 *   progress.store 全量 mastered 症候写入。
 *
 * R-021 隐性诊断:只存 ID 列表,不存症候 details。
 */
export interface TeachingStateState {
  /** 当前会话的教学状态 */
  currentState: TeachingState | null;
  /** 是否正在加载 */
  isLoading: boolean;
  /** 错误信息 */
  error: string | null;
  /** 当前 session 已精通症候 ID 列表 */
  masteredSyndromeIds: string[];

  /** 设置当前教学状态 */
  setCurrentState: (state: TeachingState | null) => void;
  /** 设置加载状态 */
  setLoading: (loading: boolean) => void;
  /** 设置错误信息 */
  setError: (error: string | null) => void;
  /** 写入已精通症候 ID 列表(由 onMastery consume 端调用) */
  setMasteredSyndromeIds: (ids: string[]) => void;
}

/**
 * 创建教学状态 Zustand store
 */
export const useTeachingStateStore = create<TeachingStateState>((set) => ({
  currentState: null,
  isLoading: false,
  error: null,
  masteredSyndromeIds: [],

  setCurrentState: (state: TeachingState | null) => {
    set({ currentState: state, error: null });
  },

  setLoading: (loading: boolean) => {
    set({ isLoading: loading });
  },

  setError: (error: string | null) => {
    set({ error });
  },

  setMasteredSyndromeIds: (ids: string[]) => {
    set({ masteredSyndromeIds: ids });
  },
}));

/**
 * 便捷选择器：获取教学进度展示数据
 */
export const selectProgressDisplay = (state: TeachingStateState): TeachingProgressDisplay | null => {
  if (!state.currentState) return null;

  const cs = state.currentState;
  const phaseNames: Record<string, string> = {
    P0_INIT: '初次见面',
    P1_WORLD: '世界观搭建',
    P2_PRACTICE_LOOP: '诊断与训练',
    P4_REVIEW: '复盘总结',
  };

  const subphaseNames: Record<string, string> = {
    S1_PROTAGONIST: '确定主角',
    S1_FIRST_SCENE: '缩小到第一个场景',
    S2_IDENTIFY: '识别问题',
    S2_TEACHING: '教学建议',
    S2_ASSIGN_TASK: '布置任务',
    S2_REVIEW_TASK: '评估练习',
    S4_SUMMARY: '总结复盘',
  };

  // 计算阶段进度
  const phaseSubphases: Record<string, string[]> = {
    P0_INIT: [],
    P1_WORLD: ['S1_PROTAGONIST', 'S1_FIRST_SCENE'],
    P2_PRACTICE_LOOP: ['S2_IDENTIFY', 'S2_TEACHING', 'S2_ASSIGN_TASK', 'S2_REVIEW_TASK'],
    P4_REVIEW: ['S4_SUMMARY'],
  };

  const subphases = phaseSubphases[cs.currentPhase] || [];
  const currentIndex = subphases.indexOf(cs.currentSubphase);
  const phaseProgress = subphases.length > 0 && currentIndex >= 0
    ? (currentIndex + 1) / subphases.length
    : 0;

  return {
    phaseName: phaseNames[cs.currentPhase] || cs.currentPhase,
    subphaseName: subphaseNames[cs.currentSubphase] || cs.currentSubphase,
    phaseProgress,
    completedActions: cs.completedActions.map(id => ({
      id,
      name: (ACTION_NAMES as Record<string, string>)[id] || id,
    })),
    nextActions: cs.nextSuggestedActions.map(id => ({
      id,
      name: (ACTION_NAMES as Record<string, string>)[id] || id,
    })),
    activeProblems: cs.activeProblems.filter(p => p.status === 'active' || p.status === 'improving'),
  };
};
