import React from 'react';
import { Loader2 } from 'lucide-react';

export type ButtonVariant = 'primary' | 'secondary' | 'ghost' | 'icon' | 'danger';
export type ButtonSize = 'sm' | 'md' | 'lg';

interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant;
  size?: ButtonSize;
  isLoading?: boolean;
  leftIcon?: React.ReactNode;
  rightIcon?: React.ReactNode;
  fullWidth?: boolean;
  children: React.ReactNode;
}

const variantClasses: Record<ButtonVariant, string> = {
  primary:
    'bg-accent-primary text-text-inverse hover:bg-accent-primary-hover shadow-sm',
  secondary:
    'bg-surface-secondary text-text-primary hover:bg-bg-hover border border-border',
  ghost:
    'bg-transparent text-text-secondary hover:bg-bg-tertiary hover:text-text-primary',
  icon:
    'bg-transparent text-text-muted hover:bg-bg-tertiary hover:text-text-primary rounded-full p-2',
  danger:
    'bg-accent-danger text-text-inverse hover:opacity-90 shadow-sm',
};

const sizeClasses: Record<ButtonSize, string> = {
  sm: 'text-small px-3 py-1.5',
  md: 'text-body px-4 py-2',
  lg: 'text-h3 px-6 py-3',
};

export const Button: React.FC<ButtonProps> = ({
  variant = 'primary',
  size = 'md',
  isLoading = false,
  leftIcon,
  rightIcon,
  fullWidth = false,
  disabled,
  children,
  className = '',
  ...props
}) => {
  const baseClasses = [
    'inline-flex items-center justify-center gap-2',
    'font-medium rounded-md',
    'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent-primary focus-visible:ring-offset-2',
    'disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none',
    variant !== 'icon' ? sizeClasses[size] : '',
    variantClasses[variant],
    fullWidth ? 'w-full' : '',
    className,
  ].join(' ');

  return (
    <button className={baseClasses} disabled={disabled || isLoading} {...props}>
      {isLoading && <Loader2 className="w-4 h-4 animate-spin" />}
      {!isLoading && leftIcon && <span className="flex-shrink-0">{leftIcon}</span>}
      <span>{children}</span>
      {!isLoading && rightIcon && <span className="flex-shrink-0">{rightIcon}</span>}
    </button>
  );
};

// Usage example:
// <Button variant="primary" leftIcon={<SendIcon />}>Send</Button>
// <Button variant="secondary">Cancel</Button>
// <Button variant="ghost">More options</Button>
// <Button variant="icon" aria-label="Settings"><SettingsIcon /></Button>
