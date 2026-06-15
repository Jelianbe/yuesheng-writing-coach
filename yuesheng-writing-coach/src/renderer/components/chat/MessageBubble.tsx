import React from 'react';
import ReactMarkdown from 'react-markdown';
import rehypeHighlight from 'rehype-highlight';
import { User } from 'lucide-react';
import { ChatMessage, SeverityLevel } from '../../shared/types';
import { Badge } from '../common/Badge';

interface MessageBubbleProps {
  message: ChatMessage;
  className?: string;
}

const severityColor: Record<SeverityLevel, 'warning' | 'danger'> = {
  L1: 'warning',
  L2: 'warning',
  L3: 'danger',
};

const severityLabel: Record<SeverityLevel, string> = {
  L1: '轻度',
  L2: '中度',
  L3: '严重',
};

/* ── 教练头像 ── */
const CoachAvatar: React.FC = () => (
  <div style={{
    width: 32,
    height: 32,
    borderRadius: '50%',
    background: 'linear-gradient(135deg, var(--accent) 0%, var(--accent-light) 100%)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    color: 'var(--text-on-accent)',
    fontSize: '0.75rem',
    fontWeight: 600,
    fontFamily: 'var(--font-body)',
    flexShrink: 0,
    boxShadow: '0 1px 3px rgba(196, 136, 58, 0.2)',
  }}>
    月
  </div>
);

/* ── 用户头像 ── */
const UserAvatar: React.FC = () => (
  <div style={{
    width: 32,
    height: 32,
    borderRadius: '50%',
    background: 'var(--bg-secondary)',
    border: '1px solid var(--border)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    flexShrink: 0,
  }}>
    <User size={14} strokeWidth={1.6} color="var(--text-tertiary)" />
  </div>
);

export const MessageBubble: React.FC<MessageBubbleProps> = ({ message, className = '' }) => {
  const isUser = message.role === 'user';
  const isSystem = message.role === 'system';

  if (isSystem) {
    return (
      <div className="message-bubble-container" style={{
        display: 'flex',
        alignItems: 'center',
        gap: 8,
        padding: '6px 12px',
        color: 'var(--text-tertiary)',
        fontSize: '0.8rem',
      }}>
        <div style={{ width: 6, height: 6, borderRadius: '50%', background: 'var(--text-tertiary)', opacity: 0.5 }} />
        <span>{message.content}</span>
      </div>
    );
  }

  return (
    <div className={`flex gap-3 message-enter ${className}`} style={{
      display: 'flex',
      gap: 10,
      flexDirection: isUser ? 'row-reverse' : 'row',
      alignItems: 'flex-start',
      padding: '0 20px',
    }}>
      {/* 头像 + 角色标签 */}
      <div style={{
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        gap: 2,
        flexShrink: 0,
        minWidth: 32,
      }}>
        {isUser ? <UserAvatar /> : <CoachAvatar />}
        <span style={{
          fontSize: '0.6rem',
          color: 'var(--text-tertiary)',
          fontFamily: 'var(--font-body)',
          opacity: 0.6,
          letterSpacing: '0.02em',
        }}>
          {isUser ? '你' : '月笙'}
        </span>
      </div>

      {/* 气泡 */}
      <div style={{
        maxWidth: '70%',
        display: 'flex',
        flexDirection: 'column',
        alignItems: isUser ? 'flex-end' : 'flex-start',
      }}>
        <div style={{
          padding: '10px 14px',
          fontSize: '0.9rem',
          lineHeight: 1.6,
          fontFamily: 'var(--font-body)',
          borderRadius: isUser
            ? 'var(--radius-lg) var(--radius-lg) var(--radius-sm) var(--radius-lg)'
            : 'var(--radius-lg) var(--radius-lg) var(--radius-lg) var(--radius-sm)',
          background: isUser ? 'var(--accent)' : 'var(--bg-card)',
          color: isUser ? 'var(--text-on-accent)' : 'var(--text-primary)',
          border: isUser ? 'none' : '1px solid var(--border)',
          boxShadow: isUser ? 'none' : '0 1px 3px rgba(44,36,22,0.06)',
          wordBreak: 'break-word',
        }}>
          {isUser ? (
            <p style={{ margin: 0, whiteSpace: 'pre-wrap', wordBreak: 'break-word' }}>
              {message.content}
            </p>
          ) : (
            <div className="markdown-content" style={{
              margin: 0,
              wordBreak: 'break-word',
            }}>
              <ReactMarkdown rehypePlugins={[rehypeHighlight]}>
                {message.content}
              </ReactMarkdown>
            </div>
          )}
        </div>

        {/* 诊断标签 */}
        {message.diagnosis && message.diagnosis.syndromes.length > 0 && !isUser && (
          <div style={{
            display: 'flex',
            flexWrap: 'wrap',
            gap: 4,
            marginTop: 6,
          }}>
            {message.diagnosis.syndromes.map((syndrome) => (
              <Badge
                key={syndrome.id}
                variant={severityColor[syndrome.severity]}
                className="cursor-default"
              >
                {syndrome.name} ({severityLabel[syndrome.severity]})
              </Badge>
            ))}
          </div>
        )}

        {/* 时间戳 */}
        <p style={{
          margin: '4px 4px 0',
          fontSize: '0.68rem',
          color: 'var(--text-tertiary)',
          opacity: 0.6,
          fontFamily: 'var(--font-body)',
        }}>
          {new Date(message.timestamp).toLocaleTimeString('zh-CN', {
            hour: '2-digit',
            minute: '2-digit',
          })}
        </p>
      </div>
    </div>
  );
};
