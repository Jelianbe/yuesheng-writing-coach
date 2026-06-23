import React from 'react';
import styles from './Card.module.css';

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
  const baseClasses = hover
    ? `${styles.card} ${styles.cardHover} ${className}`
    : `${styles.card} ${className}`;

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
