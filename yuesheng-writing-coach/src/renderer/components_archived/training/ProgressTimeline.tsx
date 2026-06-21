/**
 * ProgressTimeline — 教学进度时间线 (RWR-P1-5 / B-1)
 *
 * 依据 spec §4.2: 按 teachingStage 分组 (认知→工具→技能)
 * DoD: 不暴露诊断细节 (不显示 syndromeId, 仅显示 label)
 */

import React from 'react';
import { useProgressStore } from '../../stores/progress.store';
import styles from './TeachingProgressBar.module.css';

interface ProgressTimelineProps {
  sessionId: string | null;
}

/** 阶段定义 (与 TeachingProgressBar 对齐) */
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

export const ProgressTimeline: React.FC<ProgressTimelineProps> = ({ sessionId }) => {
  const progress = useProgressStore((s) =>
    sessionId ? s.progressMap[sessionId] : null
  );

  if (!progress || progress.issues.length === 0) {
    return (
      <div className={styles.timelineEmpty} role="status">
        暂无教学进度
      </div>
    );
  }

  // 按 status 分组
  const groups: Record<string, typeof progress.issues> = {};
  for (const issue of progress.issues) {
    if (!groups[issue.status]) groups[issue.status] = [];
    groups[issue.status].push(issue);
  }

  return (
    <div className={styles.timeline} role="region" aria-label="教学进度时间线">
      {STAGE_ORDER.filter((stage) => groups[stage] && groups[stage].length > 0).map(
        (stage) => (
          <div key={stage} className={styles.timelineStage}>
            <h4 className={styles.timelineStageTitle}>
              {STAGE_LABELS[stage]} ({groups[stage].length})
            </h4>
            <ul className={styles.timelineList}>
              {groups[stage].map((issue) => (
                <li key={issue.syndromeId} className={styles.timelineItem}>
                  <span className={styles.timelineLabel}>{issue.label}</span>
                </li>
              ))}
            </ul>
          </div>
        )
      )}
    </div>
  );
};
