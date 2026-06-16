import React, { useRef, useCallback } from 'react';
import {
  PanelLeftClose,
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
 * SoloSidebar — V3 SOLO 模式左侧栏
 *
 * 职责：
 * - 收起态完全隐藏（无窄条），月笙[▶] 独立悬浮左上角
 * - 展开态显示 header（月笙左 + [▶] 右）+ Tab + 内容区
 * - 统一 [▶] toggle：收起态 = 展开入口，展开态 = 收起入口
 * - 拖拽调节宽度
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
  const manuscriptError = useManuscriptStore(s => s.error);

  // ── 章节 store ──
  const chapters = useChapterStore(s => s.chapters);
  const currentChapter = useChapterStore(s => s.currentChapter);
  const fetchChapters = useChapterStore(s => s.fetchByWork);
  const selectChapter = useChapterStore(s => s.select);
  const openTab = useChapterStore(s => s.openTab);
  const chapterError = useChapterStore(s => s.error);

  // ── mutation callbacks ──
  const deleteChapter = useCallback(async (chapterId: string, manuscriptId: string) => {
    await useChapterStore.getState().deleteChapter(chapterId, manuscriptId);
  }, []);
  const deleteManuscript = useCallback(async (msId: string) => {
    await useManuscriptStore.getState().remove(msId);
  }, []);
  const createChapter = useCallback(async (manuscriptId: string, title: string) => {
    return await useChapterStore.getState().createChapter(manuscriptId, title);
  }, []);
  const createManuscript = useCallback(async (title: string) => {
    return await useManuscriptStore.getState().create(title);
  }, []);

  // ── 拖拽调节宽度 ──
  const [sidebarWidth, setSidebarWidth] = React.useState(() => {
    try {
      const saved = localStorage.getItem(SIDEBAR_STORAGE_KEY);
      if (saved) { const w = parseInt(saved, 10); if (!isNaN(w) && w >= SIDEBAR_WIDTH_MIN && w <= SIDEBAR_WIDTH_MAX) return w; }
    } catch { /* ignore */ }
    return SIDEBAR_WIDTH_DEFAULT;
  });
  const [isResizing, setIsResizing] = React.useState(false);
  const resizeStartX = useRef(0);
  const resizeStartWidth = useRef(0);

  React.useEffect(() => { try { localStorage.setItem(SIDEBAR_STORAGE_KEY, String(sidebarWidth)); } catch { /* ignore */ } }, [sidebarWidth]);

  const handleResizeMouseDown = useCallback((e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setIsResizing(true);
    resizeStartX.current = e.clientX;
    resizeStartWidth.current = sidebarWidth;
    document.body.style.cursor = 'col-resize';
    document.body.style.userSelect = 'none';
  }, [sidebarWidth]);

  React.useEffect(() => {
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
  React.useEffect(() => { fetchManuscripts(); }, [fetchManuscripts]);
  React.useEffect(() => { useSessionStore.getState().loadSessions(); }, []);

  /* ── 样式对象（保留动态样式）── */
  const sidebarStyle: React.CSSProperties = {
    width: sidebarCollapsed ? 0 : sidebarWidth,
    overflow: 'hidden',
    flexShrink: 0,
    display: 'flex',
    flexDirection: 'column',
    background: 'var(--bg-sidebar)',
    borderRight: sidebarCollapsed ? 'none' : '1px solid var(--border)',
    transition: isResizing ? 'none' : `width 280ms ${EASE}, border-color 280ms ${EASE}`,
    position: 'relative',
    zIndex: 50,
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

  return (
    <>
      {/* ── 收起态：月笙[▶] 独立悬浮左上角 ── */}
      {sidebarCollapsed && (
        <div className={styles.floatingBrand}>
          <span className={styles.brandText}>月笙</span>
          <button
            onClick={toggleSidebar}
            className={styles.toggleBtnCollapsed}
            title="展开侧边栏"
            aria-label="展开侧边栏"
          >
            <PanelLeftClose size={14} strokeWidth={1.6} style={{ transform: 'scaleX(-1)' }} />
          </button>
        </div>
      )}

      {/* ── 侧边栏容器 ── */}
      <div
        style={sidebarStyle}
        role="navigation"
        aria-label="侧边栏"
      >
        {/* ── 展开状态：完整侧栏 ── */}
        {!sidebarCollapsed && (
          <>
            {/* 顶部 header：月笙 + [▶] 收起 */}
            <div className={styles.soloHeader}>
              <span className={styles.brandText}>月笙</span>
              <div className={styles.headerRight}>
                <ModeSwitch />
                <button
                  onClick={e => { e.stopPropagation(); toggleSidebar(); }}
                  className={styles.toggleBtnExpanded}
                  title="收起侧边栏"
                  aria-label="收起侧边栏"
                >
                  <PanelLeftClose size={14} strokeWidth={1.6} />
                </button>
              </div>
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
                  onDeleteChapter={deleteChapter}
                  onDeleteManuscript={deleteManuscript}
                  onCreateChapter={createChapter}
                  onCreateManuscript={createManuscript}
                  chapterError={chapterError}
                  manuscriptError={manuscriptError}
                />
              )}
            </div>
          </>
        )}

        {/* ── 拖拽调节手柄（仅展开态）── */}
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
    </>
  );
};
