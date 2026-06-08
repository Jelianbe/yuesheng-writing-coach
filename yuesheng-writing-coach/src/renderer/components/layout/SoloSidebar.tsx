import React, { useEffect, useState, useRef, useCallback } from 'react';
import {
  Plus,
  MessageSquare,
  FileText,
  ChevronDown,
  ChevronRight,
  Trash2,
  PanelLeftClose,
  PanelLeftOpen,
} from 'lucide-react';
import { useUiLayoutStore } from '../../stores/ui-layout.store';
import { useSessionStore } from '../../stores/session.store';
import { useChapterStore } from '../../stores/chapter.store';
import { useManuscriptStore } from '../../stores/manuscript.store';
import { useDrawerStore } from '../../stores/drawer.store';
import ModeSwitch from './ModeSwitch';

// ── 样式常量 ──
const EASE = 'cubic-bezier(0.25, 1, 0.5, 1)';
const SIDEBAR_WIDTH_DEFAULT = 240;
const SIDEBAR_WIDTH_MIN = 180;
const SIDEBAR_WIDTH_MAX = 380;
const SIDEBAR_STORAGE_KEY = 'left-sidebar-width';

/** 按时间分组会话（使用 ChatSession 类型） */
function groupSessions(sessions: import('../../stores/session.store').ChatSession[]) {
  const now = new Date();
  const today: typeof sessions = [];
  const thisWeek: typeof sessions = [];
  const earlier: typeof sessions = [];

  for (const s of sessions) {
    const d = new Date(s.updatedAt);
    const diff = now.getTime() - d.getTime();
    const days = Math.floor(diff / 86400000);
    if (days === 0) today.push(s);
    else if (days < 7) thisWeek.push(s);
    else earlier.push(s);
  }

  return [
    ...(today.length ? [{ group: '今天', items: today }] : []),
    ...(thisWeek.length ? [{ group: '这周', items: thisWeek }] : []),
    ...(earlier.length ? [{ group: '更早', items: earlier }] : []),
  ];
}

/**
 * SoloSidebar — V2 SOLO 模式左侧栏
 *
 * 双视图：
 * - 「项目」视图：作品 + 章节树
 * - 「对话」视图：会话历史（按时间分组）
 *
 * 设计规则：
 * - 使用 CSS Variables 色板（金棕暖灰体系）
 * - lucide-react SVG 图标，无 emoji
 * - ease-out-quart 动效
 * - z-index 语义化
 */
