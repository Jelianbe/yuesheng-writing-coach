import React, { useEffect, useState, useRef, useCallback } from 'react';
import {
  Plus,
  PanelLeftClose,
  PanelLeftOpen,
} from 'lucide-react';
import { useUiLayoutStore } from '../../stores/ui-layout.store';
import { useSessionStore } from '../../stores/session.store';
import { useChapterStore } from '../../stores/chapter.store';
import { useManuscriptStore } from '../../stores/manuscript.store';
import { ModeSwitch } from './ModeSwitch';
import { SessionList } from './SessionList';
import { WorkTreePanel } from './WorkTreePanel';
import styles from './SoloSidebar.module.css';

// ── 样式常量 ──
const EASE = 'cubic-bezier(0.25, 1, 0.5, 1)';
const SIDEBAR_WIDTH_DEFAULT = 240;
const SIDEBAR_WIDTH_MIN = 180;
const SIDEBAR_WIDTH_MAX = 380;
const SIDEBAR_STORAGE_KEY = 'left-sidebar-width';

/**
 * SoloSidebar — V2 SOLO 模式左侧栏（组合器）
 *
 * 职责：
 * - 管理侧栏布局、折叠/展开、拖拽调节宽度
 * - Tab 切换（对话 / 项目视图）
 * - 组合 SessionList 与 WorkTreePanel 子组件
 */
