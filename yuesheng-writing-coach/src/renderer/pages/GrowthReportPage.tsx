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
import { ArrowLeft, TrendingUp, TrendingDown, Minus, CheckCircle2, Flame, BookOpen, Target, MessageSquare } from 'lucide-react';
import { useShallow } from 'zustand/react/shallow';
import { usePageStackStore } from '../stores/page-stack.store';
import { useGrowthStore } from '../stores/growth.store';
import { useWritingProgressStore } from '../stores/writing-progress.store';
import type { GrowthGlobalSyndromeTrend } from '../../shared/api-contracts/growth.contract';

/** 5 大能力维度(与 ability-atlas.json 的 category 一致) */
const DIMENSIONS = [
  { key: 'narrative', label: '叙事', color: 'var(--color-teaching)' },
  { key: 'character', label: '角色', color: 'var(--accent)' },
  { key: 'worldview', label: '世界观', color: 'var(--color-practice)' },
  { key: 'language', label: '语言', color: 'var(--color-growth)' },
  { key: 'learning', label: '学习', color: 'var(--color-teaching)' },
] as const;

type DimensionKey = (typeof DIMENSIONS)[number]['key'];

/** 症候 ID → 能力维度映射(基于 resources/knowledge-graph/ability-atlas.json 的 category)
 *  TODO(C-4): 改为从 ability-atlas.json 运行时加载 */
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

/** 状态 → 视觉属性映射(C-4: 页 UI 专属,保留在页面层) */
const STATUS_MAP = {
  mastered: { label: '已掌握', Icon: CheckCircle2, color: 'var(--color-growth)', bg: 'var(--color-growth-light)' },
  improving: { label: '进步中', Icon: TrendingUp, color: 'var(--color-teaching)', bg: 'var(--color-teaching-light)' },
  stable: { label: '稳定', Icon: Minus, color: 'var(--text-secondary)', bg: 'var(--bg-input)' },
  needsAttention: { label: '需关注', Icon: TrendingDown, color: 'var(--color-practice)', bg: 'var(--color-practice-light)' },
} as const;

/** 严重度 → 基础分(0-5,越高越健康) */
const SEVERITY_SCORE = {
  L1: 5,
  L2: 3,
  L3: 1,
} as const;

function severityBaseScore(severity: 'L1' | 'L2' | 'L3' | null): number {
  return severity === null ? 3 : SEVERITY_SCORE[severity];
}

/** 状态加分 */
const STATUS_BONUS = {
  mastered: 1.5,
  improving: 0.5,
  stable: 0,
  needsAttention: -1,
} as const;

const RADAR_SIZE = 220;
const CENTER = RADAR_SIZE / 2;
const RADIUS = RADAR_SIZE * 0.36;
const LEVELS = 5;
const MAX_SCORE = 7; // 基础分(5) + 状态加分(1.5) 上界

