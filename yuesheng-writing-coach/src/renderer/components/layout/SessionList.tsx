import React, { useState, useCallback } from 'react';
import { Plus, MessageSquare, Trash2 } from 'lucide-react';
import type { ChatSession } from '../../stores/session.store';
import styles from './SessionList.module.css';

const EASE = 'cubic-bezier(0.25, 1, 0.5, 1)';

/** 按时间分组会话 */
function groupSessions(sessions: ChatSession[]) {
  const now = new Date();
  const today: ChatSession[] = [];
  const thisWeek: ChatSession[] = [];
  const earlier: ChatSession[] = [];

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

interface SessionGroup {
  group: string;
  items: ChatSession[];
}

export interface SessionListProps {
  sessions: ChatSession[];
  currentSessionId: string | null;
  onSwitch: (id: string) => void;
  onDelete: (id: string) => void;
  onRename: (id: string, title: string) => void;
  onCreateSession: () => void;
}

/** 图标按钮基础样式（内联，因跨组件复用需保持一致） */
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

export const SessionList: React.FC<SessionListProps> = ({
  sessions,
  currentSessionId,
  onSwitch,
  onDelete,
  onRename,
  onCreateSession,
}) => {
  const [searchQuery, setSearchQuery] = useState('');
  const [sessionMaxCount, setSessionMaxCount] = useState(30);
  const [editingSessionId, setEditingSessionId] = useState<string | null>(null);
  const [editTitle, setEditTitle] = useState('');

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

  const renderSessionItem = useCallback((session: ChatSession) => {
    const isActive = session.id === currentSessionId;

    const handleRename = () => {
      const newTitle = editTitle.trim();
      if (newTitle && newTitle !== session.title) {
        onRename(session.id, newTitle);
      }
      setEditingSessionId(null);
    };

    return (
      <div
        key={session.id}
        className={`${styles.sessionItem} ${isActive ? styles.sessionActive : ''}`}
        onMouseEnter={e => { const a = e.currentTarget.querySelector(`.${styles.sidebarActions}`); if (a) (a as HTMLElement).style.display = 'flex'; }}
        onMouseLeave={e => { const a = e.currentTarget.querySelector(`.${styles.sidebarActions}`); if (a) (a as HTMLElement).style.display = 'none'; }}
        onClick={() => onSwitch(session.id)}
      >
        <div className={styles.sessionRow}>
          <MessageSquare size={14} strokeWidth={1.6} className={styles.icon} />
          {editingSessionId === session.id ? (
            <input
              autoFocus
              value={editTitle}
              onChange={e => setEditTitle(e.target.value)}
              onBlur={handleRename}
              onKeyDown={e => { if (e.key === 'Enter') handleRename(); if (e.key === 'Escape') setEditingSessionId(null); }}
              className={styles.renameInput}
              onClick={e => e.stopPropagation()}
            />
          ) : (
            <span className={styles.sessionTitle}>
              {session.title || '新对话'}
            </span>
          )}
        </div>

        {/* 操作按钮（hover 显示） */}
        <div className={styles.sidebarActions}>
          <button
            onClick={e => { e.stopPropagation(); setEditingSessionId(session.id); setEditTitle(session.title); }}
            style={{ ...iconBtnStyle, color: 'var(--text-tertiary)', padding: 2 }}
            title="重命名"
          >
            <span style={{ fontSize: 11 }}>✎</span>
          </button>
          <button
            onClick={e => { e.stopPropagation(); onDelete(session.id); }}
            style={{ ...iconBtnStyle, color: 'var(--error)', padding: 2 }}
            title="删除"
          >
            <Trash2 size={12} strokeWidth={1.6} />
          </button>
        </div>

        {/* 预览文本 */}
        {session.lastMessage && (
          <span className={styles.previewText}>
            {session.lastMessage}
          </span>
        )}
      </div>
    );
  }, [currentSessionId, editTitle, onSwitch, onDelete, onRename]);

  return (
    <div>
      {/* 新建按钮 */}
      <button
        onClick={e => { e.stopPropagation(); onCreateSession(); }}
        className={styles.newBtn}
      >
        <Plus size={14} strokeWidth={2} />
        <span>新对话</span>
      </button>

      {/* 搜索框 */}
      <div className={styles.searchWrapper}>
        <input
          type="text"
          value={searchQuery}
          onChange={e => setSearchQuery(e.target.value)}
          placeholder="搜索对话..."
          aria-label="搜索对话"
          className={styles.searchInput}
          onFocus={e => { e.currentTarget.style.borderColor = 'var(--accent)'; }}
          onBlur={e => { e.currentTarget.style.borderColor = 'var(--border)'; }}
        />
      </div>

      {/* 分组列表 */}
      {groupedSessions.map((group: SessionGroup) => (
        <div key={group.group}>
          <div className={styles.groupLabel}>{group.group}</div>
          {group.items.map(renderSessionItem)}
        </div>
      ))}

      {/* 显示更多 */}
      {hasMore && (
        <button
          onClick={() => setSessionMaxCount(prev => prev + 30)}
          className={styles.moreBtn}
        >
          显示更多对话
        </button>
      )}

      {/* 空状态 */}
      {sessions.length === 0 && (
        <div className={styles.emptyState}>暂无对话</div>
      )}
    </div>
  );
};