export const SoloSidebar: React.FC = () => {
  const sidebarCollapsed = useUiLayoutStore(s => s.sidebarCollapsed);
  const sidebarView = useUiLayoutStore(s => s.sidebarView);
  const setSidebarView = useUiLayoutStore(s => s.setSidebarView);
  const toggleSidebar = useUiLayoutStore(s => s.toggleSidebar);

  // ── 会话 store ──
  const sessions = useSessionStore(s => s.sessions);
  const currentSessionId = useSessionStore(s => s.currentSessionId);
  const switchSession = useSessionStore(s => s.switchSession);
  const deleteSession = useSessionStore(s => s.deleteSession);
  const renameSession = useSessionStore(s => s.renameSession);
  const createSession = useSessionStore(s => s.createSession);

  // ── 作品 store ──
  const manuscripts = useManuscriptStore(s => s.manuscripts);
  const currentManuscript = useManuscriptStore(s => s.currentManuscript);
  const selectManuscript = useManuscriptStore(s => s.select);
  const fetchManuscripts = useManuscriptStore(s => s.fetchList);

  // ── 章节 store ──
  const chapters = useChapterStore(s => s.chapters);
  const currentChapter = useChapterStore(s => s.currentChapter);
  const fetchChapters = useChapterStore(s => s.fetchByWork);
  const selectChapter = useChapterStore(s => s.select);
  const openTab = useChapterStore(s => s.openTab);

  // ── 拖拽调节宽度 ──
  const [sidebarWidth, setSidebarWidth] = useState(() => {
    try {
      const saved = localStorage.getItem(SIDEBAR_STORAGE_KEY);
      if (saved) { const w = parseInt(saved, 10); if (!isNaN(w) && w >= SIDEBAR_WIDTH_MIN && w <= SIDEBAR_WIDTH_MAX) return w; }
    } catch { /* ignore */ }
    return SIDEBAR_WIDTH_DEFAULT;
  });
  const [isResizing, setIsResizing] = useState(false);
  const resizeStartX = useRef(0);
  const resizeStartWidth = useRef(0);

  useEffect(() => { try { localStorage.setItem(SIDEBAR_STORAGE_KEY, String(sidebarWidth)); } catch { /* ignore */ } }, [sidebarWidth]);

  const handleResizeMouseDown = useCallback((e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setIsResizing(true);
    resizeStartX.current = e.clientX;
    resizeStartWidth.current = sidebarWidth;
    document.body.style.cursor = 'col-resize';
    document.body.style.userSelect = 'none';
  }, [sidebarWidth]);

  useEffect(() => {
    if (!isResizing) return;
    const handleMouseMove = (e: MouseEvent) => {
      const delta = e.clientX - resizeStartX.current;
      const newWidth = Math.min(SIDEBAR_WIDTH_MAX, Math.max(SIDEBAR_WIDTH_MIN, resizeStartWidth.current + delta));
      setSidebarWidth(newWidth);
    };
    const handleMouseUp = () => { setIsResizing(false); document.body.style.cursor = ''; document.body.style.userSelect = ''; };
    window.addEventListener('mousemove', handleMouseMove);
    window.addEventListener('mouseup', handleMouseUp);
    return () => { window.removeEventListener('mousemove', handleMouseMove); window.removeEventListener('mouseup', handleMouseUp); };
  }, [isResizing]);

  // 初始化加载
  useEffect(() => { fetchManuscripts(); }, [fetchManuscripts]);
  useEffect(() => { useSessionStore.getState().loadSessions(); }, []);

  /* ── 样式对象（保留动态样式）── */
  const sidebarStyle: React.CSSProperties = {
    width: sidebarCollapsed ? 44 : sidebarWidth,
    overflow: 'hidden',
    flexShrink: 0,
    display: 'flex',
    flexDirection: 'column',
    background: 'var(--bg-sidebar)',
    borderRight: '1px solid var(--border)',
    transition: isResizing ? 'none' : `width 280ms ${EASE}`,
    position: 'relative',
    zIndex: 50,
    cursor: sidebarCollapsed ? 'pointer' : undefined,
  };

  const tabBase: React.CSSProperties = {
    flex: 1,
    padding: '6px 0',
    textAlign: 'center',
    fontSize: 'var(--text-sm)',
    fontWeight: 500,
    cursor: 'pointer',
    border: 'none',
    background: 'transparent',
    borderRadius: 'var(--radius-sm)',
    transition: `all 180ms ${EASE}`,
    color: 'var(--text-tertiary)',
  };

  const tabActive: React.CSSProperties = {
    ...tabBase,
    color: 'var(--accent)',
    background: 'var(--accent-subtle)',
    fontWeight: 600,
  };

  /* ── 图标按钮样式 ── */
  const iconBtnStyle: React.CSSProperties = {
    display: 'inline-flex',
    alignItems: 'center',
    justifyContent: 'center',
    border: 'none',
    background: 'transparent',
    cursor: 'pointer',
    borderRadius: 'var(--radius-sm)',
    transition: `all 120ms ${EASE}`,
    outline: 'none',
  };

  const collapsedIconBtnStyle: React.CSSProperties = {
    ...iconBtnStyle,
    width: 32,
    height: 32,
    borderRadius: 'var(--radius-sm)',
    color: 'var(--text-tertiary)',
  };

  return (
    <div
      style={sidebarStyle}
      role="navigation"
      aria-label="侧边栏"
      onClick={sidebarCollapsed ? toggleSidebar : undefined}
      onMouseEnter={e => { if (sidebarCollapsed) { e.currentTarget.style.background = 'var(--accent-subtle)'; e.currentTarget.style.color = 'var(--accent)'; } }}
      onMouseLeave={e => { if (sidebarCollapsed) { e.currentTarget.style.background = 'var(--bg-sidebar)'; e.currentTarget.style.color = 'var(--text-tertiary)'; } }}
    >
      {/* ── 展开状态：完整侧栏 ── */}
      {!sidebarCollapsed && (
        <>
          {/* 顶部折叠按钮 + 模式切换 */}
          <div className={styles.soloHeader}>
            <ModeSwitch />
            <button
              onClick={e => { e.stopPropagation(); toggleSidebar(); }}
              style={{ ...iconBtnStyle, width: 24, height: 24, color: 'var(--text-tertiary)' }}
              title="收起侧边栏"
            >
              <PanelLeftClose size={14} strokeWidth={1.6} />
            </button>
          </div>

          {/* Tab 切换栏 */}
          <div className={styles.soloTabs}>
            <div className={styles.soloTabsInner}>
              <button
                style={sidebarView === 'sessions' ? tabActive : tabBase}
                onClick={e => { e.stopPropagation(); setSidebarView('sessions'); }}
              >
                对话
              </button>
              <button
                style={sidebarView === 'projects' ? tabActive : tabBase}
                onClick={e => { e.stopPropagation(); setSidebarView('projects'); }}
              >
                项目
              </button>
            </div>
          </div>

          {/* 内容区 */}
          <div className={styles.soloContent}>
            {sidebarView === 'sessions' && (
              <SessionList
                sessions={sessions}
                currentSessionId={currentSessionId}
                onSwitch={switchSession}
                onDelete={deleteSession}
                onRename={renameSession}
                onCreateSession={createSession}
              />
            )}

            {sidebarView === 'projects' && (
              <WorkTreePanel
                manuscripts={manuscripts}
                chapters={chapters}
                currentManuscriptId={currentManuscript?.id ?? null}
                currentChapterId={currentChapter?.id ?? null}
                onSelectManuscript={selectManuscript}
                onSelectChapter={selectChapter}
                onOpenTab={openTab}
                fetchChapters={fetchChapters}
              />
            )}
          </div>
        </>
      )}

      {/* ── 收起状态：44px 图标条 ── */}
      {sidebarCollapsed && (
        <div className={styles.soloCollapsed}>
          <button
            onClick={e => { e.stopPropagation(); toggleSidebar(); }}
            style={collapsedIconBtnStyle}
            title="展开侧边栏"
          >
            <PanelLeftOpen size={16} strokeWidth={1.6} />
          </button>

          <div className={styles.soloCollapsedDivider} />

          <button
            onClick={e => { e.stopPropagation(); createSession(); }}
            style={collapsedIconBtnStyle}
            title="新对话"
          >
            <Plus size={16} strokeWidth={1.6} />
          </button>
        </div>
      )}

      {/* ── 拖拽调节手柄 ── */}
      {!sidebarCollapsed && (
        <div
          onMouseDown={handleResizeMouseDown}
          className={styles.soloResizeHandle}
          onMouseEnter={e => {
            const el = e.currentTarget as HTMLElement;
            el.style.borderRightColor = 'var(--accent)';
            el.style.background = 'var(--accent-subtle)';
          }}
          onMouseLeave={e => {
            const el = e.currentTarget as HTMLElement;
            el.style.borderRightColor = 'var(--border-light)';
            el.style.background = 'transparent';
          }}
          title="拖拽调节宽度"
        />
      )}
    </div>
  );
};
