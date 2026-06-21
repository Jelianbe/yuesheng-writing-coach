/**
 * TrainingBridgeCard — 对话流中的训练桥接卡片
 *
 * 当 AI 诊断后匹配到挑战模板时，在对话流底部渲染此卡片。
 * 用户可选择"进入训练工坊"或"下次再说"。
 *
 * §4.2 被动入口（V4.0 设计）
 */

import React from 'react';
import type { TrainingRecommendation } from '../../shared/types';

// ===== 类型定义 =====

export interface TrainingBridgeCardProps {
  recommendation: TrainingRecommendation;
  onEnterWorkshop: (challengeId: string) => void;
  onDismiss: () => void;
}

// ===== 样式 =====

const cardStyle: React.CSSProperties = {
  backgroundColor: 'var(--color-accent-subtle)',
  border: '1px solid var(--color-accent)',
  borderRadius: 'var(--radius-md)',
  padding: '16px 20px',
  maxWidth: '480px',
  margin: '0 auto',
};

const headerStyle: React.CSSProperties = {
  display: 'flex',
  alignItems: 'center',
  gap: '8px',
  marginBottom: '8px',
  fontSize: '0.875rem',
  fontWeight: 600,
  color: 'var(--color-accent)',
};

const descriptionStyle: React.CSSProperties = {
  fontSize: '0.875rem',
  color: 'var(--color-text-secondary)',
  lineHeight: 1.5,
  marginBottom: '12px',
};

const buttonsStyle: React.CSSProperties = {
  display: 'flex',
  gap: '8px',
};

const primaryBtnStyle: React.CSSProperties = {
  flex: 1,
  padding: '8px 16px',
  backgroundColor: 'var(--color-accent)',
  color: 'white',
  border: 'none',
  borderRadius: 'var(--radius-sm)',
  fontSize: '0.8125rem',
  fontWeight: 500,
  cursor: 'pointer',
};

const secondaryBtnStyle: React.CSSProperties = {
  flex: 1,
  padding: '8px 16px',
  backgroundColor: 'transparent',
  color: 'var(--color-text-secondary)',
  border: '1px solid var(--border)',
  borderRadius: 'var(--radius-sm)',
  fontSize: '0.8125rem',
  cursor: 'pointer',
};

// ===== 主组件 =====

export const TrainingBridgeCard: React.FC<TrainingBridgeCardProps> = ({
  recommendation,
  onEnterWorkshop,
  onDismiss,
}) => (
  <div style={cardStyle}>
    <div style={headerStyle}>
      <span style={{ fontSize: '0.85rem', color: 'var(--accent)', fontWeight: 600 }}>!</span>
      <span>匹配到练习</span>
    </div>
    <div style={descriptionStyle}>
      针对你的「{recommendation.challengeName}」问题，
      有一个聚焦核心场景的练习
    </div>
    <div style={buttonsStyle}>
      <button
        style={primaryBtnStyle}
        onClick={() => onEnterWorkshop(recommendation.challengeId)}
      >
        进入训练工坊
      </button>
      <button
        style={secondaryBtnStyle}
        onClick={onDismiss}
      >
        下次再说
      </button>
    </div>
  </div>
);


