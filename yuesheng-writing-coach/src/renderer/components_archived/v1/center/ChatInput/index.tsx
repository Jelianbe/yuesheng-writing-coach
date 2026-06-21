/**
 * ChatInput — 消息输入框组件
 *
 * 支持：
 * - 多行 textarea（自动增高）
 * - Enter 发送，Shift+Enter 换行
 * - 发送时调用父级 onSubmit
 * - loading 状态禁用
 * - 输入框空时发送按钮置灰
 *
 * 用法:
 * ```tsx
 * <ChatInput
 *   onSubmit={(text) => handleSend(text)}
 *   isLoading={isLoading}
 * />
 * ```
 */
import { useState, useRef, useCallback, type ChangeEvent, type KeyboardEvent } from 'react';
import styles from './index.module.css';

interface ChatInputProps {
  /** 发送消息回调 */
  onSubmit: (text: string) => void;
  /** AI 是否正在响应（禁用输入） */
  isLoading: boolean;
}

/**
 * ChatInput 输入框
 */
export function ChatInput({ onSubmit, isLoading }: ChatInputProps): JSX.Element {
  const [text, setText] = useState('');
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  /** 自动调整 textarea 高度 */
  const autoResize = useCallback(() => {
    const el = textareaRef.current;
    if (!el) return;
    el.style.height = 'auto';
    el.style.height = `${Math.min(el.scrollHeight, 120)}px`;
  }, []);

  /** 发送消息 */
  const handleSend = useCallback(() => {
    const trimmed = text.trim();
    if (!trimmed || isLoading) return;

    onSubmit(trimmed);
    setText('');

    // 重置 textarea 高度
    const el = textareaRef.current;
    if (el) {
      el.style.height = 'auto';
    }
  }, [text, isLoading, onSubmit]);

  /** 内容变更 */
  const handleChange = useCallback(
    (e: ChangeEvent<HTMLTextAreaElement>) => {
      setText(e.target.value);
      autoResize();
    },
    [autoResize],
  );

  /** 键盘事件：Enter 发送，Shift+Enter 换行 */
  const handleKeyDown = useCallback(
    (e: KeyboardEvent<HTMLTextAreaElement>) => {
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        handleSend();
      }
    },
    [handleSend],
  );

  const canSend = text.trim().length > 0 && !isLoading;

  return (
    <div className={styles.wrapper}>
      <textarea
        ref={textareaRef}
        className={styles.textarea}
        value={text}
        onChange={handleChange}
        onKeyDown={handleKeyDown}
        placeholder="输入消息..."
        rows={1}
        disabled={isLoading}
        aria-label="消息输入"
        aria-disabled={isLoading}
      />
      <button
        className={styles.sendBtn}
        onClick={handleSend}
        disabled={!canSend}
        type="button"
        aria-label="发送消息"
      >
        &#9650;
      </button>
    </div>
  );
}
