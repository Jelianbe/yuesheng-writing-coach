import React from 'react';
import type { ChatSession } from '../../../stores/session.store';
import styles from './index.module.css';

interface SessionListProps {
  sessions: ChatSession[];
  currentSessionId: string | null;
  onSelect: (id: string) => void;
  filter: 'all' | 'chat' | 'train';
  onFilterChange: (filter: 'all' | 'chat' | 'train') => void;
}

type FilterValue = 'all' | 'chat' | 'train';

const FILTER_OPTIONS: { value: FilterValue; label: string }[] = [
  { value: 'all', label: '全部' },
  { value: 'chat', label: '对话' },
  { value: 'train', label: '训练' },
];

function relTime(ts: number): string {
  const d = Date.now() - ts;
  if (d < 864e5) return '今天';
  if (d < 1728e5) return '昨天';
  return '3天前';
}

export const SessionList: React.FC<SessionListProps> = ({
  sessions,
  currentSessionId,
  onSelect,
  filter,
  onFilterChange,
}) => {
  return (
    <div>
      <div className={styles.filterRow}>
        {FILTER_OPTIONS.map((opt) => {
          const isActive = filter === opt.value;
          return (
            <button
              key={opt.value}
              className={`${styles.filterBtn} ${isActive ? styles.filterBtnActive : ''}`}
              onClick={() => onFilterChange(opt.value)}
            >
              {opt.label}
            </button>
          );
        })}
      </div>

      {sessions.length === 0 ? (
        <div className={styles.empty}>暂无会话</div>
      ) : (
        sessions.map((s) => {
          const isTrain = s.title.startsWith('训练:');
          return (
            <div
              key={s.id}
              className={`${styles.item} ${currentSessionId === s.id ? styles.itemActive : ''} ${isTrain ? styles.itemTrain : ''}`}
              onClick={() => onSelect(s.id)}
            >
              <div className={styles.itemMain}>
                <span className={`${styles.itemIcon} ${isTrain ? styles.itemIconTrain : ''}`}>
                  {isTrain ? '◎' : '◌'}
                </span>
                <span className={`${styles.itemTitle} ${styles.itemTitleWrap}`}>
                  {s.title}
                </span>
                <span className={styles.msgCount}>
                  {s.messageCount ?? 0}条
                </span>
                <span className={styles.itemTime}>{relTime(s.createdAt)}</span>
              </div>
              {s.lastMessage && (
                <div className={styles.itemPreview}>{s.lastMessage}</div>
              )}
            </div>
          );
        })
      )}
    </div>
  );
};
