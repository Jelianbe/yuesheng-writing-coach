/**
 * GrowthReportPage — 成长报告
 *
 * Sprint 19 Issue 19-3 实装:
 * - 通过 useGrowthStore.fetchGlobalTrends() 拉取真实成长数据
 * - 4 状态卡片(已掌握/进步中/稳定/需关注)
 * - 5 维 SVG 雷达图(叙事/角色/世界观/语言/学习 — 来自 ability-atlas 5 大类)
 * - 趋势线(总进度 + 优势/需关注)
 * - per-syndrome 明细列表
 *
 * 数据契约:src/shared/api-contracts/growth.contract.ts
 * 通道:IPC_CHANNELS.GROWTH_GET_GLOBAL_TRENDS
 */

import React, { useEffect, useMemo } from 'react';
import { ArrowLeft, TrendingUp, TrendingDown, Minus, CheckCircle2 } from 'lucide-react';
import { useShallow } from 'zustand/react/shallow';
import { usePageStackStore } from '../stores/page-stack.store';
import { useGrowthStore } from '../stores/growth.store';
import type { GrowthGlobalSyndromeTrend } from '../../shared/api-contracts/growth.contract';

/** 5 大能力维度(与 ability-atlas.json 的 category 一致) */
const DIMENSIONS = [
  { key: 'narrative', label: '叙事', color: 'var(--color-teaching)' },
  { key: 'character', label: '角色', color: 'var(--accent)' },
  { key: 'worldview', label: '世界观', color: 'var(--color-practice)' },
  { key: 'language', label: '语言', color: 'var(--color-growth)' },
  { key: 'learning', label: '学习', color: '#7B91B5' },
] as const;

type DimensionKey = (typeof DIMENSIONS)[number]['key'];

/** 症候 ID → 能力维度映射(基于 resources/knowledge-graph/ability-atlas.json 的 related_abilities) */
const SYNDROME_TO_DIMENSION: Record<string, DimensionKey> = {
  P001: 'worldview',
  P002: 'character',
  P003: 'language',
  P004: 'narrative',
  P005: 'narrative',
  P006: 'narrative',
  P007: 'learning',
  P008: 'worldview',
  P009: 'character',
  P010: 'character',
};

/** 状态 → 视觉属性映射 */
const STATUS_MAP: Record<
  GrowthGlobalSyndromeTrend['status'],
  { label: string; Icon: typeof CheckCircle2; color: string; bg: string }
> = {
  mastered: { label: '已掌握', Icon: CheckCircle2, color: 'var(--color-growth)', bg: 'var(--color-growth-light)' },
  improving: { label: '进步中', Icon: TrendingUp, color: 'var(--color-teaching)', bg: 'var(--color-teaching-light)' },
  stable: { label: '稳定', Icon: Minus, color: 'var(--text-secondary)', bg: 'var(--bg-input)' },
  needsAttention: { label: '需关注', Icon: TrendingDown, color: 'var(--color-practice)', bg: 'var(--color-practice-light)' },
};

/** 严重度 → 基础分(0-5,越高越健康) */
const SEVERITY_SCORE: Record<'L1' | 'L2' | 'L3', number> = {
  L1: 5,
  L2: 3,
  L3: 1,
};

function severityBaseScore(severity: 'L1' | 'L2' | 'L3' | null): number {
  return severity === null ? 3 : SEVERITY_SCORE[severity];
}

/** 状态加分 */
const STATUS_BONUS: Record<GrowthGlobalSyndromeTrend['status'], number> = {
  mastered: 1.5,
  improving: 0.5,
  stable: 0,
  needsAttention: -1,
};

const RADAR_SIZE = 220;
const CENTER = RADAR_SIZE / 2;
const RADIUS = RADAR_SIZE * 0.36;
const LEVELS = 5;
const MAX_SCORE = 7; // 基础分(5) + 状态加分(1.5) 上界

