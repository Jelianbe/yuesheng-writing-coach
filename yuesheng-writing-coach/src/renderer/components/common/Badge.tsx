import React from 'react';

export type BadgeVariant = 'default' | 'accent' | 'success' | 'warning' | 'danger' | 'info';

interface BadgeProps {
  children: React.ReactNode;
  variant?: BadgeVariant;
  className?: string;
}

const variantClasses: Record<BadgeVariant, string> = {
  default: 'bg-surface-secondary text-text-secondary',
  accent: 'bg-accent-primary-light text-accent-primary',
  success: 'bg-[#E8F5E8] text-[#5A9A5A]',
  warning: 'bg-[#F8F0E0] text-[#B8922E]',
  danger: 'bg-[#F5E8E6] text-[#B05A52]',
  info: 'bg-[#E6EEF5] text-[#5A7EA0]',
};

export const Badge: React.FC<BadgeProps> = ({
  children,
  variant = 'default',
  className = '',
}) => {
  return (
    <span
      className={[
        'inline-flex items-center',
        'px-2.5 py-0.5',
        'rounded-full',
        'text-xs font-medium',
        'transition-colors duration-fast',
        variantClasses[variant],
        className,
      ].join(' ')}
    >
      {children}
    </span>
  );
};

// Usage example:
// <Badge variant="primary">P001</Badge>
// <Badge variant="danger">L3</Badge>
