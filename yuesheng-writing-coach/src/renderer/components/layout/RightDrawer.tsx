import React, { useCallback, useState, useEffect, useRef } from 'react';
import { PanelRightClose, Plus } from 'lucide-react';
import { useDrawerStore } from '../../stores/drawer.store';
import { useUiLayoutStore } from '../../stores/ui-layout.store';
import { usePanelSessionStore } from '../../stores/panel-session.store';
import { rightPanelService } from '../../services/right-panel.service';
import { SessionTabBar } from './SessionTabBar';
import { ToolGrid } from './ToolGrid';
import { ResizeHandle } from './ResizeHandle';
import {
  DEFAULT_TOOLS, SESSION_LUCIDE_ICON, EASE_OUT_QUART,
  DEFAULT_PANEL_WIDTH, RESIZE_MIN, RESIZE_MAX, STORAGE_KEY, Z_LAYER,
  HEADER_COLLAPSED_WIDTH,
} from './drawer-constants';
import type { ToolItem } from './drawer-constants';
import styles from './RightDrawer.module.css';

export interface RightDrawerProps {
  tools?: ToolItem[];
  panelContent?: Record<string, React.ReactNode>;
  onToolClick?: (toolId: string) => void;
}

/** RightDrawer V3 — header 标签 + [⤢]，收起态隐藏内容保留 header */
export const RightDrawer: React.FC<RightDrawerProps> = React.memo(({
  tools = DEFAULT_TOOLS, panelContent, onToolClick,
}) => {
  const activePanel = useDrawerStore(s => s.activePanel);
  const collapsed = useDrawerStore(s => s.collapsed);
  const closePanel = useDrawerStore(s => s.closePanel);
  const toggleCollapsed = useDrawerStore(s => s.toggleCollapsed);
  const sessions = usePanelSessionStore(s => s.sessions);
  const activeSessionId = usePanelSessionStore(s => s.activeSessionId);

  // 同步右侧栏收起状态到 UiLayoutStore
  const setRightSidebarCollapsed = useUiLayoutStore(s => s.setRightSidebarCollapsed);
  useEffect(() => {
    setRightSidebarCollapsed(collapsed);
  }, [collapsed, setRightSidebarCollapsed]);

  // 可拖拽宽度
  const [panelWidth, setPanelWidth] = useState(() => {
    try {
      const saved = localStorage.getItem(STORAGE_KEY);
      if (saved) { const w = parseInt(saved, 10); if (!isNaN(w) && w >= RESIZE_MIN && w <= RESIZE_MAX) return w; }
    } catch { /* ignore */ }
    return DEFAULT_PANEL_WIDTH;
  });
  useEffect(() => { try { localStorage.setItem(STORAGE_KEY, String(panelWidth)); } catch { /* ignore */ } }, [panelWidth]);

  // 拖拽状态
  const [isResizing, setIsResizing] = useState(false);
  const resizeStartX = useRef(0);
  const resizeStartWidth = useRef(0);

  const isExpanded = !collapsed && activePanel !== null;

  const handleResizeMouseDown = useCallback((e: React.MouseEvent) => {
    e.preventDefault();
    setIsResizing(true);
    resizeStartX.current = e.clientX;
    resizeStartWidth.current = panelWidth;
    document.body.style.cursor = 'col-resize';
    document.body.style.userSelect = 'none';
  }, [panelWidth]);

  useEffect(() => {
    if (!isResizing) return;
    const handleMouseMove = (e: MouseEvent) =>
      setPanelWidth(Math.min(RESIZE_MAX, Math.max(RESIZE_MIN, resizeStartWidth.current + resizeStartX.current - e.clientX)));
    const handleMouseUp = () => { setIsResizing(false); document.body.style.cursor = ''; document.body.style.userSelect = ''; };
    window.addEventListener('mousemove', handleMouseMove);
    window.addEventListener('mouseup', handleMouseUp);
    return () => { window.removeEventListener('mousemove', handleMouseMove); window.removeEventListener('mouseup', handleMouseUp); };
  }, [isResizing]);

  const handleIconClick = useCallback((toolId: string) => {
    if (!collapsed && activePanel === toolId) { toggleCollapsed(); return; }
    rightPanelService.openTool(toolId);
  }, [collapsed, activePanel, toggleCollapsed]);

  const handleToolClick = useCallback((tool: ToolItem) => {
    if (tool.disabled) return;
    if (tool.onClick) {
      tool.onClick();
    } else if (onToolClick) {
      onToolClick(tool.id);
    } else {
      handleIconClick(tool.id);
    }
  }, [onToolClick, handleIconClick]);

  const handleSessionSwitch = useCallback((sessionId: string) => {
    rightPanelService.switchSession(sessionId);
  }, []);

  const handleSessionRemove = useCallback((sessionId: string) => {
    rightPanelService.removeSession(sessionId);
  }, []);

  useEffect(() => {
    if (!isExpanded) return;
    const handleEsc = (e: KeyboardEvent) => { if (e.key === 'Escape') closePanel(); };
    window.addEventListener('keydown', handleEsc);
    return () => window.removeEventListener('keydown', handleEsc);
  }, [isExpanded, closePanel]);

  const containerTransition = isResizing ? 'none' : `width 200ms ${EASE_OUT_QUART}`;
  const drawerWidth = isExpanded ? panelWidth : HEADER_COLLAPSED_WIDTH;

  return (
    <div className={styles.container} style={{
      width: drawerWidth,
      transition: containerTransition,
      zIndex: Z_LAYER.modal,
    }} role="complementary" aria-label="工具面板">
      {/* 拖拽 handle — 右侧栏左边缘（仅展开态） */}
      {isExpanded && <ResizeHandle onMouseDown={handleResizeMouseDown} isExpanded={isExpanded} />}

      <div className={styles.workspace}>
        {/* Header 行：标签区左 + [⤢] 右 */}
        <div className={`${styles.headerRow} ${isExpanded ? styles.headerRowExpanded : styles.headerRowCollapsed}`}>
          {isExpanded && (
            <div className={styles.headerLeft}>
              <SessionTabBar sessions={sessions} activeSessionId={activeSessionId}
                onSwitch={handleSessionSwitch} onRemove={handleSessionRemove} sessionIcons={SESSION_LUCIDE_ICON} />
              <button className={styles.addTagBtn} title="打开工具列表" aria-label="打开工具列表">
                <Plus size={14} strokeWidth={1.8} />
              </button>
            </div>
          )}
          <div className={styles.headerRight}>
            <button onClick={toggleCollapsed}
              className={styles.actionBtn} title={isExpanded ? '收起面板' : '展开面板'}
              aria-label={isExpanded ? '收起面板' : '展开面板'}>
              <PanelRightClose size={15} strokeWidth={1.6}
                style={{ transform: isExpanded ? 'scaleX(1)' : 'scaleX(-1)', transition: 'transform 200ms ease' }} />
            </button>
          </div>
        </div>

        {/* 内容区 — 仅展开态显示 */}
        {isExpanded && (
          <>
            {activePanel && panelContent?.[activePanel] ? (
              <div key={activePanel} className={styles.contentArea}>
                {panelContent[activePanel]}
              </div>
            ) : (
              <div className={styles.contentArea}>
                <ToolGrid tools={tools} activePanel={activePanel} onToolClick={handleToolClick} />
              </div>
            )}
          </>
        )}
      </div>
    </div>
  );
});

RightDrawer.displayName = 'RightDrawer';
