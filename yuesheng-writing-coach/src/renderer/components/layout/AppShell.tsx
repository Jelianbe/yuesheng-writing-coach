import React, { useCallback, useEffect, useRef, useState } from 'react';
import { PanelRightOpen } from 'lucide-react';
import {
  APP_SHELL_MIN_WIDTH,
  CHAT_AREA_MIN_WIDTH,
  PANEL_RESIZE_MIN,
  PANEL_RESIZE_MAX,
} from './layout.constants';
import { useUiLayoutStore, type ResizeTarget } from '../../stores/ui-layout.store';
import { WindowControls } from './WindowControls';
import styles from '../../styles/AppShell.module.css';

export interface AppShellProps {
  /** 侧边栏组件 */
  sidebar: React.ReactNode;
  /** 主内容区(对话区) */
  children: React.ReactNode;
  /** 右侧面板组件(可选) */
  rightPanel?: React.ReactNode;
}

/** 响应式断点: < 1280px 右栏 overlay 模式 */
const OVERLAY_BREAKPOINT = '(max-width: 1279px)';

/**
 * AppShell V2 — SOLO 三栏独立布局(RWR-P1-1 重写版)
 *
 * 布局结构(可独立调整宽度):
 * ┌──────────┬──┬──────────────────────────┬──┬──────────────┐
 * │ Sidebar  │↔ │     Chat Area            │↔ │  Tool Panel  │
 * │ (200-480)│  │      (flex:1, ≥400)     │  │ (320-720/0)  │
 * │          │  │                          │  │              │
 * └──────────┴──┴──────────────────────────┴──┴──────────────┘
 *
 * 特性:
 * - 三栏独立可调宽度(拖拽手柄)
 * - 拖拽响应延迟 < 100ms(无过渡)
 * - < 1280px: 右栏 overlay 模式(滑入)
 * - 300ms 过渡动画(cubic-bezier)
 * - 折叠态: 0px 完全收起,无残留
 */
