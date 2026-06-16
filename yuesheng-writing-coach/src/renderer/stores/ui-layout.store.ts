// UI 布局状态管理（Zustand）
// 负责：管理界面布局状态（侧栏折叠、侧栏视图）
// 依赖：zustand

import { create } from 'zustand';

/** SOLO 侧栏视图 */
export type SidebarView = 'projects' | 'sessions';

interface UiLayoutState {
  /** 左侧栏是否折叠 */
  sidebarCollapsed: boolean;
  /** 左侧栏当前视图（项目/对话） */
  sidebarView: SidebarView;
  /** 右侧栏是否收起到图标条模式 */
  rightSidebarCollapsed: boolean;
}

interface UiLayoutActions {
  /** 切换侧栏折叠 */
  toggleSidebar: () => void;
  /** 切换侧栏视图 */
  setSidebarView: (view: SidebarView) => void;
  /** 设置右侧栏收起状态 */
  setRightSidebarCollapsed: (v: boolean) => void;
}

export const useUiLayoutStore = create<UiLayoutState & UiLayoutActions>((set) => ({
  // State
  sidebarCollapsed: false,
  sidebarView: 'sessions',
  rightSidebarCollapsed: true,

  // Actions
  toggleSidebar: () => set((s) => ({ sidebarCollapsed: !s.sidebarCollapsed })),

  setSidebarView: (view) => set({ sidebarView: view }),

  setRightSidebarCollapsed: (v) => set({ rightSidebarCollapsed: v }),
}));
