/**
 * ProjectSpacePage — 项目空间
 *
 * 对齐设计稿：
 * - Navbar: ‹ 返回 + 项目标题 + ⋯
 * - 统计区（诊断/训练/学习天数）
 * - SVG 雷达图（五维能力）
 * - CTA 按钮 + 最近记录
 */

import React from 'react';
import { ArrowLeft, Book, FileText, MessageSquare } from 'lucide-react';
import { usePageStackStore } from '../stores/page-stack.store';
import { MoreMenu } from '../components/navigation/MoreMenu';

const RADAR_LABELS = ['人物塑造', '情节节奏', '环境描写', '对话设计', '叙事视角'];
const RADAR_VALUES = [4, 3, 5, 2, 4]; // 1-5
const RADAR_SIZE = 140;
const CENTER = RADAR_SIZE / 2;
const RADIUS = RADAR_SIZE * 0.38;
const LEVELS = 5;

function RadarChart() {
  const angleStep = (Math.PI * 2) / RADAR_LABELS.length;
  // 生成网格点
  const gridPoints = Array.from({ length: LEVELS }).map((_, level) => {
    const r = (RADIUS / LEVELS) * (level + 1);
    return RADAR_LABELS.map((_, i) => {
      const a = angleStep * i - Math.PI / 2;
      return `${CENTER + r * Math.cos(a)},${CENTER + r * Math.sin(a)}`;
    }).join(' ');
  });

  // 数据点
  const dataPoints = RADAR_VALUES.map((v, i) => {
    const r = (RADIUS / 5) * v;
    const a = angleStep * i - Math.PI / 2;
    return `${CENTER + r * Math.cos(a)},${CENTER + r * Math.sin(a)}`;
  }).join(' ');

  // 标签位置
  const labelPositions = RADAR_LABELS.map((_, i) => {
    const a = angleStep * i - Math.PI / 2;
    const r = RADIUS + 18;
    return { x: CENTER + r * Math.cos(a), y: CENTER + r * Math.sin(a) };
  });

  return (
    <svg width={RADAR_SIZE} height={RADAR_SIZE} viewBox={`0 0 ${RADAR_SIZE} ${RADAR_SIZE}`}>
      {/* 网格 */}
      {gridPoints.map((pts, i) => (
        <polygon key={i} points={pts} fill="none" stroke="var(--border)" strokeWidth={0.8} />
      ))}
      {/* 轴线 */}
      {RADAR_LABELS.map((_, i) => {
        const a = angleStep * i - Math.PI / 2;
        return (
          <line
            key={i}
            x1={CENTER} y1={CENTER}
            x2={CENTER + RADIUS * Math.cos(a)} y2={CENTER + RADIUS * Math.sin(a)}
            stroke="var(--border)" strokeWidth={0.8}
          />
        );
      })}
      {/* 数据 */}
      <polygon points={dataPoints} fill="rgba(138,122,158,0.25)" stroke="var(--accent)" strokeWidth={1.5} />
      {RADAR_VALUES.map((v, i) => {
        const r = (RADIUS / 5) * v;
        const a = angleStep * i - Math.PI / 2;
        return (
          <circle key={i} cx={CENTER + r * Math.cos(a)} cy={CENTER + r * Math.sin(a)} r={2.5} fill="var(--accent)" />
        );
      })}
      {/* 标签 */}
      {labelPositions.map((pos, i) => (
        <text
          key={i}
          x={pos.x} y={pos.y}
          textAnchor="middle" dominantBaseline="middle"
          fill="var(--text-secondary)" fontSize={8}
        >
          {RADAR_LABELS[i]}
        </text>
      ))}
    </svg>
  );
}

const RECENT_RECORDS = [
  { type: '诊断', label: '人物动机分析', time: '2天前' },
  { type: '训练', label: '对话写作练习', time: '4天前' },
  { type: '教学', label: '环境描写技法学习', time: '1周前' },
];

const CHAPTERS = [
  { title: '第一章：初遇', status: '已完成' },
  { title: '第二章：暗流', status: '修改中' },
  { title: '第三章：抉择', status: '未开始' },
];

