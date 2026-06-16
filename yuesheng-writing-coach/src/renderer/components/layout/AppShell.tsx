import React, { useCallback } from 'react';
import { Plus, Settings } from 'lucide-react';
import { WindowControls } from './WindowControls';
import { useSessionStore } from '../../stores/session.store';
import { useUiLayoutStore } from '../../stores/ui-layout.store';
import { rightPanelService } from '../../services/right-panel.service';
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
 * AppShell V3 — SOLO 三栏布局（自定义标题栏）
 *
 * 布局结构：
 * ┌──────────┬──────────────────────────┬──────────────────────────┐
 * │ Sidebar  │     Chat Area            │  Right Drawer            │
 * │  (240px) │      (flex:1)           │  (420px / 48px)          │
 * │          │              [＋][⚙]     │  [标签...][＋]    [⤢]    │
 * └──────────┴──────────────────────────┴──────────────────────────┘
 *
 * - [＋][⚙] 在中间栏右上浮动（新建对话 + 打开设置）
 * - [⤢] 在右侧栏 header 右端（展开/收起 toggle）
 * - [─][□][✕] 窗口级 fixed 渲染
 * - 收起态时右侧栏保留 header（显示 [⤢]），内容区隐藏
 */
export const AppShell: React.FC<AppShellProps> = React.memo(({
  sidebar,
  children,
  rightPanel,
}) => {
  // 监听右侧栏状态，调整 [＋][⚙] 位置
  const rightSidebarCollapsed = useUiLayoutStore(s => s.rightSidebarCollapsed);

  const handleNewChat = useCallback(async () => {
    const s = await useSessionStore.getState().createSession();
    if (s) await useSessionStore.getState().switchSession(s.id);
  }, []);

  const handleOpenSettings = useCallback(() => {
    rightPanelService.switchTo('__settings__');
  }, []);

  // 收起态：[＋][⚙] 紧靠窄条（48px）左侧 → right: 48px
  // 展开态：[＋][⚙] 与右侧栏左边界对齐 → right: 0
  const plusSettingsRight = rightSidebarCollapsed ? '48px' : '0';

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
      {/* Sidebar — 左侧 */}
      {sidebar}

      {/* Main content — 对话区 */}
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
        {/* 中间栏右上浮动 [＋][⚙] — 设计 §2.3 */}
        <div
          style={{
            position: 'absolute',
            top: 0,
            right: plusSettingsRight,
            height: '40px',
            display: 'flex',
            alignItems: 'center',
            gap: '2px',
            zIndex: 10,
            pointerEvents: 'auto',
            transition: 'right 200ms ease',
          }}
        >
          <button
            onClick={handleNewChat}
            title="新建对话"
            aria-label="新建对话"
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              justifyContent: 'center',
              width: '28px',
              height: '28px',
              border: 'none',
              background: 'transparent',
              cursor: 'pointer',
              borderRadius: 'var(--radius-sm)',
              color: 'var(--text-secondary)',
              transition: 'color 120ms ease',
            }}
            onMouseEnter={e => { (e.currentTarget as HTMLButtonElement).style.color = 'var(--accent)'; }}
            onMouseLeave={e => { (e.currentTarget as HTMLButtonElement).style.color = 'var(--text-secondary)'; }}
          >
            <Plus size={16} strokeWidth={1.5} />
          </button>
          <button
            onClick={handleOpenSettings}
            title="打开设置"
            aria-label="打开设置"
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              justifyContent: 'center',
              width: '28px',
              height: '28px',
              border: 'none',
              background: 'transparent',
              cursor: 'pointer',
              borderRadius: 'var(--radius-sm)',
              color: 'var(--text-secondary)',
              transition: 'color 120ms ease',
            }}
            onMouseEnter={e => { (e.currentTarget as HTMLButtonElement).style.color = 'var(--accent)'; }}
            onMouseLeave={e => { (e.currentTarget as HTMLButtonElement).style.color = 'var(--text-secondary)'; }}
          >
            <Settings size={16} strokeWidth={1.5} />
          </button>
        </div>

        {children}
      </main>

      {/* Right panel */}
      {rightPanel}

      {/* 窗口控制按钮 [─][□][✕] — 窗口级 fixed */}
      <WindowControls />
    </div>
  );
});

AppShell.displayName = 'AppShell';
