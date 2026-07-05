/**
 * ProjectSpacePage — 项目空间
 *
 * 移动端布局:
 * - Navbar: ‹ 返回 + 项目标题 + ⋯
 * - 统计区(诊断/训练/症候) — 3 列卡片
 * - SVG 雷达图(五维能力, 200×200)
 * - CTA 按钮(扁平样式) + 最近记录
 * - 作品章节(chip 化状态)
 *
 * 数据来源:
 * - useProjectStore (按 params.id 查 project 元数据)
 * - useAbilityStore (按 params.sessionId 查能力画像,可选)
 *
 * Sprint 33 (C-2): 替换 mock 数据,接入 ability.store
 * Sprint 34: 统计卡片读取 diagnosisTrend/trainingStats 真实数据
 *           雷达图从 abilities[].abilityName 直接映射(替换关键词匹配)
 */

import React, { useEffect, useState } from 'react';
import { ArrowLeft, FileText, MessageSquare, BookOpen, Target, Sparkles } from 'lucide-react';
import { useShallow } from 'zustand/react/shallow';
import { usePageStackStore } from '../stores/page-stack.store';
import { useProjectStore } from '../stores/project.store';
import { useAbilityStore } from '../stores/ability.store';
import { MoreMenu } from '../components/navigation/MoreMenu';
import type { AbilityProfile } from '../../shared/api-contracts/ability.contract';

const RADAR_LABELS = ['人物塑造', '情节节奏', '环境描写', '对话设计', '叙事视角'] as const;
const RADAR_SIZE = 200;
const CENTER = RADAR_SIZE / 2;
const RADIUS = RADAR_SIZE * 0.36;
const LEVELS = 5;

/**
 * 从 ability profile 提取 5 维雷达值
 * 映射规则: abilities[].abilityName 直接匹配 RADAR_LABELS
 * score 为 0-100,雷达图期望 0-5 范围,除以 20 归一化
 */
function extractAbilityRadarValues(profile: AbilityProfile | null): number[] {
  if (!profile?.abilities?.length) return [];
  const result = new Array(RADAR_LABELS.length).fill(0);
  for (const a of profile.abilities) {
    const idx = RADAR_LABELS.indexOf(a.abilityName as (typeof RADAR_LABELS)[number]);
    if (idx >= 0) result[idx] = Math.round(a.score / 20);
  }
  return result;
}