export const ProjectSpacePage: React.FC<{ params?: Record<string, string> }> = ({ params }) => {
  const pop = usePageStackStore(s => s.pop);
  const push = usePageStackStore(s => s.push);
  const title = params?.title ?? '深海回响';

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      {/* Navbar */}
      <div style={{
        height: 52, display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '0 12px', borderBottom: '1px solid var(--border)',
        background: 'var(--bg-card)',
      }}>
        <button onClick={pop} style={{ border: 'none', background: 'none', cursor: 'pointer', padding: 4 }}>
          <ArrowLeft size={20} color="var(--text-primary)" />
        </button>
        <span style={{ fontSize: 16, fontWeight: 600, color: 'var(--text-primary)' }}>{title}</span>
        <MoreMenu options={[
          { label: '新建对话', icon: <MessageSquare size={16} />, onClick: () => push('chat', { title }) },
          { label: '项目设置', icon: <FileText size={16} />, onClick: () => {/* Phase C: 项目设置页 */} },
        ]} />
      </div>

      {/* 内容 */}
      <div style={{ flex: 1, overflow: 'auto', padding: '0 16px 16px' }}>
        {/* 统计区 */}
        <div style={{
          display: 'flex', gap: 8, marginTop: 16, marginBottom: 20,
        }}>
          {[
            { label: '诊断', value: '6', color: 'var(--color-teaching)' },
            { label: '训练', value: '4', color: 'var(--color-practice)' },
            { label: '学习天', value: '23', color: 'var(--color-growth)' },
          ].map(s => (
            <div key={s.label} style={{
              flex: 1, textAlign: 'center', padding: '10px 0',
              background: 'var(--bg-card)', borderRadius: 12,
              border: '1px solid var(--border)',
            }}>
              <div style={{ fontSize: 20, fontWeight: 700, color: s.color }}>{s.value}</div>
              <div style={{ fontSize: 11, color: 'var(--text-tertiary)', marginTop: 2 }}>{s.label}</div>
            </div>
          ))}
        </div>

        {/* 雷达图 */}
        <div style={{
          display: 'flex', justifyContent: 'center', marginBottom: 20,
        }}>
          <RadarChart />
        </div>

        {/* CTA 按钮 */}
        <button
          onClick={() => push('chat', { projectId: params?.id ?? '', title })}
          style={{
            width: '100%', padding: '12px 0', border: 'none', borderRadius: 12,
            background: 'linear-gradient(135deg, var(--accent), #6E5E82)',
            color: '#fff', fontSize: 15, fontWeight: 600, cursor: 'pointer',
            boxShadow: '0 4px 16px rgba(138,122,158,0.3)',
            marginBottom: 20,
          }}
        >
          开始新的学习
        </button>

        {/* 最近学习记录 */}
        <div style={{ marginBottom: 16 }}>
          <div style={{ fontSize: 13, fontWeight: 500, color: 'var(--text-secondary)', marginBottom: 8 }}>
            最近学习
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {RECENT_RECORDS.map(r => {
              const colorMap: Record<string, string> = {
                '诊断': 'var(--color-teaching)',
                '训练': 'var(--color-practice)',
                '教学': 'var(--accent)',
              };
              return (
                <div key={r.label} style={{
                  display: 'flex', alignItems: 'center', gap: 10,
                  padding: '10px 12px', background: 'var(--bg-card)', borderRadius: 10,
                  border: '1px solid var(--border)',
                }}>
                  <span style={{
                    fontSize: 10, fontWeight: 600, color: '#fff',
                    background: colorMap[r.type] ?? 'var(--accent)',
                    padding: '2px 6px', borderRadius: 4,
                  }}>
                    {r.type}
                  </span>
                  <span style={{ flex: 1, fontSize: 13, color: 'var(--text-primary)' }}>{r.label}</span>
                  <span style={{ fontSize: 11, color: 'var(--text-tertiary)' }}>{r.time}</span>
                </div>
              );
            })}
          </div>
        </div>

        {/* 作品章节 */}
        <div>
          <div style={{ fontSize: 13, fontWeight: 500, color: 'var(--text-secondary)', marginBottom: 8 }}>
            作品章节
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', borderRadius: 10, border: '1px solid var(--border)', overflow: 'hidden' }}>
            {CHAPTERS.map((ch, i) => (
              <div key={ch.title} style={{
                display: 'flex', alignItems: 'center', gap: 10,
                padding: '10px 12px',
                borderBottom: i < CHAPTERS.length - 1 ? '1px solid var(--border)' : 'none',
              }}>
                <Book size={16} color="var(--text-tertiary)" strokeWidth={1.5} />
                <span style={{ flex: 1, fontSize: 13, color: 'var(--text-primary)' }}>{ch.title}</span>
                <span style={{
                  fontSize: 11, color: ch.status === '已完成' ? 'var(--color-growth)' : ch.status === '修改中' ? 'var(--color-practice)' : 'var(--text-tertiary)',
                }}>
                  {ch.status}
                </span>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
};
