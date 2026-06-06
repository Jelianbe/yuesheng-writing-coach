import React from 'react';
import { CheckCircle, AlertTriangle, XCircle } from 'lucide-react';
import { Card } from '../common/Card';
import { RewriteEvaluation } from '../../shared/types';

type EvaluationStatus = 'improved' | 'partial' | 'unchanged';

interface EvaluationCardProps {
  /** 评估结果 */
  evaluation: RewriteEvaluation;
  /** 修改前的文本 */
  originalText?: string;
  /** 修改后的文本 */
  rewrittenText?: string;
  /** 额外操作按钮 */
  actions?: React.ReactNode;
}

const statusConfig: Record<
  EvaluationStatus,
  { icon: React.ReactNode; label: string; color: string; bgColor: string }
> = {
  improved: {
    icon: <CheckCircle className="w-5 h-5" />,
    label: '这个改法有效',
    color: 'text-[var(--color-success)]',
    bgColor: 'bg-[#E8F5E8]',
  },
  partial: {
    icon: <AlertTriangle className="w-5 h-5" />,
    label: '部分改善',
    color: 'text-[var(--color-warning)]',
    bgColor: 'bg-[#F8F0E0]',
  },
  unchanged: {
    icon: <XCircle className="w-5 h-5" />,
    label: '需要调整',
    color: 'text-[var(--color-error)]',
    bgColor: 'bg-[#F5E8E6]',
  },
};

function getStatus(improvement: string): EvaluationStatus {
  if (improvement === '明显改善') return 'improved';
  if (improvement === '略有改善') return 'partial';
  return 'unchanged';
}

/**
 * EvaluationCard — AI 修改评估卡片（M-3）
 *
 * 用户提交修改后，月笙返回评估结果。
 * 展示状态标签、评语、改前改后对比。
 */
export const EvaluationCard: React.FC<EvaluationCardProps> = ({
  evaluation,
  originalText,
  rewrittenText,
  actions,
}) => {
  const status = getStatus(evaluation.improvement);
  const config = statusConfig[status];

  return (
    <Card className="overflow-hidden animate-slide-up">
      {/* Status header */}
      <div className="flex items-center gap-2 px-4 py-3 border-b border-border">
        <span className={config.color}>{config.icon}</span>
        <span className="text-sm font-medium text-text-primary">
          {config.label}
        </span>
      </div>

      <div className="px-4 py-3 space-y-3">
        {/* Analysis */}
        <div className="text-sm text-text-secondary leading-relaxed">
          {evaluation.analysis}
        </div>

        {/* Suggestion */}
        {evaluation.suggestion && (
          <div className="text-sm text-text-secondary leading-relaxed border-t border-border pt-3">
            <span className="font-medium text-text-primary">建议：</span>
            {evaluation.suggestion}
          </div>
        )}

        {/* Before/After comparison */}
        {(originalText || rewrittenText) && (
          <div className="border-t border-border pt-3">
            <p className="text-xs text-text-tertiary font-medium mb-2">对比之前：</p>
            <div className="space-y-2">
              {originalText && (
                <div className="flex gap-2 text-sm">
                  <span className="text-accent-danger flex-shrink-0">❌</span>
                  <span className="text-text-secondary line-through opacity-70">
                    {originalText}
                  </span>
                </div>
              )}
              {rewrittenText && (
                <div className="flex gap-2 text-sm">
                  <span className="text-[var(--color-success)] flex-shrink-0">✅</span>
                  <span className="text-text-primary">
                    {rewrittenText}
                  </span>
                </div>
              )}
            </div>
          </div>
        )}

        {/* Actions */}
        {actions && (
          <div className="flex gap-2 pt-1">
            {actions}
          </div>
        )}
      </div>
    </Card>
  );
};
