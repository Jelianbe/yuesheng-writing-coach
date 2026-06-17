// UI 布局状态管理（Zustand）
// 负责：管理界面布局状态（侧栏折叠、侧栏视图、栏宽度、拖拽状态）
// 依赖：zustand
// 扩展: RWR-P1-1 增加三栏独立宽度调整 + 拖拽状态机

import { create } from 'zustand';

/** SOLO 侧栏视图 */
export type SidebarView = 'projects' | 'sessions';

/** 拖拽目标（当前正在调整哪一栏） */
export type ResizeTarget = 'sidebar' | 'rightPanel' | null;

/** 三栏宽度默认值与边界（来自 layout.constants） */
const DEFAULT_SIDEBAR_WIDTH = 240;
const MIN_SIDEBAR_WIDTH = 200;
const MAX_SIDEBAR_WIDTH = 480;
const PANEL_RESIZE_MIN = 320;
const PANEL_RESIZE_MAX = 720;
const DEFAULT_PANEL_WIDTH = 420;

interface UiLayoutState {
  /** 左侧栏是否折叠 */
  sidebarCollapsed: boolean;
  /** 左侧栏当前视图（项目/对话） */
  sidebarView: SidebarView;
  /** 左侧栏宽度（px，RWR-P1-1 新增） */
  sidebarWidth: number;
  /** 右侧栏宽度（px，RWR-P1-1 新增） */
  rightPanelWidth: number;
  /** 拖拽状态机（idle / dragging sidebar / dragging rightPanel） */
  resizing: ResizeTarget;
}

interface UiLayoutActions {
  /** 切换侧栏折叠 */
  toggleSidebar: () => void;
  /** 切换侧栏视图 */
  setSidebarView: (view: SidebarView) => void;
  /** 设置左侧栏宽度（带边界裁剪，RWR-P1-1 新增） */
  setSidebarWidth: (width: number) => void;
  /** 设置右侧栏宽度（带边界裁剪，RWR-P1-1 新增） */
  setRightPanelWidth: (width: number) => void;
  /** 开始拖拽（RWR-P1-1 新增） */
  startResize: (target: ResizeTarget) => void;
  /** 结束拖拽（RWR-P1-1 新增） */
  endResize: () => void;
}

/** 工具: 数值裁剪到 [min, max] 区间 */
const clamp = (value: number, min: number, max: number): number =>
  Math.min(max, Math.max(min, value));

export const useUiLayoutStore = create<UiLayoutState & UiLayoutActions>((set) => ({
  // State
  sidebarCollapsed: false,
  sidebarView: 'sessions',
  sidebarWidth: DEFAULT_SIDEBAR_WIDTH,
  rightPanelWidth: DEFAULT_PANEL_WIDTH,
  resizing: null,

  // Actions
  toggleSidebar: () => set((s) => ({ sidebarCollapsed: !s.sidebarCollapsed })),

  setSidebarView: (view) => set({ sidebarView: view }),

  setSidebarWidth: (width) =>
    set({ sidebarWidth: clamp(width, MIN_SIDEBAR_WIDTH, MAX_SIDEBAR_WIDTH) }),

  setRightPanelWidth: (width) =>
    set({ rightPanelWidth: clamp(width, PANEL_RESIZE_MIN, PANEL_RESIZE_MAX) }),

  startResize: (target) => set({ resizing: target }),

  endResize: () => set({ resizing: null }),
}));
