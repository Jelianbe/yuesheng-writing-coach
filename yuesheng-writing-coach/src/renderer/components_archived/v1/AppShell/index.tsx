/**
 * AppShell — 三栏布局外壳
 *
 * CSS Grid 三栏结构：
 * - 左栏（LeftPanel）：宽度由 useUiLayoutStore.sidebarWidth 控制，可折叠
 * - 中栏（CenterPanel）：flex-1 自适应
 * - 右栏（RightPanel）：固定宽度，由 useUiLayoutStore.rightPanelWidth 控制
 *
 * 左右栏间均有可拖拽 resize handle（ResizeHandle）。
 *
 * 用法:
 * ```tsx
 * <AppShell />
 * ```
 */
import { LeftPanel } from '@/components/layout/LeftPanel';
import { CenterPanel } from '@/components/layout/CenterPanel';
import { RightPanel } from '@/components/layout/RightPanel';
import { ResizeHandle } from '@/components/common/ResizeHandle';
import styles from './index.module.css';

export function AppShell(): JSX.Element {
  return (
    <div className={styles.shell} data-testid="app-shell">
      <LeftPanel />
      <ResizeHandle side="left" />
      <CenterPanel />
      <ResizeHandle side="right" />
      <RightPanel />
    </div>
  );
}
