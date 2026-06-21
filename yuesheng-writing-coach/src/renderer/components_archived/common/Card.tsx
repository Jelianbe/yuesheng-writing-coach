import React from 'react';

interface CardProps {
  children: React.ReactNode;
  className?: string;
  hover?: boolean;
  onClick?: () => void;
  role?: string;
  'aria-label'?: string;
}

export const Card: React.FC<CardProps> = ({
  children,
  className = '',
  hover = false,
  onClick,
  role,
  'aria-label': ariaLabel,
}) => {
  const baseClasses = [
    'bg-surface rounded-[var(--radius-md)] shadow-sm',
    hover ? 'transition-shadow duration-fast hover:shadow-md cursor-pointer' : '',
    className,
  ].join(' ');

  return (
    <div
      className={baseClasses}
      onClick={onClick}
      role={role}
      aria-label={ariaLabel}
      tabIndex={onClick ? 0 : undefined}
      onKeyDown={onClick ? (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onClick(); } } : undefined}
    >
      {children}
    </div>
  );
};

// Usage example:
// <Card hover onClick={() => handleClick()}>
//   <div className="p-4">Card content</div>
// </Card>
