/**
 * HistorySection — 训练工坊区块三：近期训练记录
 */

import React from 'react';
import type { TrainingRecord } from '../../shared/types';
import {
  statusIcons,
  statusColors,
} from './training-styles';
import sharedStyles from './TrainingShared.module.css';

const FILTERS = [
  { id: 'all', label: '全部' },
  { id: 'completed', label: '完成' },
  { id: 'in_progress', label: '进行中' },
  { id: 'skipped', label: '跳过' },
] as const;

type FilterId = (typeof FILTERS)[number]['id'];

export const HistorySection: React.FC<{
  history: TrainingRecord[];
  isLoading: boolean;
}> = ({ history, isLoading }) => {
  const [filter, setFilter] = React.useState<FilterId>('all');
  const [expandedId, setExpandedId] = React.useState<string | null>(null);

  const toggleExpand = React.useCallback((id: string) => {
    setExpandedId(prev => prev === id ? null : id);
  }, []);

  const filtered = React.useMemo(() => {
    if (filter === 'all') return history;
    return history.filter(r => r.status === filter);
  }, [history, filter]);

  if (isLoading) {
    return (
      <div className={sharedStyles.trainingSection}>
        <div className={sharedStyles.trainingSectionTitle}>近期训练记录</div>
        <div className={sharedStyles.trainingEmpty}>
          <p className={sharedStyles.loadingText}>加载中...</p>
        </div>
      </div>
    );
  }

  if (history.length === 0) {
    return (
      <div className={sharedStyles.trainingSection}>
        <div className={sharedStyles.trainingSectionTitle}>近期训练记录</div>
        <div className={sharedStyles.trainingEmpty}>
          <p className={sharedStyles.loadingText}>
            暂无训练记录。完成练习后，记录会显示在此处。
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className={sharedStyles.trainingSection}>
      <div className={sharedStyles.trainingSectionTitle}>近期训练记录</div>

      {/* 筛选栏 */}
      <div className={sharedStyles.historyFilterBar}>
        {FILTERS.map(f => (
          <button
            key={f.id}
            className={`${sharedStyles.historyFilterBtn} ${
              filter === f.id ? sharedStyles.historyFilterBtnActive : ''
            }`}
            onClick={() => setFilter(f.id)}
          >
            {f.label}
          </button>
        ))}
      </div>

      {/* 记录列表 */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
        {filtered.map((record) => {
          const isExpanded = expandedId === record.id;
          return (
            <React.Fragment key={record.id}>
              <div
                className={`${sharedStyles.historyRow} ${
                  record.status === 'skipped' ? sharedStyles.historySkipped : ''
                }`}
                onClick={() => toggleExpand(record.id)}
                style={{ color: record.status === 'skipped' ? 'var(--text-secondary)' : 'var(--text-primary)' }}
              >
                <span
                  className={sharedStyles.historyIcon}
                  style={{ color: statusColors[record.status] ?? '#95a5a6' }}
                >
                  {statusIcons[record.status] ?? '○'}
                </span>
                <span className={sharedStyles.historyName}>
                  {record.challengeName || record.taskId || ''}
                </span>
                {record.effectiveness != null && (
                  <span
                    className={sharedStyles.historyEffectiveness}
                    style={{ color: record.effectiveness >= 0.6 ? 'var(--success)' : 'var(--warning)' }}
                  >
                    {Math.round(record.effectiveness * 100)}% 有效
                  </span>
                )}
                <span className={sharedStyles.historyDate}>
                  {record.completedAt ?? record.assignedAt}
                </span>
              </div>
              {/* 展开详情 */}
              {isExpanded && (
                <div className={sharedStyles.historyExpanded}>
                  <div><strong>状态：</strong>{record.status === 'completed' ? '已完成' : record.status === 'in_progress' ? '进行中' : record.status === 'skipped' ? '已跳过' : record.status}</div>
                  {record.challengeName && <div><strong>名称：</strong>{record.challengeName}</div>}
                  {record.completedAt && <div><strong>完成时间：</strong>{record.completedAt}</div>}
                  {record.effectiveness != null && (
                    <div><strong>有效率：</strong>{Math.round(record.effectiveness * 100)}%</div>
                  )}
                </div>
              )}
            </React.Fragment>
          );
        })}
      </div>
    </div>
  );
};
