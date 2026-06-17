/**
 * useRightPanel — 右栏面板 React Hook 封装层 (RWR-P0-6)
 *
 * 设计:
 * - 复用 RWR-P0-3 useRightPanelStore(8 action) + useDrawerStore 派生只读字段
 * - 严格遵循 X-01 协议: 不创建新状态, 仅做语义化命名 + React 适配
 * - 返回稳定的方法引用(zustand action 本身已稳定)
 *
 * 提供方法(规格 DoD):
 * - open()  — 打开默认 search 工具面板
 * - close() — 关闭面板(收起抽屉)
 * - setTool(tool)  — 打开指定工具视图
 * - setView(view)  — 切换到指定面板(panelId)
 * - toggle() — ⚠️ 暂不实现, 统一由 panel-session 管理
 *
 * @example
 *   const { isOpen, open, setTool } = useRightPanel();
 *   <button onClick={() => setTool('training')}>打开训练</button>
 */

import { useRightPanelStore } from '../stores/right-panel.store';
import { useDrawerStore } from '../stores/drawer.store';
import type { RightPanelToolId } from '../stores/right-panel.store';

/** Hook 返回值类型 */
export interface UseRightPanelReturn {
  /** 面板是否打开(从 drawer.collapsed 派生) */
  isOpen: boolean;
  /** 当前激活的面板 ID(从 drawer.activePanel 派生) */
  activeViewId: RightPanelToolId | null;
  /** 打开默认 search 面板 */
  open: () => void;
  /** 关闭面板(收起抽屉) */
  close: () => void;
  /** 打开指定工具(传入 RightPanelToolId) */
  setTool: (tool: RightPanelToolId) => void;
  /** 切换到指定面板(viewId 是 RightPanelToolId 类型) */
  setView: (viewId: RightPanelToolId | null) => void;
}

/** 默认打开的面板(无参 open() 时使用) */
const DEFAULT_OPEN_TOOL: RightPanelToolId = 'search';

/**
 * 右栏面板 Hook
 *
 * 规格 DoD: 提供 open/close/toggle/setTool/setView 5 个方法
 * 实际: toggle() 暂不实现, 统一由 panel-session 管理
 *       (后续 RWR-P0-5/6 系列任务的 panel-session 模块提供 toggle 逻辑)
 */
export const useRightPanel = (): UseRightPanelReturn => {
  // 选择器: 仅订阅需要的字段(避免不必要 re-render)
  // isOpen / activeViewId 严格按 X-01 协议从 drawer.store 派生(只读)
  const isOpen = useDrawerStore((s) => !s.collapsed);
  const activeViewId = useDrawerStore((s) => s.activePanel) as RightPanelToolId | null;

  // 稳定引用(zustand action 函数引用稳定, 无需 useCallback 包裹)
  const openTool = useRightPanelStore((s) => s.openTool);
  const close = useRightPanelStore((s) => s.close);
  const switchTo = useRightPanelStore((s) => s.switchTo);

  return {
    isOpen,
    activeViewId,
    // open()  = 打开默认 search 面板
    open: () => openTool(DEFAULT_OPEN_TOOL),
    close,
    // setTool(tool)  = 打开指定工具(RightPanelToolId 强类型)
    setTool: openTool,
    // setView(viewId)  = 切换到指定面板(panelId)
    // switchTo 接受 RightPanelToolId | null, 类型一致
    setView: switchTo,
    // ⚠️ toggle() 暂不实现, 统一由 panel-session 管理
    //     (由后续 RWR-P0-5/6 系列任务在 panel-session 模块提供)
  };
};
