import React from 'react';
import { BookOpen, BarChart3, FileText, Book, Notebook, Settings, Route } from 'lucide-react';
import { getAllWorkspaces, type WorkspaceId } from '../../../registry/workspace-registry';
import styles from './index.module.css';

const ICON_MAP: Record<string, React.ReactNode> = {
  catalog: <BookOpen size={18} />,
  progress: <BarChart3 size={18} />,
  'learning-log': <FileText size={18} />,
  works: <Book size={18} />,
  'teaching-note': <Notebook size={18} />,
  settings: <Settings size={18} />,
  'stage-progress': <Route size={18} />,
};

const DESC_MAP: Record<string, string> = {
  catalog: '浏览和选择写作技法',
  progress: '查看教学进度记录',
  'learning-log': '记录学习心得',
  works: '管理你的作品和章节',
  'teaching-note': '教学备注与要点',
  settings: '配置 API Key 等',
  'stage-progress': '发展路径总览',
};

interface ToolGridProps {
  onOpenTool: (id: WorkspaceId) => void;
}

export const ToolGrid: React.FC<ToolGridProps> = ({ onOpenTool }) => {
  const allTools = getAllWorkspaces();
  return (
    <div className={styles.wrapper}>
      <div className={styles.title}>工具面板</div>
      <p className={styles.hint}>选择一个工具开始使用</p>
      <div className={styles.grid}>
        {allTools.map(t => (
          <button key={t.id} className={styles.item} onClick={() => onOpenTool(t.id)}
            data-testid={`toolgrid-${t.id}`}>
            <span className={styles.icon}>{ICON_MAP[t.id] ?? t.icon}</span>
            <span className={styles.name}>{t.name}</span>
            <span className={styles.desc}>{DESC_MAP[t.id] ?? t.name}</span>
          </button>
        ))}
      </div>
    </div>
  );
};
