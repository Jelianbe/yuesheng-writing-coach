/**
 * ToolGrid — 工具网格主页
 *
 * 3列网格展示所有工具，当无工具激活时显示。
 * 每个格子：图标 + 名称 + 简短描述。
 * 点击打开工具（调用 useDrawerStore.openPanel）。
 *
 * 用法:
 * ```tsx
 * <ToolGrid />
 * ```
 */
import { useCallback } from 'react';
import { useDrawerStore, type DrawerPanelId } from '@/stores/drawer.store';
import styles from './index.module.css';

/** 工具卡片配置 */
interface ToolGridItem {
  id: DrawerPanelId;
  icon: string;
  label: string;
  description: string;
}

const TOOLS: ToolGridItem[] = [
  {
    id: 'tools',
    icon: '\uD83D\uDCD6',
    label: '技法目录',
    description: '写作技法分类目录',
  },
  {
    id: 'progress',
    icon: '\uD83D\uDCCA',
    label: '教学进度',
    description: '学习进度与掌握情况',
  },
  {
    id: 'learning-log',
    icon: '\uD83D\uDCC8',
    label: '学习日志',
    description: '能力趋势与训练统计',
  },
  {
    id: 'works',
    icon: '\uD83D\uDCDD',
    label: '作品',
    description: '管理你的作品',
  },
  {
    id: 'teaching-note',
    icon: '\uD83D\uDCDD',
    label: '教学笔记',
    description: '训练记录与教练建议',
  },
  {
    id: '__settings__',
    icon: '\u2699\uFE0F',
    label: '设置',
    description: '应用与模型配置',
  },
];

export function ToolGrid(): JSX.Element {
  const openPanel = useDrawerStore((s) => s.openPanel);

  const handleClick = useCallback(
    (panelId: DrawerPanelId) => {
      openPanel(panelId);
    },
    [openPanel],
  );

  return (
    <div className={styles.grid} role="list" aria-label="工具列表">
      {TOOLS.map((tool) => (
        <button
          key={tool.id}
          className={styles.card}
          onClick={() => handleClick(tool.id)}
          role="listitem"
          type="button"
        >
          <span className={styles.cardIcon} aria-hidden="true">{tool.icon}</span>
          <span className={styles.cardLabel}>{tool.label}</span>
          <span className={styles.cardDesc}>{tool.description}</span>
        </button>
      ))}
    </div>
  );
}
