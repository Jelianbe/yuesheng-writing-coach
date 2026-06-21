import React from 'react';
import { ALL_TOOLS, type ToolId } from '../../../stores/right-tools.store';
import styles from './index.module.css';

interface ToolGridProps {
  onOpenTool: (id: ToolId) => void;
}

export const ToolGrid: React.FC<ToolGridProps> = ({ onOpenTool }) => (
  <div className={styles.grid}>
    {ALL_TOOLS.map(t => (
      <button key={t.id} className={styles.item} onClick={() => onOpenTool(t.id)}>
        <span className={styles.icon}>{t.icon}</span>
        <span className={styles.name}>{t.name}</span>
        <span className={styles.desc}>{t.id === '__settings__' ? 'ApiConfig' : t.name}</span>
      </button>
    ))}
  </div>
);
