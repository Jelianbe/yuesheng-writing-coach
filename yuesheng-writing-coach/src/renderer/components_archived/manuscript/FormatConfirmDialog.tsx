import React from 'react';

interface FormatConfirmDialogProps {
  open: boolean;
  onConfirm: () => void;
  onCancel: () => void;
}

export const FormatConfirmDialog: React.FC<FormatConfirmDialogProps> = ({
  open,
  onConfirm,
  onCancel,
}) => {
  if (!open) return null;

  return (
    <div
      style={{
        position: 'fixed',
        inset: 0,
        zIndex: 1000,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        background: 'rgba(0,0,0,0.4)',
      }}
      onClick={onCancel}
    >
      <div
        style={{
          background: 'var(--bg-primary, #fff)',
          borderRadius: 12,
          padding: 28,
          minWidth: 320,
          maxWidth: 420,
          boxShadow: '0 8px 32px rgba(0,0,0,0.2)',
        }}
        onClick={(e) => e.stopPropagation()}
      >
        <h3
          style={{
            margin: '0 0 12px 0',
            fontSize: 16,
            fontWeight: 600,
            color: 'var(--text-primary, #333)',
          }}
        >
          确认自动排版
        </h3>
        <p
          style={{
            margin: '0 0 24px 0',
            fontSize: 13,
            color: 'var(--text-secondary, #666)',
            lineHeight: 1.6,
          }}
        >
          自动排版将调整文稿的缩进和间距格式。此操作可撤销，是否继续？
        </p>
        <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 10 }}>
          <button
            onClick={onCancel}
            style={{
              padding: '8px 20px',
              borderRadius: 6,
              border: '1px solid var(--border, #ddd)',
              background: 'var(--bg-primary, #fff)',
              color: 'var(--text-primary, #333)',
              fontSize: 13,
              cursor: 'pointer',
            }}
          >
            取消
          </button>
          <button
            onClick={onConfirm}
            style={{
              padding: '8px 20px',
              borderRadius: 6,
              border: 'none',
              background: 'var(--accent, #3b82f6)',
              color: 'var(--text-on-accent)',
              fontSize: 13,
              fontWeight: 500,
              cursor: 'pointer',
            }}
          >
            确认排版
          </button>
        </div>
      </div>
    </div>
  );
};
