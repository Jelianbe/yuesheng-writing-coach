import React, { useCallback, useState, useEffect, useRef } from 'react';
import { Settings, PanelRightClose, Plus, ListChecks } from 'lucide-react';
import { useDrawerStore, type DrawerPanelId } from '../../stores/drawer.store';
import { usePanelSessionStore } from '../../stores/panel-session.store';
import { IconStripButton } from './IconStripButton';
import { SessionTabBar } from './SessionTabBar';
import { ToolGrid } from './ToolGrid';
import { ResizeHandle } from './ResizeHandle';
import {
  DEFAULT_TOOLS, TOOL_TO_SESSION_TYPE, SESSION_DEFAULT_TITLE,
  SESSION_LUCIDE_ICON, EASE_OUT_QUART, ICON_STRIP_WIDTH,
  DEFAULT_PANEL_WIDTH, RESIZE_MIN, RESIZE_MAX, STORAGE_KEY, Z_LAYER,
  SESSION_TYPE_TO_TOOL_ID,
} from './drawer-constants';
import type { ToolItem } from './drawer-constants';
import styles from './RightDrawer.module.css';

export interface RightDrawerProps {
  tools?: ToolItem[];
  panelContent?: Record<string, React.ReactNode>;
  onToolClick?: (toolId: string) => void;
}

