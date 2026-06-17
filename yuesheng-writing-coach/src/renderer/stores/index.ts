/**
 * src/renderer/stores/index.ts — Renderer 端 Zustand Store 桶导出（barrel）
 *
 * 职责：
 * - 统一从单一入口导出所有 renderer store
 * - 消费者 import 路径：`import { useXxxStore } from '@/stores'` 或 `from '../stores'`
 *
 * 当前导出（X-01 协议三大 store + 协作入口）：
 * - useDrawerStore / DrawerPanelId       — 抽屉开闭 + 面板类型
 * - usePanelSessionStore / *             — L1 标签会话
 * - useChapterStore                       — 编辑器章节标签
 * - useRightPanelStore / RightPanelToolId — 多 Store 协作统一入口
 *
 * 规约：
 * - 多 Store 协调场景必须通过 useRightPanelStore（X-01 协议）
 * - 不允许外部代码手工直接协调 drawer / panel-session / chapter
 * - 新增 store 须在此桶中显式导出，避免被遗漏
 */

export { useDrawerStore, type DrawerPanelId } from './drawer.store';
export {
  usePanelSessionStore,
  type SidebarPhase,
  type SidebarMode,
  type PanelSessionType,
  type PanelSessionData,
  type PanelSession,
} from './panel-session.store';
export { useChapterStore } from './chapter.store';
export {
  useRightPanelStore,
  type RightPanelToolId,
} from './right-panel.store';
