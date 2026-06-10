import React from 'react';
import { useEditorStore } from '../../stores/editor.store';
import { Z_INDEX } from '../layout/layout.constants';
import styles from './ManuscriptPanel.module.css';

interface FormatConfirmDialogProps {
  open: boolean;
  onConfirm: () => void;
  onCancel: () => void;
}

export const FormatConfirmDialog: React.FC<FormatConfirmDialogProps> = ({ open, onConfirm, onCancel }) => {
  const formatConfig = useEditorStore(s => s.format);

  if (!open) return null;

  return (
    <div
      className={styles.dialogOverlay}
      style={{ zIndex: Z_INDEX.formatConfirm }}
      onClick={onCancel}
    >
      <div
        onClick={e => e.stopPropagation()}
        className={styles.dialogCard}
      >
        <div className={styles.dialogTitle}>
          确认自动排版
        </div>
        <div className={styles.dialogDesc}>
          将对全文执行以下操作：
          {formatConfig.firstLineIndent > 0 && (
            <div className={styles.detailIndent}>
              · 首行缩进 {formatConfig.firstLineIndent} 格全角空格
            </div>
          )}
          {formatConfig.paragraphSpacing && (
            <div className={styles.detailIndent}>· 段落间插入空行</div>
          )}
          {!formatConfig.firstLineIndent && !formatConfig.paragraphSpacing && (
            <div className={styles.detailEmptyHint}>
              （当前无缩进和间距设置，操作不会产生可见变化）
            </div>
          )}
        </div>
        <div className={styles.dialogActions}>
          <button
            onClick={onCancel}
            className={styles.btnSecondary}
          >
            取消
          </button>
          <button
            onClick={onConfirm}
            className={styles.btnPrimary}
          >
            确认排版
          </button>
        </div>
      </div>
    </div>
  );
};
