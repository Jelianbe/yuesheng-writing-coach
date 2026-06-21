import React, { useEffect, useState } from 'react';
import { getInvoke } from '../../../../utils/ipc';
import { IPC_CHANNELS } from '../../../../shared/constants';
import styles from './index.module.css';

// -- 后端 IPC 返回类型 --
interface SyndromeTrend {
  id: string;
  name: string;
  status: 'mastered' | 'improving' | 'stable' | 'needsAttention';
  latestSeverity: 'L1' | 'L2' | 'L3' | null;
  previousSeverity: 'L1' | 'L2' | 'L3' | null;
  occurrenceCount: number;
  description: string;
}

interface GrowthSummary {
  trends: SyndromeTrend[];
  masteredCount: number;
  improvingCount: number;
  stableCount: number;
  needsAttentionCount: number;
}

const STATUS_COLORS: Record<string, string> = {
  mastered: '#5A8F68',
  improving: '#7A9F5A',
  stable: '#C8943C',
  needsAttention: '#B84A4A',
};

const STATUS_LABELS: Record<string, string> = {
  mastered: '已攻克',
  improving: '进步中',
  stable: '稳定',
  needsAttention: '需关注',
};

function severityNum(s: 'L1' | 'L2' | 'L3' | null): number {
  if (s === 'L3') return 3;
  if (s === 'L2') return 2;
  if (s === 'L1') return 1;
  return 0;
}

function severityLabel(s: 'L1' | 'L2' | 'L3' | null): string {
  if (s === 'L3') return '重';
  if (s === 'L2') return '中';
  if (s === 'L1') return '轻';
  return '-';
}

export const LearningLogWorkspace: React.FC = () => {
  const [summary, setSummary] = useState<GrowthSummary | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);

  useEffect(() => {
    (async () => {
      try {
        const data = await getInvoke()(IPC_CHANNELS.GROWTH_GET_TRENDS, {});
        if (data && typeof data === 'object' && 'trends' in data) {
          setSummary(data as GrowthSummary);
        } else {
          setLoadError('后端返回格式异常');
        }
      } catch {
        setLoadError('无法加载成长趋势数据');
      }
    })();
  }, []);

  // 统计卡片
  const statCards = summary
    ? [
        { value: summary.trends.length, color: '#7A6040', label: '追踪症候' },
        { value: summary.masteredCount, color: '#5A8F68', label: '已攻克' },
        { value: summary.needsAttentionCount, color: '#C8943C', label: '需关注' },
      ]
    : [
        { value: 0, color: '#7A6040', label: '追踪症候' },
        { value: 0, color: '#5A8F68', label: '已攻克' },
        { value: 0, color: '#C8943C', label: '需关注' },
      ];

  // 图表：显示 top 症候的严重度变化
  const chartTrends = (summary?.trends ?? []).slice(0, 8);

  // 学习条目：按状态分组
  const grouped = summary?.trends.reduce<Record<string, SyndromeTrend[]>>((acc, t) => {
    (acc[t.status] ??= []).push(t);
    return acc;
  }, {}) ?? {};

  const statusOrder = ['needsAttention', 'improving', 'stable', 'mastered'];

  return (
    <div className={styles.wrap}>
      <h3 className={styles.title}>学习日志</h3>

      {/* 统计卡片行 */}
      <div className={styles.cardRow}>
        {statCards.map(card => (
          <div key={card.label} className={styles.card}>
            <span className={styles.cardValue} style={{ color: card.color }}>{card.value}</span>
            <div className={styles.cardLabel}>{card.label}</div>
          </div>
        ))}
      </div>

      {/* 加载/错误提示 */}
      {loadError && <div className={styles.errorMsg}>{loadError}</div>}

      {/* 严重度变化图表 */}
      {chartTrends.length > 0 && (
        <div className={styles.chartSection}>
          <span className={styles.chartTitle}>症候严重度变化</span>
          <div className={styles.chartContainer}>
            {chartTrends.map(t => {
              const prev = severityNum(t.previousSeverity);
              const now = severityNum(t.latestSeverity);
              const maxH = 36;
              const prevH = prev ? (prev / 3) * maxH : 0;
              const nowH = now ? (now / 3) * maxH : 0;
              return (
                <div key={t.id} className={styles.barWrap}>
                  <span className={styles.barScore}>{severityLabel(t.latestSeverity)}</span>
                  <div style={{ display: 'flex', gap: 2, alignItems: 'flex-end', height: maxH }}>
                    {prev > 0 && (
                      <div style={{
                        width: 10, height: prevH, background: '#D6CEC0', borderRadius: 2,
                      }} title={`之前: ${severityLabel(t.previousSeverity)}`} />
                    )}
                    <div style={{
                      width: 10, height: nowH, background: STATUS_COLORS[t.status], borderRadius: 2, opacity: 0.8,
                    }} title={`当前: ${severityLabel(t.latestSeverity)}`} />
                  </div>
                  <span className={styles.barNote}>{t.name.slice(0, 4)}</span>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* 按状态分组的症候趋势 */}
      {statusOrder.map(status => {
        const items = grouped[status];
        if (!items?.length) return null;
        return (
          <div key={status} className={styles.logRow}>
            <div className={styles.dateLabel} style={{ color: STATUS_COLORS[status] }}>
              {STATUS_LABELS[status]}（{items.length}）
            </div>
            {items.map(t => (
              <div key={t.id} className={styles.entryText}>
                <span style={{ color: STATUS_COLORS[status] }}>●</span>
                {' '}{t.name}
                {t.description && <span className={styles.scoreChange}> — {t.description}</span>}
                {t.occurrenceCount > 0 && (
                  <span className={styles.scoreChange}> 出现{t.occurrenceCount}次</span>
                )}
              </div>
            ))}
          </div>
        );
      })}

      {/* 空状态 */}
      {!loadError && (!summary || summary.trends.length === 0) && (
        <div className={styles.entryText} style={{ marginTop: 8, color: '#8A7F6E' }}>
          暂无成长趋势数据。开始训练后，这里将展示你的进步轨迹。
        </div>
      )}
    </div>
  );
};
