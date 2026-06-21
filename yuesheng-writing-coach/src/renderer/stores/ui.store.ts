/**
 * ui.store.ts — V6.2 Shell 状态管理
 *
 * 职责：管理 V6.2 Shell 独有但未被其他 Store 覆盖的状态。
 *
 * 与其他 Store 的边界：
 * - 面板折叠/宽度 → useUiLayoutStore
 * - 右侧栏工具 → useDrawerStore + useRightPanelStore
 * - 子标签会话 → usePanelSessionStore
 * - 聊天会话/消息 → useSessionStore + useChatStore
 * - 作品/章节 → useManuscriptStore + useChapterStore
 * - 配置 → useConfigStore
 *
 * 本 Store 覆盖 V6.2 Shell 独有状态：
 * - 左栏 tab 切换（对话/项目）
 * - 态度档位与锁定
 * - 项目列表选中 ID
 * - 训练上下文记录
 */

import { create } from 'zustand';

/** 态度档位 */
export type AttitudeLevel = 'doubao' | 'yuesheng' | 'sensei';

/** 左侧栏 tab */
export type LeftTab = 'chat' | 'proj';

/** 训练会话上下文（H-01） */
export interface TrainingContext {
  techniqueName: string;
  category: string;
  difficulty: 'beginner' | 'intermediate' | 'advanced';
  description: string;
  coreName: string;
}

interface UiState {
  // 左栏
  leftTab: LeftTab;
  selectedProjectId: string | null;

  // 态度
  attitude: AttitudeLevel;
  attitudeLocked: boolean;

  // 训练上下文
  trainingContexts: Record<string, TrainingContext>;
}

interface UiActions {
  /** 切换左栏 tab */
  setLeftTab: (tab: LeftTab) => void;
  /** 选中项目 */
  setSelectedProjectId: (id: string | null) => void;
  /** 设置态度档位 */
  setAttitude: (level: AttitudeLevel) => void;
  /** 锁定/解锁态度 */
  toggleAttitudeLock: () => void;
  /** 记录训练会话上下文 */
  setTrainingContext: (sessionId: string, ctx: TrainingContext) => void;
  /** 清空训练上下文 */
  clearTrainingContext: (sessionId: string) => void;
}

export const useUiStore = create<UiState & UiActions>((set) => ({
  // State
  leftTab: 'chat',
  selectedProjectId: null,
  attitude: 'yuesheng',
  attitudeLocked: false,
  trainingContexts: {},

  // Actions
  setLeftTab: (tab) => set({ leftTab: tab }),

  setSelectedProjectId: (id) => set({ selectedProjectId: id }),

  setAttitude: (level) =>
    set((s) => (s.attitudeLocked ? {} : { attitude: level })),

  toggleAttitudeLock: () =>
    set((s) => ({ attitudeLocked: !s.attitudeLocked })),

  setTrainingContext: (sessionId, ctx) =>
    set((s) => ({
      trainingContexts: { ...s.trainingContexts, [sessionId]: ctx },
    })),

  clearTrainingContext: (sessionId) =>
    set((s) => {
      const { [sessionId]: _removed, ...rest } = s.trainingContexts;
      return { trainingContexts: rest };
    }),
}));
