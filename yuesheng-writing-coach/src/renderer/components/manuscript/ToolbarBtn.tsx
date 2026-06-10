import React from 'react';
import styles from './ManuscriptPanel.module.css';

interface ToolbarBtnProps {
  children: React.ReactNode;
  onClick: () => void;
  title?: string;
  disabled?: boolean;
  palette: { text: string };
}

export const ToolbarBtn: React.FC<ToolbarBtnProps> = ({ children, onClick, title, disabled, palette }) => (
  <button
    onClick={disabled ? undefined : onClick}
    title={title}
    className={`${styles.toolbarBtn}${disabled ? ` ${styles.toolbarBtnDisabled}` : ''}`}
    style={{
      color: disabled ? `${palette.text}22` : palette.text,
      opacity: disabled ? 0.3 : 0.7,
    }}
    onMouseEnter={e => {
      if (!disabled) {
        e.currentTarget.style.background = `${palette.text}0a`;
        e.currentTarget.style.opacity = '1';
      }
    }}
    onMouseLeave={e => {
      if (!disabled) {
        e.currentTarget.style.background = 'transparent';
        e.currentTarget.style.opacity = '0.7';
      }
    }}
  >
    {children}
  </button>
);
