/**
 * AbilityProfilePanel — 能力画像面板
 *
 * 通过 IPC ability:getProfile 获取 AbilityProfile 数据，展示：
 * - 能力评分（含趋势）
 * - 弱点标签
 * - 训练统计
 * - 诊断趋势
 */

import React, { useEffect, useState, useCallback } from 'react';
import { User, TrendingUp, TrendingDown, Minus, Target, ClipboardCheck, AlertTriangle } from 'lucide-react';
import type { AbilityProfile, AbilityScore, WeakPoint } from '../../shared/types';
import { getInvoke } from '../../utils/ipc';
import { IPC_CHANNELS } from '../../shared/constants';
import { useSessionStore } from '../../stores/session.store';
import styles from './panel-shared.module.css';

/** 能力评分条 */
const ScoreBar: React.FC<{ score: AbilityScore }> = ({ score }) => {
  const trendIcon = score.trend === 'up'
    ? <TrendingUp size={12} strokeWidth={1.8} color="var(--success)" />
    : score.trend === 'down'
      ? <TrendingDown size={12} strokeWidth={1.8} color="var(--error)" />
      : <Minus size={12} strokeWidth={1.8} color="var(--text-tertiary)" />;

  const barColorClass = score.score >= 70 ? styles.barFillHigh
    : score.score >= 40 ? styles.barFillMid
    : styles.barFillLow;

  return (
    <div style={{ padding: '6px 0' }}>
      <div className={`${styles.flexBetween}`} style={{ marginBottom: 3 }}>
        <span className={`${styles.textMd} ${styles.textPrimary} ${styles.fontMedium}`}>
          {score.abilityName}
        </span>
        <div className={`${styles.flexAlignCenter} ${styles.flexGap4}`}>
          <span
            className={`${styles.textMd} ${styles.fontSemiBold}`}
            style={{ color: score.dataInsufficient ? 'var(--text-tertiary)' : 'var(--text-primary)' }}
          >
            {score.dataInsufficient ? '--' : score.score.toFixed(0)}
          </span>
          {trendIcon}
        </div>
      </div>
      <div className={styles.barTrack}>
        <div
          className={`${styles.barFill} ${barColorClass}`}
          style={{
            width: score.dataInsufficient ? 0 : `${Math.min(score.score, 100)}%`,
            opacity: score.dataInsufficient ? 0.5 : undefined,
          }}
        />
      </div>
    </div>
  );
};

/** 弱点标签 */
const WeakPointBadge: React.FC<{ weak: WeakPoint }> = ({ weak }) => {
  const trendColor = weak.trend === 'improving' ? 'var(--success)' : weak.trend === 'worsening' ? 'var(--error)' : 'var(--text-tertiary)';

  return (
    <div className={styles.weakPointRow}>
      <AlertTriangle size={12} strokeWidth={1.8} color={trendColor} />
      <span className={`${styles.textPrimary} ${styles.truncate}`} style={{ flex: 1 }}>
        {weak.syndromeName}
      </span>
      <span className={styles.weakCountBadge} style={{ color: trendColor }}>
        {weak.occurrenceCount}次 · L{Math.round(weak.avgSeverity)}
      </span>
    </div>
  );
};

