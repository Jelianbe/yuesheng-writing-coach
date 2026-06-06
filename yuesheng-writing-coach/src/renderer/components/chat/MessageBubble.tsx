import React from 'react';
import ReactMarkdown from 'react-markdown';
import rehypeHighlight from 'rehype-highlight';
import { User, BookOpen, AlertCircle } from 'lucide-react';
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

export const MessageBubble: React.FC<MessageBubbleProps> = ({ message, className = '' }) => {
  const isUser = message.role === 'user';
  const isSystem = message.role === 'system';

  if (isSystem) {
    return (
      <div className={`flex items-center gap-2 py-2 text-text-muted text-small ${className}`}>
        <AlertCircle className="w-4 h-4 flex-shrink-0" />
        <span>{message.content}</span>
      </div>
    );
  }

  return (
    <div
      className={`flex gap-3 message-enter ${className} ${isUser ? 'flex-row-reverse' : ''}`}
      role="article"
      aria-label={`${isUser ? 'Your' : 'AI'} message`}
    >
      {/* Avatar */}
      <div
        className={[
          'w-8 h-8 rounded-full flex-shrink-0 flex items-center justify-center',
          'shadow-sm',
          isUser ? 'bg-accent-primary' : 'bg-surface-secondary border border-border',
        ].join(' ')}
      >
        {isUser ? (
          <User className="w-4 h-4 text-text-inverse" />
        ) : (
          <BookOpen className="w-4 h-4 text-accent-primary" strokeWidth={1.5} />
        )}
      </div>

      {/* Bubble */}
      <div className={`max-w-[70%] ${isUser ? 'items-end' : 'items-start'}`}>
        <div
          className={[
            'px-4 py-3',
            'text-base leading-relaxed',
            isUser
              ? 'bg-accent-primary text-text-inverse rounded-[var(--radius-lg)] rounded-br-[var(--radius-sm)]'
              : 'bg-surface-secondary text-text-primary border border-border rounded-[var(--radius-lg)] rounded-bl-[var(--radius-sm)] shadow-sm',
          ].join(' ')}
        >
          {isUser ? (
            <p className="whitespace-pre-wrap break-words">{message.content}</p>
          ) : (
            <div
              className={[
                'markdown-content',
                '[&>p:first-child]:mt-0 [&>p:last-child]:mb-0',
              ].join(' ')}
            >
              <ReactMarkdown rehypePlugins={[rehypeHighlight]}>
                {message.content}
              </ReactMarkdown>
            </div>
          )}
        </div>

        {/* Diagnosis indicator */}
        {message.diagnosis && message.diagnosis.syndromes.length > 0 && !isUser && (
          <div className="mt-2 flex flex-wrap gap-1.5">
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

        {/* Timestamp */}
        <p className="text-xs text-text-tertiary mt-1.5 px-1">
          {new Date(message.timestamp).toLocaleTimeString('zh-CN', {
            hour: '2-digit',
            minute: '2-digit',
          })}
        </p>
      </div>
    </div>
  );
};

// Usage example:
// <MessageBubble message={chatMessage} />
