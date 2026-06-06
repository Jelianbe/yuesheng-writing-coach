import React, { useState, useRef, useEffect, useCallback } from 'react';
import { Send, Square } from 'lucide-react';

interface MessageInputProps {
  onSend: (message: string) => void;
  onStop: () => void;
  isStreaming: boolean;
  disabled?: boolean;
  placeholder?: string;
}

export const MessageInput: React.FC<MessageInputProps> = ({
  onSend,
  onStop,
  isStreaming,
  disabled = false,
  placeholder = '输入你的写作内容或问题...',
}) => {
  const [input, setInput] = useState('');
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  const handleSubmit = useCallback(() => {
    const trimmed = input.trim();
    if (!trimmed || isStreaming || disabled) return;
    onSend(trimmed);
    setInput('');
    // Reset textarea height
    if (textareaRef.current) {
      textareaRef.current.style.height = 'auto';
    }
  }, [input, isStreaming, disabled, onSend]);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        handleSubmit();
      }
    },
    [handleSubmit]
  );

  // Auto-resize textarea
  useEffect(() => {
    const textarea = textareaRef.current;
    if (!textarea) return;
    textarea.style.height = 'auto';
    textarea.style.height = `${Math.min(textarea.scrollHeight, 200)}px`;
  }, [input]);

  // Focus input on mount
  useEffect(() => {
    textareaRef.current?.focus();
  }, []);

  const isEmpty = !input.trim();

  return (
    <div className="input-area" role="form" aria-label="Message input">
      <div className="input-wrapper">
        <textarea
          ref={textareaRef}
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={handleKeyDown}
          placeholder={placeholder}
          disabled={disabled || isStreaming}
          rows={1}
          aria-label="Message text"
        />
        {isStreaming ? (
          <button
            className="input-send-btn"
            onClick={onStop}
            aria-label="Stop generation"
            style={{ background: 'var(--error)' }}
          >
            <Square className="w-4 h-4 fill-current" />
          </button>
        ) : (
          <button
            className="input-send-btn"
            onClick={handleSubmit}
            disabled={disabled || isEmpty}
            aria-label="Send message"
          >
            <Send className="w-4 h-4" />
          </button>
        )}
      </div>
    </div>
  );
};
