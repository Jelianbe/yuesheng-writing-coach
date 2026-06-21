/**
 * ChatSearchBar — 消息搜索栏
 *
 * 从 ChatView 拆分出的搜索栏组件，支持：
 * - 实时搜索输入
 * - 清除搜索内容
 * - 关闭搜索栏
 * - Escape 键关闭
 */

import React from 'react';
import { Search, X } from 'lucide-react';
import styles from './ChatView.module.css';

interface ChatSearchBarProps {
  searchQuery: string;
  onSearchChange: (query: string) => void;
  onClose: () => void;
}

export const ChatSearchBar: React.FC<ChatSearchBarProps> = ({
  searchQuery,
  onSearchChange,
  onClose,
}) => {
  return (
    <div className={styles.searchBar}>
      <Search size={14} strokeWidth={1.6} className={styles.searchIcon} />
      <input
        type="text"
        value={searchQuery}
        onChange={e => onSearchChange(e.target.value)}
        placeholder="搜索消息内容..."
        autoFocus
        className={styles.searchInput}
        onKeyDown={e => { if (e.key === 'Escape') { onClose(); } }}
      />
      {searchQuery && (
        <button
          onClick={() => onSearchChange('')}
          className={styles.searchBtn}
          aria-label="清除搜索"
        >
          <X size={14} strokeWidth={1.6} />
        </button>
      )}
      <button
        onClick={onClose}
        className={styles.searchBtn}
        aria-label="关闭搜索"
      >
        <X size={14} strokeWidth={1.6} />
      </button>
    </div>
  );
};
