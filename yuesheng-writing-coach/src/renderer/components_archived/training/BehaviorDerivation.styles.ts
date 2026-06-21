/**
 * BehaviorDerivationTool 样式常量
 *
 * 从 BehaviorDerivationTool.tsx 拆出的纯样式定义。
 */

import type { CSSProperties } from 'react';

export const sectionStyle: CSSProperties = {
  backgroundColor: 'var(--bg-secondary)',
  borderRadius: 10,
  border: '1px solid var(--border)',
  overflow: 'hidden',
};

export const sectionTitleStyle: CSSProperties = {
  fontSize: '0.875rem',
  fontWeight: 600,
  color: 'var(--text-primary)',
  padding: '10px 16px',
  cursor: 'pointer',
  display: 'flex',
  justifyContent: 'space-between',
  alignItems: 'center',
  userSelect: 'none',
};

export const expandIconStyle: CSSProperties = {
  fontSize: '0.75rem',
  color: 'var(--text-tertiary)',
  transition: 'transform 0.2s',
};

export const inputStyle: CSSProperties = {
  width: '100%',
  padding: 8,
  borderRadius: 6,
  border: '1px solid var(--border)',
  backgroundColor: 'var(--bg-input)',
  color: 'var(--text-primary)',
  fontSize: '0.8rem',
  fontFamily: 'inherit',
  boxSizing: 'border-box',
  resize: 'vertical',
};

export const labelStyle: CSSProperties = {
  fontSize: '0.8rem',
  fontWeight: 500,
  color: 'var(--text-secondary)',
  marginBottom: 4,
  display: 'block',
};

export const fieldRowStyle: CSSProperties = {
  marginBottom: 12,
};

export const primaryBtnStyle: CSSProperties = {
  padding: '8px 24px',
  borderRadius: 6,
  border: 'none',
  backgroundColor: 'var(--accent)',
  color: 'var(--text-on-accent)',
  cursor: 'pointer',
  fontSize: '0.85rem',
  fontWeight: 500,
};

export const resultCardStyle: CSSProperties = {
  padding: 12,
  borderRadius: 8,
  backgroundColor: '#eafaf1',
  border: '1px solid #d5f5e3',
  marginTop: 16,
  fontSize: '0.85rem',
  lineHeight: 1.6,
  color: 'var(--text-primary)',
};
