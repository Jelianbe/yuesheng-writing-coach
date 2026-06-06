import React from 'react';

export interface AppShellProps {
  /** 顶栏组件 */
  header: React.ReactNode;
  /** 侧边栏组件 */
  sidebar: React.ReactNode;
  /** 主内容区 */
  children: React.ReactNode;
  /** 右侧面板组件（可选） */
  rightPanel?: React.ReactNode;
}

/**
 * AppShell — flex-column 布局容器
 *
 * 布局结构：
 * ┌─────────────────────────────────────────┐
 * │  Header (80px)                          │
 * ├────────┬──────────────────┬─────────────┤
 * │        │                  │             │
 * │ Sidebar│   Main Content   │ Right Panel │
 * │(280px) │    (flex:1)     │  (340px)    │
 * │        │                  │             │
 * └────────┴──────────────────┴─────────────┘
 *
 * RightPanel 自身管理折叠状态（collapsed prop），自带 toggle 按钮和过渡动画。
 */
export const AppShell: React.FC<AppShellProps> = React.memo(({
  header,
  sidebar,
  children,
  rightPanel,
}) => {
  return (
    <div
      className="app"
      style={{
        display: 'flex',
        flexDirection: 'column',
        height: '100vh',
        background: 'var(--bg-page)',
      }}
    >
      {/* Header — full-width top bar */}
      {header}

      {/* Content row: sidebar + main + right panel */}
      <div
        className="content-row"
        style={{
          display: 'flex',
          flex: 1,
          overflow: 'hidden',
          position: 'relative',
        }}
      >
        {/* Sidebar */}
        {sidebar}

        {/* Main content */}
        <main
          className="main"
          style={{
            flex: 1,
            display: 'flex',
            flexDirection: 'column',
            minWidth: 0,
            background: 'var(--bg-main)',
            overflow: 'hidden',
            position: 'relative',
          }}
          role="main"
          aria-label="Main content"
        >
          {children}
        </main>

        {/* Right panel — self-contained component with collapse support */}
        {rightPanel}
      </div>
    </div>
  );
});

AppShell.displayName = 'AppShell';
