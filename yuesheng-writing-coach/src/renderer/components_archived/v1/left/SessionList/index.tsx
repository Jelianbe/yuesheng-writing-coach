/**
 * SessionList — 会话列表示例
 *
 * 展示用户的所有聊天会话，支持选中切换。
 *
 * 用法:
 * ```tsx
 * <SessionList />
 * ```
 */
import { useCallback, useMemo } from 'react';
import { useSessionStore, type ChatSession } from '@/stores/session.store';
import { useTrainingStore, selectTrainingHistory } from '@/stores/training.store';
import styles from './index.module.css';

/** 格式化时间戳（Unix ms）为本地日期时间字符串 */
function formatTime(ts: number): string {
  try {
    const d = new Date(ts);
    const now = new Date();
    const diffMs = now.getTime() - d.getTime();
    const diffDays = Math.floor(diffMs / 86400000);

    if (diffDays === 0) {
      return d.toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' });
    }
    if (diffDays === 1) {
      return '昨天';
    }
    if (diffDays < 7) {
      return `${diffDays}天前`;
    }
    return d.toLocaleDateString('zh-CN', { month: 'short', day: 'numeric' });
  } catch {
    return '';
  }
}

interface SessionItemProps {
  session: ChatSession;
  isActive: boolean;
  isTraining: boolean;
  onSelect: (id: string) => void;
}

interface SessionListProps {
  searchQuery?: string;
}

function SessionItem({ session, isActive, isTraining, onSelect }: SessionItemProps): JSX.Element {
  const handleClick = useCallback(() => {
    onSelect(session.id);
  }, [session.id, onSelect]);

  const msgCount = session.messages?.length;
  const classNames = [
    styles.item,
    isActive ? styles.itemActive : '',
  ]
    .filter(Boolean)
    .join(' ');

  return (
    <button
      className={classNames}
      onClick={handleClick}
      type="button"
      aria-current={isActive ? 'true' : undefined}
      aria-label={`会话：${session.title}`}
    >
      <div className={styles.itemHeader}>
        <span className={styles.title}>{session.title}</span>
        {isTraining && <span className={styles.trainingBadge}>训练</span>}
        {msgCount !== undefined && (
          <span className={styles.badge}>{msgCount}</span>
        )}
      </div>
      <div className={styles.meta}>
        <span className={styles.time}>{formatTime(session.updatedAt)}</span>
        {session.lastMessage && (
          <span className={styles.lastMsg}>{session.lastMessage}</span>
        )}
      </div>
    </button>
  );
}

export function SessionList({ searchQuery = '' }: SessionListProps): JSX.Element {
  const allSessions = useSessionStore((s) => s.sessions);
  const currentSessionId = useSessionStore((s) => s.currentSessionId);
  const switchSession = useSessionStore((s) => s.switchSession);
  const history = useTrainingStore(selectTrainingHistory);

  const trainingSessionIds = useMemo(() => {
    const set = new Set<string>();
    for (const r of history) {
      if (r.sessionId) set.add(r.sessionId);
    }
    return set;
  }, [history]);

  const sessions = useMemo(() => {
    if (!searchQuery.trim()) return allSessions;
    const q = searchQuery.toLowerCase();
    return allSessions.filter(
      (s) =>
        s.title.toLowerCase().includes(q) ||
        (s.lastMessage && s.lastMessage.toLowerCase().includes(q)),
    );
  }, [allSessions, searchQuery]);

  if (allSessions.length === 0) {
    return (
      <div className={styles.empty}>
        暂无会话
      </div>
    );
  }

  if (sessions.length === 0) {
    return (
      <div className={styles.empty}>
        未找到匹配的会话
      </div>
    );
  }

  return (
    <div className={styles.list} role="listbox" aria-label="会话列表">
      {sessions.map((session) => (
        <SessionItem
          key={session.id}
          session={session}
          isActive={session.id === currentSessionId}
          isTraining={trainingSessionIds.has(session.id)}
          onSelect={switchSession}
        />
      ))}
    </div>
  );
}
