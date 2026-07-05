/**
 * ProjectSpacePage — 项目空间
 *
 * 移动端布局:
 * - Navbar: ‹ 返回 + 项目标题 + ⋯
 * - 统计区(诊断/训练/学习天数) — 3 列卡片
 * - SVG 雷达图(五维能力, 200×200)
 * - CTA 按钮(扁平样式) + 最近记录
 * - 作品章节(chip 化状态)
 *
 * 数据来源:
 * - useProjectStore (按 params.id 查 project 元数据)
 * - 雷达图当前为占位 mock — D-DEBT-30 待 ID 路由改造后接入 ability.store
 */

import React, { useEffect } from 'react';
import { ArrowLeft, Book, FileText, MessageSquare, BookOpen, Target, Sparkles } from 'lucide-react';
import { useShallow } from 'zustand/react/shallow';
import { usePageStackStore } from '../stores/page-stack.store';
import { useProjectStore } from '../stores/project.store';
import { MoreMenu } from '../components/navigation/MoreMenu';

const RADAR_LABELS = ['人物塑造', '情节节奏', '环境描写', '对话设计', '叙事视角'];
const RADAR_VALUES = [4, 3, 5, 2, 4]; // 1-5 - D-DEBT-30 待 ability store 接入后替换
const RADAR_SIZE = 200;
const CENTER = RADAR_SIZE / 2;
const RADIUS = RADAR_SIZE * 0.36;
const LEVELS = 5;

function RadarChart() {
  const angleStep = (Math.PI * 2) / RADAR_LABELS.length;
  const gridPoints = Array.from({ length: LEVELS }).map((_, level) => {
    const r = (RADIUS / LEVELS) * (level + 1);
    return RADAR_LABELS.map((_, i) => {
      const a = angleStep * i - Math.PI / 2;
      return `${CENTER + r * Math.cos(a)},${CENTER + r * Math.sin(a)}`;
    }).join(' ');
  });

  const dataPoints = RADAR_VALUES.map((v, i) => {
    const r = (RADIUS / 5) * v;
    const a = angleStep * i - Math.PI / 2;
    return `${CENTER + r * Math.cos(a)},${CENTER + r * Math.sin(a)}`;
  }).join(' ');

  const labelPositions = RADAR_LABELS.map((_, i) => {
    const a = angleStep * i - Math.PI / 2;
    const r = RADIUS + 14;
    return { x: CENTER + r * Math.cos(a), y: CENTER + r * Math.sin(a) };
  });

  return (
    <svg width={RADAR_SIZE} height={RADAR_SIZE} viewBox={`0 0 ${RADAR_SIZE} ${RADAR_SIZE}`}>
      {gridPoints.map((pts, i) => (
        <polygon key={i} points={pts} fill="none" stroke="var(--border)" strokeWidth={0.6} />
      ))}
      {RADAR_LABELS.map((_, i) => {
        const a = angleStep * i - Math.PI / 2;
        return (
          <line
            key={i}
            x1={CENTER} y1={CENTER}
            x2={CENTER + RADIUS * Math.cos(a)} y2={CENTER + RADIUS * Math.sin(a)}
            stroke="var(--border)" strokeWidth={0.6}
          />
        );
      })}
      <polygon points={dataPoints} fill="rgba(138,122,158,0.22)" stroke="var(--accent)" strokeWidth={1.5} />
      {RADAR_VALUES.map((v, i) => {
        const r = (RADIUS / 5) * v;
        const a = angleStep * i - Math.PI / 2;
        return (
          <circle key={i} cx={CENTER + r * Math.cos(a)} cy={CENTER + r * Math.sin(a)} r={2.5} fill="var(--accent)" />
        );
      })}
      {labelPositions.map((pos, i) => (
        <text
          key={i}
          x={pos.x} y={pos.y}
          textAnchor="middle" dominantBaseline="middle"
          fill="var(--text-secondary)" fontSize={9}
        >
          {RADAR_LABELS[i]}
        </text>
      ))}
    </svg>
  );
}

// D-DEBT-31 暂无 activity/history store 接入,保留占位
const RECENT_RECORDS = [
  { type: '诊断', label: '人物动机分析', time: '2天前' },
  { type: '训练', label: '对话写作练习', time: '4天前' },
  { type: '教学', label: '环境描写技法学习', time: '1周前' },
];

// D-DEBT-30 章节需 manuscriptId 列表,project 概念不直接对应,占位
const CHAPTERS = [
  { title: '第一章：初遇', status: 'done' as const },
  { title: '第二章：暗流', status: 'editing' as const },
  { title: '第三章：抉择', status: 'todo' as const },
];

