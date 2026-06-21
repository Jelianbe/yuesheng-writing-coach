/**
 * ReadingStepContent — Step 0: 阅读原始文本 / 阅读指导
 *
 * 阅读任务模式显示指导说明，通用模式显示用户原始文本引用。
 */
import React from 'react';
import type { ActiveTrainingSession } from '../../shared/types-training';
import styles from './ActiveTrainingView.module.css';

interface ReadingStepContentProps {
  session: ActiveTrainingSession;
}

export const ReadingStepContent: React.FC<ReadingStepContentProps> = ({ session }) => (
  <>
    {/* 阅读任务模式：显示阅读分析指导 */}
    {session.mode === 'reading_task' && (
      <div className={styles.readingGuide}>
        {session.challengeDescription ? (
          <>
            <div className={styles.sectionHeading}>阅读分析指导</div>
            {session.challengeDescription}
          </>
        ) : (
          <>
            <div className={styles.sectionHeading}>阅读分析练习</div>
            <p style={{ margin: 0 }}>
              请仔细阅读你的文本，重点关注本次训练涉及的写作问题。在下一步中写下你的分析和观察。
            </p>
          </>
        )}
      </div>
    )}

    {/* 通用模式：显示原始文本引用 */}
    {session.originalQuote && session.mode !== 'reading_task' && (
      <div className={styles.originalQuote}>
        <div className={styles.sectionHeading}>你的原始文本</div>
        &ldquo;{session.originalQuote}&rdquo;
      </div>
    )}
  </>
);
