import React from 'react';
import { APP_SHELL_MIN_WIDTH, CHAT_AREA_MIN_WIDTH } from './layout.constants';

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
 * │  (240px) │      (flex:1)           │  (380/48px)  │
 * │          │       ≥60%              │              │
 * │          │                          │              │
 * └──────────┴──────────────────────────┴──────────────┘
 *
 * - 无 Header：沉浸式写作体验
 * - 对话区 flex:1，物理上确保 ≥60% 屏幕宽度
 * - 右侧面板双态：48px 图标条 ↔ 380px 展开面板
 */
export const AppShell: React.FC<AppShellProps> = React.memo(({
  sidebar,
  children,
  rightPanel,
}) => {
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

      {/* Right panel — 双态：48px 图标条 ↔ 380px 展开面板 */}
      {rightPanel}
    </div>
  );
});

AppShell.displayName = 'AppShell';
