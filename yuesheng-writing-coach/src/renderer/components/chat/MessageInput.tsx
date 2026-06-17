/**
 * MessageInput — 范式 A 两行输入区
 *
 * Row 1: 快捷指令 pills（提问 / 上传片段 / 话题模板 / 练习 / 进步）
 * Row 2: 文本输入框 + 发送按钮
 */

import React, { useState, useRef, useEffect, useCallback } from 'react';
import { Send, Square } from 'lucide-react';

/** 快捷 pill 定义 */
interface QuickPill {
  id: string;
  label: string;
  /** 点击后注入到输入框的前缀文本 */
  prefix?: string;
}

/** 默认快捷 pills — I-01: 仅保留模板辅助 */
const DEFAULT_QUICK_PILLS: QuickPill[] = [
  { id: 'template', label: '📝 模板辅助' },
];

interface MessageInputProps {
  onSend: (message: string) => void;
  onStop: () => void;
  isStreaming: boolean;
  disabled?: boolean;
  placeholder?: string;
  /** 自定义快捷 pills（默认使用 DEFAULT_QUICK_PILLS） */
  quickPills?: QuickPill[];
  /** Pill 点击回调（返回 pill id，可用于路由到不同逻辑） */
  onQuickPillClick?: (pillId: string) => void;
}

export const MessageInput: React.FC<MessageInputProps> = ({
  onSend,
  onStop,
  isStreaming,
  disabled = false,
  placeholder = '输入你的问题或粘贴写作内容...',
  quickPills = DEFAULT_QUICK_PILLS,
  onQuickPillClick,
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

  /** 处理 pill 点击：有 prefix 则注入输入框，否则触发回调 */
  const handlePillClick = useCallback((pill: QuickPill) => {
    if (disabled || isStreaming) return;
    if (onQuickPillClick) {
      onQuickPillClick(pill.id);
      return;
    }
    if (pill.prefix !== undefined) {
      setInput((prev) => (prev ? `${prev} ${pill.prefix}` : pill.prefix) ?? '');
      textareaRef.current?.focus();
    }
  }, [onQuickPillClick, disabled, isStreaming]);

  return (
    <div className="input-area" role="form" aria-label="Message input" style={{
      borderTop: '1px solid var(--border)',
      background: 'var(--bg-main)',
      padding: '10px 20px 14px',
      flexShrink: 0,
    }}>
      {/* Row 1: 快捷 pills */}
      <div style={{
        display: 'flex',
        gap: 6,
        marginBottom: 8,
        flexWrap: 'wrap',
      }}>
        {quickPills.map((pill) => (
          <button
            key={pill.id}
            onClick={() => handlePillClick(pill)}
            disabled={disabled || isStreaming}
            aria-label={pill.label}
            style={{
              padding: '4px 12px',
              border: '1px solid var(--border)',
              borderRadius: 'var(--radius-full)',
              background: 'var(--bg-card)',
              color: 'var(--text-secondary)',
              fontFamily: 'var(--font-body)',
              fontSize: '0.75rem',
              fontWeight: 500,
              cursor: (disabled || isStreaming) ? 'not-allowed' : 'pointer',
              opacity: (disabled || isStreaming) ? 0.5 : 1,
              transition: 'all 0.15s ease',
              whiteSpace: 'nowrap',
            }}
            onMouseEnter={(e) => {
              if (disabled || isStreaming) return;
              (e.currentTarget as HTMLElement).style.borderColor = 'var(--accent)';
              (e.currentTarget as HTMLElement).style.color = 'var(--text-primary)';
            }}
            onMouseLeave={(e) => {
              if (disabled || isStreaming) return;
              (e.currentTarget as HTMLElement).style.borderColor = 'var(--border)';
              (e.currentTarget as HTMLElement).style.color = 'var(--text-secondary)';
            }}
          >
            {pill.label}
          </button>
        ))}
      </div>

      {/* Row 2: 输入框 + 发送按钮 */}
      <div className="input-wrapper" style={{
        display: 'flex',
        alignItems: 'flex-end',
        gap: 8,
        background: 'var(--bg-card)',
        border: '1px solid var(--border)',
        borderRadius: 'var(--radius-lg)',
        padding: '8px 12px',
        transition: 'border-color 0.15s ease',
      }}>
        <textarea
          ref={textareaRef}
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={handleKeyDown}
          placeholder={placeholder}
          disabled={disabled || isStreaming}
          rows={1}
          aria-label="Message text"
          style={{
            flex: 1,
            border: 'none',
            outline: 'none',
            background: 'transparent',
            color: 'var(--text-primary)',
            fontFamily: 'var(--font-body)',
            fontSize: '0.9rem',
            lineHeight: 1.5,
            resize: 'none',
            minHeight: 24,
            maxHeight: 180, /* A-2: 与输入区 clamp 上限一致 */
          }}
        />
        {isStreaming ? (
          <button
            onClick={onStop}
            style={{
              width: 32,
              height: 32,
              borderRadius: 'var(--radius-md)',
              border: 'none',
              background: 'var(--error)',
              color: 'white',
              cursor: 'pointer',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              flexShrink: 0,
              transition: 'opacity 0.15s ease',
            }}
            aria-label="Stop generation"
          >
            <Square className="w-3.5 h-3.5 fill-current" />
          </button>
        ) : (
          <button
            onClick={handleSubmit}
            disabled={disabled || isEmpty}
            style={{
              width: 32,
              height: 32,
              borderRadius: 'var(--radius-md)',
              border: 'none',
              background: isEmpty ? 'var(--bg-disabled)' : 'var(--accent)',
              color: isEmpty ? 'var(--text-tertiary)' : 'var(--text-on-accent)',
              cursor: isEmpty ? 'not-allowed' : 'pointer',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              flexShrink: 0,
              transition: 'all 0.15s ease',
            }}
            title={disabled ? '请先配置 API Key' : '发送'}
            aria-label="Send message"
          >
            <Send className="w-4 h-4" />
          </button>
        )}
      </div>
    </div>
  );
};
