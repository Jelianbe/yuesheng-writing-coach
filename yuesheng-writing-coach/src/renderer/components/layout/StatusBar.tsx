import React from 'react';
import { useManuscriptStore } from '../../stores/manuscript.store';
import { useChapterStore } from '../../stores/chapter.store';
import { useSessionStore } from '../../stores/session.store';

/* ── 状态点脉冲动画（CSS keyframe 注入）── */
const keyframesStyleId = 'status-bar-keyframes';
if (typeof document !== 'undefined' && !document.getElementById(keyframesStyleId)) {
  const style = document.createElement('style');
  style.id = keyframesStyleId;
  style.textContent = `@keyframes statusPulse {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.3; }
  }`;
  document.head.appendChild(style);
}

/**
 * StatusBar — 底部 26px 状态栏
 *
 * 显示当前上下文（作品/章节）和连接状态。
 * - 状态点：绿色脉冲表示活跃对话，灰色表示空闲
 * - 上下文：当前作品名 | 章节名（或"未选择作品"）
 * - SOLO 模式标识
 */
export const StatusBar: React.FC = () => {
  const currentManuscript = useManuscriptStore(s => s.currentManuscript);
  const currentChapter = useChapterStore(s => s.currentChapter);
  const currentSessionId = useSessionStore(s => s.currentSessionId);

  const hasActiveSession = currentSessionId !== null;

  return (
    <footer
      role="status"
      aria-label="状态栏"
      style={{
        height: 26,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        padding: '0 16px',
        background: 'var(--bg-secondary)',
        borderTop: '1px solid var(--border)',
        fontSize: '0.65rem',
        fontFamily: 'var(--font-body)',
        color: 'var(--text-tertiary)',
        flexShrink: 0,
        letterSpacing: '0.02em',
      }}
    >
      {/* 左侧：状态点 + 上下文 */}
      <div style={{
        display: 'flex',
        alignItems: 'center',
        gap: 8,
        overflow: 'hidden',
      }}>
        {/* 状态点 */}
        <span
          style={{
            width: 6,
            height: 6,
            borderRadius: '50%',
            background: hasActiveSession ? 'var(--accent)' : 'var(--text-tertiary)',
            opacity: hasActiveSession ? 0.8 : 0.3,
            flexShrink: 0,
            animation: hasActiveSession ? 'statusPulse 2s ease-in-out infinite' : 'none',
          }}
        />

        {/* 上下文路径 */}
        <span style={{
          overflow: 'hidden',
          textOverflow: 'ellipsis',
          whiteSpace: 'nowrap',
          maxWidth: 360,
          opacity: 0.75,
        }}>
          {currentManuscript
            ? `${currentManuscript.title}${currentChapter ? ` · ${currentChapter.title}` : ''}`
            : '未选择作品'}
        </span>
      </div>

      {/* 右侧：模式标识 */}
      <span style={{
        opacity: 0.45,
        fontSize: '0.6rem',
        letterSpacing: '0.04em',
        flexShrink: 0,
      }}>
        SOLO
      </span>
    </footer>
  );
};


