import React, { useState } from 'react';

interface ToolbarBtnProps {
  onClick: () => void;
  title: string;
  disabled?: boolean;
  palette: { text: string; border: string };
  children: React.ReactNode;
}

export const ToolbarBtn: React.FC<ToolbarBtnProps> = ({
  onClick,
  title,
  disabled = false,
  palette,
  children,
}) => {
  const [hovered, setHovered] = useState(false);

  return (
    <button
      onClick={onClick}
      title={title}
      disabled={disabled}
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      style={{
        display: 'inline-flex',
        alignItems: 'center',
        justifyContent: 'center',
        width: 30,
        height: 30,
        border: `1px solid ${hovered ? palette.text : 'transparent'}`,
        borderRadius: 6,
        background: hovered ? 'var(--bg-hover, rgba(0,0,0,0.05))' : 'transparent',
        color: palette.text,
        cursor: disabled ? 'not-allowed' : 'pointer',
        opacity: disabled ? 0.35 : 1,
        fontSize: 14,
        lineHeight: 1,
        transition: 'all 0.15s ease',
        outline: 'none',
        flexShrink: 0,
      }}
    >
      {children}
    </button>
  );
};
