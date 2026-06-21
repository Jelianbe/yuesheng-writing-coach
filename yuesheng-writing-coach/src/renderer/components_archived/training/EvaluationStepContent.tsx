/**
 * EvaluationStepContent — Step 2: 提交评估结果
 *
 * 展示评分卡片、完成提示、下一步建议，以及"写入编辑器"/"返回对话"操作按钮。
 */
import React from 'react';
import type { EvaluationResult } from '../../shared/types-training';
import styles from './ActiveTrainingView.module.css';

interface EvaluationStepContentProps {
  evaluationResult: EvaluationResult | null;
  submissionResult: { passed: boolean; feedback: string } | null;
  isLoading: boolean;
  onBackToChat: () => void;
  onSubmitStep: () => void;
  onSendToEditor?: () => void;
}

function scoreClass(score: number): string {
  if (score >= 7) return styles.scoreExcellent;
  if (score >= 4) return styles.scorePassable;
  return styles.scoreNeedsWork;
}

function scoreLabel(score: number): string {
  if (score >= 7) return '表现优秀';
  if (score >= 4) return '还需努力';
  return '继续练习';
}

export const EvaluationStepContent: React.FC<EvaluationStepContentProps> = ({
  evaluationResult,
  submissionResult,
  isLoading,
  onBackToChat,
  onSubmitStep,
  onSendToEditor,
}) => {
  const actionLabel = evaluationResult
    ? '返回对话'
    : isLoading
      ? '加载中...'
      : '完成训练';

  const actionClick = evaluationResult ? onBackToChat : onSubmitStep;

  return (
    <div className={styles.evaluationPanel}>
      {/* 评分展示 */}
      {evaluationResult && (
        <div className={styles.scoreCard}>
          <div className={`${styles.scoreCircle} ${scoreClass(evaluationResult.score)}`}>
            {evaluationResult.score}
          </div>
          <div>
            <div className={styles.scoreLabel}>
              {scoreLabel(evaluationResult.score)}
              {evaluationResult.improved && (
                <span className={styles.scoreImproved}>相比原文有改善</span>
              )}
            </div>
            <div className={styles.scoreHint}>满分 10 分</div>
          </div>
        </div>
      )}

      <div className={styles.completionTitle}>训练完成！</div>

      {submissionResult?.feedback && (
        <p style={{ margin: '0 0 8px 0' }}>{submissionResult.feedback}</p>
      )}

      {evaluationResult?.nextStep && (
        <div className={styles.nextStepBox}>
          <strong>下一步建议：</strong>{evaluationResult.nextStep}
        </div>
      )}

      <p style={{ margin: '8px 0 0 0' }}>训练记录已保存到你的学习档案中。</p>

      {/* 操作出口：写入编辑器 + 返回对话/完成训练 */}
      <div className={styles.evaluationActions}>
        {evaluationResult && onSendToEditor && (
          <button className={styles.sendToEditorBtn} onClick={onSendToEditor}>
            写入编辑器
          </button>
        )}
        <button
          className={styles.primaryActionBtn}
          onClick={actionClick}
          disabled={isLoading}
        >
          {actionLabel}
        </button>
      </div>
    </div>
  );
};

