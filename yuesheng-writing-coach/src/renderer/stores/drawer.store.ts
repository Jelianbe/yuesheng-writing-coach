import { create } from 'zustand';

/** 右侧抽屉可展示的面板类型 */
export type DrawerPanelId = 'diagnosis' | 'growth' | 'profile' | 'tools' | 'training' | 'tasks' | 'search' | 'works' | '__settings__';

interface DrawerState {
  /** 当前打开的面板 ID，null = 关闭 */
  activePanel: DrawerPanelId | null;
  /** 是否正在执行滑入/滑出动画 */
  isAnimating: boolean;
  /** 右侧栏是否处于收起（图标条）模式，默认收起 */
  collapsed: boolean;
}

interface DrawerActions {
  /** 打开指定面板（若已打开其他面板则先关闭再打开） */
  openPanel: (panel: DrawerPanelId) => void;
  /** 关闭当前面板（不自动收起，保持展开态方便下次使用） */
  closePanel: () => void;
  /** 切换：打开则关闭，关闭则打开 */
  togglePanel: (panel: DrawerPanelId) => void;
  /** 设置动画状态（由 RightDrawer 组件内部调用） */
  setAnimating: (v: boolean) => void;
  /** 切换收起/展开状态 */
  toggleCollapsed: () => void;
  /** 直接设置收起状态 */
  setCollapsed: (v: boolean) => void;
}

export const useDrawerStore = create<DrawerState & DrawerActions>((set) => ({
  // State
  activePanel: null,
  isAnimating: false,
  collapsed: true,

  // Actions
  openPanel: (panel) => set({ activePanel: panel, collapsed: false }),
  closePanel: () => set({ activePanel: null, isAnimating: false }),
  togglePanel: (panel) =>
    set((s) =>
      s.activePanel === panel
        ? { activePanel: null, isAnimating: false }
        : { activePanel: panel, collapsed: false }
    ),
  setAnimating: (v) => set({ isAnimating: v }),
  toggleCollapsed: () => set((s) => ({ collapsed: !s.collapsed })),
  setCollapsed: (v) => set({ collapsed: v }),
}));
