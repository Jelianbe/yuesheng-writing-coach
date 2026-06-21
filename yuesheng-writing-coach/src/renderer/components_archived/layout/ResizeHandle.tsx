import React from 'react';

// ============================================================
// ResizeHandle — 面板拖拽调节手柄（从 RightDrawer JSX 提取）
// ============================================================

export interface ResizeHandleProps {
  /** mousedown 回调（由父组件处理拖拽逻辑） */
  onMouseDown: (e: React.MouseEvent) => void;
  /** 面板是否处于展开状态 */
  isExpanded: boolean;
}

/**
 * 面板拖拽调节手柄 — 边界高亮风格。
 *
 * 设计原则：
 * - 默认态：1px 极淡边框，几乎融入背景
 * - hover 态：边界高亮为 accent 色，暗示可交互
 * - 无内部填充、无图标，保持视觉干净
 */
export const ResizeHandle: React.FC<ResizeHandleProps> = React.memo(({
  onMouseDown,
  isExpanded,
}) => {
  if (!isExpanded) return null;

  return (
    <div
      onMouseDown={onMouseDown}
      className="resize-handle"
      style={{
        width: 5,
        height: '100%',
        cursor: 'col-resize',
        flexShrink: 0,
        position: 'relative',
        background: 'transparent',
        // 默认极淡边框，hover 时通过 JS 切换到高亮
        borderLeft: '1px solid var(--border-light)',
        borderRight: '1px solid transparent',
        transition: 'border-color 150ms ease, background 150ms ease',
      }}
      onMouseEnter={(e) => {
        const el = e.currentTarget as HTMLElement;
        el.style.borderLeftColor = 'var(--accent)';
        el.style.background = 'var(--accent-subtle)';
      }}
      onMouseLeave={(e) => {
        const el = e.currentTarget as HTMLElement;
        el.style.borderLeftColor = 'var(--border-light)';
        el.style.background = 'transparent';
      }}
      title="拖拽调节宽度"
    />
  );
});

ResizeHandle.displayName = 'ResizeHandle';