const STATUS_MAP = {
  done: { label: '已完成', bg: 'var(--color-growth-light)', color: 'var(--color-growth)' },
  editing: { label: '修改中', bg: 'var(--color-practice-light)', color: 'var(--color-practice)' },
  todo: { label: '未开始', bg: 'var(--bg-input)', color: 'var(--text-tertiary)' },
} as const;

export const ProjectSpacePage: React.FC<{ params?: Record<string, string> }> = ({ params }) => {
  const pop = usePageStackStore(s => s.pop);
  const push = usePageStackStore(s => s.push);
  const { projects, fetchList, fetchById, currentProject } = useProjectStore(
    useShallow(s => ({
      projects: s.projects,
      fetchList: s.fetchList,
      fetchById: s.fetchById,
      currentProject: s.projects.find(p => p.id === params?.id),
    })),
  );
  const title = currentProject?.name ?? params?.title ?? '项目空间';
  const stats = [
    { label: '诊断', value: '—', Icon: BookOpen, color: 'var(--color-teaching)' },
    { label: '训练', value: '—', Icon: Target, color: 'var(--color-practice)' },
    { label: '学习天', value: '—', Icon: Sparkles, color: 'var(--color-growth)' },
  ];

  useEffect(() => {
    if (projects.length === 0) {
      void fetchList();
    }
    if (params?.id && !currentProject) {
      void fetchById(params.id);
    }
  }, [params?.id, projects.length, fetchList, fetchById, currentProject]);

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      {/* Navbar */}
      <div style={{
        height: 52, display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '0 12px', borderBottom: '1px solid var(--border)',
        background: 'var(--bg-card)',
      }}>
        <button onClick={pop} aria-label="返回" style={{ border: 'none', background: 'none', cursor: 'pointer', padding: 4 }}>
          <ArrowLeft size={20} color="var(--text-primary)" />
        </button>
        <span style={{ fontSize: 16, fontWeight: 600, color: 'var(--text-primary)' }}>{title}</span>
        <MoreMenu options={[
          { label: '新建对话', icon: <MessageSquare size={16} />, onClick: () => push('chat', { title }) },
          { label: '项目设置', icon: <FileText size={16} />, onClick: () => {/* Phase C: 项目设置页 */} },
        ]} />
      </div>

      {/* 内容 */}
      <div style={{ flex: 1, overflow: 'auto', padding: '12px 16px 16px' }}>
        {/* 统计区 — 3 列卡片(每列带图标) */}
        <div style={{ display: 'flex', gap: 8, marginTop: 4, marginBottom: 16 }}>
          {stats.map(s => (
            <div key={s.label} style={{
              flex: 1, padding: '10px 6px', textAlign: 'center',
              background: 'var(--bg-card)', borderRadius: 10,
              border: '1px solid var(--border)',
            }}>
              <s.Icon size={16} color={s.color} strokeWidth={1.5} style={{ marginBottom: 4 }} />
              <div style={{ fontSize: 18, fontWeight: 700, color: s.color, lineHeight: 1.2 }}>{s.value}</div>
              <div style={{ fontSize: 10, color: 'var(--text-tertiary)', marginTop: 2 }}>{s.label}</div>
            </div>
          ))}
        </div>

        {/* 雷达图 */}
        <div style={{
          display: 'flex', justifyContent: 'center', marginBottom: 12,
        }}>
          <RadarChart />
        </div>

        {/* CTA 按钮 — 扁平样式 */}
        <button
          onClick={() => push('chat', { projectId: params?.id ?? '', title })}
          style={{
            width: '100%', padding: '13px 0', border: 'none', borderRadius: 12,
            background: 'var(--accent)', color: '#fff', fontSize: 15, fontWeight: 600,
            cursor: 'pointer', marginBottom: 18,
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

        {/* 作品章节 — chip 化状态 */}
        <div>
          <div style={{ fontSize: 13, fontWeight: 500, color: 'var(--text-secondary)', marginBottom: 8 }}>
            作品章节
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', borderRadius: 10, border: '1px solid var(--border)', overflow: 'hidden' }}>
            {CHAPTERS.map((ch, i) => {
              const s = STATUS_MAP[ch.status];
              return (
                <div key={ch.title} style={{
                  display: 'flex', alignItems: 'center', gap: 10,
                  padding: '10px 12px',
                  borderBottom: i < CHAPTERS.length - 1 ? '1px solid var(--border)' : 'none',
                }}>
                  <Book size={16} color="var(--text-tertiary)" strokeWidth={1.5} />
                  <span style={{ flex: 1, fontSize: 13, color: 'var(--text-primary)' }}>{ch.title}</span>
                  <span style={{
                    fontSize: 10, fontWeight: 600,
                    background: s.bg, color: s.color,
                    padding: '2px 8px', borderRadius: 10,
                  }}>
                    {s.label}
                  </span>
                </div>
              );
            })}
          </div>
        </div>
      </div>
    </div>
  );
};
