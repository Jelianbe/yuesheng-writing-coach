import React, { useRef, useEffect, useMemo } from 'react';
import { MessageBubble } from './MessageBubble';
import { TypingIndicator } from './TypingIndicator';
import { EmptyState } from '../common/EmptyState';
import { MessageSquare, ChevronUp } from 'lucide-react';
import { ChatMessage } from '../../shared/types';

interface MessageListProps {
  messages: ChatMessage[];
  isStreaming: boolean;
  hasSession: boolean;
  /** 搜索关键词（不为空时过滤消息） */
  searchQuery?: string;
  /** 是否有更多历史消息可加载 */
  hasMore?: boolean;
  /** 是否正在加载更多历史消息 */
  isLoadingMore?: boolean;
  /** 加载更多历史消息的回调 */
  onLoadMore?: () => void;
  /** 自定义空状态的渲染 */
  emptyState?: React.ReactNode;
}

// ── 时间分组工具 ──

type TimeGroup = 'today' | 'yesterday' | 'thisWeek' | 'thisMonth' | 'earlier';

const GROUP_LABELS: Record<TimeGroup, string> = {
  today: '今天',
  yesterday: '昨天',
  thisWeek: '这周',
  thisMonth: '这个月',
  earlier: '更早',
};

function getTimeGroup(timestamp: number): TimeGroup {
  const now = new Date();
  const msgDate = new Date(timestamp);
  const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
  const msgDayStart = new Date(msgDate.getFullYear(), msgDate.getMonth(), msgDate.getDate()).getTime();
  const diffDays = Math.floor((todayStart - msgDayStart) / (1000 * 60 * 60 * 24));
  if (diffDays === 0) return 'today';
  if (diffDays === 1) return 'yesterday';
  if (diffDays < 7) return 'thisWeek';
  if (diffDays < 30) return 'thisMonth';
  return 'earlier';
}

/** 时间分隔线组件 */
const TimeSeparator: React.FC<{ label: string }> = ({ label }) => (
  <div
    style={{
      display: 'flex',
      alignItems: 'center',
      gap: 12,
      padding: '8px 0',
      userSelect: 'none',
    }}
    role="separator"
    aria-label={label}
  >
    <div style={{ flex: 1, height: '1px', background: 'var(--border-light)' }} />
    <span
      style={{
        fontSize: '0.68rem',
        color: 'var(--text-tertiary)',
        fontWeight: 500,
        letterSpacing: '0.03em',
        whiteSpace: 'nowrap',
      }}
    >
      {label}
    </span>
    <div style={{ flex: 1, height: '1px', background: 'var(--border-light)' }} />
  </div>
);

/**
 * MessageList — 消息列表容器（增强版）
 *
 * 新增功能：
 * - 时间分组（今天/昨天/这周/这个月/更早）
 * - 搜索过滤（通过 searchQuery prop）
 * - 历史消息加载（onLoadMore + hasMore）
 * - 自动滚动到最新消息
 */
export const MessageList: React.FC<MessageListProps> = ({
  messages,
  isStreaming,
  hasSession,
  searchQuery = '',
  hasMore = false,
  isLoadingMore = false,
  onLoadMore,
  emptyState,
}) => {
  const listRef = useRef<HTMLDivElement>(null);
  const bottomRef = useRef<HTMLDivElement>(null);
  const prevMessageCountRef = useRef(messages.length);

  // Auto-scroll to bottom only on new messages (not on load more)
  useEffect(() => {
    const prevCount = prevMessageCountRef.current;
    prevMessageCountRef.current = messages.length;
    // Only auto-scroll if messages were added at the bottom (new message, not loading history)
    if (messages.length > prevCount) {
      bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
    }
  }, [messages.length]);

  // ── 搜索过滤 ──
  const filteredMessages = useMemo(() => {
    if (!searchQuery.trim()) return messages;
    const query = searchQuery.trim().toLowerCase();
    return messages.filter((msg) =>
      msg.content.toLowerCase().includes(query)
    );
  }, [messages, searchQuery]);

  // ── 时间分组渲染 ──
  const renderedMessages = useMemo(() => {
    if (filteredMessages.length === 0) return [];

    const elements: React.ReactElement[] = [];
    let lastGroup: TimeGroup | null = null;

    filteredMessages.forEach((msg, index) => {
      const group = getTimeGroup(msg.timestamp);
      if (group !== lastGroup) {
        elements.push(
          <TimeSeparator key={`sep-${group}-${index}`} label={GROUP_LABELS[group]} />
        );
        lastGroup = group;
      }
      elements.push(<MessageBubble key={msg.id} message={msg} />);
    });

    return elements;
  }, [filteredMessages]);

  if (!hasSession) {
    return (
      <div
        style={{
          flex: 1,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
        }}
      >
        {emptyState || (
          <EmptyState
            icon={MessageSquare}
            title="写点什么，我们聊聊"
            description="开始一段新的对话，或从左侧选择一个已有会话"
          />
        )}
      </div>
    );
  }

  if (messages.length === 0) {
    return (
      <div
        style={{
          flex: 1,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
        }}
      >
        <EmptyState
          icon={MessageSquare}
          title="发送第一条消息"
          description="粘贴你的写作内容，让月笙帮你分析"
        />
      </div>
    );
  }

  return (
    <div
      ref={listRef}
      style={{
        flex: 1,
        overflowY: 'auto',
        padding: '12px 20px 0',
      }}
      role="log"
      aria-label="Chat messages"
      aria-live="polite"
    >
      <div style={{ maxWidth: '48rem', margin: '0 auto' }}>
        {/* 搜索无结果提示 */}
        {searchQuery.trim() && filteredMessages.length === 0 && (
          <div
            style={{
              textAlign: 'center',
              padding: '40px 20px',
              color: 'var(--text-tertiary)',
              fontSize: '0.82rem',
            }}
          >
            没有匹配的消息
          </div>
        )}

        {/* 加载更多历史消息按钮 */}
        {hasMore && !searchQuery.trim() && (
          <div style={{ textAlign: 'center', padding: '8px 0 4px' }}>
            <button
              onClick={onLoadMore}
              disabled={isLoadingMore}
              style={{
                display: 'inline-flex',
                alignItems: 'center',
                gap: 6,
                padding: '6px 16px',
                border: '1px solid var(--border)',
                borderRadius: 'var(--radius-full)',
                background: 'var(--bg-card)',
                color: 'var(--text-tertiary)',
                fontSize: '0.75rem',
                cursor: isLoadingMore ? 'not-allowed' : 'pointer',
                fontFamily: 'var(--font-body)',
                transition: 'all 0.15s ease',
                opacity: isLoadingMore ? 0.6 : 1,
              }}
              onMouseEnter={(e) => {
                if (!isLoadingMore) {
                  e.currentTarget.style.borderColor = 'var(--accent)';
                  e.currentTarget.style.color = 'var(--text-secondary)';
                }
              }}
              onMouseLeave={(e) => {
                if (!isLoadingMore) {
                  e.currentTarget.style.borderColor = 'var(--border)';
                  e.currentTarget.style.color = 'var(--text-tertiary)';
                }
              }}
            >
              <ChevronUp size={14} strokeWidth={1.6} />
              {isLoadingMore ? '加载中...' : '加载更多历史消息'}
            </button>
          </div>
        )}

        <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
          {renderedMessages}
        </div>

        {/* Typing indicator */}
        {isStreaming && <TypingIndicator />}
      </div>

      {/* Scroll anchor */}
      <div ref={bottomRef} />
    </div>
  );
};
