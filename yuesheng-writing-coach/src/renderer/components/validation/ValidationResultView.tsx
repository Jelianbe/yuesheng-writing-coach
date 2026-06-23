/**
 * ValidationResultView — 验证结果展示
 *
 * 展示训练评估结果：评分、反馈、掌握度
 * 提供"进入复盘"入口
 */

import React from 'react';
import type { EvaluationResult } from '../../shared/types';
import sharedStyles from '../training/TrainingShared.module.css';

export interface ValidationResultViewProps {
  /** 评估结果 */
  evaluationResult: EvaluationResult | null;
  /** 提交反馈 */
  feedback: string;
  /** 已掌握技法 ID 列表 */
  masteredSyndromeIds: string[];
  /** 进入复盘阶段 */
  onEnterRetro?: () => void;
  /** 返回对话 */
  onBackToChat: () => void;
}

export const ValidationResultView: React.FC<ValidationResultViewProps> = ({
  evaluationResult,
  feedback,
  masteredSyndromeIds,
  onEnterRetro,
  onBackToChat,
}) => {
  const hasMastered = masteredSyndromeIds.length > 0;
  const score = evaluationResult?.score ?? 0;
  const displayFeedback = evaluationResult?.feedback ?? feedback;

  return (
    <div className={`${sharedStyles.retroContainer} animate-fade-in`}>
      <div className={sharedStyles.retroHeader}>
        <div style={{ fontSize: '1.1rem', fontWeight: 600, color: 'var(--text-primary)' }}>
          验证结果
        </div>
      </div>

      <div className={sharedStyles.retroBody}>
        <div className={sharedStyles.retroCard}>
          <div style={{ fontSize: '0.85rem', color: 'var(--text-secondary)', marginBottom: 12 }}>
            {hasMastered ? '🎉 你在本项训练中表现良好' : '继续练习，你的进步会在积累中显现'}
          </div>

          {/* 评分展示 */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 16, marginBottom: 16 }}>
            <div style={{
              width: 64, height: 64, borderRadius: '50%',
              background: score >= 7 ? 'var(--success-light)' : 'var(--warning-light)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              fontSize: '1.5rem', fontWeight: 700,
              color: score >= 7 ? 'var(--success)' : 'var(--warning)',
            }}>
              {score}/10
            </div>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: '0.95rem', color: 'var(--text-primary)', marginBottom: 4 }}>
                评分
              </div>
              <div style={{
                height: 8, borderRadius: 4,
                background: 'var(--border)',
                overflow: 'hidden',
              }}>
                <div style={{
                  height: '100%', width: `${(score / 10) * 100}%`,
                  borderRadius: 4,
                  background: score >= 7
                    ? 'var(--success)'
                    : score >= 5
                      ? 'var(--warning)'
                      : 'var(--error)',
                  transition: 'width 0.5s ease',
                }} />
              </div>
            </div>
          </div>

          {/* 反馈文本 */}
          <div style={{
            padding: 12, borderRadius: 8,
            background: 'var(--accent-subtle)',
            fontSize: '0.875rem', lineHeight: 1.6,
            color: 'var(--text-primary)',
            marginBottom: 16,
          }}>
            {displayFeedback}
          </div>

          {/* 掌握状态 */}
          {hasMastered && (
            <div style={{
              padding: '8px 12px', borderRadius: 6,
              background: 'var(--success-light)',
              fontSize: '0.85rem', color: 'var(--success)',
              marginBottom: 16,
            }}>
              已掌握 {masteredSyndromeIds.length} 个技法方向
            </div>
          )}
        </div>
      </div>

      {/* 操作区 */}
      <div className={sharedStyles.retroFooter}>
        <div style={{ display: 'flex', gap: 8 }}>
          <button
            className={sharedStyles.secondaryBtn}
            onClick={onBackToChat}
          >
            返回对话
          </button>
          {onEnterRetro && (
            <button
              className={sharedStyles.primaryBtn}
              onClick={onEnterRetro}
            >
              进入复盘
            </button>
          )}
        </div>
      </div>
    </div>
  );
};
