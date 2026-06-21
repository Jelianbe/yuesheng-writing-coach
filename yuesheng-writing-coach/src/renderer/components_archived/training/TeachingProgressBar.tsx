/**
 * TeachingProgressBar — 右侧栏教学进度面板 (RWR-P1-5 / B-1)
 *
 * 依据 spec §4.2:
 *   - 位置: 右侧栏纵向时序进度 (非中间栏)
 *   - 0/N 数字 + 阶段分组 (认知→工具→技能)
 *   - 点击展开 ProgressTimeline (DoD: 不暴露诊断细节)
 *   - 分母只增不减
 *
 * 依赖: progress.store (P0-2 已就位) / panel-session.store
 */

import React, { useState, useCallback } from 'react';
import { ChevronDown, ChevronRight, BarChart3 } from 'lucide-react';
import { useProgressStore } from '../../stores/progress.store';
import { useSessionStore } from '../../stores/session.store';
import { ProgressTimeline } from './ProgressTimeline';
import styles from './TeachingProgressBar.module.css';

/** 阶段定义 (与 ProgressIssue.status 对应) */
const STAGE_LABELS: Record<'identified' | 'teaching' | 'mastered' | 'relapsed', string> = {
  identified: '认知',
  teaching: '工具',
  mastered: '技能',
  relapsed: '复发',
};

const STAGE_ORDER: Array<'identified' | 'teaching' | 'mastered' | 'relapsed'> = [
  'identified',
  'teaching',
  'mastered',
  'relapsed',
];

export const TeachingProgressBar: React.FC = () => {
  const currentSessionId = useSessionStore((s) => s.currentSessionId);
  const currentProgress = useProgressStore((s) => s.currentProgress);
  const [expanded, setExpanded] = useState(false);

  const handleToggle = useCallback(() => {
    setExpanded((prev) => !prev);
  }, []);

  // 0/N 数字 (分母只增不减, 从 progressMap 派生)
  const resolved = currentProgress?.resolvedIssues ?? 0;
  const total = currentProgress?.totalIssues ?? 0;
  const display = `${resolved}/${total}`;

  // 各阶段计数 (按 issues[].status 分组)
  const stageCounts = STAGE_ORDER.reduce<Record<string, number>>(
    (acc, stage) => {
      acc[stage] =
        currentProgress?.issues.filter((i) => i.status === stage).length ?? 0;
      return acc;
    },
    {}
  );

  // 当前指针: 第一个未 mastered 的 issue 阶段
  const currentPointer =
    currentProgress?.issues.find((i) => i.status !== 'mastered')?.status ?? null;

  return (
    <div className={styles.container}>
      <button
        className={styles.header}
        onClick={handleToggle}
        type="button"
        aria-expanded={expanded}
        aria-label="展开教学进度详情"
      >
        <div className={styles.headerLeft}>
          <BarChart3 size={14} strokeWidth={1.6} className={styles.headerIcon} />
          <span className={styles.headerTitle}>教学进度</span>
        </div>
        <div className={styles.headerRight}>
          <span className={styles.counter}>{display}</span>
          {expanded ? (
            <ChevronDown size={14} strokeWidth={1.6} />
          ) : (
            <ChevronRight size={14} strokeWidth={1.6} />
          )}
        </div>
      </button>

      {/* 阶段分组概览 (粗粒度, 不暴露细节) */}
      <div className={styles.phases} role="list" aria-label="教学阶段">
        {STAGE_ORDER.filter((s) => s !== 'relapsed').map((stage) => (
          <div
            key={stage}
            className={`${styles.phaseGroup} ${
              currentPointer === stage ? styles.phaseGroupActive : ''
            }`}
            role="listitem"
            aria-current={currentPointer === stage ? 'step' : undefined}
          >
            <span className={styles.phaseName}>{STAGE_LABELS[stage]}</span>
            <span className={styles.phaseCount}>{stageCounts[stage]}</span>
          </div>
        ))}
      </div>

      {expanded && <ProgressTimeline sessionId={currentSessionId} />}
    </div>
  );
};
