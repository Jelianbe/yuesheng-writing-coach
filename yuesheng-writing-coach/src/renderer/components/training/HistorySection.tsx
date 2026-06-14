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

export const HistorySection: React.FC<{
  history: TrainingRecord[];
  isLoading: boolean;
  getTaskName?: (taskId: string) => string | undefined;
}> = ({ history, isLoading, getTaskName }) => {
  if (isLoading) {
    return (
      <div className={sharedStyles.trainingSection}>
        <div className={sharedStyles.trainingSectionTitle}>近期训练记录</div>
        <div className={sharedStyles.trainingEmpty}>
          <p style={{ color: 'var(--text-secondary)', fontSize: '0.875rem', margin: 0 }}>
            加载中...
          </p>
        </div>
      </div>
    );
  }

  if (history.length === 0) {
    return (
      <div className={sharedStyles.trainingSection}>
        <div className={sharedStyles.trainingSectionTitle}>近期训练记录</div>
        <div className={sharedStyles.trainingEmpty}>
          <p style={{ color: 'var(--text-secondary)', fontSize: '0.875rem', margin: 0 }}>
            暂无训练记录。完成练习后，记录会显示在此处。
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className={sharedStyles.trainingSection}>
      <div className={sharedStyles.trainingSectionTitle}>近期训练记录</div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
        {history.map((record) => (
          <div
            key={record.id}
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: 8,
              padding: '6px 0',
              fontSize: '0.85rem',
              color: record.status === 'skipped' ? 'var(--text-secondary)' : 'var(--text-primary)',
              opacity: record.status === 'skipped' ? 0.7 : 1,
            }}
          >
            <span style={{ color: statusColors[record.status] ?? '#95a5a6', fontWeight: 600, width: 20, textAlign: 'center' }}>
              {statusIcons[record.status] ?? '○'}
            </span>
            <span style={{ flex: 1 }}>{record.taskId ? (getTaskName?.(record.taskId) ?? record.taskId) : ''}</span>
            {record.effectiveness != null && (
              <span style={{ fontSize: '0.75rem', color: record.effectiveness >= 0.6 ? '#27ae60' : '#e67e22' }}>
                {Math.round(record.effectiveness * 100)}% 有效
              </span>
            )}
            <span style={{ fontSize: '0.75rem', color: 'var(--text-secondary)' }}>
              {record.completedAt ?? record.assignedAt}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
};


