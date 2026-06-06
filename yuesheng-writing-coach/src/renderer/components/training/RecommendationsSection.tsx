/**
 * RecommendationsSection — 训练工坊区块二：推荐训练任务
 */

import React from 'react';
import type { TrainingRecommendation } from '../../shared/types';
import {
  sectionStyle,
  sectionTitleStyle,
  emptyStyle,
  recCardStyle,
  startBtnStyle,
} from './training-styles';

const RecommendationsSection: React.FC<{
  recommendations: TrainingRecommendation[];
  onStartTraining: (challengeId: string) => void;
}> = ({ recommendations, onStartTraining }) => {
  if (recommendations.length === 0) {
    return (
      <div style={sectionStyle}>
        <div style={sectionTitleStyle}>推荐训练任务</div>
        <div style={emptyStyle}>
          <p style={{ color: 'var(--color-text-secondary)', fontSize: '0.875rem', margin: 0 }}>
            暂无推荐。完成诊断后，AI 会根据你的问题推荐针对性的练习。
          </p>
        </div>
      </div>
    );
  }

  return (
    <div style={sectionStyle}>
      <div style={sectionTitleStyle}>推荐训练任务</div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        {recommendations.map((rec) => (
          <div
            key={rec.challengeId}
            style={{
              ...recCardStyle,
              borderLeft: `4px solid var(--color-accent-primary)`,
            }}
          >
            <div style={{ flex: 1 }}>
              <div style={{ fontWeight: 600, fontSize: '0.875rem', color: 'var(--color-text-primary)', marginBottom: 2 }}>
                {rec.challengeName}
                <span style={{
                  marginLeft: 6,
                  fontSize: '0.75rem',
                  fontWeight: 400,
                  color: 'var(--color-text-secondary)',
                  backgroundColor: 'var(--color-accent-subtle)',
                  padding: '1px 6px',
                  borderRadius: 8,
                }}>
                  {rec.tier === 'structural' ? '结构性问题' : '表面优化'} · ~15min
                </span>
              </div>
              <div style={{ fontSize: '0.8rem', color: 'var(--color-text-secondary)', lineHeight: 1.5, marginBottom: 6 }}>
                {rec.description}
              </div>
              {rec.constraint && (
                <div style={{
                  fontSize: '0.75rem',
                  color: '#d35400',
                  backgroundColor: '#fef5e7',
                  padding: '2px 8px',
                  borderRadius: 4,
                  display: 'inline-block',
                  marginBottom: 8,
                }}>
                  约束：{rec.constraint}
                </div>
              )}
            </div>
            <button
              style={startBtnStyle}
              onClick={() => onStartTraining(rec.challengeId)}
            >
              开始练习
            </button>
          </div>
        ))}
      </div>
    </div>
  );
};

export default RecommendationsSection;
