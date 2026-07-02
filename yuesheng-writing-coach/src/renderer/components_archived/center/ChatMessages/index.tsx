import React from 'react';
import type { ChatMessage } from '../../../shared/types';
import styles from './index.module.css';

interface ChatMessagesProps {
  messages: ChatMessage[];
  trainingCtx?: import('../../../stores/ui.store').TrainingContext | null;
}

const DIFF_LABEL_SHORT: Record<string, string> = {
  beginner: '初级', intermediate: '中级', advanced: '高级',
};

export const ChatMessages: React.FC<ChatMessagesProps> = ({ messages, trainingCtx }) => (
  <>
    {trainingCtx && (
      <div className={styles.trainBanner}>
        <div className={styles.trainBannerHdr}>
          <span className={styles.trainBannerName}>{trainingCtx.techniqueName}</span>
          <span className={styles.trainBannerDiff}>
            {DIFF_LABEL_SHORT[trainingCtx.difficulty] || trainingCtx.difficulty}
          </span>
          <span className={styles.trainBannerCat}>{trainingCtx.category}</span>
        </div>
        <p className={styles.trainBannerDesc}>
          {trainingCtx.description ? `${trainingCtx.description.slice(0, 80)}…` : ''}
        </p>
        <p className={styles.trainBannerCore}>
          <span className={styles.trainBannerCoreLabel}>所属：</span>{trainingCtx.coreName}
        </p>
      </div>
    )}
    <div className={styles.messagesContainer}>
      {messages.map((msg, i) => (
        <div
          key={msg.id ?? i}
          className={`${styles.messageRow} ${msg.role === 'user' ? styles.messageUser : ''}`}
        >
          <div className={styles.messageAvatar}>
            {msg.role === 'assistant' ? '月' : '我'}
          </div>
          <div className={styles.messageContent}>
            <div className={`${styles.messageBubble} ${
              msg.role === 'user' ? styles.messageBubbleUser : styles.messageBubbleAssistant
            }`}>
              {typeof msg.content === 'string'
                ? msg.content.split('\n').map((p, j) => <p key={j}>{p}</p>)
                : msg.content}
            </div>
            <div className={styles.messageTime}>
              {new Date(msg.timestamp ?? Date.now()).toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' })}
            </div>
          </div>
        </div>
      ))}
    </div>
  </>
);
