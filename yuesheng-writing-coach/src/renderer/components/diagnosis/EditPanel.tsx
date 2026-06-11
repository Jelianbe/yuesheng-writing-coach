import React, { useState } from 'react';
import { X } from 'lucide-react';
import { Button } from '../common/Button';

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
    <div className="border border-border rounded-[var(--radius-md)] bg-surface shadow-sm animate-expand">
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-3 border-b border-border">
        <span className="text-sm font-medium text-text-primary">
          修改 — {syndromeName}
        </span>
        <Button
          variant="icon"
          onClick={onCancel}
          aria-label="Close edit panel"
          className="btn-hover-effect"
        >
          <X className="w-4 h-4" />
        </Button>
      </div>

      <div className="p-4 space-y-3">
        {/* Original text (read-only) */}
        <div>
          <label className="text-xs text-text-tertiary font-medium mb-1.5 block">
            原文
          </label>
          <div className="bg-surface-secondary rounded-[var(--radius-sm)] p-3 text-sm text-text-secondary leading-relaxed border border-border">
            {originalTexts.map((text, i) => (
              <p key={i} className={i > 0 ? 'mt-2' : ''}>
                {text}
              </p>
            ))}
          </div>
        </div>

        {/* User rewrite area */}
        <div>
          <label className="text-xs text-text-tertiary font-medium mb-1.5 block">
            你的修改
          </label>
          <textarea
            value={rewritten}
            onChange={(e) => setRewritten(e.target.value)}
            placeholder="在这里写下你的修改..."
            rows={4}
            className="w-full resize-none py-3 px-4 text-sm bg-surface border border-border rounded-[var(--radius-md)]
              placeholder:text-text-tertiary text-text-primary
              focus:outline-none focus:ring-2 focus:ring-accent-primary/30 focus:border-accent-primary
              transition-all duration-fast"
            aria-label="Rewrite text"
          />
        </div>

        {/* Actions */}
        <div className="flex justify-end gap-2">
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