export const AppShell: React.FC<AppShellProps> = React.memo(({
  sidebar,
  children,
  rightPanel,
}) => {
  // 布局状态
  const sidebarCollapsed = useUiLayoutStore((s) => s.sidebarCollapsed);
  const sidebarWidth = useUiLayoutStore((s) => s.sidebarWidth);
  const rightPanelWidth = useUiLayoutStore((s) => s.rightPanelWidth);
  const resizing = useUiLayoutStore((s) => s.resizing);
  const toggleSidebar = useUiLayoutStore((s) => s.toggleSidebar);
  const setSidebarWidth = useUiLayoutStore((s) => s.setSidebarWidth);
  const setRightPanelWidth = useUiLayoutStore((s) => s.setRightPanelWidth);
  const startResize = useUiLayoutStore((s) => s.startResize);
  const endResize = useUiLayoutStore((s) => s.endResize);

  // 响应式: < 1280px 进入 overlay 模式
  const [isOverlay, setIsOverlay] = useState(
    () => window.matchMedia(OVERLAY_BREAKPOINT).matches
  );

  useEffect(() => {
    const mql = window.matchMedia(OVERLAY_BREAKPOINT);
    const handler = (e: MediaQueryListEvent) => setIsOverlay(e.matches);
    mql.addEventListener('change', handler);
    return () => mql.removeEventListener('change', handler);
  }, []);

  // 拖拽逻辑(RWR-P1-1 新增)
  // 使用 ref 记录拖拽起始位置,避免 React state 频繁更新
  const dragStateRef = useRef<{
    target: ResizeTarget;
    startX: number;
    startWidth: number;
  } | null>(null);

  const handleMouseDown = useCallback(
    (target: Exclude<ResizeTarget, null>) => (e: React.MouseEvent) => {
      e.preventDefault();
      const startWidth =
        target === 'sidebar' ? sidebarWidth : rightPanelWidth;
      dragStateRef.current = {
        target,
        startX: e.clientX,
        startWidth,
      };
      startResize(target);
    },
    [sidebarWidth, rightPanelWidth, startResize]
  );

  // 全局 mousemove / mouseup 监听(仅在拖拽时生效)
  useEffect(() => {
    if (!resizing) return;

    const handleMouseMove = (e: MouseEvent) => {
      const state = dragStateRef.current;
      if (!state) return;
      const delta = e.clientX - state.startX;
      if (state.target === 'sidebar') {
        // 左侧栏: 向右拖=加宽,向左拖=缩窄
        setSidebarWidth(state.startWidth + delta);
      } else if (state.target === 'rightPanel') {
        // 右侧栏: 向左拖=加宽(反向)
        setRightPanelWidth(state.startWidth - delta);
      }
    };

    const handleMouseUp = () => {
      dragStateRef.current = null;
      endResize();
    };

    // 用 passive: false 允许 preventDefault
    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('mouseup', handleMouseUp);
    return () => {
      document.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('mouseup', handleMouseUp);
    };
  }, [resizing, setSidebarWidth, setRightPanelWidth, endResize]);

  // 计算当前激活的拖拽手柄
  const isDragging = resizing !== null;

  return (
    <div
      className={isDragging ? `${styles.shell} ${styles.shellDragging}` : styles.shell}
      style={
        {
          minWidth: `${APP_SHELL_MIN_WIDTH}px`,
          // CSS 变量传递宽度给子元素
          ['--sidebar-width' as string]: `${sidebarWidth}px`,
          ['--right-panel-width' as string]: `${rightPanelWidth}px`,
        } as React.CSSProperties
      }
    >
      {/* 品牌标识悬浮 — 侧栏折叠态时显示 */}
      {sidebarCollapsed && (
        <div className={styles.brandFloat}>
          <span className={styles.brandText}>月笙</span>
          <button
            onClick={toggleSidebar}
            className={styles.brandBtn}
            title="展开侧边栏"
            aria-label="展开侧边栏"
          >
            <PanelRightOpen size={14} strokeWidth={1.6} />
          </button>
        </div>
      )}

      {/* Sidebar — 左侧栏 */}
      <aside
        className={
          sidebarCollapsed
            ? `${styles.sidebar} ${styles.sidebarCollapsed}`
            : styles.sidebar
        }
        aria-label="侧边栏"
        aria-hidden={sidebarCollapsed}
      >
        {sidebar}
      </aside>

      {/* 侧栏拖拽手柄(展开态才显示) */}
      {!sidebarCollapsed && (
        <div
          className={
            resizing === 'sidebar'
              ? `${styles.handle} ${styles.handleActive}`
              : styles.handle
          }
          onMouseDown={handleMouseDown('sidebar')}
          role="separator"
          aria-orientation="vertical"
          aria-label="调整侧栏宽度"
          aria-valuenow={sidebarWidth}
          aria-valuemin={200}
          aria-valuemax={480}
          tabIndex={0}
        />
      )}

      {/* Main content — 主区 */}
      <main
        className={styles.main}
        style={{ minWidth: CHAT_AREA_MIN_WIDTH }}
        role="main"
        aria-label="对话区"
      >
        {children}
      </main>

      {/* 右栏拖拽手柄(右栏存在且非 overlay 模式) */}
      {rightPanel && !isOverlay && (
        <div
          className={
            resizing === 'rightPanel'
              ? `${styles.handle} ${styles.handleActive}`
              : styles.handle
          }
          onMouseDown={handleMouseDown('rightPanel')}
          role="separator"
          aria-orientation="vertical"
          aria-label="调整右栏宽度"
          aria-valuenow={rightPanelWidth}
          aria-valuemin={PANEL_RESIZE_MIN}
          aria-valuemax={PANEL_RESIZE_MAX}
          tabIndex={0}
        />
      )}

      {/* Right panel — 右侧栏(可选) */}
      {rightPanel && (
        <aside
          className={
            isOverlay
              ? styles.rightPanel // overlay 模式由 CSS 定位
              : styles.rightPanel
          }
          style={{ minWidth: 0 }}
          aria-label="工具面板"
        >
          {rightPanel}
        </aside>
      )}

      {/* 窗口控制按钮 — [＋][⚙][⤢][─][□][✕] */}
      <WindowControls />
    </div>
  );
});

AppShell.displayName = 'AppShell';
