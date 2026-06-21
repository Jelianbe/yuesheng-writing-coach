/**
 * LeftPanel — 左侧栏容器
 *
 * 包含 LeftHeader、标签页切换按钮（[对话]/[项目]）、内容列表。
 * 根据折叠状态和宽度动态渲染。
 *
 * 用法:
 * ```tsx
 * <LeftPanel />
 * ```
 */
import { useCallback, useState } from 'react';
import { useUiLayoutStore } from '@/stores/ui-layout.store';
import { useUiStore } from '@/stores/ui.store';
import type { LeftTab } from '@/stores/ui.store';
import { LeftHeader } from '@/components/left/LeftHeader';
import { SessionList } from '@/components/left/SessionList';
import { ProjectList } from '@/components/left/ProjectList';
import styles from './index.module.css';

const TABS: { key: LeftTab; label: string }[] = [
  { key: 'chat', label: '对话' },
  { key: 'proj', label: '项目' },
];

export function LeftPanel(): JSX.Element {
  const sidebarCollapsed = useUiLayoutStore((s) => s.sidebarCollapsed);
  const sidebarWidth = useUiLayoutStore((s) => s.sidebarWidth);

  const leftTab = useUiStore((s) => s.leftTab);
  const setLeftTab = useUiStore((s) => s.setLeftTab);

  const [searchQuery, setSearchQuery] = useState('');

  const handleTabClick = useCallback(
    (tab: LeftTab) => {
      setLeftTab(tab);
    },
    [setLeftTab],
  );

  const handleSearchChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      setSearchQuery(e.target.value);
    },
    [],
  );

  if (sidebarCollapsed) {
    return <div className={styles.collapsed} />;
  }

  return (
    <div
      className={styles.panel}
      style={{ width: sidebarWidth }}
    >
      <LeftHeader />

      <div className={styles.searchWrap}>
        <span className={styles.searchIcon} aria-hidden="true">{'\uD83D\uDD0D'}</span>
        <input
          className={styles.searchInput}
          type="search"
          placeholder="搜索会话或项目..."
          aria-label="搜索会话或项目"
          value={searchQuery}
          onChange={handleSearchChange}
        />
      </div>

      <nav className={styles.tabs} role="tablist" aria-label="左侧面板标签">
        {TABS.map(({ key, label }) => (
          <button
            key={key}
            className={[
              styles.tab,
              leftTab === key ? styles.tabActive : '',
            ]
              .filter(Boolean)
              .join(' ')}
            onClick={() => handleTabClick(key)}
            role="tab"
            aria-selected={leftTab === key}
            type="button"
          >
            {label}
          </button>
        ))}
      </nav>

      <div className={styles.content} role="tabpanel">
        {leftTab === 'chat' ? (
          <SessionList searchQuery={searchQuery} />
        ) : (
          <ProjectList searchQuery={searchQuery} />
        )}
      </div>
    </div>
  );
}
