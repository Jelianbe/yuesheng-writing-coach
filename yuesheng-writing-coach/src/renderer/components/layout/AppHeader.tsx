import React, { useCallback } from 'react';
import { MessageSquare, PenTool } from 'lucide-react';
import type { ParadigmMode } from '../../stores/paradigm.store';

// ===== 类型 =====

export interface AppHeaderProps {
  /** 会话标题文本 */
  title?: string;
  /** 当前范式模式 */
  paradigm?: ParadigmMode;
  /** 范式切换回调 */
  onParadigmChange?: (mode: ParadigmMode) => void;
}

// ===== 常量 =====

/** Header 高度 (px) */
const HEADER_HEIGHT = 40;

// ===== 样式常量 =====

const headerStyle: React.CSSProperties = {
  height: HEADER_HEIGHT,
  minHeight: HEADER_HEIGHT,
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'space-between',
  padding: '0 16px',
  borderBottom: '1px solid var(--border)',
  background: 'var(--bg-main)',
  boxShadow: 'var(--shadow-sm)',
  flexShrink: 0,
  zIndex: 100,
  position: 'relative',
};

const logoStyle: React.CSSProperties = {
  width: 28,
  height: 28,
  background: 'linear-gradient(135deg, var(--accent), #D4A56A)',
  borderRadius: 'var(--radius-sm)',
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  fontFamily: 'var(--font-display)',
  fontWeight: 700,
  fontSize: 13,
  color: '#FFF',
  flexShrink: 0,
};

const titleStyle: React.CSSProperties = {
  fontFamily: 'var(--font-display)',
  fontSize: '0.875rem',
  fontWeight: 600,
  color: 'var(--text-primary)',
};

/** 图标按钮基础样式（28x28，用于范式切换） */
function iconBtnStyle(): React.CSSProperties {
  return {
    width: 28,
    height: 28,
    borderRadius: 'var(--radius-sm)',
    border: '1px solid var(--border)',
    background: 'transparent',
    color: 'var(--text-tertiary)',
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    transition: 'all 150ms ease-out-quart',
  };
}

// ===== 主组件 =====

/**
 * 应用顶部导航栏（极简版 — 三栏分离设计）
 *
 * 三栏功能分配（参考 Trae IDE）：
 * - 左侧栏 (AppSidebar)：导航 + 作品树 + 任务 + 新建入口
 * - 中间区：纯对话
 * - 右侧栏 (RightDrawer)：工具面板 + 设置（底部图标）
 * - Header：仅 logo + 标题 + 范式切换
 *
 * 高度 40px，职责最小化。
 */
export const AppHeader: React.FC<AppHeaderProps> = React.memo(({
  title = '',
  paradigm = 'chat',
  onParadigmChange,
}) => {
  /** 范式切换 */
  const handleParadigmToggle = useCallback(() => {
    onParadigmChange?.(paradigm === 'chat' ? 'editor' : 'chat');
  }, [paradigm, onParadigmChange]);

  const ParadigmIcon = paradigm === 'chat' ? MessageSquare : PenTool;

  return (
    <header style={headerStyle} role="banner" aria-label="应用顶部导航">
      {/* 左侧：logo + 标题 */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
        <div style={logoStyle}>月</div>
        <span style={titleStyle}>{title || '月笙写作教练'}</span>
      </div>

      {/* 右侧：仅范式切换图标 */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
        {onParadigmChange && (
          <button
            onClick={handleParadigmToggle}
            style={iconBtnStyle()}
            title={paradigm === 'chat' ? '切换到编辑模式' : '切换到对话模式'}
            aria-label="切换范式"
            onMouseEnter={(e) => {
              const el = e.currentTarget as HTMLElement;
              el.style.borderColor = 'var(--accent)';
              el.style.color = 'var(--text-primary)';
            }}
            onMouseLeave={(e) => {
              const el = e.currentTarget as HTMLElement;
              el.style.borderColor = 'var(--border)';
              el.style.color = 'var(--text-tertiary)';
            }}
          >
            <ParadigmIcon size={15} strokeWidth={1.8} />
          </button>
        )}
      </div>
    </header>
  );
});

AppHeader.displayName = 'AppHeader';
