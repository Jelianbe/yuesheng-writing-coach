import React from 'react';
import { LucideIcon } from 'lucide-react';
import styles from './EmptyState.module.css';

interface EmptyStateProps {
  icon: LucideIcon;
  title: string;
  description: string;
  action?: React.ReactNode;
  className?: string;
}

export const EmptyState: React.FC<EmptyStateProps> = ({
  icon: Icon,
  title,
  description,
  action,
  className = '',
}) => {
  return (
    <div className={`${styles.emptyState} ${className}`}>
      <div className={styles.iconWrap}>
        <Icon className={styles.icon} strokeWidth={1.5} />
      </div>
      <h3 className={styles.title}>{title}</h3>
      <p className={styles.description}>{description}</p>
      {action && <div className={styles.actions}>{action}</div>}
    </div>
  );
};

// Usage example:
// <EmptyState
//   icon={MessageSquare}
//   title="No messages yet"
//   description="Start a conversation by sending a message"
// />
