/**
 * TabBar — 移动端底部导航（3 tab）
 *
 * Tab: 书架 📚 | 对话 💬 | 应用 🧩
 * 使用 lucide-react 图标
 */

import React from 'react';
import { Book, MessageCircle, Puzzle } from 'lucide-react';
import { usePageStackStore } from '../../stores/page-stack.store';
import styles from './TabBar.module.css';

const TABS = [
  { key: 'bookshelf' as const, label: '书架', Icon: Book },
  { key: 'conversations' as const, label: '对话', Icon: MessageCircle },
  { key: 'apps' as const, label: '应用', Icon: Puzzle },
];

export const TabBar: React.FC = () => {
  const activeTab = usePageStackStore(s => s.activeTab);
  const navigateToTab = usePageStackStore(s => s.navigateToTab);

  return (
    <nav className={styles.tabbar}>
      {TABS.map(({ key, label, Icon }) => {
        const isActive = key === activeTab;
        return (
          <button
            key={key}
            className={`${styles.tab} ${isActive ? styles.tabActive : ''}`}
            onClick={() => navigateToTab(key)}
            aria-label={label}
            aria-current={isActive ? 'page' : undefined}
            aria-pressed={isActive}
          >
            <Icon size={22} strokeWidth={isActive ? 2 : 1.5} />
            <span className={styles.tabLabel}>{label}</span>
            {isActive && <span className={styles.tabIndicator} />}
          </button>
        );
      })}
    </nav>
  );
};
