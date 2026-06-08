/**
 * BeatCheckChart — SF-004 场景分布迷你图表
 *
 * 展示叙事节拍完整性检测结果（来自 DiagnosisAnalysis.beatCheck）。
 * 纯 CSS 实现，无外部图表依赖。
 * 绿条 = 节拍存在，灰条 = 节拍缺失。
 */
import React from 'react';
import { BarChart3 } from 'lucide-react';

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
    <div className="border border-border rounded-[var(--radius-sm)] overflow-hidden">
      {/* Header */}
      <div className="px-3 py-2 bg-bg-tertiary/50 border-b border-border flex items-center gap-2">
        <BarChart3 className="w-3.5 h-3.5 text-accent-primary" />
        <span className="text-xs font-medium text-text-secondary">叙事节拍完整性</span>
        <span className="text-xs text-text-tertiary ml-auto">
          {presentCount}/{totalCount} ({completionRate}%)
        </span>
      </div>

      {/* Chart body */}
      <div className="px-3 py-2.5 space-y-2">
        {entries.map(({ key, label, present }) => (
          <div key={key} className="flex items-center gap-2">
            {/* Label */}
            <span className="text-xs text-text-secondary w-16 flex-shrink-0 text-right">
              {label}
            </span>
            {/* Bar track */}
            <div className="flex-1 h-4 bg-bg-tertiary rounded-full overflow-hidden">
              <div
                className={`h-full rounded-full transition-all duration-500 ease-out ${
                  present ? 'bg-accent-success' : 'bg-text-muted/30'
                }`}
                style={{
                  width: present ? '100%' : '8%',
                  minWidth: present ? undefined : '8px',
                }}
              />
            </div>
            {/* Status indicator */}
            <span className={`text-xs w-6 flex-shrink-0 ${
              present ? 'text-accent-success' : 'text-text-muted'
            }`}>
              {present ? '✓' : '—'}
            </span>
          </div>
        ))}

        {/* Legend / hint */}
        <p className="text-[10px] text-text-muted pt-1 leading-tight">
          检测文本是否包含标准的叙事节拍。缺失的节拍可能意味着节奏问题。
        </p>
      </div>
    </div>
  );
};

export default BeatCheckChart;
