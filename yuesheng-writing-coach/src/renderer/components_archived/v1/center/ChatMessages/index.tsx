/**
 * ChatMessages — 消息列表组件
 *
 * 显示聊天消息列表，支持：
 * - 按时间倒序（最新在最下）
 * - 自动滚动到底部
 * - 空状态提示
 * - 角色区分样式（assistant 暖色左对齐 / user 灰底右对齐）
 * - 内容 \n 渲染为段落
 * - AI 加载态骨架
 * - 错误提示
 *
 * 用法:
 * ```tsx
 * <ChatMessages messages={messages} isLoading={isLoading} error={error} />
 * ```
 */
import { useEffect, useRef } from 'react';
import type { ChatMessage } from '@/shared/types-chat';
import styles from './index.module.css';

interface ChatMessagesProps {
  messages: ChatMessage[];
  isLoading: boolean;
  error: string | null;
}

/** 格式化时间戳为 HH:mm 格式 */
function formatTime(ts: number): string {
  try {
    return new Date(ts).toLocaleTimeString('zh-CN', {
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    });
  } catch {
    return '';
  }
}

/** 将 \n 分隔的文本渲染为 <p> 段落 */
function renderContent(content: string): JSX.Element[] {
  return content.split('\n').map((line, index) => (
    <p key={index} className={styles.paragraph}>
      {line || '\u00A0'}
    </p>
  ));
}

/**
 * 单条消息
 */
function MessageItem({ message }: { message: ChatMessage }): JSX.Element {
  const isAssistant = message.role === 'assistant';

  const messageClass = [
    styles.message,
    isAssistant ? styles.messageAssistant : styles.messageUser,
  ]
    .filter(Boolean)
    .join(' ');

  const bubbleClass = [
    styles.bubble,
    isAssistant ? styles.bubbleAssistant : styles.bubbleUser,
  ]
    .filter(Boolean)
    .join(' ');

  const avatarClass = [
    styles.avatar,
    isAssistant ? styles.avatarAssistant : styles.avatarUser,
  ]
    .filter(Boolean)
    .join(' ');

  const timestampClass = [
    styles.timestamp,
    isAssistant ? styles.timestampAssistant : styles.timestampUser,
  ]
    .filter(Boolean)
    .join(' ');

  return (
    <div
      className={messageClass}
      role="listitem"
      aria-label={`${isAssistant ? 'AI教练' : '我'}的消息`}
    >
      <div className={avatarClass} aria-hidden="true">
        {isAssistant ? '月' : '我'}
      </div>
      <div>
        <div className={bubbleClass}>
          {renderContent(message.content)}
        </div>
        <div className={timestampClass}>
          {formatTime(message.timestamp)}
        </div>
      </div>
    </div>
  );
}

/** 加载中骨架（跳动圆点） */
function LoadingDots(): JSX.Element {
  return (
    <div className={styles.loadingDots} aria-label="AI 正在思考" role="status">
      <span className={styles.dot} />
      <span className={styles.dot} />
      <span className={styles.dot} />
      <span aria-hidden="true" style={{ display: 'none' }}>加载中</span>
    </div>
  );
}

/**
 * ChatMessages 消息列表
 *
 * @param messages - 消息数组
 * @param isLoading - AI 是否正在响应
 * @param error - 错误信息
 */
export function ChatMessages({
  messages,
  isLoading,
  error,
}: ChatMessagesProps): JSX.Element {
  const bottomRef = useRef<HTMLDivElement>(null);

  // 新消息到达时自动滚到底部
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages, isLoading]);

  // 空状态
  if (messages.length === 0 && !isLoading && !error) {
    return (
      <div className={styles.empty} role="status">
        <span className={styles.emptyIcon} aria-hidden="true">&#9998;</span>
        <span>开始一段对话吧</span>
      </div>
    );
  }

  return (
    <div className={styles.container} role="list" aria-label="聊天消息列表">
      {messages.map((msg) => (
        <MessageItem key={msg.id} message={msg} />
      ))}

      {/* AI 正在响应时显示骨架 */}
      {isLoading && <LoadingDots />}

      {/* 错误提示 */}
      {error && (
        <div className={styles.errorMsg} role="alert">
          {error}
        </div>
      )}

      {/* 滚动锚点 */}
      <div ref={bottomRef} />
    </div>
  );
}
