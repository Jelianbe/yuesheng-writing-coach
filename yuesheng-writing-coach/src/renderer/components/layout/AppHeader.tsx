import React from 'react';

export interface AppHeaderProps {
  /** 会话标题文本 */
  title?: string;
  /** 阶段徽章文本 */
  badge?: string;
  /** 当前模型显示文字 */
  currentModel?: string;
  /** 设置按钮点击回调 */
  onOpenSettings?: () => void;
  /** 当前教学态度 */
  attitude?: 'gentle' | 'direct' | 'sharp';
  /** 态度切换回调 */
  onAttitudeChange?: (attitude: 'gentle' | 'direct' | 'sharp') => void;
}

const attitudeLabels: Record<string, string> = {
  gentle: '温和',
  direct: '直接',
  sharp: '尖锐',
};

export const AppHeader: React.FC<AppHeaderProps> = React.memo(({
  title = '',
  badge = '',
  currentModel = '',
  onOpenSettings,
  attitude = 'direct',
  onAttitudeChange,
}) => {
  return (
    <header
      style={{
        height: 'var(--header-height)',
        minHeight: 'var(--header-height)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        padding: '0 24px',
        borderBottom: '1px solid var(--border)',
        background: 'var(--bg-main)',
        boxShadow: 'var(--shadow-sm)',
        flexShrink: 0,
        zIndex: 100,
        position: 'relative',
      }}
      role="banner"
      aria-label="Application header"
    >
      {/* Left: logo + title + badge */}
      <div style={{ display: 'flex', alignItems: 'center', gap: '16px' }}>
        <div
          style={{
            width: 36,
            height: 36,
            background: 'linear-gradient(135deg, var(--accent), #D4A56A)',
            borderRadius: 'var(--radius-md)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            fontFamily: 'var(--font-display)',
            fontWeight: 700,
            fontSize: 16,
            color: 'var(--text-on-accent)',
            boxShadow: 'var(--shadow-md)',
            flexShrink: 0,
          }}
        >
          月
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
          <span
            style={{
              fontFamily: 'var(--font-display)',
              fontSize: '1rem',
              fontWeight: 600,
              color: 'var(--text-primary)',
            }}
          >
            {title}
          </span>
          {badge && (
            <span
              style={{
                fontSize: '0.7rem',
                padding: '2px 8px',
                borderRadius: 'var(--radius-full)',
                background: 'var(--accent-light)',
                color: 'var(--accent)',
                fontWeight: 500,
                whiteSpace: 'nowrap',
              }}
            >
              {badge}
            </span>
          )}
        </div>
      </div>

      {/* Right: model badge + attitude selector + settings */}
      <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
        {currentModel && (
          <span
            style={{
              fontSize: '0.7rem',
              padding: '2px 8px',
              borderRadius: 'var(--radius-full)',
              background: 'var(--success-light)',
              color: 'var(--success)',
              fontWeight: 500,
            }}
          >
            {currentModel}
          </span>
        )}

        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: '6px',
            fontSize: '0.75rem',
            color: 'var(--text-secondary)',
          }}
        >
          {(['gentle', 'direct', 'sharp'] as const).map((key) => (
            <button
              key={key}
              onClick={() => onAttitudeChange?.(key)}
              style={{
                padding: '4px 10px',
                border: `1px solid ${attitude === key ? 'var(--accent)' : 'var(--border)'}`,
                borderRadius: 'var(--radius-full)',
                background: attitude === key ? 'var(--accent)' : 'transparent',
                fontFamily: 'var(--font-body)',
                fontSize: '0.75rem',
                color: attitude === key ? 'var(--text-on-accent)' : 'var(--text-secondary)',
                cursor: 'pointer',
                transition: 'all 0.15s ease',
              }}
              aria-pressed={attitude === key}
            >
              {attitudeLabels[key]}
            </button>
          ))}
        </div>

        <button
          onClick={onOpenSettings}
          style={{
            width: 32,
            height: 32,
            borderRadius: 'var(--radius-md)',
            border: '1px solid var(--border)',
            background: 'var(--bg-card)',
            cursor: 'pointer',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            color: 'var(--text-tertiary)',
            transition: 'all 0.15s',
            fontSize: '0.85rem',
          }}
          title="设置"
          aria-label="Settings"
        >
          ⚙
        </button>
      </div>
    </header>
  );
});

AppHeader.displayName = 'AppHeader';
