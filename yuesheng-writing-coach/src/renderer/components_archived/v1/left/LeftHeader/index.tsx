/**
 * LeftHeader — 左侧栏顶部
 *
 * 展示月笙品牌标识、侧栏收起按钮、项目选择器。
 *
 * 用法:
 * ```tsx
 * <LeftHeader />
 * ```
 */
import { useCallback } from 'react';
import { useUiLayoutStore } from '@/stores/ui-layout.store';
import { useUiStore } from '@/stores/ui.store';
import { useManuscriptStore } from '@/stores/manuscript.store';
import styles from './index.module.css';

export function LeftHeader(): JSX.Element {
  const sidebarCollapsed = useUiLayoutStore((s) => s.sidebarCollapsed);
  const toggleSidebar = useUiLayoutStore((s) => s.toggleSidebar);

  const selectedProjectId = useUiStore((s) => s.selectedProjectId);
  const setSelectedProjectId = useUiStore((s) => s.setSelectedProjectId);

  const manuscripts = useManuscriptStore((s) => s.manuscripts);
  const create = useManuscriptStore((s) => s.create);

  const handleProjectChange = useCallback(
    (e: React.ChangeEvent<HTMLSelectElement>) => {
      const value = e.target.value;
      setSelectedProjectId(value || null);
    },
    [setSelectedProjectId],
  );

  const handleCreateProject = useCallback(async () => {
    const title = prompt('请输入项目名称：');
    if (!title?.trim()) return;
    const genre = prompt('请输入类型（可选，如：玄幻/现实/奇幻）：') || undefined;
    await create(title.trim(), undefined, genre);
  }, [create]);

  return (
    <div className={styles.header}>
      <span className={styles.brand}>月笙</span>

      <button
        className={styles.collapseBtn}
        onClick={toggleSidebar}
        aria-label={sidebarCollapsed ? '展开侧栏' : '收起侧栏'}
        title={sidebarCollapsed ? '展开侧栏' : '收起侧栏'}
        type="button"
      >
        {sidebarCollapsed ? '\u25B6' : '\u25C0'}
      </button>

      <select
        className={styles.projectSelect}
        value={selectedProjectId ?? ''}
        onChange={handleProjectChange}
        aria-label="选择项目"
      >
        <option value="">选择项目</option>
        {manuscripts.map((m) => (
          <option key={m.id} value={m.id}>
            {m.title}
          </option>
        ))}
      </select>

      <button
        className={styles.createBtn}
        onClick={handleCreateProject}
        type="button"
        aria-label="新建项目"
        title="新建项目"
      >
        +
      </button>
    </div>
  );
}
