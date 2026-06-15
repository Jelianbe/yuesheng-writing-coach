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

const EASE_OUT_QUART = 'cubic-bezier(0.25, 1, 0.5, 1)';

/** 能力评分条 */
const ScoreBar: React.FC<{ score: AbilityScore }> = ({ score }) => {
  const trendIcon = score.trend === 'up'
    ? <TrendingUp size={12} strokeWidth={1.8} color="var(--success)" />
    : score.trend === 'down'
      ? <TrendingDown size={12} strokeWidth={1.8} color="var(--error)" />
      : <Minus size={12} strokeWidth={1.8} color="var(--text-tertiary)" />;

  return (
    <div style={{ padding: '6px 0' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 3 }}>
        <span style={{ fontSize: '0.78rem', color: 'var(--text-primary)', fontWeight: 500 }}>
          {score.abilityName}
        </span>
        <div style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
          <span style={{ fontSize: '0.78rem', fontWeight: 600, color: score.dataInsufficient ? 'var(--text-tertiary)' : 'var(--text-primary)' }}>
            {score.dataInsufficient ? '--' : score.score.toFixed(0)}
          </span>
          {trendIcon}
        </div>
      </div>
      <div style={{ height: 4, borderRadius: 2, background: 'var(--bg-hover)', position: 'relative', overflow: 'hidden' }}>
        <div style={{
          height: '100%',
          width: score.dataInsufficient ? 0 : `${Math.min(score.score, 100)}%`,
          borderRadius: 2,
          background: score.score >= 70 ? 'var(--success)' : score.score >= 40 ? 'var(--accent)' : 'var(--error)',
          opacity: score.dataInsufficient ? 0.5 : 0.8,
          transition: `width 600ms ${EASE_OUT_QUART}`,
        }} />
      </div>
    </div>
  );
};

