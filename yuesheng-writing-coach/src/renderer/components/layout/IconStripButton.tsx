import React from 'react';
import type { LucideIcon } from 'lucide-react';

// ============================================================
// IconStripButton — 图标条按钮（从 RightDrawer.renderIconButton 提取）
// ============================================================

/** 图标条按钮尺寸常量 */
const ICON_BUTTON_SIZE = 36;
const EASE_OUT_QUART = 'cubic-bezier(0.25, 1, 0.5, 1)';

/** 按钮基础样式（模块级常量，避免每次渲染重建） */
const BASE_STYLE: React.CSSProperties = {
  width: ICON_BUTTON_SIZE,
  height: ICON_BUTTON_SIZE,
  borderRadius: 'var(--radius-sm)',
  borderWidth: 1,
  borderStyle: 'solid',
  borderColor: 'transparent',
  background: 'transparent',
  color: 'var(--text-tertiary)',
  cursor: 'pointer',
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  padding: 0,
  transition: `all 150ms ${EASE_OUT_QUART}`,
  outline: 'none',
  flexShrink: 0,
  position: 'relative',
};

/** 禁用态覆盖样式 */
const DISABLED_STYLE: React.CSSProperties = {
  opacity: 0.45,
  pointerEvents: 'none',
};

/** 激活态覆盖样式 */
const ACTIVE_STYLE: React.CSSProperties = {
  borderColor: 'var(--accent)',
  background: 'var(--accent-light)',
  color: 'var(--accent)',
};

export interface IconStripButtonProps {
  /** 工具 ID，用于 key 和点击回调 */
  toolId: string;
  /** Lucide 图标组件 */
  IconComponent: LucideIcon;
  /** 是否为当前激活面板 */
  isActive: boolean;
  /** 是否禁用 */
  isDisabled?: boolean;
  /** 点击回调 */
  onClick: (toolId: string) => void;
  /** 无障碍标签 / tooltip 文本 */
  label: string;
}

/**
 * 图标条中的单个按钮。
 *
 * - 激活态：accent 边框 + accent 浅底 + accent 色图标
 * - 默认态：透明背景，hover 时显示边框和 hover 底色
 * - 禁用态：降低透明度 + 禁用指针事件
 */
export const IconStripButton: React.FC<IconStripButtonProps> = React.memo(({
  toolId,
  IconComponent,
  isActive,
  isDisabled = false,
  onClick,
  label,
}) => {
  const color = isDisabled ? 'var(--text-tertiary)' : 'var(--text-tertiary)';
  const cursor = isDisabled ? 'not-allowed' : 'pointer';
  const mergedBase = { ...BASE_STYLE, color, cursor, ...(isDisabled ? DISABLED_STYLE : {}) };

  /* ── 激活态按钮 ── */
  if (isActive && !isDisabled) {
    return (
      <button
        onClick={() => onClick(toolId)}
        style={{ ...mergedBase, ...ACTIVE_STYLE }}
        title={label}
        aria-label={label}
        aria-pressed="true"
      >
        <IconComponent size={18} strokeWidth={1.9} />
      </button>
    );
  }

  /* ── 默认/禁用态按钮 ── */
  return (
    <button
      onClick={() => onClick(toolId)}
      title={label}
      aria-label={label}
      style={mergedBase}
      onMouseEnter={e => Object.assign(e.currentTarget.style, {
        background: 'var(--bg-hover)',
        color: 'var(--text-secondary)',
        borderColor: 'var(--border)',
      })}
      onMouseLeave={e => Object.assign(e.currentTarget.style, {
        background: 'transparent',
        color: 'var(--text-tertiary)',
        borderColor: 'transparent',
      })}
      onMouseDown={e => { e.currentTarget.style.transform = 'scale(0.95)'; }}
      onMouseUp={() => {}}
      onFocus={e => { e.currentTarget.style.borderColor = 'var(--accent)'; }}
      onBlur={e => { e.currentTarget.style.borderColor = 'transparent'; }}
    >
      <IconComponent size={18} strokeWidth={1.6} />
    </button>
  );
});

IconStripButton.displayName = 'IconStripButton';