const SoloSidebar: React.FC = () => {
  const sidebarCollapsed = useUiLayoutStore(s => s.sidebarCollapsed);
  const sidebarView = useUiLayoutStore(s => s.sidebarView);
  const setSidebarView = useUiLayoutStore(s => s.setSidebarView);
  const toggleSidebar = useUiLayoutStore(s => s.toggleSidebar);

  const sessions = useSessionStore(s => s.sessions);
  const currentSessionId = useSessionStore(s => s.currentSessionId);
  const switchSession = useSessionStore(s => s.switchSession);
  const deleteSession = useSessionStore(s => s.deleteSession);
  const renameSession = useSessionStore(s => s.renameSession);
  const createSession = useSessionStore(s => s.createSession);

  const manuscripts = useManuscriptStore(s => s.manuscripts);
  const currentManuscript = useManuscriptStore(s => s.currentManuscript);
  const selectManuscript = useManuscriptStore(s => s.select);
  const fetchManuscripts = useManuscriptStore(s => s.fetchList);

  const chapters = useChapterStore(s => s.chapters);
  const currentChapter = useChapterStore(s => s.currentChapter);
  const fetchChapters = useChapterStore(s => s.fetchByWork);
  const selectChapter = useChapterStore(s => s.select);
  const openTab = useChapterStore(s => s.openTab);

  const [editingSessionId, setEditingSessionId] = useState<string | null>(null);
  const [editTitle, setEditTitle] = useState('');
  const [expandedManuscripts, setExpandedManuscripts] = useState<Set<string>>(new Set());
  // 新建作品弹出卡
  const [showWorkPopup, setShowWorkPopup] = useState(false);
  const [workTitle, setWorkTitle] = useState('');
  const [workError, setWorkError] = useState<string | null>(null);
  const workInputRef = useRef<HTMLInputElement>(null);
  // 新建章节弹出卡
  const [showChapterPopup, setShowChapterPopup] = useState<string | null>(null); // manuscriptId
  const [chapterTitle, setChapterTitle] = useState('');
  const [chapterError, setChapterError] = useState<string | null>(null);
  const chapterInputRef = useRef<HTMLInputElement>(null);

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
      // 向右拖增大，向左拖减小（以左侧为基准）
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
  useEffect(() => { if (showWorkPopup) workInputRef.current?.focus(); }, [showWorkPopup]);
  useEffect(() => { if (showChapterPopup) chapterInputRef.current?.focus(); }, [showChapterPopup]);
  // V2-019: 搜索过滤 + 加载更多
  const [searchQuery, setSearchQuery] = useState('');
  const [sessionMaxCount, setSessionMaxCount] = useState(30);

  // 过滤 + 限制对话数
  const filteredSessions = sessions.filter(s => {
    if (!searchQuery.trim()) return true;
    const q = searchQuery.toLowerCase();
    const title = (s.title || '').toLowerCase();
    const msg = (s.lastMessage || '').toLowerCase();
    return title.includes(q) || msg.includes(q);
  });
  const visibleSessions = filteredSessions.slice(0, sessionMaxCount);
  const hasMore = filteredSessions.length > sessionMaxCount;
  const groupedSessions = groupSessions(visibleSessions);


  /* ── 样式 ── */
  const SIDEBAR_TAB_WIDTH = 44;
  const sidebarStyle: React.CSSProperties = {
    width: sidebarCollapsed ? SIDEBAR_TAB_WIDTH : sidebarWidth,
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

  const listItemStyle: React.CSSProperties = {
    display: 'flex',
    alignItems: 'center',
    gap: 8,
    padding: '8px 12px',
    cursor: 'pointer',
    borderRadius: 'var(--radius-sm)',
    transition: `all 120ms ${EASE}`,
    fontSize: 'var(--text-sm)',
    border: 'none',
    background: 'transparent',
    color: 'var(--text-secondary)',
    width: '100%',
    textAlign: 'left',
  };

  /* ── 渲染：对话列表项 ── */
  const renderSessionItem = (session: import('../../stores/session.store').ChatSession) => {
    const isActive = session.id === currentSessionId;

    const handleRename = () => {
      const newTitle = editTitle.trim();
      if (newTitle && newTitle !== session.title) {
        renameSession(session.id, newTitle);
      }
      setEditingSessionId(null);
    };

    return (
      <div
        key={session.id}
        style={{
          ...listItemStyle,
          background: isActive ? 'var(--accent-subtle)' : undefined,
          fontWeight: isActive ? 600 : 400,
          color: isActive ? 'var(--accent)' : 'var(--text-secondary)',
          flexDirection: 'column',
          alignItems: 'stretch',
          gap: 2,
          padding: '6px 12px',
          position: 'relative',
        }}
        onMouseEnter={e => { const a = e.currentTarget.querySelector('.sidebar-actions'); if (a) (a as HTMLElement).style.display = 'flex'; }}
        onMouseLeave={e => { const a = e.currentTarget.querySelector('.sidebar-actions'); if (a) (a as HTMLElement).style.display = 'none'; }}
        onClick={() => switchSession(session.id)}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, minWidth: 0 }}>
          <MessageSquare size={14} strokeWidth={1.6} style={{ flexShrink: 0 }} />
          {editingSessionId === session.id ? (
            <input
              autoFocus
              value={editTitle}
              onChange={e => setEditTitle(e.target.value)}
              onBlur={handleRename}
              onKeyDown={e => { if (e.key === 'Enter') handleRename(); if (e.key === 'Escape') setEditingSessionId(null); }}
              style={{
                flex: 1,
                background: 'var(--bg-input)',
                border: '1px solid var(--border-focus)',
                borderRadius: 'var(--radius-sm)',
                padding: '2px 6px',
                fontSize: 'var(--text-sm)',
                color: 'var(--text-primary)',
                outline: 'none',
                minWidth: 0,
              }}
              onClick={e => e.stopPropagation()}
            />
          ) : (
            <span style={{
              flex: 1,
              overflow: 'hidden',
              textOverflow: 'ellipsis',
              whiteSpace: 'nowrap',
              fontSize: 'var(--text-sm)',
              lineHeight: 1.4,
            }}>
              {session.title || '新对话'}
            </span>
          )}
        </div>

        {/* 操作按钮（hover 显示） */}
        <div className="sidebar-actions" style={{
          position: 'absolute',
          right: 8,
          top: '50%',
          transform: 'translateY(-50%)',
          display: 'none',
          gap: 2,
          background: 'var(--bg-sidebar)',
          paddingLeft: 4,
        }}>
          <button
            onClick={e => { e.stopPropagation(); setEditingSessionId(session.id); setEditTitle(session.title); }}
            style={{ ...iconBtnStyle, color: 'var(--text-tertiary)', padding: 2 }}
            title="重命名"
          >
            <span style={{ fontSize: 11 }}>✎</span>
          </button>
          <button
            onClick={e => { e.stopPropagation(); deleteSession(session.id); }}
            style={{ ...iconBtnStyle, color: 'var(--error)', padding: 2 }}
            title="删除"
          >
            <Trash2 size={12} strokeWidth={1.6} />
          </button>
        </div>

        {/* 预览文本 */}
        {session.lastMessage && (
          <span style={{
            fontSize: 'var(--text-xs)',
            color: 'var(--text-tertiary)',
            overflow: 'hidden',
            textOverflow: 'ellipsis',
            whiteSpace: 'nowrap',
            paddingLeft: 22,
            opacity: 0.7,
          }}>
            {session.lastMessage}
          </span>
        )}
      </div>
    );
  };

  /* ── 渲染：作品树节点 ── */
  const renderManuscriptItem = (ms: import('../../shared/types').Manuscript) => {
    const isActive = ms.id === currentManuscript?.id;
    const isExpanded = expandedManuscripts.has(ms.id);

    const toggleExpand = (e: React.MouseEvent) => {
      e.stopPropagation();
      const next = new Set(expandedManuscripts);
      if (isExpanded) {
        next.delete(ms.id);
      } else {
        next.add(ms.id);
        fetchChapters(ms.id);
      }
      setExpandedManuscripts(next);
    };

    const handleSelectManuscript = () => {
      selectManuscript(ms.id);
      // 点击项目只选中+展开章节列表，不操作右侧栏
      if (!isExpanded) {
        const next = new Set(expandedManuscripts);
        next.add(ms.id);
        setExpandedManuscripts(next);
        fetchChapters(ms.id);
      }
    };

    const chapterList = chapters.filter(c => c.manuscript_id === ms.id);

    return (
      <div key={ms.id}>
        <div
          style={{
            ...listItemStyle,
            background: isActive ? 'var(--accent-subtle)' : undefined,
            fontWeight: isActive ? 600 : 400,
            color: isActive ? 'var(--accent)' : 'var(--text-secondary)',
            gap: 4,
          }}
          onClick={handleSelectManuscript}
        >
          <button
            onClick={toggleExpand}
            style={iconBtnStyle}
            aria-label={isExpanded ? '折叠' : '展开'}
          >
            {isExpanded ? <ChevronDown size={12} strokeWidth={1.8} /> : <ChevronRight size={12} strokeWidth={1.8} />}
          </button>
          <FileText size={14} strokeWidth={1.6} style={{ flexShrink: 0 }} />
          <span style={{
            flex: 1,
            overflow: 'hidden',
            textOverflow: 'ellipsis',
            whiteSpace: 'nowrap',
            fontSize: 'var(--text-sm)',
          }}>
            {ms.title}
          </span>
        </div>

        {isExpanded && (
          <div style={{ paddingLeft: 28 }}>
            {chapterList.length === 0 ? (
              <div style={{
                ...listItemStyle,
                fontSize: 'var(--text-xs)',
                color: 'var(--text-tertiary)',
                opacity: 0.5,
                cursor: 'default',
                padding: '4px 12px',
              }}>
                暂无章节
              </div>
            ) : (
              chapterList.map(ch => {
                const isChapterActive = ch.id === currentChapter?.id;
                return (
                  <div
                    key={ch.id}
                    style={{
                      ...listItemStyle,
                      padding: '4px 12px',
                      fontSize: 'var(--text-xs)',
                      background: isChapterActive ? 'var(--accent-faint)' : undefined,
                      color: isChapterActive ? 'var(--accent)' : 'var(--text-tertiary)',
                      gap: 6,
                    }}
                    onClick={async () => {
                      // 确保章节列表已加载，避免异步竞争导致 selectChapter 找不到章节
                      if (chapters.filter(c => c.manuscript_id === ms.id).length === 0) {
                        await fetchChapters(ms.id);
                      }
                      selectChapter(ch.id);
                      openTab(ch.id, ms.title);
                      useDrawerStore.getState().openPanel('works');
                    }}
                  >
                    <span style={{
                      overflow: 'hidden',
                      textOverflow: 'ellipsis',
                      whiteSpace: 'nowrap',
                    }}>
                      {ch.title}
                    </span>
                  </div>
                );
              })
            )}
            {/* 新建章节按钮与弹出卡 */}
            {showChapterPopup === ms.id ? (
              <div className="animate-pop-in" style={{
                margin: '6px 0',
                padding: '10px',
                border: '1px solid var(--border)',
                borderRadius: 'var(--radius-sm)',
                background: 'var(--bg-card)',
                boxShadow: '0 4px 12px rgba(61,50,41,0.1)',
                display: 'flex',
                flexDirection: 'column',
                gap: 6,
              }}>
                <input
                  ref={chapterInputRef}
                  type="text"
                  value={chapterTitle}
                  onChange={e => { setChapterTitle(e.target.value); setChapterError(null); }}
                  onKeyDown={async e => {
                    if (e.key === 'Enter' && chapterTitle.trim()) {
                      const r = await useChapterStore.getState().createChapter(ms.id, chapterTitle.trim());
                      if (r) { setChapterTitle(''); setShowChapterPopup(null); }
                      else { setChapterError(useChapterStore.getState().error || '创建失败'); }
                    }
                    if (e.key === 'Escape') { setChapterTitle(''); setShowChapterPopup(null); }
                  }}
                  placeholder="章节名称..."
                  style={{
                    width: '100%',
                    padding: '4px 8px',
                    border: '1px solid var(--border)',
                    borderRadius: 'var(--radius-sm)',
                    background: 'var(--bg-input)',
                    color: 'var(--text-primary)',
                    fontFamily: 'var(--font-body)',
                    fontSize: '0.72rem',
                    outline: 'none',
                    boxSizing: 'border-box',
                  }}
                />
                {chapterError && <div style={{ fontSize: '0.65rem', color: 'var(--error)' }}>{chapterError}</div>}
                <div style={{ display: 'flex', gap: 4, justifyContent: 'flex-end' }}>
                  <button
                    onClick={() => { setChapterTitle(''); setShowChapterPopup(null); }}
                    style={{ padding: '2px 10px', border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', background: 'transparent', color: 'var(--text-secondary)', cursor: 'pointer', fontSize: '0.68rem', fontFamily: 'var(--font-body)' }}
                  >
                    取消
                  </button>
                  <button
                    onClick={async () => {
                      if (chapterTitle.trim()) {
                        const r = await useChapterStore.getState().createChapter(ms.id, chapterTitle.trim());
                        if (r) { setChapterTitle(''); setShowChapterPopup(null); }
                        else { setChapterError(useChapterStore.getState().error || '创建失败'); }
                      }
                    }}
                    style={{ padding: '2px 10px', border: '1px solid var(--accent)', borderRadius: 'var(--radius-sm)', background: 'var(--accent)', color: '#fff', cursor: 'pointer', fontSize: '0.68rem', fontFamily: 'var(--font-body)' }}
                  >
                    创建
                  </button>
                </div>
              </div>
            ) : (
              <button
                onClick={e => {
                  e.stopPropagation();
                  setShowWorkPopup(false);
                  setShowChapterPopup(prev => prev === ms.id ? null : ms.id);
                }}
                style={{
                  ...listItemStyle,
                  padding: '4px 12px',
                  fontSize: 'var(--text-xs)',
                  color: 'var(--accent)',
                  gap: 4,
                  opacity: 0.7,
                }}
              >
                <Plus size={11} strokeWidth={2} />
                <span>新建章节</span>
              </button>
            )}
          </div>
        )}
      </div>
    );
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
          <div style={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            padding: '4px 8px',
            flexShrink: 0,
            height: 32,
          }}>
            <ModeSwitch />
            <button
              onClick={e => { e.stopPropagation(); toggleSidebar(); }}
              style={{
                ...iconBtnStyle,
                width: 24,
                height: 24,
                color: 'var(--text-tertiary)',
              }}
              title="收起侧边栏"
            >
              <PanelLeftClose size={14} strokeWidth={1.6} />
            </button>
          </div>

          {/* Tab 切换栏 */}
          <div style={{
            padding: '0 10px 8px',
            flexShrink: 0,
          }}>
            <div style={{
              display: 'flex',
              gap: 4,
              background: 'var(--bg-hover)',
              borderRadius: 'var(--radius-sm)',
              padding: 2,
            }}>
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
          <div style={{
            flex: 1,
            overflowY: 'auto',
            overflowX: 'hidden',
            scrollbarWidth: 'thin',
            scrollbarColor: 'var(--border) transparent',
          }}>
            {/* 对话视图 */}
            {sidebarView === 'sessions' && (
              <div>
                <button
                  onClick={e => { e.stopPropagation(); createSession(); }}
                  style={{
                    ...listItemStyle,
                    gap: 8,
                    color: 'var(--accent)',
                    fontWeight: 500,
                    padding: '6px 12px',
                    marginBottom: 4,
                  }}
                >
                  <Plus size={14} strokeWidth={2} />
                  <span>新对话</span>
                </button>
                {/* V2-019: 搜索框 */}
                <div style={{ padding: '0 12px 8px' }}>
                  <input
                    type="text"
                    value={searchQuery}
                    onChange={e => setSearchQuery(e.target.value)}
                    placeholder="搜索对话..."
                    aria-label="搜索对话"
                    style={{
                      width: '100%',
                      padding: '4px 8px',
                      border: '1px solid var(--border)',
                      borderRadius: 'var(--radius-sm)',
                      background: 'var(--bg-input)',
                      color: 'var(--text-primary)',
                      fontFamily: 'var(--font-body)',
                      fontSize: 'var(--text-xs)',
                      outline: 'none',
                      boxSizing: 'border-box',
                      transition: 'border-color 150ms ease',
                    }}
                    onFocus={e => { e.currentTarget.style.borderColor = 'var(--accent)'; }}
                    onBlur={e => { e.currentTarget.style.borderColor = 'var(--border)'; }}
                  />
                </div>
                {groupedSessions.map(group => (
                  <div key={group.group}>
                    <div style={{
                      padding: '8px 12px 4px',
                      fontSize: 'var(--text-xs)',
                      color: 'var(--text-tertiary)',
                      fontWeight: 500,
                      letterSpacing: '0.02em',
                    }}>
                      {group.group}
                    </div>
                    {group.items.map(renderSessionItem)}
                  </div>
                ))}
                {/* V2-019: 显示更多 */}
                {hasMore && (
                  <button
                    onClick={() => setSessionMaxCount(prev => prev + 30)}
                    style={{
                      ...listItemStyle,
                      justifyContent: 'center',
                      gap: 4,
                      color: 'var(--accent)',
                      fontSize: 'var(--text-xs)',
                      opacity: 0.7,
                    }}
                  >
                    显示更多对话
                  </button>
                )}
                {sessions.length === 0 && (
                  <div style={{
                    padding: '24px 16px',
                    textAlign: 'center',
                    color: 'var(--text-tertiary)',
                    fontSize: 'var(--text-xs)',
                    opacity: 0.6,
                  }}>
                    暂无对话
                  </div>
                )}
              </div>
            )}

            {/* 项目视图 */}
            {sidebarView === 'projects' && (
              <div style={{ position: 'relative' }}>
                {/* 新作品按钮 */}
                <button
                  onClick={e => {
                    e.stopPropagation();
                    setShowChapterPopup(null);
                    setShowWorkPopup(prev => !prev);
                  }}
                  style={{
                    ...listItemStyle,
                    gap: 8,
                    color: 'var(--accent)',
                    fontWeight: 500,
                    padding: '6px 12px',
                    marginBottom: 4,
                  }}
                >
                  <Plus size={14} strokeWidth={2} />
                  <span>新作品</span>
                </button>

                {/* 新建作品弹出卡 */}
                {showWorkPopup && (
                  <div className="animate-pop-in" style={{
                    margin: '0 12px 8px',
                    padding: '12px',
                    border: '1px solid var(--border)',
                    borderRadius: 'var(--radius-md)',
                    background: 'var(--bg-card)',
                    boxShadow: '0 4px 16px rgba(61,50,41,0.12)',
                    display: 'flex',
                    flexDirection: 'column',
                    gap: 8,
                  }}>
                    <div style={{ fontSize: '0.75rem', fontWeight: 600, color: 'var(--text-primary)' }}>
                      新建作品
                    </div>
                    <input
                      ref={workInputRef}
                      type="text"
                      value={workTitle}
                      onChange={e => { setWorkTitle(e.target.value); setWorkError(null); }}
                      onKeyDown={async e => {
                        if (e.key === 'Enter' && workTitle.trim()) {
                          const r = await useManuscriptStore.getState().create(workTitle.trim());
                          if (r) { setWorkTitle(''); setShowWorkPopup(false); }
                          else { setWorkError(useManuscriptStore.getState().error || '创建失败'); }
                        }
                        if (e.key === 'Escape') { setWorkTitle(''); setShowWorkPopup(false); }
                      }}
                      placeholder="输入作品名称..."
                      style={{
                        width: '100%',
                        padding: '6px 8px',
                        border: '1px solid var(--border)',
                        borderRadius: 'var(--radius-sm)',
                        background: 'var(--bg-input)',
                        color: 'var(--text-primary)',
                        fontFamily: 'var(--font-body)',
                        fontSize: '0.78rem',
                        outline: 'none',
                        boxSizing: 'border-box',
                      }}
                    />
                    {workError && <div style={{ fontSize: '0.68rem', color: 'var(--error)' }}>{workError}</div>}
                    <div style={{ display: 'flex', gap: 6, justifyContent: 'flex-end' }}>
                      <button
                        onClick={() => { setWorkTitle(''); setShowWorkPopup(false); }}
                        style={{ padding: '4px 12px', border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', background: 'transparent', color: 'var(--text-secondary)', cursor: 'pointer', fontSize: '0.72rem', fontFamily: 'var(--font-body)' }}
                      >
                        取消
                      </button>
                      <button
                        onClick={async () => {
                          if (workTitle.trim()) {
                            const r = await useManuscriptStore.getState().create(workTitle.trim());
                            if (r) { setWorkTitle(''); setShowWorkPopup(false); }
                            else { setWorkError(useManuscriptStore.getState().error || '创建失败'); }
                          }
                        }}
                        style={{ padding: '4px 12px', border: '1px solid var(--accent)', borderRadius: 'var(--radius-sm)', background: 'var(--accent)', color: '#fff', cursor: 'pointer', fontSize: '0.72rem', fontFamily: 'var(--font-body)' }}
                      >
                        创建
                      </button>
                    </div>
                  </div>
                )}

                {manuscripts.map(renderManuscriptItem)}
                {manuscripts.length === 0 && (
                  <div style={{
                    padding: '24px 16px',
                    textAlign: 'center',
                    color: 'var(--text-tertiary)',
                    fontSize: 'var(--text-xs)',
                    opacity: 0.6,
                  }}>
                    暂无作品
                  </div>
                )}
              </div>
            )}
          </div>
        </>
      )}

      {/* ── 收起状态：44px 图标条 ── */}
      {sidebarCollapsed && (
        <div style={{
          width: 44,
          flex: 1,
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          gap: 12,
          padding: '8px 0',
        }}>
          {/* 展开侧栏 */}
          <button
            onClick={e => { e.stopPropagation(); toggleSidebar(); }}
            style={collapsedIconBtnStyle}
            title="展开侧边栏"
          >
            <PanelLeftOpen size={16} strokeWidth={1.6} />
          </button>

          {/* 分隔线 */}
          <div style={{ width: 20, height: 1, background: 'var(--border)', opacity: 0.5 }} />

          {/* 新对话 */}
          <button
            onClick={e => { e.stopPropagation(); createSession(); }}
            style={collapsedIconBtnStyle}
            title="新对话"
          >
            <Plus size={16} strokeWidth={1.6} />
          </button>
        </div>
      )}

      {/* ── 拖拽调节手柄（展开态时显示在右侧边缘）── */}
      {!sidebarCollapsed && (
        <div
          onMouseDown={handleResizeMouseDown}
          style={{
            position: 'absolute',
            top: 0,
            right: 0,
            width: 5,
            height: '100%',
            cursor: 'col-resize',
            zIndex: 10,
            background: 'transparent',
            borderRight: '1px solid var(--border-light)',
            borderLeft: '1px solid transparent',
            transition: 'border-color 150ms ease, background 150ms ease',
          }}
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

/** 图标按钮基础样式 */
const iconBtnStyle: React.CSSProperties = {
  display: 'inline-flex',
  alignItems: 'center',
  justifyContent: 'center',
  border: 'none',
  background: 'transparent',
  cursor: 'pointer',
  borderRadius: 'var(--radius-sm)',
  transition: 'all 120ms cubic-bezier(0.25, 1, 0.5, 1)',
  outline: 'none',
};

/** 收起状态的图标按钮样式 */
const collapsedIconBtnStyle: React.CSSProperties = {
  ...iconBtnStyle,
  width: 32,
  height: 32,
  borderRadius: 'var(--radius-sm)',
  color: 'var(--text-tertiary)',
};

export default SoloSidebar;
