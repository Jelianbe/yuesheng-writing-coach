/**
 * LearningLogWorkspace — 学习日志工作区（GAP-01 / H-03）
 *
 * 数据源：trainingStore（训练历史）、teachingStateStore（会话次数+已攻克症候）、
 * progressStore（教学进度）、SYNDROME_NAMES（症候映射）。
 *
 * 用法:
 * ```tsx
 * <LearningLogWorkspace />
 * ```
 */
import { useMemo } from 'react';
import { useTrainingStore, selectTrainingHistory } from '@/stores/training.store';
import { useTeachingStateStore } from '@/stores/teaching-state.store';
import { useProgressStore } from '@/stores/progress.store';
import { SYNDROME_NAMES } from '../../../../shared/mappings';
import styles from './index.module.css';

// ===== 常量 =====

const ISSUE_STATUS_LABEL: Record<string, string> = {
  mastered: '已掌握',
  teaching: '教学中',
  identified: '已发现',
  relapsed: '复发',
};

const STATUS_CLASS_MAP: Record<string, string> = {
  mastered: styles.statusMastered,
  teaching: styles.statusTeaching,
  identified: styles.statusIdentified,
  relapsed: styles.statusRelapsed,
};

// ===== 工具函数 =====

function countByStatus(
  issues: Array<{ status: string }>,
  status: string,
): number {
  return issues.filter((i) => i.status === status).length;
}

// ===== 子组件 =====

function StatusChip({
  status,
  count,
}: {
  status: string;
  count: number;
}): JSX.Element | null {
  if (count <= 0) return null;
  const label = ISSUE_STATUS_LABEL[status] ?? status;
  const className = STATUS_CLASS_MAP[status] ?? '';
  return (
    <span className={`${styles.statusChip} ${className}`}>
      {label} {count}
    </span>
  );
}

function MasteredSyndromeList({ ids }: { ids: string[] }): JSX.Element {
  if (ids.length === 0) {
    return <p className={styles.centerMessage}>暂无已攻克症候</p>;
  }

  return (
    <ul className={styles.syndromeList} role="list" aria-label="已攻克症候列表">
      {ids.map((id) => (
        <li key={id} className={`${styles.card} ${styles.syndromeItem}`}>
          <span className={styles.syndromeDot} aria-hidden="true" />
          <span className={styles.syndromeName}>
            {SYNDROME_NAMES[id] ?? id}
          </span>
        </li>
      ))}
    </ul>
  );
}

// ===== 主组件 =====

export function LearningLogWorkspace(): JSX.Element {
  const history = useTrainingStore(selectTrainingHistory);
  const masteredSyndromeIds = useTeachingStateStore((s) => s.masteredSyndromeIds);
  const progressMap = useProgressStore((s) => s.progressMap);

  const stats = useMemo(() => {
    const totalTrainings = history.length;
    const completedTrainings = history.filter(
      (h) => h.status === 'completed',
    ).length;
    const sessionCount = Object.keys(progressMap).length;
    return { totalTrainings, completedTrainings, sessionCount };
  }, [history, progressMap]);

  const progressEntries = useMemo(
    () => Object.entries(progressMap),
    [progressMap],
  );

  const hasNoData =
    stats.totalTrainings === 0 &&
    stats.sessionCount === 0 &&
    masteredSyndromeIds.length === 0 &&
    progressEntries.length === 0;

  if (hasNoData) {
    return (
      <div className={styles.container}>
        <div className={styles.header}>
          <h3 className={styles.title}>学习日志</h3>
        </div>
        <div className={styles.emptyState}>
          <span className={styles.emptyIcon} aria-hidden="true">{'\uD83D\uDCDD'}</span>
          <p className={styles.emptyText}>暂无学习日志数据</p>
        </div>
      </div>
    );
  }

  return (
    <div className={styles.container}>
      <div className={styles.header}>
        <h3 className={styles.title}>学习日志</h3>
      </div>

      <div className={styles.statCards} role="group" aria-label="学习统计">
        <div className={styles.statCard} role="figure" aria-label="训练总次数">
          <span className={styles.statCardValue}>{stats.totalTrainings}</span>
          <span className={styles.statCardLabel}>训练总次数</span>
        </div>
        <div className={styles.statCard} role="figure" aria-label="已完成训练">
          <span className={styles.statCardValue}>{stats.completedTrainings}</span>
          <span className={styles.statCardLabel}>已完成训练</span>
        </div>
        <div className={styles.statCard} role="figure" aria-label="当前会话次数">
          <span className={styles.statCardValue}>{stats.sessionCount}</span>
          <span className={styles.statCardLabel}>当前会话次数</span>
        </div>
      </div>

      <div className={styles.scrollArea}>
        <section className={styles.section} aria-label="已攻克症候">
          <h4 className={styles.sectionTitle}>已攻克症候</h4>
          <MasteredSyndromeList ids={masteredSyndromeIds} />
        </section>

        <section className={styles.progressSection} aria-label="教学进度">
          <h4 className={styles.sectionTitle}>
            教学进度（{progressEntries.length} 个会话）
          </h4>
          {progressEntries.length === 0 ? (
            <p className={styles.centerMessage}>暂无教学进度数据</p>
          ) : (
            <ul className={styles.syndromeList} role="list" aria-label="教学进度列表">
              {progressEntries.map(([sessionId, progress]) => (
                <li key={sessionId} className={`${styles.card} ${styles.progressItem}`}>
                  <div className={styles.progressItemHeader}>
                    <span className={styles.progressSessionLabel}>
                      {progress.stage || '会话'}
                    </span>
                    <span className={styles.progressTotal}>
                      {progress.resolvedIssues}/{progress.totalIssues}
                    </span>
                  </div>
                  <div className={styles.progressStatusRow}>
                    <StatusChip
                      status="mastered"
                      count={countByStatus(progress.issues, 'mastered')}
                    />
                    <StatusChip
                      status="teaching"
                      count={countByStatus(progress.issues, 'teaching')}
                    />
                    <StatusChip
                      status="identified"
                      count={countByStatus(progress.issues, 'identified')}
                    />
                    <StatusChip
                      status="relapsed"
                      count={countByStatus(progress.issues, 'relapsed')}
                    />
                  </div>
                </li>
              ))}
            </ul>
          )}
        </section>
      </div>
    </div>
  );
}
