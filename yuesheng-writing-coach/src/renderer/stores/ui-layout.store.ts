// UI 布局状态管理（Zustand）
// 负责：管理界面布局状态（侧栏折叠、右侧面板模式、对话区宽度等）
// 依赖：zustand

import { create } from 'zustand';

/** 右侧面板模式 */
export type RightPanelMode = 'collapsed' | 'icons' | 'expanded';

/** SOLO 侧栏视图 */
export type SidebarView = 'projects' | 'sessions';

interface UiLayoutState {
  /** 左侧栏是否折叠 */
  sidebarCollapsed: boolean;
  /** 左侧栏当前视图（项目/对话） */
  sidebarView: SidebarView;
  /** 右侧面板模式 */
  rightPanelMode: RightPanelMode;
  /** 上次展开的面板 ID（用于记忆） */
  lastPanelId: string | null;
  /** 对话区宽度百分比（默认 60） */
  chatAreaWidthPercent: number;
}

interface UiLayoutActions {
  /** 切换侧栏折叠 */
  toggleSidebar: () => void;
  /** 设置侧栏折叠状态 */
  setSidebarCollapsed: (v: boolean) => void;
  /** 切换侧栏视图 */
  setSidebarView: (view: SidebarView) => void;
  /** 切换右侧面板模式 */
  setRightPanelMode: (mode: RightPanelMode) => void;
  /** 展开指定面板（附带记忆） */
  expandPanel: (panelId: string) => void;
  /** 收起右侧面板 */
  collapseRightPanel: () => void;
  /** 设置对话区宽度 */
  setChatAreaWidthPercent: (pct: number) => void;
}

export const useUiLayoutStore = create<UiLayoutState & UiLayoutActions>((set) => ({
  // State
  sidebarCollapsed: false,
  sidebarView: 'sessions',
  rightPanelMode: 'collapsed',
  lastPanelId: null,
  chatAreaWidthPercent: 60,

  // Actions
  toggleSidebar: () => set((s) => ({ sidebarCollapsed: !s.sidebarCollapsed })),
  setSidebarCollapsed: (v) => set({ sidebarCollapsed: v }),

  setSidebarView: (view) => set({ sidebarView: view }),

  setRightPanelMode: (mode) => set({ rightPanelMode: mode }),

  expandPanel: (panelId) => set({
    rightPanelMode: 'expanded',
    lastPanelId: panelId,
  }),

  collapseRightPanel: () => set({
    rightPanelMode: 'collapsed',
  }),

  setChatAreaWidthPercent: (pct) => set({ chatAreaWidthPercent: Math.max(50, Math.min(80, pct)) }),
}));
