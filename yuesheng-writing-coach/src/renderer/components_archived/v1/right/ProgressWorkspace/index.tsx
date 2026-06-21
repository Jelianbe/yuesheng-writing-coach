/**
 * ProgressWorkspace — 教学进度工作区
 *
 * 使用 useProgressStore 显示当前教学进度信息：
 * 会话 ID、总问题数、各状态计数、当前分组。
 *
 * 用法:
 * ```tsx
 * <ProgressWorkspace />
 * ```
 */
import { useMemo } from 'react';
import { useProgressStore } from '@/stores/progress.store';
import styles from './index.module.css';

/** 问题状态中文映射 */
const STATUS_LABEL: Record<string, string> = {
  identified: '已识别',
  mastered: '已掌握',
  relapsed: '已复发',
};

/** 显示状态中文映射 */
const DISPLAY_STATUS_LABEL: Record<string, string> = {
  idle: '待开始',
  diagnosing: '诊断中',
  teaching: '教学中',
  reflecting: '反思中',
  completed: '已完成',
};

function countByStatus(
  issues: Array<{ status: string }>,
): Record<string, number> {
  const counts: Record<string, number> = {};
  for (const issue of issues) {
    const key = issue.status;
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return counts;
}

export function ProgressWorkspace(): JSX.Element {
  const currentProgress = useProgressStore((s) => s.currentProgress);
  const isLoading = useProgressStore((s) => s.isLoading);
  const error = useProgressStore((s) => s.error);

  const statusCounts = useMemo(
    () => (currentProgress ? countByStatus(currentProgress.issues) : {}),
    [currentProgress],
  );

  if (isLoading) {
    return (
      <div className={styles.container}>
        <div className={styles.centerMessage}>加载中...</div>
      </div>
    );
  }

  if (error) {
    return (
      <div className={styles.container}>
        <div className={styles.centerMessage}>
          <span className={styles.errorText}>{error}</span>
        </div>
      </div>
    );
  }

  if (!currentProgress) {
    return (
      <div className={styles.container}>
        <div className={styles.emptyState}>
          <span className={styles.emptyIcon} aria-hidden="true">{'\uD83D\uDCCA'}</span>
          <p className={styles.emptyText}>暂无教学进度数据</p>
        </div>
      </div>
    );
  }

  return (
    <div className={styles.container}>
      {/* 标题区 */}
      <div className={styles.header}>
        <h3 className={styles.title}>教学进度</h3>
      </div>

      <div className={styles.content}>
        {/* 会话 ID */}
        <div className={styles.card}>
          <span className={styles.cardLabel}>当前会话</span>
          <span className={styles.cardValue}>{currentProgress.sessionId}</span>
        </div>

        {/* 统计数据 */}
        <div className={styles.statGrid}>
          <div className={styles.statItem}>
            <span className={styles.statCount}>{currentProgress.totalIssues}</span>
            <span className={styles.statLabel}>总问题数</span>
          </div>
          <div className={styles.statItem}>
            <span className={styles.statCount}>{currentProgress.resolvedIssues}</span>
            <span className={styles.statLabel}>已解决</span>
          </div>
        </div>

        {/* 各状态计数 */}
        {Object.entries(statusCounts).length > 0 && (
          <div className={styles.card}>
            <span className={styles.cardLabel}>问题状态分布</span>
            <div className={styles.statGrid}>
              {Object.entries(statusCounts).map(([status, count]) => (
                <div key={status} className={styles.statItem}>
                  <span className={styles.statCount}>{count}</span>
                  <span className={styles.statLabel}>
                    {STATUS_LABEL[status] ?? status}
                  </span>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* 当前分组 */}
        {currentProgress.phaseGroup && (
          <div className={styles.card}>
            <span className={styles.cardLabel}>当前分组</span>
            <span className={styles.phaseTag}>{currentProgress.phaseGroup}</span>
          </div>
        )}

        {/* 展示状态 */}
        <div className={styles.card}>
          <span className={styles.cardLabel}>会话状态</span>
          <span className={styles.cardValue}>
            {DISPLAY_STATUS_LABEL[currentProgress.displayStatus] ??
              currentProgress.displayStatus}
          </span>
        </div>
      </div>
    </div>
  );
}
