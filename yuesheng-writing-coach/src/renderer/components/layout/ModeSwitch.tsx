import React from 'react';
import { useParadigmStore } from '../../stores/paradigm.store';

/**
 * ModeSwitch — SOLO/IDE 胶囊切换器
 *
 * 放置在底部状态栏右侧，用于切换对话 / 编辑器两种范式。
 * - 默认 SOLO（chat-first）
 * - IDE 侧不实现界面，仅占位提示
 * - 切换时无需二次确认
 */
export const ModeSwitch: React.FC = () => {
  const activeParadigm = useParadigmStore(s => s.activeParadigm);
  const setParadigm = useParadigmStore(s => s.setParadigm);

  const isSolo = activeParadigm === 'chat';

  return (
    <div
      role="radiogroup"
      aria-label="模式切换"
      style={{
        display: 'flex',
        gap: 0,
        background: 'var(--bg-hover)',
        borderRadius: 'var(--radius-full)',
        padding: 2,
        cursor: 'pointer',
        flexShrink: 0,
      }}
    >
      {/* SOLO */}
      <button
        role="radio"
        aria-checked={isSolo}
        onClick={() => setParadigm('chat')}
        style={{
          padding: '1px 8px',
          border: 'none',
          borderRadius: 'var(--radius-full)',
          background: isSolo ? 'var(--bg-card)' : 'transparent',
          color: isSolo ? 'var(--text-primary)' : 'var(--text-tertiary)',
          fontFamily: 'var(--font-body)',
          fontSize: '0.6rem',
          fontWeight: isSolo ? 600 : 400,
          cursor: 'pointer',
          letterSpacing: '0.04em',
          transition: 'all 120ms cubic-bezier(0.25, 1, 0.5, 1)',
          boxShadow: isSolo ? '0 1px 2px rgba(44,36,22,0.08)' : 'none',
        }}
      >
        SOLO
      </button>

      {/* IDE */}
      <button
        role="radio"
        aria-checked={!isSolo}
        onClick={() => setParadigm('editor')}
        title={!isSolo ? '编辑器模式 - 开发中' : undefined}
        style={{
          padding: '1px 8px',
          border: 'none',
          borderRadius: 'var(--radius-full)',
          background: !isSolo ? 'var(--bg-card)' : 'transparent',
          color: !isSolo ? 'var(--text-primary)' : 'var(--text-tertiary)',
          fontFamily: 'var(--font-body)',
          fontSize: '0.6rem',
          fontWeight: !isSolo ? 600 : 400,
          cursor: 'pointer',
          letterSpacing: '0.04em',
          transition: 'all 120ms cubic-bezier(0.25, 1, 0.5, 1)',
          boxShadow: !isSolo ? '0 1px 2px rgba(44,36,22,0.08)' : 'none',
        }}
      >
        IDE
      </button>
    </div>
  );
};


