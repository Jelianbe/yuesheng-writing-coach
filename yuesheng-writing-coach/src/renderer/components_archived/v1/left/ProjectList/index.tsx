/**
 * ProjectList — 项目列表示例
 *
 * 展示用户的所有作品项目，支持选中切换。
 *
 * 用法:
 * ```tsx
 * <ProjectList />
 * ```
 */
import { useCallback, useEffect, useMemo } from 'react';
import { useManuscriptStore } from '@/stores/manuscript.store';
import { useRightPanelStore } from '@/stores/right-panel.store';
import type { Manuscript } from '../../../../shared/types';
import styles from './index.module.css';

/** 格式化时间戳（Unix ms）为本地日期时间字符串 */
function formatTime(ts: number): string {
  try {
    const d = new Date(ts);
    const now = new Date();
    const diffMs = now.getTime() - d.getTime();
    const diffDays = Math.floor(diffMs / 86400000);

    if (diffDays === 0) {
      return d.toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' });
    }
    if (diffDays === 1) {
      return '昨天';
    }
    if (diffDays < 7) {
      return `${diffDays}天前`;
    }
    return d.toLocaleDateString('zh-CN', { month: 'short', day: 'numeric' });
  } catch {
    return '';
  }
}

interface ProjectItemProps {
  manuscript: Manuscript;
  isActive: boolean;
  onSelect: (id: string) => void;
}

function ProjectItem({ manuscript, isActive, onSelect }: ProjectItemProps): JSX.Element {
  const handleClick = useCallback(() => {
    onSelect(manuscript.id);
  }, [manuscript.id, onSelect]);

  const classNames = [
    styles.item,
    isActive ? styles.itemActive : '',
  ]
    .filter(Boolean)
    .join(' ');

  return (
    <button
      className={classNames}
      onClick={handleClick}
      type="button"
      aria-current={isActive ? 'true' : undefined}
      aria-label={`项目：${manuscript.title}`}
    >
      <div className={styles.itemHeader}>
        <span className={styles.title}>{manuscript.title}</span>
        <span className={styles.genre}>{manuscript.genre}</span>
      </div>
      {manuscript.description && (
        <p className={styles.desc}>{manuscript.description}</p>
      )}
      <div className={styles.meta}>
        <span className={styles.time}>{formatTime(manuscript.updated_at)}</span>
        <span className={styles.status}>
          {manuscript.status === 'active' ? '进行中' : '已归档'}
        </span>
      </div>
    </button>
  );
}

interface ProjectListProps {
  searchQuery?: string;
}

export function ProjectList({ searchQuery = '' }: ProjectListProps): JSX.Element {
  const allManuscripts = useManuscriptStore((s) => s.manuscripts);
  const currentManuscript = useManuscriptStore((s) => s.currentManuscript);
  const select = useManuscriptStore((s) => s.select);
  const create = useManuscriptStore((s) => s.create);
  const fetchList = useManuscriptStore((s) => s.fetchList);
  const openRightPanel = useRightPanelStore((s) => s.openTool);

  const handleCreate = useCallback(async () => {
    const title = prompt('请输入项目名称：');
    if (!title?.trim()) return;
    const genre = prompt('请输入类型（可选，如：玄幻/现实/奇幻）：') || undefined;
    const created = await create(title.trim(), undefined, genre);
    if (created) {
      select(created.id);
    }
  }, [create, select]);

  const handleSelect = useCallback(
    (id: string) => {
      select(id);
      openRightPanel('works');
    },
    [select, openRightPanel],
  );

  // 首次加载
  useEffect(() => {
    if (allManuscripts.length === 0) {
      fetchList();
    }
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  const manuscripts = useMemo(() => {
    if (!searchQuery.trim()) return allManuscripts;
    const q = searchQuery.toLowerCase();
    return allManuscripts.filter(
      (m) =>
        m.title.toLowerCase().includes(q) ||
        (m.description && m.description.toLowerCase().includes(q)),
    );
  }, [allManuscripts, searchQuery]);

  if (allManuscripts.length === 0) {
    return (
      <div className={styles.empty}>
        <div className={styles.emptyContent}>
          <span className={styles.emptyText}>暂无项目</span>
          <button className={styles.createBtn} onClick={handleCreate} type="button">
            + 新建项目
          </button>
        </div>
      </div>
    );
  }

  if (manuscripts.length === 0) {
    return (
      <div className={styles.empty}>
        <div className={styles.emptyContent}>
          <span className={styles.emptyText}>未找到匹配的项目</span>
        </div>
      </div>
    );
  }

  return (
    <div className={styles.list} role="listbox" aria-label="项目列表">
      {manuscripts.map((m) => (
        <ProjectItem
          key={m.id}
          manuscript={m}
          isActive={m.id === currentManuscript?.id}
          onSelect={handleSelect}
        />
      ))}
    </div>
  );
}
