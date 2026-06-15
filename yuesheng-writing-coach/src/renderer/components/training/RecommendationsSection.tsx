/**
 * RecommendationsSection — 训练工坊区块二：推荐训练任务
 *
 * 当推荐卡片的 challengeId 能映射到结构化任务（structured-tasks.ts）时，
 * 展示丰富的任务信息（内容、字数、禁止词等）；否则 fallback 到原有行为。
 *
 * A3 自荐阅读框架：
 * 当用户训练表现好（评估分数 >= 7）时，在推荐训练任务下方展示相关阅读材料。
 */

import React, { useEffect, useState } from 'react';
import type { TrainingRecommendation } from '../../shared/types';
import { getStructuredTasksForChallenge } from '../../shared/structured-tasks';
import { getInvoke } from '../../utils/ipc';
import { ConfigApi } from '../../../shared/api-contracts/config.contract';
import sharedStyles from './TrainingShared.module.css';
import styles from './RecommendationsSection.module.css';

// A3: 阅读推荐条目类型
interface ReadingRecommendation {
  id: string;
  title: string;
  syndromeId: string;
  difficulty: string;
  categoryId: string;
  tags: string[];
  excerpt: string;
  analysisPrompt: string;
  referenceExcerpt?: string | null;
}

// A3: 阅读推荐阈值（与 main process 保持一致）
const READING_RECOMMENDATION_THRESHOLD = 7;

export const RecommendationsSection: React.FC<{
  recommendations: TrainingRecommendation[];
  onStartTraining: (challengeId: string) => void;
  /** A3: 最近一次训练的评估分数（用于判断是否推荐阅读） */
  lastEvaluationScore?: number;
  /** A3: 最近训练对应的症候 ID（用于匹配阅读材料） */
  lastSyndromeId?: string;
  /** A3: 开始阅读回调 */
  onStartReading?: (readingId: string, syndromeId: string) => void;
}> = ({ recommendations, onStartTraining, lastEvaluationScore, lastSyndromeId, onStartReading }) => {
  // A3: 阅读推荐状态
  const [readingRecommendations, setReadingRecommendations] = useState<ReadingRecommendation[]>([]);
  const [readingLoading, setReadingLoading] = useState(false);

  // A3: 判断是否应该推荐阅读
  const shouldShowReading = lastEvaluationScore != null && lastEvaluationScore >= READING_RECOMMENDATION_THRESHOLD;

  // A3: 加载阅读推荐
  useEffect(() => {
    if (!shouldShowReading || !lastSyndromeId) {
      setReadingRecommendations([]);
      return;
    }

    let cancelled = false;
    setReadingLoading(true);

    getInvoke()(ConfigApi.getReadingEntry.channel, { syndromeId: lastSyndromeId })
      .then((result) => {
        if (cancelled) return;
        const entries = (result as { entries?: ReadingRecommendation[] })?.entries ?? [];
        setReadingRecommendations(entries.slice(0, 3));
      })
      .catch(() => {
        if (!cancelled) setReadingRecommendations([]);
      })
      .finally(() => {
        if (!cancelled) setReadingLoading(false);
      });

    return () => { cancelled = true; };
  }, [shouldShowReading, lastSyndromeId]);

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

      {/* ===== A3 自荐阅读区域 ===== */}
      {shouldShowReading && (
        <div className={styles.readingSection}>
          <div className={styles.readingHeader}>
            <span className={styles.readingIcon}>📚</span>
            <span className={styles.readingTitle}>相关阅读推荐</span>
            <span className={styles.readingBadge}>表现优秀</span>
          </div>
          <div className={styles.readingDescription}>
            你在刚才的训练中表现不错！阅读优秀范文可以帮你进一步提升。
          </div>

          {readingLoading && (
            <div className={styles.readingLoading}>加载阅读材料中...</div>
          )}

          {!readingLoading && readingRecommendations.length === 0 && (
            <div className={styles.readingEmpty}>暂无匹配的阅读材料</div>
          )}

          {!readingLoading && readingRecommendations.length > 0 && (
            <div className={styles.readingList}>
              {readingRecommendations.map((entry) => (
                <div key={entry.id} className={styles.readingCard}>
                  <div className={styles.readingCardHeader}>
                    <span className={styles.readingCardTitle}>{entry.title}</span>
                    <span className={styles.readingDifficulty}>
                      {entry.difficulty === 'easy' ? '入门' : entry.difficulty === 'medium' ? '进阶' : '高级'}
                    </span>
                  </div>
                  <div className={styles.readingExcerpt}>
                    {entry.excerpt.length > 150 ? `${entry.excerpt.slice(0, 150)}...` : entry.excerpt}
                  </div>
                  <div className={styles.readingTags}>
                    {entry.tags.slice(0, 3).map((tag) => (
                      <span key={tag} className={styles.readingTag}>{tag}</span>
                    ))}
                  </div>
                  <button
                    className={styles.readingStartBtn}
                    onClick={() => onStartReading?.(entry.id, entry.syndromeId)}
                  >
                    开始阅读
                  </button>
                </div>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
};
