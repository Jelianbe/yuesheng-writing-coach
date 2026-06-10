import React, { useRef, useEffect } from 'react';
import { Check } from 'lucide-react';
import type { NewMenuOption } from './AppSidebar.types';
import { DEFAULT_NEW_OPTIONS, Z_LAYER } from './AppSidebar.types';
import styles from './AppSidebar.module.css';

interface NewMenuProps {
  options?: NewMenuOption[];
  onSelect: (optionId: string) => void;
  onClose: () => void;
  anchorRect?: DOMRect | null;
}

/**
 * 新建菜单弹出面板
 *
 * 设计规范遵循 Impeccable Product UI:
 * - Solid background + subtle border（非 glassmorphism / backdrop-blur）
 * - 弹出动画: ease-out-quart，无 bounce
 * - 轻量 shadow 且 blur ≤ 8px
 * - [Impeccable Rule: z-index] 使用语义化层级 Z_LAYER.dropdown (100)
 * - 每个选项完整交互状态: default / hover / active / focus-visible
 */
export const NewMenu: React.FC<NewMenuProps> = React.memo(({
  options = DEFAULT_NEW_OPTIONS,
  onSelect,
  onClose,
  anchorRect,
}) => {
  const menuRef = useRef<HTMLDivElement>(null);

  // 点击外部关闭
  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) {
        onClose();
      }
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, [onClose]);

  // ESC 关闭
  useEffect(() => {
    const handleEsc = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    document.addEventListener('keydown', handleEsc);
    return () => document.removeEventListener('keydown', handleEsc);
  }, [onClose]);

  const panelStyle: React.CSSProperties = {
    left: anchorRect ? `${anchorRect.left}px` : '48px',
    top: anchorRect ? `${anchorRect.bottom + 4}px` : '120px',
    zIndex: Z_LAYER.dropdown,
  };

  return (
    <div ref={menuRef} className={styles.menuPanel} style={panelStyle} role="menu" aria-label="新建选项">
      {options.map(opt => {
        if (opt.divider) {
          return <div key={opt.id} className={styles.menuDivider} />;
        }

        // 分组标题行
        if (opt.group) {
          return (
            <div key={`${opt.id}-group`} className={styles.menuGroupLabel}>
              {opt.group}
            </div>
          );
        }

        const isDefault = opt.default;
        const IconComponent = opt.icon;

        return (
          <button
            key={opt.id}
            onClick={() => { onSelect(opt.id); onClose(); }}
            role="menuitem"
            className={[
              styles.menuOption,
              isDefault ? styles.menuOptionDefault : styles.menuOptionNormal,
            ].join(' ')}
          >
            {/* 图标 */}
            {IconComponent && (
              <IconComponent
                size={16}
                strokeWidth={1.5}
                className="flex-shrink-0"
                color={isDefault ? 'var(--accent)' : 'var(--text-secondary)'}
              />
            )}
            {/* 文字区域 */}
            <div className="flex-1 min-w-0">
              <div className="leading-tight">{opt.label}</div>
              {opt.description && (
                <div className="text-[10px] mt-0.5" style={{ color: 'var(--text-tertiary)' }}>
                  {opt.description}
                </div>
              )}
            </div>
            {/* 默认标记 */}
            {isDefault && (
              <Check size={14} strokeWidth={2.5} className="flex-shrink-0" style={{ color: 'var(--accent)' }} />
            )}
          </button>
        );
      })}
    </div>
  );
});
NewMenu.displayName = 'NewMenu';
