/**
 * StepIndicatorList — 步骤状态列表
 *
 * 展示所有训练步骤的完成/活跃/待定状态。
 */
import React from 'react';
import type { TrainingStep } from '../../shared/types-training';
import styles from './ActiveTrainingView.module.css';

interface StepIndicatorListProps {
  steps: TrainingStep[];
}

export const StepIndicatorList: React.FC<StepIndicatorListProps> = ({ steps }) => (
  <div className={styles.stepList}>
    {steps.map((step) => {
      const isActive = step.status === 'active';
      const isCompleted = step.status === 'completed';

      let badgeClass = styles.stepBadgePending;
      if (isCompleted) badgeClass = styles.stepBadgeCompleted;
      else if (isActive) badgeClass = styles.stepBadgeActive;

      const badgeContent = isCompleted
        ? '✓'
        : isActive
          ? steps.indexOf(step) + 1
          : '';

      return (
        <div
          key={step.id}
          className={`${styles.stepItem} ${isActive ? styles.stepItemActive : ''}`}
        >
          <span className={badgeClass}>{badgeContent}</span>
          <div>
            <div className={`${styles.stepTitle} ${isActive ? styles.stepTitleActive : ''}`}>
              {step.title}
            </div>
            {isActive && step.description && (
              <div className={styles.stepDesc}>{step.description}</div>
            )}
          </div>
        </div>
      );
    })}
  </div>
);
