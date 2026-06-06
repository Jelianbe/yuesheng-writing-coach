/**
 * TrainingWorkshop 共享样式常量
 *
 * 从 TrainingWorkshop.tsx 提取的样式，供所有子组件复用。
 */

import type React from 'react';
import type { SeverityLevel } from '../../shared/types';

/** 引用截断最大字符数 */
export const MAX_QUOTE_LENGTH = 60;

export const severityStyles: Record<SeverityLevel, { color: string; bg: string; label: string }> = {
  L3: { color: '#c0392b', bg: '#fdf0ef', label: '严重' },
  L2: { color: '#d35400', bg: '#fef5e7', label: '中等' },
  L1: { color: '#7f8c8d', bg: '#f2f3f4', label: '轻微' },
};

export const statusIcons: Record<string, string> = {
  completed: '✓',
  assigned: '○',
  in_progress: '◎',
  skipped: '—',
};

export const statusColors: Record<string, string> = {
  completed: '#27ae60',
  assigned: '#f39c12',
  in_progress: '#3498db',
  skipped: '#95a5a6',
};

// ===== 布局容器 =====

export const containerStyle: React.CSSProperties = {
  display: 'flex',
  flexDirection: 'column',
  height: '100%',
  width: '100%',
  backgroundColor: 'var(--color-bg-primary)',
};

export const sectionStyle: React.CSSProperties = {
  marginBottom: 24,
};

export const sectionTitleStyle: React.CSSProperties = {
  fontSize: '0.9rem',
  fontWeight: 600,
  color: 'var(--color-text-primary)',
  marginBottom: 12,
  paddingBottom: 6,
  borderBottom: '1px solid var(--border)',
};

export const emptyStyle: React.CSSProperties = {
  padding: 16,
  backgroundColor: 'var(--color-bg-secondary)',
  borderRadius: 8,
  textAlign: 'center',
};

export const loadingStyle: React.CSSProperties = {
  display: 'flex',
  flexDirection: 'column',
  alignItems: 'center',
  justifyContent: 'center',
  height: '100%',
  gap: 12,
};

// ===== 卡片样式 =====

export const cardStyle: React.CSSProperties = {
  flex: '1 1 280px',
  maxWidth: 'calc(50% - 6px)',
  padding: 12,
  backgroundColor: '#fff',
  borderRadius: 8,
  border: '1px solid var(--border)',
  boxShadow: '0 1px 3px rgba(0,0,0,0.05)',
};

export const recCardStyle: React.CSSProperties = {
  display: 'flex',
  justifyContent: 'space-between',
  alignItems: 'flex-start',
  gap: 12,
  padding: 12,
  backgroundColor: '#fff',
  borderRadius: 8,
  border: '1px solid var(--border)',
  boxShadow: '0 1px 3px rgba(0,0,0,0.05)',
};

// ===== 按钮样式 =====

export const startBtnStyle: React.CSSProperties = {
  padding: '5px 14px',
  backgroundColor: 'var(--color-accent-primary)',
  color: '#fff',
  border: 'none',
  borderRadius: 6,
  fontSize: '0.8rem',
  fontWeight: 500,
  cursor: 'pointer',
  whiteSpace: 'nowrap',
  transition: 'opacity 0.15s',
};

export const backBtnStyle: React.CSSProperties = {
  padding: '6px 16px',
  backgroundColor: 'transparent',
  color: 'var(--color-text-secondary)',
  border: '1px solid var(--border)',
  borderRadius: 6,
  fontSize: '0.85rem',
  cursor: 'pointer',
};

export const primaryBtnStyle: React.CSSProperties = {
  padding: '8px 20px',
  backgroundColor: 'var(--color-accent-primary)',
  color: '#fff',
  border: 'none',
  borderRadius: 6,
  fontSize: '0.85rem',
  fontWeight: 500,
  cursor: 'pointer',
  transition: 'opacity 0.15s',
};

export const secondaryBtnStyle: React.CSSProperties = {
  padding: '8px 20px',
  backgroundColor: 'transparent',
  color: 'var(--color-text-secondary)',
  border: '1px solid var(--border)',
  borderRadius: 6,
  fontSize: '0.85rem',
  cursor: 'pointer',
};
