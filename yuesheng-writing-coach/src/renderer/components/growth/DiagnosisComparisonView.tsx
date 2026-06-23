/**
 * DiagnosisComparisonView — 诊断对比视图（V4 H-03）
 *
 * 功能：
 * - 展示症候地图纵向对比（过去→现在）
 * - 通过 growth:getTrends 获取趋势数据
 * - 高亮改善/退步项，提供对比视图
 */

import React, { useEffect, useState } from 'react';
import { BarChart3, TrendingUp, TrendingDown, Minus } from 'lucide-react';
import { getInvoke } from '../../utils/ipc';
import { IPC_CHANNELS } from '../../shared/constants';
import { useSessionStore } from '../../stores/session.store';
import { TrendChart } from './TrendChart';
import { ToggleButton } from './ToggleButton';

interface SyndromeTrendData {
  name: string;
  status: 'mastered' | 'improving' | 'stable' | 'needsAttention';
  occurrenceCount: number;
  description: string;
}

const STATUS_CONFIG: Record<string, { label: string; color: string; bgColor: string }> = {
  mastered: { label: '已掌握', color: 'var(--success)', bgColor: '#5B8C5A18' },
  improving: { label: '改善中', color: 'var(--warning)', bgColor: '#D4A04A18' },
  stable: { label: '稳定', color: 'var(--info)', bgColor: '#6B8FA318' },
  needsAttention: { label: '需关注', color: 'var(--error)', bgColor: '#C0392B18' },
};

const TREND_ICON: Record<string, React.ReactNode> = {
  mastered: <TrendingUp size={14} strokeWidth={1.8} color="var(--success)" />,
  improving: <TrendingUp size={14} strokeWidth={1.8} color="var(--warning)" />,
  stable: <Minus size={14} strokeWidth={1.8} color="var(--info)" />,
  needsAttention: <TrendingDown size={14} strokeWidth={1.8} color="var(--error)" />,
};

