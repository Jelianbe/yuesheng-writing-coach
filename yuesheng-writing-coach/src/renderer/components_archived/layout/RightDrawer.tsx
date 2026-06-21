import React, { useCallback, useState, useEffect, useRef } from 'react';
import { Plus } from 'lucide-react';
import { useDrawerStore } from '../../stores/drawer.store';
import { usePanelSessionStore } from '../../stores/panel-session.store';
import { useRightPanelStore } from '../../stores';
import { SessionTabBar } from './SessionTabBar';
import { ToolGrid } from './ToolGrid';
import {
  DEFAULT_TOOLS, SESSION_LUCIDE_ICON, EASE_OUT_QUART,
  DEFAULT_PANEL_WIDTH, RESIZE_MIN, RESIZE_MAX, STORAGE_KEY, Z_LAYER,
} from './drawer-constants';
import type { ToolItem } from './drawer-constants';
import styles from './RightDrawer.module.css';

export interface RightDrawerProps {
  tools?: ToolItem[];
  panelContent?: Record<string, React.ReactNode>;
  onToolClick?: (toolId: string) => void;
}

/**
 * RightDrawer V5 — 设计文档 2026-06-15 对齐
 *
 * 结构：[拖拽handle][标签header][内容区]
 * - 移除 navBar（图标条），功能由标签层取代
 * - 收起态：header 保留（约 160px），显示 [标签][＋] [⤢]
 * - 展开态：完整显示 header + 内容区
 * - 拖拽 handle 在左边缘
 */
export const RightDrawer: React.FC<RightDrawerProps> = React.memo(({
  tools = DEFAULT_TOOLS, panelContent, onToolClick,
}) => {
  const activePanel = useDrawerStore(s => s.activePanel);
  const collapsed = useDrawerStore(s => s.collapsed);
  const closePanel = useDrawerStore(s => s.closePanel);
  const sessions = usePanelSessionStore(s => s.sessions);
  const activeSessionId = usePanelSessionStore(s => s.activeSessionId);

  // ── 可拖拽宽度（localStorage 持久化）──
  const [panelWidth, setPanelWidth] = useState(() => {
    try {
      const saved = localStorage.getItem(STORAGE_KEY);
      if (saved) { const w = parseInt(saved, 10); if (!isNaN(w) && w >= RESIZE_MIN && w <= RESIZE_MAX) return w; }
    } catch (e) {
      if (process.env.NODE_ENV === 'development') {
        console.warn('[RightDrawer] Failed to read localStorage:', e);
      }
    }
    return DEFAULT_PANEL_WIDTH;
  });
  useEffect(() => { try { localStorage.setItem(STORAGE_KEY, String(panelWidth)); } catch (e) {
    if (process.env.NODE_ENV === 'development') {
      console.warn('[RightDrawer] Failed to write localStorage:', e);
    }
  } }, [panelWidth]);

  // ── 拖拽状态 ──
  const [isResizing, setIsResizing] = useState(false);
  const resizeStartX = useRef(0);
  const resizeStartWidth = useRef(0);

  const isExpanded = !collapsed && activePanel !== null;
  // 收起态：仅 header 宽度（约 160px）；展开态：完整宽度
  const COLLAPSED_WIDTH = 160;
  const drawerWidth = isExpanded ? panelWidth : (activePanel !== null ? COLLAPSED_WIDTH : 0);
  const hasCustomContent = isExpanded && activePanel !== null && panelContent?.[activePanel] !== undefined;

  /* 拖拽 mousedown — handle 在左边缘 */
  const handleResizeMouseDown = useCallback((e: React.MouseEvent) => {
    e.preventDefault();
    setIsResizing(true);
    resizeStartX.current = e.clientX;
    resizeStartWidth.current = panelWidth;
    document.body.style.cursor = 'col-resize';
    document.body.style.userSelect = 'none';
  }, [panelWidth]);

  // 拖拽 mousemove/mouseup 全局监听
  useEffect(() => {
    if (!isResizing) return;
    const handleMouseMove = (e: MouseEvent) =>
      setPanelWidth(Math.min(RESIZE_MAX, Math.max(RESIZE_MIN, resizeStartWidth.current + resizeStartX.current - e.clientX)));
    const handleMouseUp = () => { setIsResizing(false); document.body.style.cursor = ''; document.body.style.userSelect = ''; };
    window.addEventListener('mousemove', handleMouseMove);
    window.addEventListener('mouseup', handleMouseUp);
    return () => { window.removeEventListener('mousemove', handleMouseMove); window.removeEventListener('mouseup', handleMouseUp); };
  }, [isResizing]);

  const handleToolClick = useCallback((tool: ToolItem) => {
    if (tool.disabled) return;
    tool.onClick ? tool.onClick() : onToolClick ? onToolClick(tool.id) : useRightPanelStore.getState().openTool(tool.id);
  }, [onToolClick]);

  /* 标签切换 */
  const handleSessionSwitch = useCallback((sessionId: string) => {
    useRightPanelStore.getState().switchSession(sessionId);
  }, []);

  /* 移除会话 */
  const handleSessionRemove = useCallback((sessionId: string) => {
    useRightPanelStore.getState().removeSession(sessionId);
  }, []);

  // Esc 关闭面板
  useEffect(() => {
    if (!isExpanded) return;
    const handleEsc = (e: KeyboardEvent) => { if (e.key === 'Escape') closePanel(); };
    window.addEventListener('keydown', handleEsc);
    return () => window.removeEventListener('keydown', handleEsc);
  }, [isExpanded, closePanel]);

  // ── 渲染 ──
  const containerTransition = isResizing ? 'none' : `width 200ms ${EASE_OUT_QUART}`;

  // 完全关闭(默认态 collapsed === true 且 activePanel === null)不渲染
  // 显式展开后(!collapsed 且 activePanel === null)显示工具网格
  if (activePanel === null && collapsed) {
    return null;
  }

  return (
    <div
      className={styles.container}
      style={{
        width: drawerWidth,
        transition: containerTransition,
        zIndex: Z_LAYER.modal,
      }}
      role="complementary"
      aria-label="工具面板"
    >
      {/* 拖拽 handle — 左边缘（仅展开态） */}
      {isExpanded && (
        <div
          onMouseDown={handleResizeMouseDown}
          className={styles.resizeHandle}
          title="拖拽调节宽度"
        />
      )}

      {/* Header 区 — 始终存在（设计文档 §4.1） */}
      <div className={styles.headerRow}>
        <SessionTabBar
          sessions={sessions}
          activeSessionId={activeSessionId}
          onSwitch={handleSessionSwitch}
          onRemove={handleSessionRemove}
          sessionIcons={SESSION_LUCIDE_ICON}
        />

        {/* [＋] 新建标签按钮 */}
        <button
          onClick={() => { /* 新建标签 — 后续实现 */ }}
          className={styles.actionBtn}
          title="新建标签"
        >
          <Plus size={14} strokeWidth={1.8} />
        </button>
      </div>

      {/* 内容区 — 仅展开态显示 */}
      {isExpanded && (
        <div className={styles.contentArea}>
          {hasCustomContent && activePanel ? (
            <div key={activePanel}>
              {panelContent?.[activePanel] ?? null}
            </div>
          ) : (
            <ToolGrid tools={tools} activePanel={activePanel} onToolClick={handleToolClick} />
          )}
        </div>
      )}
    </div>
  );
});

RightDrawer.displayName = 'RightDrawer';
