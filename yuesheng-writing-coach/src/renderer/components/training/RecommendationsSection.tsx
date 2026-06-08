/**
 * RecommendationsSection — 训练工坊区块二：推荐训练任务
 *
 * 当推荐卡片的 challengeId 能映射到结构化任务（structured-tasks.ts）时，
 * 展示丰富的任务信息（内容、字数、禁止词等）；否则 fallback 到原有行为。
 */

import React from 'react';
import type { TrainingRecommendation } from '../../shared/types';
import { getStructuredTasksForChallenge } from '../../shared/structured-tasks';
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
          <p style={{ color: 'var(--text-secondary)', fontSize: '0.875rem', margin: 0 }}>
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
        {recommendations.map((rec) => {
          const structuredTasks = getStructuredTasksForChallenge(rec.challengeId);
          const hasStructuredTasks = structuredTasks.length > 0;

          return (
            <div
              key={rec.challengeId}
              style={{
                ...recCardStyle,
                borderLeft: `4px solid var(--accent)`,
              }}
            >
              <div style={{ flex: 1 }}>
                <div style={{ fontWeight: 600, fontSize: '0.875rem', color: 'var(--text-primary)', marginBottom: 2 }}>
                  {rec.challengeName}
                  <span style={{
                    marginLeft: 6,
                    fontSize: '0.75rem',
                    fontWeight: 400,
                    color: 'var(--text-secondary)',
                    backgroundColor: 'var(--accent-subtle)',
                    padding: '1px 6px',
                    borderRadius: 8,
                  }}>
                    {rec.tier === 'structural' ? '结构性问题' : '表面优化'} · ~15min
                  </span>
                  {hasStructuredTasks && (
                    <span style={{
                      marginLeft: 6,
                      fontSize: '0.75rem',
                      fontWeight: 400,
                      color: '#27ae60',
                      backgroundColor: '#eafaf1',
                      padding: '1px 6px',
                      borderRadius: 8,
                    }}>
                      结构化任务 ×{structuredTasks.length}
                    </span>
                  )}
                </div>
                <div style={{ fontSize: '0.8rem', color: 'var(--text-secondary)', lineHeight: 1.5, marginBottom: 6 }}>
                  {rec.description}
                </div>

                {/* ===== 结构化任务丰富信息展示 ===== */}
                {hasStructuredTasks && (
                  <div style={{
                    marginTop: 8,
                    padding: '10px 12px',
                    backgroundColor: 'var(--bg-secondary)',
                    borderRadius: 6,
                    border: '1px solid var(--border)',
                    fontSize: '0.8rem',
                  }}>
                    {/* 任务内容预览（取第一个任务的 content） */}
                    {structuredTasks[0].content && (
                      <div style={{ marginBottom: 8, color: 'var(--text-primary)', lineHeight: 1.6 }}>
                        <span style={{ fontWeight: 500, color: 'var(--text-secondary)', fontSize: '0.75rem' }}>任务要求：</span>
                        {structuredTasks[0].content.split('\n')[0]}
                      </div>
                    )}

                    {/* 元信息行：字数 + 禁止词 + 场景 */}
                    <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap', fontSize: '0.75rem', color: 'var(--text-tertiary)' }}>
                      {structuredTasks[0].wordCount && (
                        <span style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
                          <span>📝</span> 目标字数：{structuredTasks[0].wordCount} 字
                        </span>
                      )}
                      {structuredTasks[0].forbiddenWords && structuredTasks[0].forbiddenWords.length > 0 && (
                        <span style={{ display: 'flex', alignItems: 'center', gap: 4, color: '#e74c3c' }}>
                          <span>🚫</span> 禁止词：{structuredTasks[0].forbiddenWords.length} 个
                        </span>
                      )}
                      {structuredTasks[0].scene && (
                        <span style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
                          <span>🎬</span> 场景设定
                        </span>
                      )}
                      {structuredTasks[0].mode === 'reading' && (
                        <span style={{ display: 'flex', alignItems: 'center', gap: 4, color: '#3498db' }}>
                          <span>📖</span> 阅读任务
                        </span>
                      )}
                    </div>

                    {/* 禁止词标签（仅当数量较少时展示） */}
                    {structuredTasks[0].forbiddenWords && structuredTasks[0].forbiddenWords.length > 0 && structuredTasks[0].forbiddenWords.length <= 6 && (
                      <div style={{ marginTop: 8, display: 'flex', flexWrap: 'wrap', gap: 4 }}>
                        {structuredTasks[0].forbiddenWords.map((word) => (
                          <span
                            key={word}
                            style={{
                              fontSize: '0.7rem',
                              padding: '1px 6px',
                              borderRadius: 4,
                              backgroundColor: '#fdf0ef',
                              color: '#c0392b',
                              border: '1px solid #fadbd8',
                            }}
                          >
                            {word}
                          </span>
                        ))}
                      </div>
                    )}
                  </div>
                )}

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
              {rec.techniques && rec.techniques.length > 0 && (
                <div style={{ marginTop: 4, fontSize: '0.75rem', color: 'var(--text-secondary)' }}>
                  <span style={{ fontWeight: 500 }}>参考技法：</span>
                  {rec.techniques.map((t, i) => (
                    <span key={t.id}>
                      {i > 0 && ' · '}
                      <span title={t.description}>{t.name}（{t.source}）</span>
                    </span>
                  ))}
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
          );
        })}
      </div>
    </div>
  );
};

export default RecommendationsSection;
