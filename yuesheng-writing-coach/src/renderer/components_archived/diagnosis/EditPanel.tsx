import React, { useState } from 'react';
import { X } from 'lucide-react';
import { Button } from '../common/Button';
import styles from './EditPanel.module.css';

interface EditPanelProps {
  /** 原文段落 */
  originalTexts: string[];
  /** 综合征名称 */
  syndromeName: string;
  /** 提交修改的回调 */
  onSubmit: (rewrittenText: string) => void;
  /** 取消回调 */
  onCancel: () => void;
  /** 是否正在提交 */
  isSubmitting?: boolean;
}

/**
 * EditPanel — 修改原文入口（M-2）
 *
 * 诊断卡片中点击"尝试修改"后展开的内联编辑区。
 * 上方显示只读原文，下方为用户可编辑区域。
 */
export const EditPanel: React.FC<EditPanelProps> = ({
  originalTexts,
  syndromeName,
  onSubmit,
  onCancel,
  isSubmitting = false,
}) => {
  const [rewritten, setRewritten] = useState('');

  const handleSubmit = () => {
    if (!rewritten.trim()) return;
    onSubmit(rewritten.trim());
  };

  return (
    <div className={`${styles.container} animate-expand`}>
      {/* Header */}
      <div className={styles.header}>
        <span className={styles.headerTitle}>
          修改 — {syndromeName}
        </span>
        <Button
          variant="icon"
          onClick={onCancel}
          aria-label="Close edit panel"
          className="btn-hover-effect"
        >
          <X className={styles.closeIcon} />
        </Button>
      </div>

      <div className={styles.body}>
        {/* Original text (read-only) */}
        <div>
          <label className={styles.fieldLabel}>
            原文
          </label>
          <div className={styles.originalBox}>
            {originalTexts.map((text, i) => (
              <p key={i} className={i > 0 ? styles.paragraph : ''}>
                {text}
              </p>
            ))}
          </div>
        </div>

        {/* User rewrite area */}
        <div>
          <label className={styles.fieldLabel}>
            你的修改
          </label>
          <textarea
            value={rewritten}
            onChange={(e) => setRewritten(e.target.value)}
            placeholder="在这里写下你的修改..."
            rows={4}
            className={styles.textarea}
            aria-label="Rewrite text"
          />
        </div>

        {/* Actions */}
        <div className={styles.actions}>
          <Button
            variant="secondary"
            size="sm"
            onClick={onCancel}
            className="btn-hover-effect"
          >
            取消
          </Button>
          <Button
            variant="primary"
            size="sm"
            onClick={handleSubmit}
            disabled={!rewritten.trim() || isSubmitting}
            isLoading={isSubmitting}
            className="btn-hover-effect"
          >
            提交评估
          </Button>
        </div>
      </div>
    </div>
  );
};
