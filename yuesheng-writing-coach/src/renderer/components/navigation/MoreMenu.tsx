/**
 * MoreMenu — 右上角 ⋮ 下拉菜单
 * 共用组件，用于 ChatPage / ProjectSpacePage
 *
 * 行为：
 * - 点击按钮切换显示/隐藏
 * - 点击菜单项执行操作并关闭
 * - 点击 backdrop 关闭
 * - ESC 键关闭
 */

import { useEffect, useRef, useState } from 'react';
import type { ReactNode } from 'react';
import styles from './MoreMenu.module.css';

export interface MoreMenuOption {
  label: string;
  icon?: ReactNode;
  onClick: () => void;
}

interface MoreMenuProps {
  options: MoreMenuOption[];
}

export function MoreMenu({ options }: MoreMenuProps) {
  const [open, setOpen] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;

    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setOpen(false);
    };
    document.addEventListener('keydown', onKeyDown);
    return () => document.removeEventListener('keydown', onKeyDown);
  }, [open]);

  return (
    <div ref={menuRef} className={styles.wrapper}>
      <button
        className={styles.trigger}
        onClick={(e) => { e.stopPropagation(); setOpen((v) => !v); }}
        aria-label="更多操作"
        aria-expanded={open}
        aria-haspopup="menu"
      >
        {/* inline MoreHorizontal 以避免破坏渲染结构 */}
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round" aria-hidden>
          <circle cx="12" cy="5" r="1" />
          <circle cx="12" cy="12" r="1" />
          <circle cx="12" cy="19" r="1" />
        </svg>
      </button>

      {open && (
        <>
          <div className={styles.backdrop} onClick={() => setOpen(false)} />
          <div className={styles.menu} role="menu" aria-label="操作菜单">
            {options.map((opt) => (
              <button
                key={opt.label}
                className={styles.menuItem}
                role="menuitem"
                onClick={() => { opt.onClick(); setOpen(false); }}
              >
                {opt.icon && <span className={styles.menuIcon}>{opt.icon}</span>}
                <span>{opt.label}</span>
              </button>
            ))}
          </div>
        </>
      )}
    </div>
  );
}
