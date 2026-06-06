import React, { useRef, useEffect } from 'react';
import { MessageBubble } from '../chat/MessageBubble';
import { MessageInput } from '../chat/MessageInput';
import { TypingIndicator } from '../chat/TypingIndicator';
import { EmptyState } from '../common/EmptyState';
import { MessageSquare } from 'lucide-react';
import { ChatMessage } from '../../shared/types';

interface ChatPageProps {
  messages: ChatMessage[];
  isStreaming: boolean;
  onSend: (message: string) => void;
  onStop: () => void;
  hasSession: boolean;
}

export const ChatPage: React.FC<ChatPageProps> = ({
  messages,
  isStreaming,
  onSend,
  onStop,
  hasSession,
}) => {
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);

  // Auto-scroll to bottom when messages change
  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  if (!hasSession) {
    return (
      <div className="flex-1 flex items-center justify-center bg-bg-primary">
        <EmptyState
          icon={MessageSquare}
          title="开始你的写作之旅"
          description="选择一个会话或创建新会话，开始与月笙的写作辅导对话"
        />
      </div>
    );
  }

  return (
    <div className="flex-1 flex flex-col bg-bg-primary min-w-0">
      {/* Messages area */}
      <div
        ref={containerRef}
        className="flex-1 overflow-y-auto px-4 sm:px-6 py-6"
        role="log"
        aria-label="Chat messages"
        aria-live="polite"
      >
        {messages.length === 0 ? (
          <div className="max-w-2xl mx-auto text-center py-12">
            <div className="w-16 h-16 rounded-2xl bg-bg-secondary shadow-sm flex items-center justify-center mx-auto mb-4">
              <MessageSquare className="w-8 h-8 text-accent-primary" strokeWidth={1.5} />
            </div>
            <h2 className="text-h2 font-semibold text-text-primary mb-2">
              你好，我是月笙
            </h2>
            <p className="text-body text-text-secondary max-w-md mx-auto">
              你的写作教练。请分享你的写作内容，我会帮你识别问题并提供针对性的训练建议。
            </p>
          </div>
        ) : (
          <div className="max-w-3xl mx-auto space-y-6">
            {messages.map((message) => (
              <MessageBubble
                key={message.id}
                message={message}
              />
            ))}
            {isStreaming && <TypingIndicator />}
            <div ref={messagesEndRef} />
          </div>
        )}
      </div>

      {/* Input area */}
      <MessageInput
        onSend={onSend}
        onStop={onStop}
        isStreaming={isStreaming}
        disabled={!hasSession}
      />
    </div>
  );
};

// Usage example:
// <ChatPage
//   messages={messages}
//   isStreaming={isStreaming}
//   onSend={handleSend}
//   onStop={handleStop}
//   hasSession={!!activeSession}
// />