function RadarChart({ values }: { values: number[] }) {
  const angleStep = (Math.PI * 2) / RADAR_LABELS.length;
  const gridPoints = Array.from({ length: LEVELS }).map((_, level) => {
    const r = (RADIUS / LEVELS) * (level + 1);
    return RADAR_LABELS.map((_, i) => {
      const a = angleStep * i - Math.PI / 2;
      return `${CENTER + r * Math.cos(a)},${CENTER + r * Math.sin(a)}`;
    }).join(' ');
  });

  const hasData = values.length === RADAR_LABELS.length && values.some(v => v > 0);
  const dataPoints = hasData
    ? values.map((v, i) => {
        const r = (RADIUS / 5) * v;
        const a = angleStep * i - Math.PI / 2;
        return `${CENTER + r * Math.cos(a)},${CENTER + r * Math.sin(a)}`;
      }).join(' ')
    : '';

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
      {hasData && (
        <>
          <polygon points={dataPoints} fill="var(--accent)" fillOpacity={0.22} stroke="var(--accent)" strokeWidth={1.5} />
          {values.map((v, i) => {
            const r = (RADIUS / 5) * v;
            const a = angleStep * i - Math.PI / 2;
            return (
              <circle key={i} cx={CENTER + r * Math.cos(a)} cy={CENTER + r * Math.sin(a)} r={2.5} fill="var(--accent)" />
            );
          })}
        </>
      )}
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
  const { profile, loading: abilityLoading, fetchProfile } = useAbilityStore(
    useShallow(s => ({
      profile: s.profile,
      loading: s.loading,
      fetchProfile: s.fetchProfile,
    })),
  );
  const title = currentProject?.name ?? params?.title ?? '项目空间';
  const [radarValues, setRadarValues] = useState<number[]>([]);

  // Sprint 34: 从 ability profile 读取真实统计数据
  const stats = [
    {
      label: '诊断',
      value: String(profile?.diagnosisTrend?.totalDiagnoses ?? '0'),
      Icon: BookOpen,
      color: 'var(--color-teaching)',
    },
    {
      label: '训练',
      value: String(profile?.trainingStats?.totalCompleted ?? '0'),
      Icon: Target,
      color: 'var(--color-practice)',
    },
    {
      label: '症候',
      value: String(
        profile?.diagnosisTrend?.syndromeFrequency
          ? Object.keys(profile.diagnosisTrend.syndromeFrequency).length
          : '0',
      ),
      Icon: Sparkles,
      color: 'var(--color-growth)',
    },
  ];

  useEffect(() => {
    if (projects.length === 0) {
      void fetchList();
    }
    if (params?.id && !currentProject) {
      void fetchById(params.id);
    }
  }, [params?.id, projects.length, fetchList, fetchById, currentProject]);

  // C-2: 当 params.sessionId 存在时,从 ability.store 获取真实能力画像
  useEffect(() => {
    const sessionId = params?.sessionId;
    if (!sessionId) return;
    void fetchProfile(sessionId);
  }, [params?.sessionId, fetchProfile]);

  // Sprint 34: profile 更新时从 abilities 提取雷达值
  useEffect(() => {
    setRadarValues(extractAbilityRadarValues(profile));
  }, [profile]);

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
          { label: '项目设置', icon: <FileText size={16} />, onClick: () => {/* Phase C: 项目设置页 */}, disabled: true },
        ]} />
      </div>

      {/* 内容 */}
      <div style={{ flex: 1, overflow: 'auto', padding: '12px 16px 16px' }}>
        {/* 统计区 — 3 列卡片 */}
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
          position: 'relative',
        }}>
          {abilityLoading ? (
            <div style={{
              width: RADAR_SIZE, height: RADAR_SIZE,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              fontSize: 12, color: 'var(--text-tertiary)',
            }}>
              加载中…
            </div>
          ) : (
            <>
              <RadarChart values={radarValues} />
              {radarValues.length === 0 && (
                <div style={{
                  position: 'absolute', bottom: 4, left: 0, right: 0,
                  textAlign: 'center', fontSize: 11, color: 'var(--text-tertiary)',
                }}>
                  暂无能力数据
                </div>
              )}
            </>
          )}
        </div>

        {/* CTA 按钮 */}
        <button
          onClick={() => push('chat', { projectId: params?.id ?? '', title })}
          style={{
            width: '100%', padding: '13px 0', border: 'none', borderRadius: 12,
            background: 'var(--accent)', color: 'var(--text-on-accent)', fontSize: 15, fontWeight: 600,
            cursor: 'pointer', marginBottom: 18,
          }}
        >
          开始新的学习
        </button>

        {/* 最近学习记录 — C-2: 暂无 activity IPC,显示空状态 */}
        <div style={{ marginBottom: 16 }}>
          <div style={{ fontSize: 13, fontWeight: 500, color: 'var(--text-secondary)', marginBottom: 8 }}>
            最近学习
          </div>
          <div style={{
            padding: '24px 16px', textAlign: 'center',
            fontSize: 12, color: 'var(--text-tertiary)',
            background: 'var(--bg-card)', borderRadius: 10,
            border: '1px solid var(--border)',
          }}>
            暂无学习记录
          </div>
        </div>

        {/* 作品章节 — C-2: project→manuscript 映射未 DB 持久化,显示空状态 */}
        <div>
          <div style={{ fontSize: 13, fontWeight: 500, color: 'var(--text-secondary)', marginBottom: 8 }}>
            作品章节
          </div>
          <div style={{
            padding: '24px 16px', textAlign: 'center',
            fontSize: 12, color: 'var(--text-tertiary)',
            background: 'var(--bg-card)', borderRadius: 10,
            border: '1px solid var(--border)',
          }}>
            暂无章节
          </div>
        </div>
      </div>
    </div>
  );
};