/** 30天活动柱状图 */
const ActivityBarChart: React.FC<{ data: { date: string; count: number }[] }> = ({ data }) => {
  const BAR_W = 6;
  const BAR_GAP = 2;
  const HEIGHT = 60;
  const PADDING = 4;
  const maxCount = Math.max(...data.map(d => d.count), 1);
  const totalW = data.length * (BAR_W + BAR_GAP);
  const today = new Date().toISOString().slice(0, 10);

  return (
    <svg width={totalW} height={HEIGHT}
      style={{ display: 'block', maxWidth: '100%', overflow: 'visible' }}
    >
      {data.map((d, i) => {
        const barH = Math.max(2, (d.count / maxCount) * (HEIGHT - PADDING * 2));
        const x = i * (BAR_W + BAR_GAP);
        const y = HEIGHT - PADDING - barH;
        const isToday = d.date === today;
        return (
          <rect
            key={d.date}
            x={x} y={y}
            width={BAR_W} height={barH}
            rx={2} ry={2}
            fill={d.count > 0 ? (isToday ? 'var(--accent)' : 'var(--color-teaching)') : 'var(--bg-input)'}
            opacity={d.count > 0 ? 0.7 : 0.4}
          >
            <title>{d.date}: {d.count} 字</title>
          </rect>
        );
      })}
    </svg>
  );
};

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
        fill="var(--accent)"
        fillOpacity={0.22}
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
  const { overview, loading: loadingProgress, error: _progressError, fetchOverview } = useWritingProgressStore(
    useShallow(s => ({
      overview: s.overview,
      loading: s.loading,
      error: s.error,
      fetchOverview: s.fetchOverview,
    })),
  );

  useEffect(() => {
    void fetchGlobalTrends();
    void fetchOverview();
  }, [fetchGlobalTrends, fetchOverview]);

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
        {/* 进度总览 — Sprint 40 */}
        {!loadingProgress && overview && (
          <div style={{ marginBottom: 16 }}>
            {/* 写作统计行 */}
            <div style={{ fontSize: 13, fontWeight: 500, color: 'var(--text-secondary)', marginBottom: 6 }}>
              <BookOpen size={14} strokeWidth={1.5} style={{ marginRight: 4, verticalAlign: -2 }} />
              写作进度
            </div>
            <div style={{ display: 'flex', gap: 6, marginBottom: 6, flexWrap: 'wrap' }}>
              {[
                { label: '今日', value: overview.todayWordCount.toLocaleString(), suffix: '字' },
                { label: '本周', value: overview.weeklyWordCount.toLocaleString(), suffix: '字' },
                { label: '本月', value: overview.monthlyWordCount.toLocaleString(), suffix: '字' },
                { label: '总计', value: overview.totalWordCount.toLocaleString(), suffix: '字' },
                { label: '连续', value: `${overview.writingStreak}`, 
                  suffix: '天', icon: <Flame size={14} color={overview.writingStreak > 0 ? 'var(--color-practice)' : 'var(--text-tertiary)'} strokeWidth={1.5} /> },
              ].map(s => (
                <div key={s.label} style={{
                  flex: 1, minWidth: 60, padding: '6px 8px',
                  background: 'var(--bg-card)', borderRadius: 8,
                  border: '1px solid var(--border)',
                }}>
                  <div style={{ fontSize: 16, fontWeight: 700, color: s.label === '连续' && overview.writingStreak > 0 ? 'var(--color-practice)' : 'var(--text-primary)' }}>
                    {s.icon ?? null} {s.value}
                    <span style={{ fontSize: 10, fontWeight: 400, color: 'var(--text-tertiary)', marginLeft: 2 }}>{s.suffix}</span>
                  </div>
                  <div style={{ fontSize: 10, color: 'var(--text-tertiary)', marginTop: 1 }}>{s.label}</div>
                </div>
              ))}
            </div>

            {/* 训练/会话统计行 */}
            <div style={{ fontSize: 13, fontWeight: 500, color: 'var(--text-secondary)', marginBottom: 6 }}>
              <Target size={14} strokeWidth={1.5} style={{ marginRight: 4, verticalAlign: -2 }} />
              训练与活跃度
            </div>
            <div style={{ display: 'flex', gap: 6, marginBottom: 6, flexWrap: 'wrap' }}>
              {[
                { label: '总训练', value: `${overview.completedTraining} / ${overview.totalTraining}`, suffix: '' },
                { label: '平均分', value: overview.averageScore != null ? `${overview.averageScore}` : '—', suffix: '' },
                { label: '总对话', value: `${overview.totalSessions}`, suffix: '次' },
                { label: '本周', value: `${overview.weeklySessions}`, suffix: '次新对话',
                  icon: <MessageSquare size={14} color="var(--accent)" strokeWidth={1.5} style={{ verticalAlign: -2, marginRight: 2 }} /> },
              ].map(s => (
                <div key={s.label} style={{
                  flex: 1, minWidth: 60, padding: '6px 8px',
                  background: 'var(--bg-card)', borderRadius: 8,
                  border: '1px solid var(--border)',
                }}>
                  <div style={{ fontSize: 16, fontWeight: 600, color: 'var(--text-primary)' }}>
                    {s.icon ?? null} {s.value}
                  </div>
                  <div style={{ fontSize: 10, color: 'var(--text-tertiary)', marginTop: 1 }}>{s.label}</div>
                </div>
              ))}
            </div>

            {/* 30天活动柱状图 */}
            {overview.dailyWordCounts.length > 0 && (
              <div style={{
                background: 'var(--bg-card)', borderRadius: 10,
                border: '1px solid var(--border)', padding: '8px 10px',
              }}>
                <div style={{ fontSize: 11, color: 'var(--text-tertiary)', marginBottom: 4 }}>
                  近 30 天写作活动
                </div>
                <div style={{ overflowX: 'auto' }}>
                  <ActivityBarChart data={overview.dailyWordCounts} />
                </div>
              </div>
            )}

            <div style={{ height: 1, background: 'var(--border)', margin: '12px 0' }} />
          </div>
        )}

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
