import React, { useRef, useEffect } from 'react';
import { MessageBubble } from './MessageBubble';
import { TypingIndicator } from './TypingIndicator';
import { EmptyState } from '../common/EmptyState';
import { MessageSquare } from 'lucide-react';
import { ChatMessage } from '../../shared/types';

interface MessageListProps {
  messages: ChatMessage[];
  isStreaming: boolean;
  hasSession: boolean;
  /** 自定义空状态的渲染 */
  emptyState?: React.ReactNode;
}

/**
 * MessageList — 消息列表容器
 *
 * 自动滚动到最新消息，支持流式加载时的打字指示器。
 */
export const MessageList: React.FC<MessageListProps> = ({
  messages,
  isStreaming,
  hasSession,
  emptyState,
}) => {
  const listRef = useRef<HTMLDivElement>(null);
  const bottomRef = useRef<HTMLDivElement>(null);

  // Auto-scroll to bottom on new messages
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages, isStreaming]);

  if (!hasSession) {
    return (
      <div className="flex-1 flex items-center justify-center">
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
      <div className="flex-1 flex items-center justify-center">
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
      className="flex-1 overflow-y-auto px-4 pt-6"
      role="log"
      aria-label="Chat messages"
      aria-live="polite"
    >
      <div className="max-w-3xl mx-auto space-y-4">
        {messages.map((msg) => (
          <MessageBubble key={msg.id} message={msg} />
        ))}

        {/* Typing indicator */}
        {isStreaming && <TypingIndicator />}
      </div>

      {/* Scroll anchor */}
      <div ref={bottomRef} />
    </div>
  );
};
