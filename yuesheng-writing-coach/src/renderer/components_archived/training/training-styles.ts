/**
 * TrainingWorkshop 共享常量（非样式部分）
 *
 * 纯静态样式已迁移至 TrainingShared.module.css。
 * 本文件保留：数据映射、缓动常量、业务配置等无法用 CSS 表达的内容。
 */

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

// ===== 缓动常量 =====

/** ease-out-quart 缓动 */
export const EASE_OUT = 'cubic-bezier(0.25, 1, 0.5, 1)';
/** 默认过渡时长 */
export const TRANSITION_NORMAL = '250ms';
/** 慢过渡 */
export const TRANSITION_SLOW = '350ms';
