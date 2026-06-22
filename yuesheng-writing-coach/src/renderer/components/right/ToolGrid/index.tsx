import React from 'react';
import { getAllWorkspaces, type WorkspaceId } from '../../../registry/workspace-registry';
import styles from './index.module.css';

interface ToolGridProps {
  onOpenTool: (id: WorkspaceId) => void;
}

export const ToolGrid: React.FC<ToolGridProps> = ({ onOpenTool }) => {
  const allTools = getAllWorkspaces();
  return (
    <div className={styles.grid}>
      {allTools.map(t => (
        <button key={t.id} className={styles.item} onClick={() => onOpenTool(t.id)}>
          <span className={styles.icon}>{t.icon}</span>
          <span className={styles.name}>{t.name}</span>
          <span className={styles.desc}>{t.id === '__settings__' ? 'ApiConfig' : t.name}</span>
        </button>
      ))}
    </div>
  );
};
