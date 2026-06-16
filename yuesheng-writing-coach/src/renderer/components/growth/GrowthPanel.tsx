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
import styles from './growth.module.css';
import shared from '../profile/panel-shared.module.css';

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
      <div className={`${shared.flexCol} ${shared.flexGap12}`}>
        <div className={styles.toggleRow}>
          <ToggleButton showGlobal={showGlobal} onToggle={() => setShowGlobal(v => !v)} />
        </div>
        <div className={shared.loadingContainer}>
          加载中...
        </div>
      </div>
    );
  }

  const totalOccurrences = trends.reduce((sum, t) => sum + t.occurrenceCount, 0);
  const hasNoRealData = trends.length === 0 || totalOccurrences === 0;

  if (hasNoRealData) {
    return (
      <div className={`${shared.flexCol} ${shared.flexGap12}`}>
        <div className={styles.toggleRow}>
          <ToggleButton showGlobal={showGlobal} onToggle={() => setShowGlobal(v => !v)} />
        </div>
        <div className={shared.emptyState}>
          <TrendingUp size={36} strokeWidth={1.4} opacity={0.5} />
          <span className={shared.textLg}>暂无成长记录</span>
          <span className={shared.textSm}>完成训练后，成长数据将在此展示</span>
        </div>
      </div>
    );
  }

  return (
    <div className={shared.panelContainer}>
      <div className={styles.toggleRow}>
        <ToggleButton showGlobal={showGlobal} onToggle={() => setShowGlobal(v => !v)} />
      </div>

      {/* 统计卡片 */}
      <div className={styles.statGrid}>
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
              className={styles.statCard}
              style={{ background: cfg.bgColor }}
            >
              <div className={styles.statValue} style={{ color: cfg.color }}>
                {count}
              </div>
              <div className={styles.statLabel}>
                {cfg.label}
              </div>
            </div>
          );
        })}
      </div>

      {/* 趋势图表 */}
      <div className={styles.trendSection}>
        <div className={shared.sectionHeader}>
          症候出现频次
        </div>
        <TrendChart data={trends} />
      </div>

      {/* 症候详情列 */}
      <div className={styles.listSection}>
        <div className={shared.sectionHeader}>
          详细列表
        </div>
        <div className={styles.listContainer}>
          {trends.map(t => {
            const cfg = STATUS_CONFIG[t.status] || STATUS_CONFIG.stable;
            return (
              <div key={t.name + t.status} className={styles.listRow}>
                <div className={styles.statusDot} style={{ background: cfg.color }} />
                <span className={`${shared.textMd} ${shared.textPrimary} ${shared.truncate}`}>
                  {t.name}
                </span>
                <span className={`${shared.textXs} ${shared.fontMedium}`} style={{ color: cfg.color, whiteSpace: 'nowrap' }}>
                  {t.occurrenceCount} 次
                </span>
                <span className={styles.statusBadge} style={{ background: cfg.bgColor }}>
                  {cfg.label}
                </span>
              </div>
            );
          })}
        </div>
      </div>

      {/* 底部提示 */}
      <div className={shared.footerNote}>
        基于诊断历史自动生成
      </div>
    </div>
  );
};
