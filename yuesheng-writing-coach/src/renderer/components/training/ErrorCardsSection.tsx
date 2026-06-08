/**
 * ErrorCardsSection — 训练工坊区块一：你的常见问题
 */

import React from 'react';
import type { ErrorCard } from '../../shared/types';
import {
  sectionStyle,
  sectionTitleStyle,
  emptyStyle,
  cardStyle,
  startBtnStyle,
  severityStyles,
  MAX_QUOTE_LENGTH,
} from './training-styles';

const ErrorCardsSection: React.FC<{
  cards: ErrorCard[];
  onStartTraining: (challengeId: string) => void;
}> = ({ cards, onStartTraining }) => {
  if (cards.length === 0) {
    return (
      <div style={sectionStyle}>
        <div style={sectionTitleStyle}>你的常见问题</div>
        <div style={emptyStyle}>
          <p style={{ color: 'var(--text-secondary)', fontSize: '0.875rem', margin: 0 }}>
            暂无诊断记录。发送写作内容后，AI 会自动分析并显示在此处。
          </p>
        </div>
      </div>
    );
  }

  return (
    <div style={sectionStyle}>
      <div style={sectionTitleStyle}>你的常见问题</div>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 12 }}>
        {cards.map((card) => {
          const sevStyle = severityStyles[card.severity] ?? severityStyles.L1;
          return (
            <div
              key={card.syndromeId}
              style={{
                ...cardStyle,
                borderLeft: `4px solid ${sevStyle.color}`,
              }}
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
                <button
                  style={startBtnStyle}
                  onClick={() => onStartTraining(card.matchedChallengeId!)}
                >
                  开始练习
                </button>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
};

export default ErrorCardsSection;
