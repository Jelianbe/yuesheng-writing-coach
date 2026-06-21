import React from 'react';
import { X } from 'lucide-react';
import type { ToolItem } from './drawer-constants';

// ============================================================
// ToolGrid — 工具网格空状态（从 RightDrawer.renderContent 提取）
// ============================================================

/** 字体层级常量（与 drawer-constants 统一） */
const FONT = {
  body: '13px',
  caption: '11px',
} as const;

const EASE_OUT_QUART = 'cubic-bezier(0.25, 1, 0.5, 1)';

export interface ToolGridProps {
  /** 工具列表 */
  tools: ToolItem[];
  /** 当前激活的面板 ID */
  activePanel: string | null;
  /** 点击工具项回调 */
  onToolClick: (tool: ToolItem) => void;
}

/**
 * 工具网格 —— 无自定义内容时的空状态视图。
 *
 * 以 2 列网格展示所有工具卡片，每个卡片含图标 + 标签。
 * 底部附带"选择一个工具开始"提示区域。
 */
export const ToolGrid: React.FC<ToolGridProps> = React.memo(({
  tools,
  activePanel,
  onToolClick,
}) => {
  /** 单个工具卡片的基础样式 */
  const cardBaseStyle: React.CSSProperties = {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    padding: '14px 10px',
    borderRadius: 'var(--radius-md)',
    borderWidth: 1,
    borderStyle: 'solid',
    borderColor: 'transparent',
    cursor: 'pointer',
    transition: `all 150ms ${EASE_OUT_QUART}`,
    outline: 'none',
    position: 'relative',
    overflow: 'hidden',
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 20, padding: '16px 16px' }}>
      {/* 工具网格 */}
      <nav aria-label="工具列表" style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8 }}>
        {tools.map(tool => {
          const isActive = activePanel === tool.id;
          const IconComponent = tool.icon;

          /* ── 禁用态 ── */
          if (tool.disabled) {
            return (
              <button
                key={tool.id}
                disabled
                style={{
                  ...cardBaseStyle,
                  borderColor: 'var(--border-light)',
                  color: 'var(--text-tertiary)',
                  opacity: 0.5,
                  pointerEvents: 'none',
                }}
                title={tool.description || tool.label}
              >
                <IconComponent size={21} strokeWidth={1.6} />
                <span style={{
                  fontSize: FONT.caption,
                  fontWeight: 500,
                  textAlign: 'center',
                  lineHeight: 1.3,
                }}>
                  {tool.label}
                </span>
              </button>
            );
          }

          /* ── 激活态 ── */
          if (isActive) {
            return (
              <button
                key={tool.id}
                onClick={() => onToolClick(tool)}
                style={{
                  ...cardBaseStyle,
                  borderColor: 'var(--accent)',
                  background: 'var(--accent-subtle)',
                  color: 'var(--accent)',
                }}
                title={tool.description || tool.label}
              >
                <IconComponent size={21} strokeWidth={1.9} />
                <span style={{
                  fontSize: FONT.caption,
                  fontWeight: 600,
                  textAlign: 'center',
                  lineHeight: 1.3,
                }}>
                  {tool.label}
                </span>
              </button>
            );
          }

          /* ── 默认态 ── */
          return (
            <button
              key={tool.id}
              onClick={() => onToolClick(tool)}
              title={tool.description || tool.label}
              onMouseEnter={e => Object.assign(e.currentTarget.style, {
                borderColor: 'var(--border)',
                background: 'var(--bg-hover)',
                color: 'var(--text-primary)',
              })}
              onMouseLeave={e => Object.assign(e.currentTarget.style, {
                borderColor: 'var(--border-light)',
                background: 'transparent',
                color: 'var(--text-secondary)',
              })}
              onMouseDown={e => { e.currentTarget.style.transform = 'scale(0.98)'; }}
              onMouseUp={e => { e.currentTarget.style.transform = 'scale(1)'; }}
              style={{ ...cardBaseStyle, borderColor: 'var(--border-light)', color: 'var(--text-secondary)' }}
            >
              <IconComponent size={21} strokeWidth={1.6} />
              <span style={{
                fontSize: FONT.caption,
                fontWeight: 500,
                textAlign: 'center',
                lineHeight: 1.3,
              }}>
                {tool.label}
              </span>
            </button>
          );
        })}
      </nav>

      {/* 空状态提示区 */}
      <div style={{ borderTop: '1px solid var(--border-light)', paddingTop: 4 }}>
        <section
          aria-label="空状态提示"
          style={{
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'flex-start',
            padding: '4px 0',
            gap: 12,
          }}
        >
          <div style={{
            width: 72,
            height: 52,
            borderRadius: 'var(--radius-md)',
            background: 'var(--bg-hover)',
            border: '1.5px dashed var(--border)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            color: 'var(--text-tertiary)',
            opacity: 0.7,
          }}>
            <X size={22} strokeWidth={1.4} />
          </div>
          <p style={{
            fontSize: FONT.body,
            fontWeight: 500,
            color: 'var(--text-secondary)',
            margin: 0,
            lineHeight: 1.5,
          }}>
            选择一个工具开始
          </p>
          <p style={{
            fontSize: FONT.caption,
            color: 'var(--text-tertiary)',
            margin: 0,
            lineHeight: 1.5,
            opacity: 0.75,
          }}>
            打开或创建作品以继续
          </p>
        </section>
      </div>
    </div>
  );
});

ToolGrid.displayName = 'ToolGrid';