/** RightDrawer V4 — 工具会话标签 + 两层导航：[拖拽][图标条][L1会话标签][内容区] */
export const RightDrawer: React.FC<RightDrawerProps> = React.memo(({
  tools = DEFAULT_TOOLS, panelContent, onToolClick,
}) => {
  const activePanel = useDrawerStore(s => s.activePanel);
  const collapsed = useDrawerStore(s => s.collapsed);
  const openPanel = useDrawerStore(s => s.openPanel);
  const closePanel = useDrawerStore(s => s.closePanel);
  const toggleCollapsed = useDrawerStore(s => s.toggleCollapsed);
  const sessions = usePanelSessionStore(s => s.sessions);
  const activeSessionId = usePanelSessionStore(s => s.activeSessionId);
  const upsertSession = usePanelSessionStore(s => s.upsertSession);
  const switchSession = usePanelSessionStore(s => s.switchSession);
  const removeSession = usePanelSessionStore(s => s.removeSession);

  // ── 可拖拽宽度（localStorage 持久化）──
  const [panelWidth, setPanelWidth] = useState(() => {
    try {
      const saved = localStorage.getItem(STORAGE_KEY);
      if (saved) { const w = parseInt(saved, 10); if (!isNaN(w) && w >= RESIZE_MIN && w <= RESIZE_MAX) return w; }
    } catch { /* ignore */ }
    return DEFAULT_PANEL_WIDTH;
  });
  useEffect(() => { try { localStorage.setItem(STORAGE_KEY, String(panelWidth)); } catch {} }, [panelWidth]);

  // ── 拖拽状态 ──
  const [isResizing, setIsResizing] = useState(false);
  const resizeStartX = useRef(0);
  const resizeStartWidth = useRef(0);

  const isExpanded = !collapsed && activePanel !== null;
  const drawerWidth = isExpanded ? ICON_STRIP_WIDTH + panelWidth : ICON_STRIP_WIDTH;
  const hasCustomContent = isExpanded && activePanel !== null && panelContent?.[activePanel] !== undefined;

  /* 拖拽 mousedown → 记录起始位置 */
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

  /* 图标点击 → 打开面板 + 创建/激活会话（FIX-02: 补充 openPanel 调用） */
  const handleIconClick = useCallback((toolId: string) => {
    // 已展开且点击同一图标 → 收起
    if (!collapsed && activePanel === toolId) { toggleCollapsed(); return; }
    const sessionType = TOOL_TO_SESSION_TYPE[toolId] ?? 'edit';
    upsertSession(sessionType, SESSION_DEFAULT_TITLE[sessionType] ?? toolId, '');
    // FIX-02 核心：同步展开 drawer 面板
    openPanel(toolId as DrawerPanelId);
  }, [collapsed, activePanel, toggleCollapsed, upsertSession, openPanel]);

  const handleToolClick = useCallback((tool: ToolItem) => {
    if (tool.disabled) return;
    tool.onClick ? tool.onClick() : onToolClick ? onToolClick(tool.id) : handleIconClick(tool.id);
  }, [onToolClick, handleIconClick]);

  /* 标签切换 → 联动 panel-session + drawer activePanel（FIX-03 核心） */
  const handleSessionSwitch = useCallback((sessionId: string) => {
    switchSession(sessionId);
    // 根据会话类型反推 toolId，同步 drawer 的 activePanel
    const session = sessions.find(s => s.id === sessionId);
    if (session) {
      const toolId = SESSION_TYPE_TO_TOOL_ID[session.type];
      if (toolId) openPanel(toolId as any);
    }
  }, [switchSession, sessions, openPanel]);

  /* Issue2: 移除会话时自动联动 — 若移除的是当前激活会话，切到最后一个剩余会话 */
  const handleSessionRemove = useCallback((sessionId: string) => {
    const wasActive = sessionId === activeSessionId;
    removeSession(sessionId);
    // 移除后若已无会话 → 收起面板
    const remaining = usePanelSessionStore.getState().sessions;
    if (remaining.length === 0) { closePanel(); return; }
    // 若被移除的是激活会话 → 自动切到最后一个
    if (wasActive) {
      const last = remaining[remaining.length - 1];
      handleSessionSwitch(last.id);
    }
  }, [activeSessionId, removeSession, closePanel, handleSessionSwitch]);

  // Esc 关闭面板
  useEffect(() => {
    if (!isExpanded) return;
    const handleEsc = (e: KeyboardEvent) => { if (e.key === 'Escape') closePanel(); };
    window.addEventListener('keydown', handleEsc);
    return () => window.removeEventListener('keydown', handleEsc);
  }, [isExpanded, closePanel]);

  // ── 渲染 ──
  const containerTransition = isResizing ? 'none' : `width 200ms ${EASE_OUT_QUART}, opacity 200ms ${EASE_OUT_QUART}`;
  const findLabel = (id: string): string => tools.find(t => t.id === id)?.label || id;

  return (
    <>
      <div className={styles.container} style={{
        width: drawerWidth, transition: containerTransition, zIndex: Z_LAYER.modal,
      }} role="complementary" aria-label="工具面板" aria-hidden={!isExpanded && collapsed}>
        <ResizeHandle onMouseDown={handleResizeMouseDown} isExpanded={isExpanded} />

        {/* 图标条 */}
        <nav aria-label="工具导航" className={`${styles.navBar} ${isExpanded ? styles.navBarBorderExpanded : styles.navBarBorderCollapsed}`}
          style={{ width: ICON_STRIP_WIDTH }}>
          {tools.map(tool => (
            <IconStripButton key={tool.id} toolId={tool.id} IconComponent={tool.icon}
              isActive={activePanel === tool.id} isDisabled={tool.disabled}
              onClick={handleIconClick} label={findLabel(tool.id)} />
          ))}
          <div className={styles.navSettingsArea}>
            <IconStripButton toolId="__settings__" IconComponent={Settings}
              isActive={false} onClick={handleIconClick} label="设置" />
          </div>
        </nav>

        {/* 工作区 */}
        {isExpanded && (<div className={styles.workspace} style={{ width: panelWidth }}>
          {/* Header 行：标签栏 + 操作按钮 + 收起按钮 */}
          <div className={styles.headerRow}>
            <SessionTabBar sessions={sessions} activeSessionId={activeSessionId}
              onSwitch={handleSessionSwitch} onRemove={handleSessionRemove} sessionIcons={SESSION_LUCIDE_ICON} />

            {/* Issue5: 按面板类型显示不同操作按钮 */}
            {activePanel === 'works' && (
              <button onClick={() => { /* 新建章节 — 由 ManuscriptPanel 内部处理或 IPC 触发 */ }}
                className={styles.actionBtn} style={{ color: 'var(--accent)' }} title="新建章节">
                <Plus size={14} strokeWidth={1.8} />
              </button>
            )}
            {activePanel === 'tasks' && (
              <button onClick={() => { /* 新建任务 — 由 TaskPanel 内部处理 */ }}
                className={styles.actionBtn} style={{ color: 'var(--accent)' }} title="新建任务">
                <ListChecks size={14} strokeWidth={1.8} />
              </button>
            )}

            {/* Issue4: 收起按钮 */}
            <button onClick={toggleCollapsed}
              className={`${styles.actionBtn} ${styles.actionBtnAuto}`} style={{ color: 'var(--text-tertiary)' }}
              title="收起面板">
              <PanelRightClose size={15} strokeWidth={1.6} />
            </button>
          </div>

          {hasCustomContent && activePanel ? (
            <div key={activePanel} className={styles.contentArea}>
              {panelContent?.[activePanel] ?? null}
            </div>
          ) : (
            <ToolGrid tools={tools} activePanel={activePanel} onToolClick={handleToolClick} />
          )}
        </div>)}
      </div>
    </>
  );
});

RightDrawer.displayName = 'RightDrawer';
