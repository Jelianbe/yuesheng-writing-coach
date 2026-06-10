/**
 * GoalTrackingPanel — SF-002 三级目标追踪面板
 *
 * 展示短期（步骤完成度）、中期（技法掌握）、长期（症候改善）三级进度。
 */
import React from 'react';
import type { ActiveTrainingSession } from '../../shared/types-training';
import styles from './ActiveTrainingView.module.css';

interface GoalTrackingPanelProps {
  session: ActiveTrainingSession;
}

export const GoalTrackingPanel: React.FC<GoalTrackingPanelProps> = ({ session }) => {
  const shortPercent = ((session.currentStepIndex + 1) / session.steps.length) * 100;
  const midPercent = session.corePatterns ? 60 : 30;

  return (
    <div className={styles.goalTracking}>
      {/* 短期目标 */}
      <div className={styles.goalItem}>
        <div className={styles.goalLabel}>短期 · 步骤完成度</div>
        <div className={styles.goalBarTrack}>
          <div className={styles.goalBarFillShort} style={{ width: `${shortPercent}%` }} />
        </div>
        <div className={styles.goalDetail}>
          {session.currentStepIndex + 1}/{session.steps.length} 步
        </div>
      </div>

      {/* 中期目标 */}
      <div className={styles.goalItem}>
        <div className={styles.goalLabel}>中期 · 技法掌握</div>
        <div className={styles.goalBarTrack}>
          <div className={styles.goalBarFillMid} style={{ width: `${midPercent}%` }} />
        </div>
        <div className={styles.goalDetail}>
          {session.corePatterns ?? '基础练习'}
        </div>
      </div>

      {/* 长期目标 */}
      <div className={styles.goalItem}>
        <div className={styles.goalLabel}>长期 · 症候改善</div>
        <div className={styles.goalBarTrack}>
          <div className={styles.goalBarFillLong} style={{ width: `${session.longTermProgress}%` }} />
        </div>
        <div className={styles.goalDetail}>
          {session.targetSyndrome ?? '综合提升'} · {session.longTermProgress}%
        </div>
      </div>
    </div>
  );
};
