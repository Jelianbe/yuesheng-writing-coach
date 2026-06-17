/**
 * ProjectSelector — 中间栏 header 项目选择器 (RWR-P1-3)
 *
 * 规格 DoD:
 * - 下拉显示当前项目名
 * - 点击切换项目
 *
 * 设计:
 * - 默认选中"我的作品集"(RWR-P0-5 default-project)
 * - 调 project:list 加载项目列表
 * - 调 project:update 切换 (作为全局当前项目)
 *
 * 注意: 本次实现聚焦 UI + 列表加载, "当前项目"全局状态
 * 由后续 RWR-P1-5 引入 currentProjectId 字段时承接
 */

import React, { useState, useCallback, useEffect } from 'react';
import { ChevronDown, FolderOpen } from 'lucide-react';
import { IPC_CHANNELS } from '../../shared/constants';
import { getInvoke } from '../../utils/ipc';
import type { ApiResponse } from '../../../shared/api-contracts/base';
import type {
  ProjectInfo,
  ProjectListResponse,
} from '../../../shared/api-contracts/project.contract';
import styles from '../../styles/ProjectSelector.module.css';

export interface ProjectSelectorProps {
  /** 当前选中的项目 ID */
  currentProjectId?: string;
  /** 选择项目回调 */
  onProjectChange?: (projectId: string) => void;
}

export const ProjectSelector: React.FC<ProjectSelectorProps> = ({
  currentProjectId,
  onProjectChange,
}) => {
  const [projects, setProjects] = useState<ProjectInfo[]>([]);
  const [open, setOpen] = useState(false);
  const [loading, setLoading] = useState(false);

  // 加载项目列表
  const loadProjects = useCallback(async () => {
    setLoading(true);
    try {
      const invoke = getInvoke();
      const res = (await invoke(IPC_CHANNELS.PROJECT_LIST, {})) as unknown as ApiResponse<ProjectListResponse>;
      if (res.success && res.data) {
        setProjects(res.data);
      }
    } catch (err) {
      // 静默失败 — 不弹 toast(R-007 无 toast 约束)
      console.error('[ProjectSelector] 加载项目列表失败:', err);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadProjects();
  }, [loadProjects]);

  // 切换下拉
  const toggleOpen = useCallback(() => {
    setOpen((prev) => !prev);
  }, []);

  // 选择项目
  const handleSelect = useCallback(
    (projectId: string) => {
      setOpen(false);
      onProjectChange?.(projectId);
    },
    [onProjectChange]
  );

  // 当前显示的项目名
  const currentProject = projects.find((p) => p.id === currentProjectId);
  const displayName = currentProject?.name ?? (loading ? '加载中...' : '我的作品集');

  return (
    <div className={styles.selector}>
      <button
        type="button"
        onClick={toggleOpen}
        className={styles.trigger}
        aria-label="选择项目"
        aria-haspopup="listbox"
        aria-expanded={open}
      >
        <FolderOpen size={14} strokeWidth={1.6} />
        <span className={styles.label}>{displayName}</span>
        <ChevronDown
          size={12}
          strokeWidth={1.8}
          className={open ? `${styles.chevron} ${styles.chevronOpen}` : styles.chevron}
        />
      </button>

      {open && (
        <ul className={styles.menu} role="listbox" aria-label="项目列表">
          {projects.length === 0 ? (
            <li className={styles.empty}>{loading ? '加载中...' : '暂无项目'}</li>
          ) : (
            projects.map((p) => (
              <li key={p.id}>
                <button
                  type="button"
                  role="option"
                  aria-selected={p.id === currentProjectId}
                  onClick={() => handleSelect(p.id)}
                  className={
                    p.id === currentProjectId
                      ? `${styles.option} ${styles.optionActive}`
                      : styles.option
                  }
                >
                  <span className={styles.optionName}>{p.name}</span>
                  {p.description && (
                    <span className={styles.optionDesc}>{p.description}</span>
                  )}
                </button>
              </li>
            ))
          )}
        </ul>
      )}
    </div>
  );
};
