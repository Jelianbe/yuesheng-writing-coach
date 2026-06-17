/**
 * 右侧抽屉状态管理
 *
 * 职责：控制右侧栏的展开/收起状态和当前激活的面板
 *
 * == 协作协议（X-01）==
 * 与右侧栏其他 store（panel-session.store / chapter.store）的协作规则：
 * 1. drawer.store 仅管理"抽屉开关 + 面板类型"（SSOT：面板开闭状态）
 * 2. panel-session.store 管理 "L1 标签会话"（SSOT：右侧栏打开内容）
 * 3. chapter.store 管理 "章节内容展示"（SSOT：编辑器标签）
 *    drawer.activePanel 由当前活跃会话的类型反推，非独立状态源。
 *
 * **所有多 Store 操作必须通过 right-panel.actions.ts 的统一入口，**
 * **禁止外部代码直接协调三个 Store。**
 *
 * 正确用法（X-01 协议）：
 *   rightPanelActions.openTool('training');       // 训练面板
 *   rightPanelActions.openEditor(chapterId, title); // 章节编辑器
 *   rightPanelActions.removeSession(sessionId);    // 移除会话（自动收起）
 *   rightPanelActions.switchSession(sessionId);    // 切换标签（同步面板）
 *
 * 错误用法（违反协议 — 手工协调多 Store）：
 *   useDrawerStore.getState().openPanel('works');
 *   usePanelSessionStore.getState().upsertSession('edit', '编辑', '');
 *
 * === 映射关系 ===
 * 使用 drawer-constants.ts 中的 TOOL_TO_SESSION_TYPE / SESSION_TYPE_TO_TOOL_ID
 * 在 panelId 和 sessionType 之间双向转换。
 */

import { create } from 'zustand';

/** 右侧抽屉可展示的面板类型 */
export type DrawerPanelId = 'diagnosis' | 'growth' | 'profile' | 'tools' | 'training' | 'search' | 'works' | 'progress' | '__settings__';

interface DrawerState {
  /** 当前打开的面板 ID，null = 关闭 */
  activePanel: DrawerPanelId | null;
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
  /** 切换收起/展开状态 */
  toggleCollapsed: () => void;
  /** 直接设置收起状态 */
  setCollapsed: (v: boolean) => void;
}

export const useDrawerStore = create<DrawerState & DrawerActions>((set) => ({
  // State
  activePanel: null,
  collapsed: true,

  // Actions
  openPanel: (panel) => set({ activePanel: panel, collapsed: false }),
  closePanel: () => set({ activePanel: null }),
  togglePanel: (panel) =>
    set((s) =>
      s.activePanel === panel
        ? { activePanel: null }
        : { activePanel: panel, collapsed: false }
    ),
  toggleCollapsed: () => set((s) => ({ collapsed: !s.collapsed })),
  setCollapsed: (v) => set({ collapsed: v }),
}));
