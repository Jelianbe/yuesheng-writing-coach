/**
 * BeatCheckChart — SF-004 场景分布迷你图表
 *
 * 展示叙事节拍完整性检测结果（来自 DiagnosisAnalysis.beatCheck）。
 * 纯 CSS 实现，无外部图表依赖。
 * 绿条 = 节拍存在，灰条 = 节拍缺失。
 */
import React from 'react';
import { BarChart3 } from 'lucide-react';
import styles from './BeatCheckChart.module.css';

/** 标准叙事节拍的中文标签映射 */
const BEAT_LABELS: Record<string, string> = {
  opening_hook: '开篇钩子',
  inciting_incident: '激励事件',
  midpoint_twist: '中点转折',
  climax: '高潮',
  resolution: '结局',
};

/** 节拍显示顺序 */
const BEAT_ORDER = ['opening_hook', 'inciting_incident', 'midpoint_twist', 'climax', 'resolution'];

interface BeatCheckChartProps {
  /** beatCheck 数据（来自诊断结果） */
  beatCheck: Record<string, boolean>;
}

export const BeatCheckChart: React.FC<BeatCheckChartProps> = ({ beatCheck }) => {
  const entries = BEAT_ORDER
    .filter((key) => key in beatCheck)
    .map((key) => ({
      key,
      label: BEAT_LABELS[key] ?? key,
      present: beatCheck[key],
    }));

  if (entries.length === 0) return null;

  const presentCount = entries.filter((e) => e.present).length;
  const totalCount = entries.length;
  const completionRate = totalCount > 0 ? Math.round((presentCount / totalCount) * 100) : 0;

  return (
    <div className={styles.container}>
      {/* Header */}
      <div className={styles.header}>
        <BarChart3 className={styles.headerIcon} />
        <span className={styles.headerText}>叙事节拍完整性</span>
        <span className={styles.headerCount}>
          {presentCount}/{totalCount} ({completionRate}%)
        </span>
      </div>

      {/* Chart body */}
      <div className={styles.body}>
        {entries.map(({ key, label, present }) => (
          <div key={key} className={styles.row}>
            {/* Label */}
            <span className={styles.label}>
              {label}
            </span>
            {/* Bar track */}
            <div className={styles.barTrack}>
              <div
                className={present ? styles.barFillPresent : styles.barFillMissing}
                style={{
                  width: present ? '100%' : '8%',
                  minWidth: present ? undefined : '8px',
                }}
              />
            </div>
            {/* Status indicator */}
            <span className={present ? styles.statusPresent : styles.statusMissing}>
              {present ? '✓' : '—'}
            </span>
          </div>
        ))}

        {/* Legend / hint */}
        <p className={styles.hint}>
          检测文本是否包含标准的叙事节拍。缺失的节拍可能意味着节奏问题。
        </p>
      </div>
    </div>
  );
}
