/**
 * TrainingHeader — 训练头部栏 + 进度条
 *
 * 从 ActiveTrainingView.tsx 拆出，包含返回按钮、标题信息和进度指示。
 */
import React from 'react';
import { ArrowLeft } from 'lucide-react';
import type { ActiveTrainingSession } from '../../shared/types-training';
import styles from './ActiveTrainingView.module.css';

interface TrainingHeaderProps {
  session: ActiveTrainingSession;
  onBackToChat: () => void;
}

export const TrainingHeader: React.FC<TrainingHeaderProps> = ({ session, onBackToChat }) => {
  const progressPercent = ((session.currentStepIndex + 1) / session.steps.length) * 100;

  return (
    <>
      <div className={styles.header}>
        <div className={styles.headerLeft}>
          <button
            className={styles.backBtn}
            onClick={onBackToChat}
            title="返回对话"
          >
            <ArrowLeft size={15} strokeWidth={1.8} />
          </button>
          <div>
            <div className={styles.headerTitle}>{session.challengeName}</div>
            <div className={styles.headerStep}>
              步骤 {session.currentStepIndex + 1}/{session.steps.length}
            </div>
          </div>
        </div>
      </div>

      <div className={styles.progressWrap}>
        <div className={styles.progressTrack}>
          <div className={styles.progressFill} style={{ width: `${progressPercent}%` }} />
        </div>
      </div>
    </>
  );
};
