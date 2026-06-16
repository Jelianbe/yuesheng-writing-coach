/**
 * SearchPanel — 全局搜索面板
 *
 * 跨会话搜索消息内容，结果按会话分组展示。
 * 点击结果跳转到对应会话。
 */

import React, { useState, useCallback, useRef } from 'react';
import { Search, X, MessageSquare, ArrowRight } from 'lucide-react';
import { getInvoke } from '../../utils/ipc';
import { IPC_CHANNELS } from '../../shared/constants';
import styles from './search-panel.module.css';
import shared from '../profile/panel-shared.module.css';

interface SearchResultItem {
  sessionId: string;
  sessionTitle: string;
  messageId: string;
  content: string;
  timestamp: number;
}

interface SearchResultGroup {
  sessionId: string;
  sessionTitle: string;
  messages: SearchResultItem[];
}

export const SearchPanel: React.FC = () => {
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<SearchResultGroup[]>([]);
  const [loading, setLoading] = useState(false);
  const [searched, setSearched] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  const handleSearch = useCallback(async () => {
    const q = query.trim();
    if (!q) return;
    setLoading(true);
    setSearched(true);
    try {
      const invoke = getInvoke();
      const result = await invoke(IPC_CHANNELS.SESSION_SEARCH_MESSAGES, { query: q }) as {
        success: boolean; data?: SearchResultGroup[];
      };
      if (result.success && result.data) {
        setResults(result.data);
      } else {
        setResults([]);
      }
    } catch {
      setResults([]);
    } finally {
      setLoading(false);
    }
  }, [query]);

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') handleSearch();
    if (e.key === 'Escape') { setQuery(''); setResults([]); setSearched(false); }
  };

  const switchToSession = (sessionId: string) => {
    // 通过全局事件通知 App.tsx 切换会话
    window.dispatchEvent(new CustomEvent('switch-session', { detail: { sessionId } }));
  };

  return (
    <div className={styles.panel}>
      {/* 搜索框 */}
      <div className={styles.searchRow}>
        <div className={styles.inputContainer}>
          <Search size={14} strokeWidth={1.6} className={styles.searchIcon} />
          <input
            ref={inputRef}
            type="text"
            value={query}
            onChange={e => setQuery(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder="搜索所有会话消息..."
            autoFocus
            className={styles.textInput}
          />
          {query && (
            <button onClick={() => { setQuery(''); setResults([]); setSearched(false); inputRef.current?.focus(); }}
              className={styles.clearBtn}>
              <X size={14} strokeWidth={1.6} />
            </button>
          )}
        </div>
        <button onClick={handleSearch} disabled={!query.trim() || loading}
          className={styles.searchBtn}
          style={{
            border: `1px solid ${!query.trim() ? 'var(--border-light)' : 'var(--accent)'}`,
            background: !query.trim() ? 'transparent' : 'var(--accent)',
            color: !query.trim() ? 'var(--text-tertiary)' : 'var(--text-on-accent)',
            cursor: !query.trim() ? 'not-allowed' : 'pointer',
            opacity: loading ? 0.7 : 1,
          }}>
          {loading ? '搜索中...' : '搜索'}
        </button>
      </div>

      {/* 搜索结果 */}
      {searched && !loading && results.length === 0 && (
        <div className={styles.emptyResults}>
          没有找到匹配的结果
        </div>
      )}

      {results.length > 0 && (
        <div className={styles.resultsContainer}>
          <div className={`${shared.textSm} ${shared.textTertiary}`}>
            找到 {results.reduce((s, g) => s + g.messages.length, 0)} 条结果
          </div>

          {results.map(group => (
            <div key={group.sessionId}>
              <div className={`${shared.flexAlignCenter} ${shared.flexGap4} ${shared.textSm} ${shared.fontSemiBold} ${shared.textSecondary} ${styles.sessionHeader}`}>
                <MessageSquare size={12} strokeWidth={1.6} />
                {group.sessionTitle || '未命名会话'}
              </div>
              <div className={styles.messageList}>
                {group.messages.map(msg => (
                  <button
                    key={msg.messageId}
                    onClick={() => switchToSession(msg.sessionId)}
                    className={styles.resultItem}
                  >
                    <span className={styles.messageText}>
                      {msg.content.length > 120 ? msg.content.slice(0, 120) + '...' : msg.content}
                    </span>
                    <ArrowRight size={12} strokeWidth={1.6} className={styles.arrowIcon} />
                  </button>
                ))}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
};
