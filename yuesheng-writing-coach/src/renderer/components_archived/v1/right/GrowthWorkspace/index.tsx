/**
 * GrowthWorkspace — 成长工作区
 *
 * 使用 useTeachingStateStore + useProgressStore 显示成长数据：
 * 会话次数、当前模式、活跃阶段、训练次数。
 *
 * 用法:
 * ```tsx
 * <GrowthWorkspace />
 * ```
 */
import { useMemo } from 'react';
import { useTeachingStateStore } from '@/stores/teaching-state.store';
import { useProgressStore } from '@/stores/progress.store';
import styles from './index.module.css';

/** 阶段名称中文映射 */
const PHASE_LABEL: Record<string, string> = {
  P0_INIT: '初次见面',
  P1_WORLD: '世界观搭建',
  P2_PRACTICE_LOOP: '诊断与训练',
  P4_REVIEW: '复盘总结',
};

/** 当前阶段 → 模式映射 */
const PHASE_TO_MODE: Record<string, string> = {
  P0_INIT: 'diagnosis',
  P1_WORLD: 'teaching',
  P2_PRACTICE_LOOP: 'training',
  P4_REVIEW: 'review',
};

/** 模式中文映射 */
const MODE_LABEL: Record<string, string> = {
  diagnosis: '诊断模式',
  teaching: '教学模式',
  training: '训练模式',
  review: '复习模式',
};

export function GrowthWorkspace(): JSX.Element {
  const currentState = useTeachingStateStore((s) => s.currentState);
  const progressMap = useProgressStore((s) => s.progressMap);

  const sessionCount = useMemo(
    () => Object.keys(progressMap).length,
    [progressMap],
  );

  const activeProblems = currentState?.activeProblems ?? [];
  const currentPhase = currentState?.currentPhase ?? '';
  const currentSubphase = currentState?.currentSubphase ?? '';
  const mode = PHASE_TO_MODE[currentPhase] ?? 'diagnosis';

  const hasData = sessionCount > 0 || Boolean(currentState);

  if (!hasData) {
    return (
      <div className={styles.container}>
        <div className={styles.header}>
          <h3 className={styles.title}>成长记录</h3>
        </div>
        <div className={styles.emptyState}>
          <span className={styles.emptyIcon} aria-hidden="true">{'\uD83D\uDCC8'}</span>
          <p className={styles.emptyText}>暂无成长数据</p>
        </div>
      </div>
    );
  }

  return (
    <div className={styles.container}>
      {/* 标题区 */}
      <div className={styles.header}>
        <h3 className={styles.title}>成长记录</h3>
      </div>

      <div className={styles.content}>
        {/* 会话次数 */}
        <div className={styles.statGrid}>
          <div className={styles.statItem}>
            <span className={styles.statCount}>{sessionCount}</span>
            <span className={styles.statLabel}>会话次数</span>
          </div>
          <div className={styles.statItem}>
            <span className={styles.statCount}>{activeProblems.length}</span>
            <span className={styles.statLabel}>活跃问题</span>
          </div>
        </div>

        {/* 当前模式 */}
        <div className={styles.card}>
          <span className={styles.cardLabel}>当前模式</span>
          <span className={styles.modeTag}>{MODE_LABEL[mode] ?? mode}</span>
        </div>

        {/* 活跃阶段 */}
        {currentPhase && (
          <div className={styles.card}>
            <span className={styles.cardLabel}>活跃阶段</span>
            <span className={styles.cardValue}>
              {PHASE_LABEL[currentPhase] ?? currentPhase}
            </span>
          </div>
        )}

        {/* 当前子阶段 */}
        {currentSubphase && (
          <div className={styles.card}>
            <span className={styles.cardLabel}>当前子阶段</span>
            <span className={styles.cardValue}>{currentSubphase}</span>
          </div>
        )}

        {/* 训练记录数 */}
        {sessionCount > 0 && (
          <div className={styles.card}>
            <span className={styles.cardLabel}>训练记录</span>
            <span className={styles.cardValue}>{sessionCount} 次训练</span>
          </div>
        )}
      </div>
    </div>
  );
}
