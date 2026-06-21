/**
 * RetroSummaryView — 复盘总结展示
 *
 * 展示训练历史的整体复盘：
 * - 总训练次数 / 症候覆盖数
 * - 各症候改善趋势（初始分 → 当前分，改善幅度）
 * - 已掌握技法列表
 * - 建议继续关注的症候
 * - 总结评语
 */

import React from 'react';
import sharedStyles from '../training/TrainingShared.module.css';

export interface SyndromeRetroSummary {
  syndromeId: string;
  syndromeName: string;
  trainingCount: number;
  initialScore: number | null;
  currentScore: number | null;
  improvement: number | null;
  mastered: boolean;
}

export interface RetroSummaryViewProps {
  /** 总训练次数 */
  totalTrainingCount: number;
  /** 参与的症候数量 */
  syndromeCount: number;
  /** 各症候训练记录摘要 */
  syndromeSummaries: SyndromeRetroSummary[];
  /** 总体改善幅度（0-100%） */
  overallImprovement: number;
  /** 已掌握技法列表 */
  masteredTechniques: string[];
  /** 建议继续关注的症候 */
  recommendedFocus: string[];
  /** 总结评语 */
  summary: string;
  /** 返回对话 */
  onBackToChat: () => void;
  /** 进入新训练 */
  onStartNewTraining?: () => void;
}

export const RetroSummaryView: React.FC<RetroSummaryViewProps> = ({
  totalTrainingCount,
  syndromeCount,
  syndromeSummaries,
  overallImprovement,
  masteredTechniques,
  recommendedFocus,
  summary,
  onBackToChat,
  onStartNewTraining,
}) => {
  return (
    <div className={`${sharedStyles.retroContainer} animate-fade-in`}>
      <div className={sharedStyles.retroHeader}>
        <div style={{ fontSize: '1.1rem', fontWeight: 600, color: 'var(--text-primary)' }}>
          复盘总结
        </div>
      </div>

      <div className={sharedStyles.retroBody}>
        <div style={{ maxWidth: 640, margin: '0 auto', display: 'flex', flexDirection: 'column', gap: 20 }}>
          {/* 总体概况 */}
          <div className={sharedStyles.retroCard}>
            <div style={{ fontSize: '0.95rem', fontWeight: 600, color: 'var(--text-primary)', marginBottom: 12 }}>
              总体概况
            </div>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 12 }}>
              <StatCard label="训练次数" value={String(totalTrainingCount)} />
              <StatCard label="涉及症候" value={String(syndromeCount)} />
              <StatCard label="改善幅度" value={improvementLabel(overallImprovement)} color={overallImprovement > 0 ? 'var(--success, #2e7d32)' : 'var(--text-secondary)'} />
            </div>
          </div>

          {/* 各症候详情 */}
          {syndromeSummaries.length > 0 && (
            <div className={sharedStyles.retroCard}>
              <div style={{ fontSize: '0.95rem', fontWeight: 600, color: 'var(--text-primary)', marginBottom: 12 }}>
                症候改善详情
              </div>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                {syndromeSummaries.map((s) => (
                  <div key={s.syndromeId} style={{
                    display: 'flex', alignItems: 'center', gap: 12,
                    padding: '10px 12px', borderRadius: 6,
                    background: s.mastered ? 'var(--success-light, #e8f5e9)' : 'transparent',
                    border: '1px solid var(--border)',
                  }}>
                    <div style={{ flex: 1 }}>
                      <div style={{ fontSize: '0.85rem', fontWeight: 500, color: 'var(--text-primary)' }}>
                        {s.syndromeName}
                        {s.mastered && (
                          <span style={{ marginLeft: 8, fontSize: '0.75rem', color: 'var(--success, #2e7d32)' }}>
                            ✅ 已掌握
                          </span>
                        )}
                      </div>
                      <div style={{ fontSize: '0.75rem', color: 'var(--text-secondary)', marginTop: 2 }}>
                        {s.trainingCount} 次训练
                        {s.initialScore != null && ` | 初始分 ${s.initialScore}`}
                        {s.currentScore != null && ` → 当前分 ${s.currentScore}`}
                      </div>
                    </div>
                    {s.improvement != null && (
                      <div style={{
                        fontSize: '0.85rem', fontWeight: 600,
                        color: s.improvement >= 0 ? 'var(--success, #2e7d32)' : 'var(--danger, #c62828)',
                      }}>
                        {s.improvement >= 0 ? '+' : ''}{s.improvement}%
                      </div>
                    )}
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* 已掌握技法 */}
          {masteredTechniques.length > 0 && (
            <div className={sharedStyles.retroCard}>
              <div style={{ fontSize: '0.95rem', fontWeight: 600, color: 'var(--text-primary)', marginBottom: 12 }}>
                已掌握技法
              </div>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
                {masteredTechniques.map((t, i) => (
                  <span key={i} style={{
                    padding: '4px 10px', borderRadius: 12,
                    background: 'var(--success-light, #e8f5e9)', color: 'var(--success, #2e7d32)',
                    fontSize: '0.8rem', fontWeight: 500,
                  }}>
                    ✅ {t}
                  </span>
                ))}
              </div>
            </div>
          )}

          {/* 建议继续关注 */}
          {recommendedFocus.length > 0 && (
            <div className={sharedStyles.retroCard}>
              <div style={{ fontSize: '0.95rem', fontWeight: 600, color: 'var(--text-primary)', marginBottom: 12 }}>
                建议继续关注
              </div>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
                {recommendedFocus.map((f, i) => (
                  <span key={i} style={{
                    padding: '4px 10px', borderRadius: 12,
                    background: 'var(--warning-light, #fff3e0)', color: 'var(--warning, #f57c00)',
                    fontSize: '0.8rem', fontWeight: 500,
                  }}>
                    {f}
                  </span>
                ))}
              </div>
            </div>
          )}

          {/* 总结评语 */}
          <div className={sharedStyles.retroCard}>
            <div style={{ fontSize: '0.95rem', fontWeight: 600, color: 'var(--text-primary)', marginBottom: 12 }}>
              教练寄语
            </div>
            <div style={{ fontSize: '0.875rem', lineHeight: 1.6, color: 'var(--text-primary)' }}>
              {summary}
            </div>
          </div>
        </div>
      </div>

      <div className={sharedStyles.retroFooter}>
        <div style={{ display: 'flex', gap: 8 }}>
          <button className={sharedStyles.secondaryBtn} onClick={onBackToChat}>
            返回对话
          </button>
          {onStartNewTraining && (
            <button className={sharedStyles.primaryBtn} onClick={onStartNewTraining}>
              继续训练
            </button>
          )}
        </div>
      </div>
    </div>
  );
};

// ---- 辅助组件 ----

interface StatCardProps {
  label: string;
  value: string;
  color?: string;
}

const StatCard: React.FC<StatCardProps> = ({ label, value, color }) => (
  <div style={{
    textAlign: 'center', padding: '12px 8px',
    borderRadius: 6, background: 'var(--bg-secondary)',
  }}>
    <div style={{ fontSize: '1.3rem', fontWeight: 700, color: color ?? 'var(--text-primary)' }}>
      {value}
    </div>
    <div style={{ fontSize: '0.75rem', color: 'var(--text-secondary)', marginTop: 4 }}>
      {label}
    </div>
  </div>
);

function improvementLabel(value: number): string {
  if (value > 0) return `+${value}%`;
  if (value < 0) return `${value}%`;
  return '—';
}
