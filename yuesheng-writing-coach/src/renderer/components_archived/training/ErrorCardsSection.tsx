/**
 * ErrorCardsSection — 训练工坊区块一：你的常见问题
 */

import React from 'react';
import type { ErrorCard, TrainingRecommendation } from '../../shared/types';
import {
  severityStyles,
  MAX_QUOTE_LENGTH,
} from './training-styles';
import sharedStyles from './TrainingShared.module.css';

export const ErrorCardsSection: React.FC<{
  cards: ErrorCard[];
  recommendations: TrainingRecommendation[];
  onStartTraining: (challengeId: string) => void;
}> = ({ cards, recommendations, onStartTraining }) => {
  // B2: 每个 card 独立展开/收起推荐列表
  const [expandedCards, setExpandedCards] = React.useState<Set<string>>(new Set());

  const toggleExpand = (syndromeId: string) => {
    setExpandedCards(prev => {
      const next = new Set(prev);
      if (next.has(syndromeId)) {
        next.delete(syndromeId);
      } else {
        next.add(syndromeId);
      }
      return next;
    });
  };
  if (cards.length === 0) {
    return (
      <div className={sharedStyles.trainingSection}>
        <div className={sharedStyles.trainingSectionTitle}>你的常见问题</div>
        <div className={sharedStyles.trainingEmpty}>
          <p style={{ color: 'var(--text-secondary)', fontSize: '0.875rem', margin: 0 }}>
            暂无诊断记录。发送写作内容后，AI 会自动分析并显示在此处。
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className={sharedStyles.trainingSection}>
      <div className={sharedStyles.trainingSectionTitle}>你的常见问题</div>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 12 }}>
        {cards.map((card) => {
          const sevStyle = severityStyles[card.severity] ?? severityStyles.L1;
          return (
            <div
              key={card.syndromeId}
              className={sharedStyles.trainingCard}
              style={{ borderLeft: `4px solid ${sevStyle.color}` }}
            >
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 6 }}>
                <div>
                  <span style={{ fontWeight: 600, fontSize: '0.875rem', color: 'var(--text-primary)' }}>
                    {card.syndromeName}
                  </span>
                  <span
                    style={{
                      display: 'inline-block',
                      marginLeft: 6,
                      padding: '1px 6px',
                      borderRadius: 8,
                      fontSize: '0.75rem',
                      fontWeight: 500,
                      color: sevStyle.color,
                      backgroundColor: sevStyle.bg,
                    }}
                  >
                    {card.severity} · {sevStyle.label}
                  </span>
                </div>
                <span style={{ fontSize: '0.75rem', color: 'var(--text-secondary)', whiteSpace: 'nowrap', marginLeft: 8 }}>
                  {card.diagnosisCount} 次诊断
                </span>
              </div>
              {card.lastQuote && (
                <div style={{
                  fontSize: '0.8rem',
                  color: 'var(--text-secondary)',
                  lineHeight: 1.5,
                  marginBottom: 8,
                  paddingLeft: 8,
                  borderLeft: '2px solid var(--border)',
                  fontStyle: 'italic',
                }}>
                  &ldquo;{card.lastQuote.length > MAX_QUOTE_LENGTH ? card.lastQuote.slice(0, MAX_QUOTE_LENGTH) + '...' : card.lastQuote}&rdquo;
                </div>
              )}
              {card.matchedChallengeId && (
                <div>
                  <button
                    className={sharedStyles.trainingStartBtn}
                    onClick={() => toggleExpand(card.syndromeId)}
                  >
                    {expandedCards.has(card.syndromeId) ? '收起推荐' : '相关训练'}
                  </button>

                  {/* B2: 展开显示与该 card 症候相关的推荐任务 */}
                  {expandedCards.has(card.syndromeId) && (
                    <div style={{ marginTop: 10, display: 'flex', flexDirection: 'column', gap: 6 }}>
                      {recommendations
                        .filter(r => r.syndromeId === card.syndromeId)
                        .map(rec => (
                          <div
                            key={rec.challengeId}
                            className={sharedStyles.trainingRecCard}
                            style={{ margin: 0, padding: '8px 10px' }}
                          >
                            <div style={{ flex: 1 }}>
                              <div style={{ fontWeight: 500, fontSize: '0.8rem', color: 'var(--text-primary)' }}>
                                {rec.challengeName}
                              </div>
                              {rec.description && (
                                <div style={{ fontSize: '0.75rem', color: 'var(--text-secondary)', marginTop: 2 }}>
                                  {rec.description}
                                </div>
                              )}
                            </div>
                            <button
                              className={sharedStyles.trainingStartBtn}
                              onClick={() => onStartTraining(rec.challengeId)}
                            >
                              开始练习
                            </button>
                          </div>
                        ))}
                      {recommendations.filter(r => r.syndromeId === card.syndromeId).length === 0 && (
                        <div style={{ fontSize: '0.75rem', color: 'var(--text-secondary)', padding: '4px 0' }}>
                          暂无相关训练任务
                        </div>
                      )}
                    </div>
                  )}
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
};


