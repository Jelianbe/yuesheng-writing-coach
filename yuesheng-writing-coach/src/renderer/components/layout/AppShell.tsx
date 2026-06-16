import React from 'react';
import { PanelRightOpen } from 'lucide-react';
import { APP_SHELL_MIN_WIDTH, CHAT_AREA_MIN_WIDTH } from './layout.constants';
import { useUiLayoutStore } from '../../stores/ui-layout.store';
import { WindowControls } from './WindowControls';
import styles from './AppShell.module.css';

export interface AppShellProps {
  /** 侧边栏组件 */
  sidebar: React.ReactNode;
  /** 主内容区（对话区） */
  children: React.ReactNode;
  /** 右侧面板组件（可选） */
  rightPanel?: React.ReactNode;
}

/**
 * AppShell V2 — SOLO 三栏布局（无 Header）
 *
 * 布局结构（V2 SOLO 模式）：
 * ┌──────────┬──────────────────────────┬──────────────┐
 * │          │                          │              │
 * │ Sidebar  │     Chat Area            │  Tool Panel  │
 * │  (240px) │      (flex:1)           │  (380/0px)   │
 * │          │       ≥60%              │              │
 * │          │                          │              │
 * ──────────┴──────────────────────────┴──────────────┘
 *
 * - 无 Header：沉浸式写作体验
 * - 对话区 flex:1，物理上确保 ≥60% 屏幕宽度
 * - 右侧面板双态：0px 完全隐藏 ↔ 380px 展开面板
 * - 窗口右上角：[＋][⚙][⤢][─][□][✕] 由 WindowControls 统一管理
 */
export const AppShell: React.FC<AppShellProps> = React.memo(({
  sidebar,
  children,
  rightPanel,
}) => {
  // 左侧栏状态（用于品牌标识悬浮）
  const sidebarCollapsed = useUiLayoutStore(s => s.sidebarCollapsed);
  const toggleSidebar = useUiLayoutStore(s => s.toggleSidebar);

  return (
    <div
      className="app-solo"
      style={{
        display: 'flex',
        height: '100vh',
        minWidth: `${APP_SHELL_MIN_WIDTH}px`,
        background: 'var(--bg-page)',
        overflow: 'hidden',
      }}
    >
      {/* 品牌标识悬浮 — 左侧栏收起态时显示，共用中间栏背景 */}
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

      {/* Sidebar — 左侧 240px */}
      {sidebar}

      {/* Main content — 对话区，flex:1 确保 ≥60% */}
      <main
        className="solo-chat-area"
        style={{
          flex: 1,
          display: 'flex',
          flexDirection: 'column',
          minWidth: CHAT_AREA_MIN_WIDTH,
          maxWidth: '100%',
          background: 'var(--bg-main)',
          overflow: 'hidden',
          position: 'relative',
          borderLeft: '1px solid var(--border)',
          borderRight: rightPanel ? '1px solid var(--border)' : 'none',
        }}
        role="main"
        aria-label="对话区"
      >
        {children}
      </main>

      {/* Right panel — 双态：0px 完全隐藏 ↔ 380px 展开面板 */}
      {rightPanel}

      {/* 窗口控制按钮 — [＋][⚙][⤢][─][□][✕] */}
      <WindowControls />
    </div>
  );
});

AppShell.displayName = 'AppShell';