export const AbilityProfilePanel: React.FC = () => {
  const [profile, setProfile] = useState<AbilityProfile | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const sessionId = useSessionStore(s => s.currentSessionId);

  const fetchProfile = useCallback(async () => {
    if (!sessionId) return;
    setLoading(true);
    setError(null);
    try {
      const invoke = getInvoke();
      const result = await invoke(IPC_CHANNELS.ABILITY_GET_PROFILE, { sessionId }) as {
        success: boolean; data?: AbilityProfile | null; error?: string;
      };
      if (result.success && result.data) {
        setProfile(result.data);
      } else if (result.success && !result.data) {
        setProfile(null);
      } else {
        setError(result.error || '获取能力画像失败');
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : '未知错误');
    } finally {
      setLoading(false);
    }
  }, [sessionId]);

  useEffect(() => { fetchProfile(); }, [fetchProfile]);

  if (loading) {
    return (
      <div className={styles.loadingContainer}>
        加载中...
      </div>
    );
  }

  if (error) {
    return (
      <div className={`${styles.flexCol} ${styles.flexGap8} ${styles.textCenter} ${styles.textBase} ${styles.textError}`} style={{ padding: '24px' }}>
        <AlertTriangle size={24} strokeWidth={1.4} style={{ margin: '0 auto', opacity: 0.5 }} />
        <span>加载失败</span>
        <span className={styles.textSm} style={{ opacity: 0.7 }}>{error}</span>
        <button onClick={fetchProfile} className={styles.retryBtn}>
          重试
        </button>
      </div>
    );
  }

  if (!profile || profile.abilities.length === 0) {
    return (
      <div className={styles.emptyState}>
        <User size={36} strokeWidth={1.4} opacity={0.3} />
        <span className={styles.textLg}>暂无能力画像数据</span>
        <span className={styles.textSm}>进行诊断后，能力画像将自动生成</span>
      </div>
    );
  }

  return (
    <div className={styles.panelContainer}>
      {/* 能力评分 */}
      <div>
        <div className={styles.sectionHeader}>
          <Target size={13} strokeWidth={1.6} /> 能力评分
        </div>
        <div className={`${styles.card} ${styles.cardPaddingSm}`}>
          {profile.abilities.map(a => <ScoreBar key={a.abilityId} score={a} />)}
        </div>
      </div>

      {/* 弱点标签 */}
      {profile.weakPoints.length > 0 && (
        <div>
          <div className={styles.sectionHeader}>
            <AlertTriangle size={13} strokeWidth={1.6} /> 薄弱环节
          </div>
          <div className={`${styles.card} ${styles.flexCol}`}>
            {profile.weakPoints.map(w => <WeakPointBadge key={w.syndromeId} weak={w} />)}
          </div>
        </div>
      )}

      {/* 统计摘要 */}
      <div>
        <div className={styles.sectionHeader}>
          <ClipboardCheck size={13} strokeWidth={1.6} /> 训练概况
        </div>
        <div className={styles.grid3Col}>
          <div className={styles.statBox}>
            <div className={`${styles.textXl} ${styles.fontSemiBold} ${styles.textAccent}`}>{profile.trainingStats.totalAssigned}</div>
            <div className={`${styles.textXs} ${styles.textTertiary}`} style={{ marginTop: 2 }}>总任务数</div>
          </div>
          <div className={styles.statBox}>
            <div className={`${styles.textXl} ${styles.fontSemiBold} ${styles.textSuccess}`}>{profile.trainingStats.totalCompleted}</div>
            <div className={`${styles.textXs} ${styles.textTertiary}`} style={{ marginTop: 2 }}>已完成</div>
          </div>
          <div className={styles.statBox}>
            <div className={`${styles.textXl} ${styles.fontSemiBold} ${styles.textPrimary}`}>{(profile.trainingStats.completionRate * 100).toFixed(0)}%</div>
            <div className={`${styles.textXs} ${styles.textTertiary}`} style={{ marginTop: 2 }}>完成率</div>
          </div>
        </div>
      </div>

      {/* 诊断趋势 */}
      <div>
        <div className={styles.sectionHeader}>
          <ClipboardCheck size={13} strokeWidth={1.6} /> 诊断数据
        </div>
        <div className={`${styles.flexRow} ${styles.flexGap8} ${styles.textSm} ${styles.textTertiary}`}>
          <span>诊断次数: <strong style={{ color: 'var(--text-primary)' }}>{profile.diagnosisTrend.totalDiagnoses}</strong></span>
          <span>平均置信度: <strong style={{ color: 'var(--text-primary)' }}>{(profile.diagnosisTrend.avgConfidence * 100).toFixed(0)}%</strong></span>
        </div>
      </div>

      {/* 底部时间戳 */}
      <div className={styles.footerNote}>
        更新于 {new Date(profile.computedAt).toLocaleString()}
      </div>
    </div>
  );
};
