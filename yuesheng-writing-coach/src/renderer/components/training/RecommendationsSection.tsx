/**
 * RecommendationsSection — 训练工坊区块二：推荐训练任务
 *
 * 当推荐卡片的 challengeId 能映射到结构化任务（structured-tasks.ts）时，
 * 展示丰富的任务信息（内容、字数、禁止词等）；否则 fallback 到原有行为。
 */

import React from 'react';
import type { TrainingRecommendation } from '../../shared/types';
import { getStructuredTasksForChallenge } from '../../shared/structured-tasks';
import sharedStyles from './TrainingShared.module.css';
import styles from './RecommendationsSection.module.css';

export const RecommendationsSection: React.FC<{
  recommendations: TrainingRecommendation[];
  onStartTraining: (challengeId: string) => void;
}> = ({ recommendations, onStartTraining }) => {
  if (recommendations.length === 0) {
    return (
      <div className={sharedStyles.trainingSection}>
        <div className={sharedStyles.trainingSectionTitle}>推荐训练任务</div>
        <div className={sharedStyles.trainingEmpty}>
          <p className={styles.emptyText}>
            暂无推荐。完成诊断后，AI 会根据你的问题推荐针对性的练习。
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className={sharedStyles.trainingSection}>
      <div className={sharedStyles.trainingSectionTitle}>推荐训练任务</div>
      <div className={styles.recList}>
        {recommendations.map((rec) => {
          const structuredTasks = getStructuredTasksForChallenge(rec.challengeId);
          const hasStructuredTasks = structuredTasks.length > 0;

          return (
            <div
              key={rec.challengeId}
              className={`${sharedStyles.trainingRecCard} ${styles.recCard}`}
            >
              <div className={styles.cardBody}>
                <div className={styles.challengeNameRow}>
                  {rec.challengeName}
                  <span className={styles.tierBadge}>
                    {rec.tier === 'structural' ? '结构性问题' : '表面优化'} · ~15min
                  </span>
                  {hasStructuredTasks && (
                    <span className={styles.structuredTaskBadge}>
                      结构化任务 ×{structuredTasks.length}
                    </span>
                  )}
                </div>
                <div className={styles.description}>
                  {rec.description}
                </div>

                {/* ===== 结构化任务丰富信息展示 ===== */}
                {hasStructuredTasks && (
                  <div className={styles.structuredInfoPanel}>
                    {/* 任务内容预览（取第一个任务的 content） */}
                    {structuredTasks[0].content && (
                      <div className={styles.taskContentPreview}>
                        <span className={styles.taskLabel}>任务要求：</span>
                        {structuredTasks[0].content.split('\n')[0]}
                      </div>
                    )}

                    {/* 元信息行：字数 + 禁止词 + 场景 */}
                    <div className={styles.metaInfoRow}>
                      {structuredTasks[0].wordCount && (
                        <span className={styles.metaItem}>
                          <span>📝</span> 目标字数：{structuredTasks[0].wordCount} 字
                        </span>
                      )}
                      {structuredTasks[0].forbiddenWords && structuredTasks[0].forbiddenWords.length > 0 && (
                        <span className={styles.forbiddenMetaItem}>
                          <span>🚫</span> 禁止词：{structuredTasks[0].forbiddenWords.length} 个
                        </span>
                      )}
                      {structuredTasks[0].scene && (
                        <span className={styles.metaItem}>
                          <span>🎬</span> 场景设定
                        </span>
                      )}
                      {structuredTasks[0].mode === 'reading' && (
                        <span className={styles.readingMetaItem}>
                          <span>📖</span> 阅读任务
                        </span>
                      )}
                    </div>

                    {/* 禁止词标签（仅当数量较少时展示） */}
                    {structuredTasks[0].forbiddenWords && structuredTasks[0].forbiddenWords.length > 0 && structuredTasks[0].forbiddenWords.length <= 6 && (
                      <div className={styles.forbiddenWordsContainer}>
                        {structuredTasks[0].forbiddenWords.map((word) => (
                          <span
                            key={word}
                            className={styles.forbiddenWordTag}
                          >
                            {word}
                          </span>
                        ))}
                      </div>
                    )}
                  </div>
                )}

                {rec.constraint && (
                <div className={styles.constraintBox}>
                  约束：{rec.constraint}
                </div>
              )}
              {rec.techniques && rec.techniques.length > 0 && (
                <div className={styles.techniquesSection}>
                  <span className={styles.techniquesLabel}>参考技法：</span>
                  {rec.techniques.map((t, i) => (
                    <span key={t.id}>
                      {i > 0 && ' · '}
                      <span title={t.description}>{t.name}（{t.source}）</span>
                    </span>
                  ))}
                </div>
              )}
            </div>
            <button
              className={sharedStyles.trainingStartBtn}
              onClick={() => onStartTraining(rec.challengeId)}
            >
              开始练习
            </button>
          </div>
          );
        })}
      </div>
    </div>
  );
};
