import React from 'react';
import type { LucideIcon } from 'lucide-react';

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
    <div
      className={[
        'flex flex-col items-center justify-center',
        'py-12 px-6',
        'text-center',
        'animate-fade-in',
        className,
      ].join(' ')}
    >
      <div className="w-14 h-14 rounded-full bg-surface-secondary flex items-center justify-center mb-4">
        <Icon className="w-7 h-7 text-text-tertiary" strokeWidth={1.5} />
      </div>
      <h3 className="text-lg font-medium text-text-primary mb-1">{title}</h3>
      <p className="text-sm text-text-secondary max-w-xs mb-6">{description}</p>
      {action && <div className="flex gap-3">{action}</div>}
    </div>
  );
};

// Usage example:
// <EmptyState
//   icon={MessageSquare}
//   title="No messages yet"
//   description="Start a conversation by sending a message"
// />
