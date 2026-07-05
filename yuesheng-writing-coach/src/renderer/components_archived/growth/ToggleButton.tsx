import React from 'react';

interface ToggleButtonProps {
  showGlobal: boolean;
  onToggle: () => void;
}

/** 全局趋势切换按钮（RP-03） */
export const ToggleButton: React.FC<ToggleButtonProps> = ({ showGlobal, onToggle }) => (
  <button
    type="button"
    onClick={onToggle}
    style={{
      padding: '3px 10px',
      borderRadius: 'var(--radius-full)',
      border: '1px solid var(--border-light)',
      background: showGlobal ? 'var(--accent)' : 'transparent',
      color: showGlobal ? 'var(--text-on-accent)' : 'var(--text-tertiary)',
      fontSize: '0.65rem',
      cursor: 'pointer',
      transition: 'all 0.15s ease',
      whiteSpace: 'nowrap',
    }}
  >
    {showGlobal ? '全部历史' : '当前会话'}
  </button>
);