export const DiagnosisComparisonView: React.FC = () => {
  const [trends, setTrends] = useState<SyndromeTrendData[]>([]);
  const [summary, setSummary] = useState({ masteredCount: 0, improvingCount: 0, stableCount: 0, needsAttentionCount: 0 });
  const [loading, setLoading] = useState(true);
  const [showGlobal, setShowGlobal] = useState(false);
  const sessionId = useSessionStore(s => s.currentSessionId);

  useEffect(() => {
    let mounted = true;
    const fetchData = async () => {
      setLoading(true);
      try {
        const invoke = getInvoke();
        const channel = showGlobal ? IPC_CHANNELS.GROWTH_GET_GLOBAL_TRENDS : IPC_CHANNELS.GROWTH_GET_TRENDS;
        const params = showGlobal ? undefined : { sessionId };
        const result = await invoke(channel, params) as {
          success: boolean;
          data?: { trends: SyndromeTrendData[]; masteredCount: number; improvingCount: number; stableCount?: number; needsAttentionCount: number };
        };
        if (mounted && result.success && result.data) {
          const trendList = result.data.trends || [];
          setTrends(trendList);
          setSummary({
            masteredCount: result.data.masteredCount || 0,
            improvingCount: result.data.improvingCount || 0,
            stableCount: result.data.stableCount ?? trendList.filter(t => t.status === 'stable').length,
            needsAttentionCount: result.data.needsAttentionCount || 0,
          });
        }
      } catch (e) {
        console.warn('[DiagnosisComparison] Failed to load data:', e);
      } finally {
        if (mounted) setLoading(false);
      }
    };
    fetchData();
    return () => { mounted = false; };
  }, [sessionId, showGlobal]);

  if (loading) {
    return (
      <div style={{ padding: '20px', textAlign: 'center', color: 'var(--text-tertiary)', fontSize: '0.82rem' }}>
        加载中...
      </div>
    );
  }

  const totalOccurrences = trends.reduce((sum, t) => sum + t.occurrenceCount, 0);
  const hasNoRealData = trends.length === 0 || totalOccurrences === 0;

  if (hasNoRealData) {
    return (
      <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
        <div style={{ display: 'flex', justifyContent: 'flex-end', padding: '0 4px' }}>
          <ToggleButton showGlobal={showGlobal} onToggle={() => setShowGlobal(v => !v)} />
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: '40px 20px', color: 'var(--text-tertiary)', gap: 12, textAlign: 'center' }}>
          <BarChart3 size={36} strokeWidth={1.4} opacity={0.5} />
          <span style={{ fontSize: '0.85rem' }}>暂无诊断对比数据</span>
          <span style={{ fontSize: '0.72rem' }}>完成多次诊断后，对比结果将在此展示</span>
        </div>
      </div>
    );
  }

  // 按状态分组：改善项（mastered/improving）和注意项（needsAttention）
  const improvedItems = trends.filter(t => t.status === 'mastered' || t.status === 'improving');
  const regressedItems = trends.filter(t => t.status === 'needsAttention');

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      {/* 全局趋势切换 */}
      <div style={{ display: 'flex', justifyContent: 'flex-end', padding: '0 4px' }}>
        <ToggleButton showGlobal={showGlobal} onToggle={() => setShowGlobal(v => !v)} />
      </div>

      {/* 概览对比卡片 */}
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
        <div style={{ padding: '12px', borderRadius: 'var(--radius-sm)', background: '#5B8C5A12', border: '1px solid #5B8C5A30' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 8 }}>
            <TrendingUp size={16} strokeWidth={1.8} color="var(--success)" />
            <span style={{ fontSize: '0.72rem', fontWeight: 600, color: 'var(--success)' }}>改善项</span>
          </div>
          <div style={{ fontSize: '1.3rem', fontWeight: 700, color: 'var(--success)' }}>
            {summary.masteredCount + summary.improvingCount}
          </div>
          <div style={{ fontSize: '0.62rem', color: 'var(--text-tertiary)', marginTop: 2 }}>
            已掌握 {summary.masteredCount} / 改善中 {summary.improvingCount}
          </div>
        </div>
        <div style={{ padding: '12px', borderRadius: 'var(--radius-sm)', background: '#C0392B12', border: '1px solid #C0392B30' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 8 }}>
            <TrendingDown size={16} strokeWidth={1.8} color="var(--error)" />
            <span style={{ fontSize: '0.72rem', fontWeight: 600, color: 'var(--error)' }}>需关注</span>
          </div>
          <div style={{ fontSize: '1.3rem', fontWeight: 700, color: 'var(--error)' }}>
            {summary.needsAttentionCount}
          </div>
          <div style={{ fontSize: '0.62rem', color: 'var(--text-tertiary)', marginTop: 2 }}>
            稳定 {summary.stableCount}
          </div>
        </div>
      </div>

      {/* 频率趋势图 */}
      <div>
        <div style={{ fontSize: '0.72rem', fontWeight: 600, color: 'var(--text-secondary)', letterSpacing: '0.03em', padding: '0 2px 6px' }}>
          症候频次对比
        </div>
        <TrendChart data={trends} />
      </div>

      {/* 改善项列表 */}
      {improvedItems.length > 0 && (
        <div>
          <div style={{ fontSize: '0.72rem', fontWeight: 600, color: 'var(--text-secondary)', letterSpacing: '0.03em', padding: '0 2px 6px' }}>
            已改善症候
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
            {improvedItems.map(t => {
              const cfg = STATUS_CONFIG[t.status] || STATUS_CONFIG.stable;
              return (
                <div key={t.name + t.status} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '6px 8px', borderRadius: 'var(--radius-sm)', transition: 'background 0.15s ease' }}
                  onMouseEnter={e => { (e.currentTarget as HTMLElement).style.background = 'var(--bg-hover)'; }}
                  onMouseLeave={e => { (e.currentTarget as HTMLElement).style.background = 'transparent'; }}>
                  {TREND_ICON[t.status] || null}
                  <span style={{ flex: 1, fontSize: '0.78rem', color: 'var(--text-primary)', minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                    {t.name}
                  </span>
                  <span style={{ fontSize: '0.62rem', color: cfg.color, padding: '1px 5px', borderRadius: 'var(--radius-full)', background: cfg.bgColor, whiteSpace: 'nowrap' }}>
                    {cfg.label}
                  </span>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* 需关注项列表 */}
      {regressedItems.length > 0 && (
        <div>
          <div style={{ fontSize: '0.72rem', fontWeight: 600, color: 'var(--text-secondary)', letterSpacing: '0.03em', padding: '0 2px 6px' }}>
            需重点关注的症候
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
            {regressedItems.map(t => {
              const cfg = STATUS_CONFIG[t.status] || STATUS_CONFIG.stable;
              return (
                <div key={t.name + t.status} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '6px 8px', borderRadius: 'var(--radius-sm)', background: '#C0392B08', transition: 'background 0.15s ease' }}
                  onMouseEnter={e => { (e.currentTarget as HTMLElement).style.background = '#C0392B14'; }}
                  onMouseLeave={e => { (e.currentTarget as HTMLElement).style.background = '#C0392B08'; }}>
                  <TrendingDown size={14} strokeWidth={1.8} color="var(--error)" />
                  <span style={{ flex: 1, fontSize: '0.78rem', color: 'var(--text-primary)', minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                    {t.name}
                  </span>
                  <span style={{ fontSize: '0.62rem', color: cfg.color, padding: '1px 5px', borderRadius: 'var(--radius-full)', background: cfg.bgColor, whiteSpace: 'nowrap' }}>
                    {t.occurrenceCount} 次
                  </span>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* 底部提示 */}
      <div style={{ padding: '8px 2px 0', fontSize: '0.62rem', color: 'var(--text-tertiary)', opacity: 0.6, borderTop: '1px solid var(--border-light)' }}>
        基于诊断历史自动生成 — 显示整体趋势变化
      </div>
    </div>
  );
};
