/**
 * GrowthPanel — 成长记录面板（V2-021 MVP）
 *
 * 功能：
 * - 通过 IPC growth:getTrends 获取成长趋势数据
 * - 1 维趋势线展示（SVG 折线图）
 * - 状态分类统计（已掌握/改善中/需关注）
 */

import React, { useEffect, useState } from 'react';
import { TrendingUp } from 'lucide-react';
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
  mastered: { label: '已掌握', color: '#5B8C5A', bgColor: '#5B8C5A18' },
  improving: { label: '改善中', color: '#D4A04A', bgColor: '#D4A04A18' },
  stable: { label: '稳定', color: '#6B8FA3', bgColor: '#6B8FA318' },
  needsAttention: { label: '需关注', color: '#C0392B', bgColor: '#C0392B18' },
};

export const GrowthPanel: React.FC = () => {
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
        if (showGlobal) {
          // 全部历史：调用 growth:getGlobalTrends（无需 sessionId）
          const result = await invoke(IPC_CHANNELS.GROWTH_GET_GLOBAL_TRENDS) as {
            success: boolean;
            data?: { trends: SyndromeTrendData[]; masteredCount: number; improvingCount: number; stableCount?: number; needsAttentionCount: number };
          };
          if (mounted && result.success && result.data) {
            const trendList = result.data.trends || [];
            setTrends(trendList);
            const stableCount = result.data.stableCount ?? trendList.filter(t => t.status === 'stable').length;
            setSummary({
              masteredCount: result.data.masteredCount || 0,
              improvingCount: result.data.improvingCount || 0,
              stableCount,
              needsAttentionCount: result.data.needsAttentionCount || 0,
            });
          }
        } else {
          if (!sessionId) return;
          const result = await invoke(IPC_CHANNELS.GROWTH_GET_TRENDS, { sessionId }) as {
            success: boolean;
            data?: { trends: SyndromeTrendData[]; masteredCount: number; improvingCount: number; stableCount?: number; needsAttentionCount: number };
          };
          if (mounted && result.success && result.data) {
            const trendList = result.data.trends || [];
            setTrends(trendList);
            const stableCount = result.data.stableCount ?? trendList.filter(t => t.status === 'stable').length;
            setSummary({
              masteredCount: result.data.masteredCount || 0,
              improvingCount: result.data.improvingCount || 0,
              stableCount,
              needsAttentionCount: result.data.needsAttentionCount || 0,
            });
          }
        }
      } catch (e) {
        // 加载失败时保持静默，避免阻塞UI
        console.warn('[GrowthPanel] Failed to load data:', e);
      } finally {
        if (mounted) setLoading(false);
      }
    };
    fetchData();
    return () => { mounted = false; };
  }, [sessionId, showGlobal]);

  if (loading) {
    return (
      <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
        <div style={{ display: 'flex', justifyContent: 'flex-end', padding: '0 4px' }}>
          <ToggleButton showGlobal={showGlobal} onToggle={() => setShowGlobal(v => !v)} />
        </div>
        <div style={{ padding: '20px', textAlign: 'center', color: 'var(--text-tertiary)', fontSize: '0.82rem' }}>
          加载中...
        </div>
      </div>
    );
  }

  // 空状态判断：无趋势数据 或 所有症候出现次数为0（未做过诊断）
  const totalOccurrences = trends.reduce((sum, t) => sum + t.occurrenceCount, 0);
  const hasNoRealData = trends.length === 0 || totalOccurrences === 0;

  if (hasNoRealData) {
    return (
      <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
        <div style={{ display: 'flex', justifyContent: 'flex-end', padding: '0 4px' }}>
          <ToggleButton showGlobal={showGlobal} onToggle={() => setShowGlobal(v => !v)} />
        </div>
        <div
          style={{
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            justifyContent: 'center',
            padding: '40px 20px',
            color: 'var(--text-tertiary)',
            gap: 12,
            textAlign: 'center',
          }}
        >
          <TrendingUp size={36} strokeWidth={1.4} opacity={0.5} />
          <span style={{ fontSize: '0.85rem' }}>暂无成长记录</span>
          <span style={{ fontSize: '0.72rem' }}>完成训练后，成长数据将在此展示</span>
        </div>
      </div>
    );
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      {/* RP-03: 全局趋势切换 */}
      <div style={{ display: 'flex', justifyContent: 'flex-end', padding: '0 4px' }}>
        <ToggleButton showGlobal={showGlobal} onToggle={() => setShowGlobal(v => !v)} />
      </div>
      {/* 统计卡片 */}
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 8 }}>
        {Object.entries(STATUS_CONFIG).map(([key, cfg]) => {
          const count =
            key === 'mastered' ? summary.masteredCount
            : key === 'improving' ? summary.improvingCount
            : key === 'stable' ? summary.stableCount
            : key === 'needsAttention' ? summary.needsAttentionCount
            : 0;
          return (
            <div
              key={key}
              style={{
                padding: '10px 8px',
                borderRadius: 'var(--radius-sm)',
                background: cfg.bgColor,
                textAlign: 'center',
              }}
            >
              <div style={{ fontSize: '1.1rem', fontWeight: 600, color: cfg.color }}>
                {count}
              </div>
              <div style={{ fontSize: '0.65rem', color: 'var(--text-tertiary)', marginTop: 2 }}>
                {cfg.label}
              </div>
            </div>
          );
        })}
      </div>

      {/* 趋势图表 */}
      <div>
        <div style={{ fontSize: '0.72rem', fontWeight: 600, color: 'var(--text-secondary)', letterSpacing: '0.03em', padding: '0 2px 6px' }}>
          症候出现频次
        </div>
        <TrendChart data={trends} />
      </div>

      {/* 症候详情列 */}
      <div>
        <div style={{ fontSize: '0.72rem', fontWeight: 600, color: 'var(--text-secondary)', letterSpacing: '0.03em', padding: '0 2px 6px' }}>
          详细列表
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
          {trends.map(t => {
            const cfg = STATUS_CONFIG[t.status] || STATUS_CONFIG.stable;
            return (
              <div
                key={t.name + t.status}
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: 8,
                  padding: '6px 8px',
                  borderRadius: 'var(--radius-sm)',
                  transition: 'background 0.15s ease',
                }}
                onMouseEnter={e => { (e.currentTarget as HTMLElement).style.background = 'var(--bg-hover)'; }}
                onMouseLeave={e => { (e.currentTarget as HTMLElement).style.background = 'transparent'; }}
              >
                <div
                  style={{
                    width: 6,
                    height: 6,
                    borderRadius: '50%',
                    background: cfg.color,
                    flexShrink: 0,
                  }}
                />
                <span style={{ flex: 1, fontSize: '0.78rem', color: 'var(--text-primary)', minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                  {t.name}
                </span>
                <span style={{ fontSize: '0.65rem', color: cfg.color, fontWeight: 500, whiteSpace: 'nowrap' }}>
                  {t.occurrenceCount} 次
                </span>
                <span style={{ fontSize: '0.62rem', color: 'var(--text-tertiary)', padding: '1px 5px', borderRadius: 'var(--radius-full)', background: cfg.bgColor, whiteSpace: 'nowrap' }}>
                  {cfg.label}
                </span>
              </div>
            );
          })}
        </div>
      </div>

      {/* 底部提示 */}
      <div style={{ padding: '8px 2px 0', fontSize: '0.62rem', color: 'var(--text-tertiary)', opacity: 0.6, borderTop: '1px solid var(--border-light)' }}>
        基于诊断历史自动生成
      </div>
    </div>
  );
};
