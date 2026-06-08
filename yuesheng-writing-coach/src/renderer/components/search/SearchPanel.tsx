/**
 * SearchPanel — 全局搜索面板
 *
 * 跨会话搜索消息内容，结果按会话分组展示。
 * 点击结果跳转到对应会话。
 */

import React, { useState, useCallback, useRef } from 'react';
import { Search, X, MessageSquare, ArrowRight } from 'lucide-react';
import { getInvoke } from '../../utils/ipc';

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

const EASE_OUT_QUART = 'cubic-bezier(0.25, 1, 0.5, 1)';

const SearchPanel: React.FC = () => {
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
      const result = await invoke('session:searchMessages', { query: q }) as {
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
    <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
      {/* 搜索框 */}
      <div style={{ display: 'flex', gap: 6 }}>
        <div style={{ flex: 1, display: 'flex', alignItems: 'center', gap: 6, padding: '6px 10px', border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', background: 'var(--bg-input)', transition: `border-color 200ms ${EASE_OUT_QUART}` }}
          onFocusCapture={() => { }}>
          <Search size={14} strokeWidth={1.6} style={{ color: 'var(--text-tertiary)', flexShrink: 0 }} />
          <input
            ref={inputRef}
            type="text"
            value={query}
            onChange={e => setQuery(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder="搜索所有会话消息..."
            autoFocus
            style={{
              flex: 1,
              border: 'none',
              outline: 'none',
              background: 'transparent',
              color: 'var(--text-primary)',
              fontFamily: 'var(--font-body)',
              fontSize: '0.82rem',
            }}
          />
          {query && (
            <button onClick={() => { setQuery(''); setResults([]); setSearched(false); inputRef.current?.focus(); }}
              style={{ border: 'none', background: 'transparent', cursor: 'pointer', color: 'var(--text-tertiary)', padding: 2, display: 'flex' }}>
              <X size={14} strokeWidth={1.6} />
            </button>
          )}
        </div>
        <button onClick={handleSearch} disabled={!query.trim() || loading}
          style={{
            padding: '6px 14px',
            border: `1px solid ${!query.trim() ? 'var(--border-light)' : 'var(--accent)'}`,
            borderRadius: 'var(--radius-sm)',
            background: !query.trim() ? 'transparent' : 'var(--accent)',
            color: !query.trim() ? 'var(--text-tertiary)' : 'var(--text-on-accent)',
            fontSize: '0.78rem',
            cursor: !query.trim() ? 'not-allowed' : 'pointer',
            fontFamily: 'var(--font-body)',
            transition: `all 150ms ${EASE_OUT_QUART}`,
            opacity: loading ? 0.7 : 1,
          }}>
          {loading ? '搜索中...' : '搜索'}
        </button>
      </div>

      {/* 搜索结果 */}
      {searched && !loading && results.length === 0 && (
        <div style={{ padding: '24px', textAlign: 'center', color: 'var(--text-tertiary)', fontSize: '0.82rem' }}>
          没有找到匹配的结果
        </div>
      )}

      {results.length > 0 && (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          <div style={{ fontSize: '0.72rem', color: 'var(--text-tertiary)' }}>
            找到 {results.reduce((s, g) => s + g.messages.length, 0)} 条结果
          </div>

          {results.map(group => (
            <div key={group.sessionId}>
              <div style={{ fontSize: '0.72rem', fontWeight: 600, color: 'var(--text-secondary)', padding: '0 2px 6px', display: 'flex', alignItems: 'center', gap: 4 }}>
                <MessageSquare size={12} strokeWidth={1.6} />
                {group.sessionTitle || '未命名会话'}
              </div>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
                {group.messages.map(msg => (
                  <button
                    key={msg.messageId}
                    onClick={() => switchToSession(msg.sessionId)}
                    style={{
                      display: 'flex', alignItems: 'flex-start', gap: 8,
                      padding: '8px 10px',
                      border: '1px solid var(--border-light)',
                      borderRadius: 'var(--radius-sm)',
                      background: 'transparent',
                      cursor: 'pointer',
                      textAlign: 'left',
                      fontFamily: 'var(--font-body)',
                      transition: `all 150ms ${EASE_OUT_QUART}`,
                    }}
                    onMouseEnter={e => { e.currentTarget.style.borderColor = 'var(--border)'; e.currentTarget.style.background = 'var(--bg-hover)'; }}
                    onMouseLeave={e => { e.currentTarget.style.borderColor = 'var(--border-light)'; e.currentTarget.style.background = 'transparent'; }}
                  >
                    <span style={{ flex: 1, fontSize: '0.78rem', color: 'var(--text-primary)', lineHeight: 1.5, display: '-webkit-box', WebkitLineClamp: 3, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>
                      {msg.content.length > 120 ? msg.content.slice(0, 120) + '...' : msg.content}
                    </span>
                    <ArrowRight size={12} strokeWidth={1.6} style={{ color: 'var(--text-tertiary)', flexShrink: 0, marginTop: 4 }} />
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

export default SearchPanel;
