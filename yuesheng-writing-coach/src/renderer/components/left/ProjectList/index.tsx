import React from 'react';
import styles from './index.module.css';

interface ProjectItem {
  id: string;
  name: string;
  description: string | null;
}

interface ProjectListProps {
  projects: ProjectItem[];
  selectedProjectId: string | null;
  onSelect: (id: string) => void;
}

export const ProjectList: React.FC<ProjectListProps> = ({ projects, selectedProjectId, onSelect }) => {
  if (projects.length === 0) {
    return <div className={styles.empty}>暂无项目</div>;
  }

  return (
    <div>
      {projects.map(p => (
        <div
          key={p.id}
          className={`${styles.item} ${selectedProjectId === p.id ? styles.itemActive : ''}`}
          onClick={() => onSelect(p.id)}
        >
          <span className={styles.itemIcon}>{p.description ? '☰' : '✎'}</span>
          <div className={styles.itemBody}>
            <div className={styles.itemName}>{p.name}</div>
            {p.description && (
              <div className={styles.itemDesc}>{p.description}</div>
            )}
          </div>
        </div>
      ))}
    </div>
  );
};