function RadarChart({ values }: { values: number[] }) {
  const angleStep = (Math.PI * 2) / DIMENSIONS.length;
  const gridPoints = Array.from({ length: LEVELS }).map((_, level) => {
    const r = (RADIUS / LEVELS) * (level + 1);
    return DIMENSIONS.map((_, i) => {
      const a = angleStep * i - Math.PI / 2;
      return `${CENTER + r * Math.cos(a)},${CENTER + r * Math.sin(a)}`;
    }).join(' ');
  });

  const dataPoints = values.map((v, i) => {
    const r = (RADIUS / MAX_SCORE) * v;
    const a = angleStep * i - Math.PI / 2;
    return `${CENTER + r * Math.cos(a)},${CENTER + r * Math.sin(a)}`;
  }).join(' ');

  const labelPositions = DIMENSIONS.map((_, i) => {
    const a = angleStep * i - Math.PI / 2;
    const r = RADIUS + 16;
    return { x: CENTER + r * Math.cos(a), y: CENTER + r * Math.sin(a) };
  });

  return (
    <svg
      width={RADAR_SIZE}
      height={RADAR_SIZE}
      viewBox={`0 0 ${RADAR_SIZE} ${RADAR_SIZE}`}
      role="img"
      aria-label="5 维能力雷达图"
      data-testid="growth-radar"
    >
      {gridPoints.map((pts, i) => (
        <polygon key={i} points={pts} fill="none" stroke="var(--border)" strokeWidth={0.6} />
      ))}
      {DIMENSIONS.map((_, i) => {
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
      <polygon
        points={dataPoints}
        fill="rgba(138,122,158,0.22)"
        stroke="var(--accent)"
        strokeWidth={1.5}
      />
      {values.map((v, i) => {
        const r = (RADIUS / MAX_SCORE) * v;
        const a = angleStep * i - Math.PI / 2;
        return (
          <circle
            key={i}
            cx={CENTER + r * Math.cos(a)}
            cy={CENTER + r * Math.sin(a)}
            r={2.5}
            fill="var(--accent)"
          />
        );
      })}
      {labelPositions.map((pos, i) => (
        <text
          key={i}
          x={pos.x}
          y={pos.y}
          textAnchor="middle"
          dominantBaseline="middle"
          fill="var(--text-secondary)"
          fontSize={10}
        >
          {DIMENSIONS[i].label}
        </text>
      ))}
    </svg>
  );
}

/** 按 5 大维度聚合症候趋势得分 */
function aggregateDimensionScores(trends: GrowthGlobalSyndromeTrend[]): number[] {
  const buckets: Record<DimensionKey, number[]> = {
    narrative: [], character: [], worldview: [], language: [], learning: [],
  };
  for (const t of trends) {
    const dim = SYNDROME_TO_DIMENSION[t.syndromeId] ?? 'narrative';
    const base = severityBaseScore(t.latestSeverity);
    const score = Math.max(0, Math.min(MAX_SCORE, base + STATUS_BONUS[t.status]));
    buckets[dim].push(score);
  }
  return DIMENSIONS.map(d => {
    const arr = buckets[d.key];
    if (arr.length === 0) return 0;
    return Math.round((arr.reduce((a, b) => a + b, 0) / arr.length) * 10) / 10;
  });
}

export const GrowthReportPage: React.FC<{ params?: Record<string, string> }> = () => {
  const pop = usePageStackStore(s => s.pop);
  const { trends, global, loading, error, fetchGlobalTrends } = useGrowthStore(
    useShallow(s => ({
      trends: s.trends,
      global: s.global,
      loading: s.loading,
      error: s.error,
      fetchGlobalTrends: s.fetchGlobalTrends,
    })),
  );

  useEffect(() => {
    void fetchGlobalTrends();
  }, [fetchGlobalTrends]);

  const dimensionValues = useMemo(() => aggregateDimensionScores(trends), [trends]);
  const hasRealData = trends.length > 0;

  const statusCounts = useMemo(() => {
    const counts = { mastered: 0, improving: 0, stable: 0, needsAttention: 0 };
    for (const t of trends) counts[t.status] += 1;
    return counts;
  }, [trends]);

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      {/* Navbar */}
      <header style={{
        height: 52, display: 'flex', alignItems: 'center', gap: 8,
        padding: '0 12px', borderBottom: '1px solid var(--border)',
        background: 'var(--bg-card)', flexShrink: 0,
      }}>
        <button onClick={pop} aria-label="返回" style={{ border: 'none', background: 'none', cursor: 'pointer', padding: 4 }}>
          <ArrowLeft size={20} color="var(--text-primary)" strokeWidth={1.5} />
        </button>
        <h1 style={{ fontSize: 16, fontWeight: 600, color: 'var(--text-primary)', margin: 0 }}>成长报告</h1>
      </header>

      {/* 内容区 */}
      <div style={{ flex: 1, overflow: 'auto', padding: '16px 16px 8px' }}>
        {error && (
          <div style={{ padding: 12, marginBottom: 12, borderRadius: 8, background: 'var(--error-light)', color: 'var(--error)', fontSize: 12 }}>
            {error}
          </div>
        )}

        {loading && trends.length === 0 ? (
          <div data-testid="growth-loading" style={{ padding: 40, textAlign: 'center', color: 'var(--text-tertiary)', fontSize: 13 }}>
            数据加载中…
          </div>
        ) : !hasRealData ? (
          <div data-testid="growth-empty" style={{ padding: 40, textAlign: 'center', color: 'var(--text-tertiary)', fontSize: 13 }}>
            暂无成长数据,先去对话中发起几次诊断吧
          </div>
        ) : (
          <>
            {/* 顶部 4 状态卡片 */}
            <div data-testid="growth-status-cards" style={{ display: 'flex', gap: 8, marginBottom: 16 }}>
              {(Object.keys(STATUS_MAP) as Array<GrowthGlobalSyndromeTrend['status']>).map(key => {
                const cfg = STATUS_MAP[key];
                const count = statusCounts[key];
                return (
                  <div key={key} style={{
                    flex: 1, padding: '10px 6px', textAlign: 'center',
                    background: 'var(--bg-card)', borderRadius: 10,
                    border: '1px solid var(--border)',
                  }}>
                    <cfg.Icon size={16} color={cfg.color} strokeWidth={1.5} style={{ marginBottom: 4 }} />
                    <div style={{ fontSize: 18, fontWeight: 700, color: cfg.color, lineHeight: 1.2 }}>{count}</div>
                    <div style={{ fontSize: 10, color: 'var(--text-tertiary)', marginTop: 2 }}>{cfg.label}</div>
                  </div>
                );
              })}
            </div>

            {/* 5 维雷达图 */}
            <div data-testid="growth-radar-section" style={{
              background: 'var(--bg-card)', borderRadius: 12,
              border: '1px solid var(--border)',
              padding: '12px 0 8px', marginBottom: 16,
            }}>
              <div style={{ fontSize: 13, fontWeight: 500, color: 'var(--text-secondary)', padding: '0 14px', marginBottom: 4 }}>
                5 维能力画像
              </div>
              <div style={{ fontSize: 11, color: 'var(--text-tertiary)', padding: '0 14px', marginBottom: 8 }}>
                基于 {trends.length} 个症候诊断聚合
              </div>
              <div style={{ display: 'flex', justifyContent: 'center' }}>
                <RadarChart values={dimensionValues} />
              </div>
            </div>

            {/* 趋势线:总览 + 优势/关注 */}
            <div data-testid="growth-trend-summary" style={{
              background: 'var(--bg-card)', borderRadius: 12,
              border: '1px solid var(--border)', padding: 14, marginBottom: 16,
            }}>
              <div style={{ fontSize: 13, fontWeight: 500, color: 'var(--text-secondary)', marginBottom: 10 }}>
                趋势总览
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 }}>
                <span style={{ fontSize: 12, color: 'var(--text-tertiary)' }}>总进度</span>
                <span style={{ fontSize: 16, fontWeight: 600, color: 'var(--accent)' }}>
                  {global ? Math.round((statusCounts.mastered / trends.length) * 100) : 0}%
                </span>
              </div>
              <div style={{ fontSize: 12, color: 'var(--text-secondary)', lineHeight: 1.6 }}>
                {global && global.topGainers.length > 0 && (
                  <div style={{ marginBottom: 4 }}>
                    <span style={{ color: 'var(--color-growth)' }}>优势方向</span>
                    ：{global.topGainers.join('、')}
                  </div>
                )}
                {global && global.topLosers.length > 0 && (
                  <div>
                    <span style={{ color: 'var(--color-practice)' }}>需要关注</span>
                    ：{global.topLosers.join('、')}
                  </div>
                )}
                {global && global.topGainers.length === 0 && global.topLosers.length === 0 && (
                  <div style={{ color: 'var(--text-tertiary)' }}>尚无明显趋势,继续诊断即可积累数据</div>
                )}
              </div>
            </div>

            {/* 症候明细列表 */}
            <div data-testid="growth-syndrome-list">
              <div style={{ fontSize: 13, fontWeight: 500, color: 'var(--text-secondary)', marginBottom: 8, padding: '0 4px' }}>
                症候详情
              </div>
              <div style={{ display: 'flex', flexDirection: 'column', borderRadius: 10, border: '1px solid var(--border)', overflow: 'hidden' }}>
                {trends.map((t, i) => {
                  const cfg = STATUS_MAP[t.status];
                  return (
                    <div
                      key={t.syndromeId}
                      style={{
                        display: 'flex', alignItems: 'center', gap: 10,
                        padding: '10px 12px',
                        borderBottom: i < trends.length - 1 ? '1px solid var(--border)' : 'none',
                      }}
                    >
                      <div style={{ flex: 1, minWidth: 0 }}>
                        <div style={{ fontSize: 13, color: 'var(--text-primary)', fontWeight: 500 }}>{t.name}</div>
                        <div style={{ fontSize: 11, color: 'var(--text-tertiary)', marginTop: 2 }}>
                          {t.latestSeverity ? `严重度 ${t.latestSeverity}` : '尚未诊断'} · 出现 {t.occurrenceCount} 次
                        </div>
                      </div>
                      <span style={{
                        fontSize: 10, fontWeight: 600,
                        background: cfg.bg, color: cfg.color,
                        padding: '3px 8px', borderRadius: 10, flexShrink: 0,
                      }}>
                        {cfg.label}
                      </span>
                    </div>
                  );
                })}
              </div>
            </div>
          </>
        )}
      </div>
    </div>
  );
};
