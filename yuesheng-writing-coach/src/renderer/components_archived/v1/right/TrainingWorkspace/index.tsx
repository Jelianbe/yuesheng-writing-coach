/**
 * TrainingWorkspace — 训练工作区
 *
 * 使用 useTrainingStore 显示当前训练状态和推荐训练列表。
 * 有活跃训练时显示训练详情；无活跃训练时显示推荐列表。
 *
 * 用法:
 * ```tsx
 * <TrainingWorkspace />
 * ```
 */
import { useCallback } from 'react';
import {
  useTrainingStore,
  selectActiveTraining,
  selectRecommendations,
  selectIsLoading,
} from '@/stores/training.store';
import styles from './index.module.css';

/** 严重度中文映射 */
const SEVERITY_LABEL: Record<string, string> = {
  L1: '轻微',
  L2: '中等',
  L3: '严重',
};

/** 严重度 CSS 类名映射 */
const SEVERITY_CLASS: Record<string, string> = {
  L1: styles.diffBeginner,
  L2: styles.diffIntermediate,
  L3: styles.diffAdvanced,
};

export function TrainingWorkspace(): JSX.Element {
  const activeTraining = useTrainingStore(selectActiveTraining);
  const recommendations = useTrainingStore(selectRecommendations);
  const isLoading = useTrainingStore(selectIsLoading);
  const startTraining = useTrainingStore((s) => s.startTraining);
  const errorCards = useTrainingStore((s) => s.errorCards);

  const handleStartTraining = useCallback(
    (challengeId: string) => {
      startTraining(challengeId);
    },
    [startTraining],
  );

  if (isLoading) {
    return (
      <div className={styles.container}>
        <div className={styles.centerMessage}>加载中...</div>
      </div>
    );
  }

  return (
    <div className={styles.container}>
      {/* 标题区 */}
      <div className={styles.header}>
        <h3 className={styles.title}>
          {activeTraining ? '当前训练' : '训练推荐'}
        </h3>
      </div>

      <div className={styles.content}>
        {/* 活跃训练 */}
        {activeTraining && (
          <div className={styles.activeCard}>
            <span className={styles.activeLabel}>进行中</span>
            <span className={styles.activeName}>
              {activeTraining.challengeName}
            </span>
            <p className={styles.activeDesc}>
              {activeTraining.challengeDescription}
            </p>
            <div className={styles.activeDesc}>
              步骤 {activeTraining.currentStepIndex + 1} / {activeTraining.steps.length}
            </div>
          </div>
        )}

        {/* 错误卡片统计 */}
        {!activeTraining && errorCards.length > 0 && (
          <div className={styles.card}>
            <span className={styles.cardLabel}>待训练症候</span>
            <span className={styles.cardValue}>{errorCards.length} 项</span>
          </div>
        )}

        {/* 推荐训练列表 */}
        {!activeTraining && recommendations.length > 0 && (
          <>
            <h4 className={styles.recommendTitle}>
              为你推荐（{recommendations.length}）
            </h4>
            <div className={styles.recommendList}>
              {recommendations.map((rec) => (
                <button
                  key={rec.challengeId}
                  className={styles.recommendCard}
                  onClick={() => handleStartTraining(rec.challengeId)}
                  type="button"
                >
                  <div className={styles.recommendHeader}>
                    <span className={styles.recommendName}>
                      {rec.challengeName}
                    </span>
                    <span
                      className={[
                        styles.difficultyTag,
                        SEVERITY_CLASS[rec.severity] ?? '',
                      ].join(' ')}
                    >
                      {SEVERITY_LABEL[rec.severity] ?? rec.severity}
                    </span>
                  </div>
                  <p className={styles.recommendDesc}>{rec.description}</p>
                </button>
              ))}
            </div>
          </>
        )}

        {/* 无数据 */}
        {!activeTraining && recommendations.length === 0 && (
          <div className={styles.emptyState}>
            <span className={styles.emptyIcon} aria-hidden="true">{'\uD83C\uDFAF'}</span>
            <p className={styles.emptyText}>暂无训练推荐</p>
          </div>
        )}
      </div>
    </div>
  );
}
