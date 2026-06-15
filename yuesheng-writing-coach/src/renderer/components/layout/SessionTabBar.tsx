import React, { useRef, useCallback } from 'react';
import type { LucideIcon } from 'lucide-react';
import { FileText } from 'lucide-react';
import type { PanelSession, PanelSessionType } from '../../stores/panel-session.store';

// ============================================================
// SessionTabBar — L1 会话标签栏（从 RightDrawer.renderSessionHeader 提取）
// ============================================================

/** 字体层级常量（与 RightDrawer 统一） */
const FONT = {
  caption: '11px',
  micro: '10px',
} as const;

const EASE_OUT_QUART = 'cubic-bezier(0.25, 1, 0.5, 1)';

export interface SessionTabBarProps {
  /** 当前所有会话列表 */
  sessions: PanelSession[];
  /** 当前激活的会话 ID */
  activeSessionId: string | null;
  /** 切换会话回调 */
  onSwitch: (id: string) => void;
  /** 移除会话回调 */
  onRemove: (id: string) => void;
  /** SessionType → Lucide 图标映射 */
  sessionIcons: Record<PanelSessionType, LucideIcon>;
}

/**
 * L1 层级：工具会话标签栏。
 *
 * 特性：
 * - 激活标签更大更醒目，非激活标签紧凑
 * - 支持鼠标滚轮左右滚动（溢出时）
 * - 水平滚动容器，隐藏原生滚动条
 */
export const SessionTabBar: React.FC<SessionTabBarProps> = React.memo(({
  sessions,
  activeSessionId,
  onSwitch,
  onRemove,
  sessionIcons,
}) => {
  const scrollRef = useRef<HTMLDivElement>(null);

  // 滚轮水平滚动：在溢出容器内用滚轮左右切换标签
  const handleWheel = useCallback((e: React.WheelEvent) => {
    if (!scrollRef.current || Math.abs(e.deltaY) < Math.abs(e.deltaX)) return;
    e.preventDefault();
    scrollRef.current.scrollLeft += e.deltaY;
  }, []);

  return (
    <div
      ref={scrollRef}
      onWheel={handleWheel}
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: 2,
        padding: '6px 8px 4px',
        borderBottom: '1px solid var(--border-light)',
        background: 'var(--bg-sidebar)',
        flexShrink: 0,
        minHeight: 38,
        overflowX: 'auto',
        overflowY: 'hidden',
        scrollbarWidth: 'none',
      }}
    >
      {sessions.map(sess => {
        const isActive = sess.id === activeSessionId;
        const SessionIcon = sessionIcons[sess.type] ?? FileText;

        return (
          <div
            key={sess.id}
            onClick={() => onSwitch(sess.id)}
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              gap: isActive ? 6 : 4,
              // 动态大小：激活标签更大，非激活更紧凑
              padding: isActive ? '5px 13px' : '4px 9px',
              borderRadius: 'var(--radius-sm)',
              fontSize: isActive ? FONT.caption : FONT.micro,
              cursor: 'pointer',
              color: isActive ? 'var(--text-primary)' : 'var(--text-secondary)',
              border: isActive ? '1px solid var(--border)' : '1px solid transparent',
              background: isActive ? 'var(--bg-card)' : 'transparent',
              fontWeight: isActive ? 600 : 400,
              boxShadow: isActive ? '0 1px 3px rgba(0,0,0,0.04)' : 'none',
              transition: `all 130ms ${EASE_OUT_QUART}`,
              whiteSpace: 'nowrap',
              flexShrink: 0,
            }}
          >
            {/* 类型图标 */}
            <span style={{
              opacity: isActive ? 1 : 0.45,
              flexShrink: 0,
              display: 'flex',
              alignItems: 'center',
            }}>
              <SessionIcon size={isActive ? 12 : 11} strokeWidth={1.8} />
            </span>

            {/* 标题文本 */}
            <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', maxWidth: isActive ? 120 : 80 }}>
              {sess.title}
            </span>

            {/* 关闭按钮 */}
            <span
              onClick={(e) => { e.stopPropagation(); onRemove(sess.id); }}
              style={{
                width: 14,
                height: 14,
                borderRadius: '50%',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                opacity: 0.5,
                transition: 'opacity 80ms',
                flexShrink: 0,
                fontSize: FONT.micro,
                color: 'inherit',
              }}
              onMouseEnter={e => {
                (e.target as HTMLElement).style.opacity = '1';
                (e.target as HTMLElement).style.color = '#C05040';
              }}
              onMouseLeave={e => {
                (e.target as HTMLElement).style.opacity = '0.5';
                (e.target as HTMLElement).style.color = '';
              }}
            >
              {'\u2715'}
            </span>
          </div>
        );
      })}

      {/* 弹性填充 */}
      <div style={{ flex: 1, minWidth: 8 }} />
    </div>
  );
});

SessionTabBar.displayName = 'SessionTabBar';
