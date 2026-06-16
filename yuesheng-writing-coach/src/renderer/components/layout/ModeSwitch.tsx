import React from 'react';

/**
 * ModeSwitch — 范式指示器（V2+ 仅 SOLO）
 *
 * IDE 模式入口已移除，保留为纯展示组件。
 */
export const ModeSwitch: React.FC = () => {
  return (
    <div
      style={{
        display: 'flex',
        gap: 0,
        background: 'var(--bg-hover)',
        borderRadius: 'var(--radius-full)',
        padding: 2,
        flexShrink: 0,
      }}
    >
      <span
        style={{
          padding: '1px 8px',
          borderRadius: 'var(--radius-full)',
          background: 'var(--bg-card)',
          color: 'var(--text-primary)',
          fontFamily: 'var(--font-body)',
          fontSize: '0.6rem',
          fontWeight: 600,
          letterSpacing: '0.04em',
          boxShadow: '0 1px 2px rgba(44,36,22,0.08)',
        }}
      >
        SOLO
      </span>
    </div>
  );
};
