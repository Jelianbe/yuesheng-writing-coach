import React from 'react';
import { CheckCircle, AlertTriangle, XCircle } from 'lucide-react';
import { Card } from '../common/Card';
import { RewriteEvaluation } from '../../shared/types';
import styles from './EvaluationCard.module.css';

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
  { icon: React.ReactNode; label: string; iconClass: string }
> = {
  improved: {
    icon: <CheckCircle className={styles.statusIcon} />,
    label: '这个改法有效',
    iconClass: styles.statusIconImproved,
  },
  partial: {
    icon: <AlertTriangle className={styles.statusIcon} />,
    label: '部分改善',
    iconClass: styles.statusIconPartial,
  },
  unchanged: {
    icon: <XCircle className={styles.statusIcon} />,
    label: '需要调整',
    iconClass: styles.statusIconUnchanged,
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
    <Card className={`${styles.card} animate-slide-up`}>
      {/* Status header */}
      <div className={styles.statusHeader}>
        <span className={config.iconClass}>{config.icon}</span>
        <span className={styles.statusLabel}>
          {config.label}
        </span>
      </div>

      <div className={styles.body}>
        {/* Analysis */}
        <div className={styles.analysis}>
          {evaluation.analysis}
        </div>

        {/* Suggestion */}
        {evaluation.suggestion && (
          <div className={styles.suggestion}>
            <span className={styles.suggestionLabel}>建议：</span>
            {evaluation.suggestion}
          </div>
        )}

        {/* Before/After comparison */}
        {(originalText || rewrittenText) && (
          <div className={styles.comparison}>
            <p className={styles.comparisonTitle}>对比之前：</p>
            <div className={styles.comparisonList}>
              {originalText && (
                <div className={styles.comparisonItem}>
                  <span className={styles.originalIcon}>❌</span>
                  <span className={styles.originalText}>
                    {originalText}
                  </span>
                </div>
              )}
              {rewrittenText && (
                <div className={styles.comparisonItem}>
                  <span className={styles.rewrittenIcon}>✅</span>
                  <span className={styles.rewrittenText}>
                    {rewrittenText}
                  </span>
                </div>
              )}
            </div>
          </div>
        )}

        {/* Actions */}
        {actions && (
          <div className={styles.actions}>
            {actions}
          </div>
        )}
      </div>
    </Card>
  );
};
