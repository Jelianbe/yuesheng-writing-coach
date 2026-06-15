import React from 'react';

interface SyndromeTrendData {
  name: string;
  status: 'mastered' | 'improving' | 'stable' | 'needsAttention';
  occurrenceCount: number;
  description: string;
}

const STATUS_CONFIG: Record<string, { label: string; color: string; bgColor: string }> = {
  mastered: { label: '已掌握', color: '#5B8C5A', bgColor: '#5B8C5A18' },
  improving: { label: '改善中', color: '#D4A04A', bgColor: '#D4A04A18' },
  stable: { label: '稳定', color: '#6B8FA3', bgColor: '#6B8FA318' },
  needsAttention: { label: '需关注', color: '#C0392B', bgColor: '#C0392B18' },
};

interface TrendChartProps {
  data: SyndromeTrendData[];
}

/** 简化趋势线 - svg 柱状/折线图 */
export const TrendChart: React.FC<TrendChartProps> = ({ data }) => {
  if (data.length === 0) return null;

  const sorted = [...data].sort((a, b) => b.occurrenceCount - a.occurrenceCount).slice(0, 8);
  const maxOcc = Math.max(...sorted.map(d => d.occurrenceCount), 1);
  const barWidth = Math.max(20, Math.min(36, 280 / sorted.length));

  return (
    <div style={{ width: '100%', overflow: 'hidden' }}>
      <svg
        width="100%"
        height="100"
        viewBox={`0 0 ${sorted.length * (barWidth + 8) + 20} 100`}
        style={{ display: 'block' }}
      >
        {/* 网格线 */}
        <line x1="10" y1="90" x2={sorted.length * (barWidth + 8) + 10} y2="90" stroke="var(--border-light)" strokeWidth="1" />
        <line x1="10" y1="50" x2={sorted.length * (barWidth + 8) + 10} y2="50" stroke="var(--border-light)" strokeWidth="0.5" strokeDasharray="3,3" />

        {/* 柱状条 */}
        {sorted.map((item, i) => {
          const x = 10 + i * (barWidth + 8);
          const h = (item.occurrenceCount / maxOcc) * 60;
          const y = 90 - h;
          const color = STATUS_CONFIG[item.status]?.color || 'var(--text-tertiary)';
          return (
            <g key={item.name}>
              <rect
                x={x}
                y={y}
                width={barWidth}
                height={h}
                rx={3}
                fill={color}
                opacity={0.75}
              >
                <title>{item.name}: {item.occurrenceCount} 次 ({STATUS_CONFIG[item.status]?.label || item.status})</title>
              </rect>
              <text
                x={x + barWidth / 2}
                y={98}
                textAnchor="middle"
                fill="var(--text-tertiary)"
                fontSize="8"
                fontFamily="var(--font-body)"
              >
                {item.name.length > 4 ? item.name.slice(0, 3) + '..' : item.name}
              </text>
            </g>
          );
        })}
      </svg>
    </div>
  );
};
