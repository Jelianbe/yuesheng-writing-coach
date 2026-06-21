import React, { useState, useCallback } from 'react';
import { useConfigStore } from '../../../stores/config.store';
import { useChatStore } from '../../../stores/chat.store';
import { useUiStore } from '../../../stores/ui.store';
import styles from './index.module.css';

interface FooterProps {
  chatSessionId: string | null;
  onToggleTemplate?: () => void;
}

const ATT_LEVELS = [
  { id: 'doubao' as const,  color: '#5A8F68', label: '豆包' },
  { id: 'yuesheng' as const,color: '#C8943C', label: '月笙如歌' },
  { id: 'sensei' as const,  color: '#B84A4A', label: 'Sensei' },
];

export const Footer: React.FC<FooterProps> = ({ chatSessionId, onToggleTemplate }) => {
  const { attitudeLevel, setAttitudeLevel } = useConfigStore();
  const { trainingContexts } = useUiStore();
  const [text, setText] = useState('');
  const [locked, setLocked] = useState(false);

  const handleSend = useCallback(async () => {
    if (!text.trim() || !chatSessionId) return;
    const trainingCtx = trainingContexts[chatSessionId];
    const studentContext = trainingCtx
      ? JSON.stringify({
          techniqueName: trainingCtx.techniqueName,
          coreName: trainingCtx.coreName,
          difficulty: trainingCtx.difficulty,
          category: trainingCtx.category,
          description: trainingCtx.description,
        })
      : '';
    useChatStore.getState().sendMessage(text.trim(), {
      sessionId: chatSessionId,
      attitudeLevel,
      studentContext,
    });
    setText('');
  }, [text, chatSessionId, attitudeLevel, trainingContexts]);

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleSend();
    }
  };

  return (
    <footer className={styles.footer}>
      {/* Top row: [模板] + attitude lights + lock */}
      <div className={styles.topRow}>
        <div className={styles.leftActions}>
          <button
            className={styles.templateBtn}
            onClick={onToggleTemplate}
            disabled={!chatSessionId}
          >[模板]</button>
        </div>
        <div className={styles.rightActions}>
          <div className={styles.attLights}>
            {ATT_LEVELS.map(lv => (
              <button
                key={lv.id}
                className={`${styles.attDot} ${attitudeLevel === lv.id ? styles.attActive : ''}`}
                style={{
                  borderColor: lv.color,
                  background: attitudeLevel === lv.id ? lv.color : 'transparent',
                  opacity: locked ? 0.6 : 1,
                }}
                onClick={() => !locked && setAttitudeLevel(lv.id)}
                title={lv.label}
              />
            ))}
          </div>
          <button
            className={styles.lockBtn}
            onClick={() => setLocked(!locked)}
            title={locked ? '已锁定' : '未锁定'}
          >
            {locked ? '🔒' : '🔓'}
          </button>
        </div>
      </div>

      {/* Textarea + Send */}
      <div className={styles.inputWrap}>
        <textarea
          className={styles.textarea}
          placeholder="输入你的作品，或直接开始对话..."
          value={text}
          onChange={e => setText(e.target.value)}
          onKeyDown={handleKeyDown}
        />
        <button
          className={styles.sendBtn}
          disabled={!text.trim() || !chatSessionId}
          onClick={handleSend}
        >发送</button>
      </div>
    </footer>
  );
};