/** 弱点标签 */
const WeakPointBadge: React.FC<{ weak: WeakPoint }> = ({ weak }) => {
  const trendColor = weak.trend === 'improving' ? 'var(--success)' : weak.trend === 'worsening' ? 'var(--error)' : 'var(--text-tertiary)';

  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 6,
      padding: '6px 8px', borderRadius: 'var(--radius-sm)',
      fontSize: '0.78rem',
      transition: `background 150ms ${EASE_OUT_QUART}`,
    }}
      onMouseEnter={e => { (e.currentTarget as HTMLElement).style.background = 'var(--bg-hover)'; }}
      onMouseLeave={e => { (e.currentTarget as HTMLElement).style.background = 'transparent'; }}
    >
      <AlertTriangle size={12} strokeWidth={1.8} color={trendColor} />
      <span style={{ flex: 1, color: 'var(--text-primary)', minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
        {weak.syndromeName}
      </span>
      <span style={{ fontSize: '0.65rem', color: trendColor, fontWeight: 500 }}>
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
      <div style={{ padding: '24px', textAlign: 'center', color: 'var(--text-tertiary)', fontSize: '0.82rem' }}>
        加载中...
      </div>
    );
  }

  if (error) {
    return (
      <div style={{ padding: '24px', textAlign: 'center', color: 'var(--error)', fontSize: '0.82rem', display: 'flex', flexDirection: 'column', gap: 8 }}>
        <AlertTriangle size={24} strokeWidth={1.4} style={{ margin: '0 auto', opacity: 0.5 }} />
        <span>加载失败</span>
        <span style={{ fontSize: '0.72rem', opacity: 0.7 }}>{error}</span>
        <button onClick={fetchProfile}
          style={{ padding: '4px 12px', border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', background: 'transparent', color: 'var(--text-secondary)', cursor: 'pointer', fontSize: '0.72rem', fontFamily: 'var(--font-body)' }}>
          重试
        </button>
      </div>
    );
  }

  if (!profile || profile.abilities.length === 0) {
    return (
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: '40px 20px', color: 'var(--text-tertiary)', gap: 12, textAlign: 'center' }}>
        <User size={36} strokeWidth={1.4} opacity={0.3} />
        <span style={{ fontSize: '0.85rem' }}>暂无能力画像数据</span>
        <span style={{ fontSize: '0.72rem' }}>进行诊断后，能力画像将自动生成</span>
      </div>
    );
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      {/* 能力评分 */}
      <div>
        <div style={{ fontSize: '0.72rem', fontWeight: 600, color: 'var(--text-secondary)', letterSpacing: '0.03em', padding: '0 2px 8px', display: 'flex', alignItems: 'center', gap: 4 }}>
          <Target size={13} strokeWidth={1.6} /> 能力评分
        </div>
        <div style={{ border: '1px solid var(--border-light)', borderRadius: 'var(--radius-md)', padding: '4px 10px' }}>
          {profile.abilities.map(a => <ScoreBar key={a.abilityId} score={a} />)}
        </div>
      </div>

      {/* 弱点标签 */}
      {profile.weakPoints.length > 0 && (
        <div>
          <div style={{ fontSize: '0.72rem', fontWeight: 600, color: 'var(--text-secondary)', letterSpacing: '0.03em', padding: '0 2px 8px', display: 'flex', alignItems: 'center', gap: 4 }}>
            <AlertTriangle size={13} strokeWidth={1.6} /> 薄弱环节
          </div>
          <div style={{ border: '1px solid var(--border-light)', borderRadius: 'var(--radius-md)', display: 'flex', flexDirection: 'column' }}>
            {profile.weakPoints.map(w => <WeakPointBadge key={w.syndromeId} weak={w} />)}
          </div>
        </div>
      )}

      {/* 统计摘要 */}
      <div>
        <div style={{ fontSize: '0.72rem', fontWeight: 600, color: 'var(--text-secondary)', letterSpacing: '0.03em', padding: '0 2px 8px', display: 'flex', alignItems: 'center', gap: 4 }}>
          <ClipboardCheck size={13} strokeWidth={1.6} /> 训练概况
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 6 }}>
          <div style={{ padding: '10px 4px', borderRadius: 'var(--radius-sm)', background: 'var(--bg-hover)', textAlign: 'center' }}>
            <div style={{ fontSize: '1rem', fontWeight: 600, color: 'var(--accent)' }}>{profile.trainingStats.totalAssigned}</div>
            <div style={{ fontSize: '0.62rem', color: 'var(--text-tertiary)', marginTop: 2 }}>总任务数</div>
          </div>
          <div style={{ padding: '10px 4px', borderRadius: 'var(--radius-sm)', background: 'var(--bg-hover)', textAlign: 'center' }}>
            <div style={{ fontSize: '1rem', fontWeight: 600, color: 'var(--success)' }}>{profile.trainingStats.totalCompleted}</div>
            <div style={{ fontSize: '0.62rem', color: 'var(--text-tertiary)', marginTop: 2 }}>已完成</div>
          </div>
          <div style={{ padding: '10px 4px', borderRadius: 'var(--radius-sm)', background: 'var(--bg-hover)', textAlign: 'center' }}>
            <div style={{ fontSize: '1rem', fontWeight: 600, color: 'var(--text-primary)' }}>{(profile.trainingStats.completionRate * 100).toFixed(0)}%</div>
            <div style={{ fontSize: '0.62rem', color: 'var(--text-tertiary)', marginTop: 2 }}>完成率</div>
          </div>
        </div>
      </div>

      {/* 诊断趋势 */}
      <div>
        <div style={{ fontSize: '0.72rem', fontWeight: 600, color: 'var(--text-secondary)', letterSpacing: '0.03em', padding: '0 2px 8px', display: 'flex', alignItems: 'center', gap: 4 }}>
          <ClipboardCheck size={13} strokeWidth={1.6} /> 诊断数据
        </div>
        <div style={{ display: 'flex', gap: 8, fontSize: '0.72rem', color: 'var(--text-tertiary)' }}>
          <span>诊断次数: <strong style={{ color: 'var(--text-primary)' }}>{profile.diagnosisTrend.totalDiagnoses}</strong></span>
          <span>平均置信度: <strong style={{ color: 'var(--text-primary)' }}>{(profile.diagnosisTrend.avgConfidence * 100).toFixed(0)}%</strong></span>
        </div>
      </div>

      {/* 底部时间戳 */}
      <div style={{ padding: '4px 2px 0', fontSize: '0.62rem', color: 'var(--text-tertiary)', opacity: 0.6, borderTop: '1px solid var(--border-light)' }}>
        更新于 {new Date(profile.computedAt).toLocaleString()}
      </div>
    </div>
  );
};


