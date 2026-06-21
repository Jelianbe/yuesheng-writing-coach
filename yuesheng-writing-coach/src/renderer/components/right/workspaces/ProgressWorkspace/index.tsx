import React, { useEffect, useState } from 'react';
import { SYNDROME_NAMES } from '../../../../../shared/mappings';
import { getInvoke } from '../../../../utils/ipc';
import { useSessionStore } from '../../../../stores/session.store';
import type { TeachingStateGetResponse } from '../../../../../shared/api-contracts/teaching-state.contract';
import type { AbilityProfile } from '../../../../../shared/api-contracts/ability.contract';
import type { DiagnosisEntry } from '../../../../../shared/api-contracts/diagnosis.contract';
import styles from './index.module.css';

const PHASE_STEPS = ['提交作品', '诊断分析', '教学中', '已收尾', '等待修改'];

const dotCls = (trained: boolean, severity: string) =>
  trained ? styles.dotTrained : severity === 'high' ? styles.dotHigh : styles.dotMedium;

const stepCircleCls = (stepIdx: number, currentIdx: number) =>
  stepIdx < currentIdx ? styles.stepDone : stepIdx === currentIdx ? styles.stepCurrent : styles.stepFuture;

const trendCls = (t: string) =>
  t === 'up' ? styles.trendUp : t === 'down' ? styles.trendDown : styles.trendStable;

const trendIcon = (t: string) => (t === 'up' ? '↑' : t === 'down' ? '↓' : '→');

function mapPhaseToStep(phase: string): number {
  const map: Record<string, number> = {
    P0_INIT: 0, P0_ENGAGE: 0,
    P1_WORLD: 1,
    P2_PRACTICE_LOOP: 2,
    P4_REVIEW: 3,
  };
  return map[phase] ?? 0;
}

export const ProgressWorkspace: React.FC = () => {
  const currentSessionId = useSessionStore(s => s.currentSessionId);

  const [teachingState, setTeachingState] = useState<TeachingStateGetResponse | null>(null);
  const [abilityProfile, setAbilityProfile] = useState<AbilityProfile | null>(null);
  const [diagnosisEntries, setDiagnosisEntries] = useState<DiagnosisEntry[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!currentSessionId) {
      setLoading(false);
      return;
    }

    (async () => {
      setLoading(true);
      try {
        const [tsRes, abRes, diagRes] = await Promise.all([
          getInvoke()('teachingState:get', { sessionId: currentSessionId }),
          getInvoke()('ability:getProfile', { sessionId: currentSessionId }),
          getInvoke()('diagnosis:query', { sessionId: currentSessionId, limit: 1 }),
        ]);

        const ts = tsRes as TeachingStateGetResponse | undefined;
        if (ts?.sessionId) setTeachingState(ts);

        const ab = abRes as { profile?: AbilityProfile } | undefined;
        if (ab?.profile) setAbilityProfile(ab.profile);

        const diag = diagRes as { entries?: DiagnosisEntry[] } | undefined;
        if (diag?.entries) setDiagnosisEntries(diag.entries);
      } catch (e) {
        console.warn('[ProgressWorkspace] IPC load failed', e);
      } finally {
        setLoading(false);
      }
    })();
  }, [currentSessionId]);

  if (loading) {
    return <div className={styles.title}>加载教学进度中...</div>;
  }

  if (!currentSessionId || !teachingState) {
    return (
      <div className={styles.container}>
        <h3 className={styles.title}>教学进度</h3>
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: '40px 0', gap: 8 }}>
          <span style={{ fontSize: 32, opacity: 0.3 }}>📊</span>
          <div style={{ fontSize: 13, color: '#8A7F6E' }}>暂无教学数据</div>
          <div style={{ fontSize: 11, color: '#A89F90' }}>创建会话后，教学进度将自动追踪</div>
        </div>
      </div>
    );
  }

  const ap = teachingState;
  const mastered = ap.activeProblems?.filter(p => p.trained).length ?? 0;
  const total = ap.activeProblems?.length ?? 0;
  const currentStepIdx = mapPhaseToStep(ap.currentPhase ?? '');

  return (
    <div>
      <h3 className={styles.title}>教学进度</h3>

      <div className={styles.statCard}>
        <span className={styles.statMastered}>{mastered}</span>
        <span className={styles.statSlash}>/</span>
        <span className={styles.statTotal}>{total}</span>
        <span className={styles.statLabel}>已掌握</span>
      </div>

      <div className={styles.phaseRow}>
        <span className={styles.phaseLabel}>
          当前阶段: <span className={styles.phaseValue}>{ap.phaseName || ap.currentPhase}</span>
        </span>
        <span className={styles.phaseSub}>({ap.subphaseName || ap.currentSubphase})</span>
        <div className={styles.progressTrack}>
          <div className={styles.progressFill} style={{ width: `${Math.round((ap.phaseProgress ?? 0) * 100)}%` }} />
        </div>
      </div>

      {ap.diagnosisSummary && (
        <div className={styles.diagSummary}>诊断摘要: {ap.diagnosisSummary}</div>
      )}

      <div className={styles.problemsSection}>
        <span className={styles.problemsTitle}>当前问题:</span>
        {ap.activeProblems?.map(p => (
          <div key={p.syndromeId} className={`${styles.problemRow} ${p.trained ? styles.problemRowTrained : ''}`}>
            <span className={`${styles.dot} ${dotCls(p.trained, p.severity)}`} />
            <span className={styles.problemName}>{SYNDROME_NAMES[p.syndromeId] || p.syndromeId}</span>
            {p.score !== undefined && <span className={styles.problemScore}>得分: {p.score}</span>}
            {p.trained
              ? <span className={styles.tagMastered}>✓已掌握</span>
              : <span className={styles.tagPending}>●待训练</span>
            }
          </div>
        ))}
      </div>

      <div className={styles.phaseViewTitle}>
        阶段视图 <span className={styles.phaseViewSub}>{'← 当前指针标记'}</span>
      </div>
      {PHASE_STEPS.map((n, i) => (
        <div key={i} className={styles.phaseStep}>
          <div className={`${styles.stepCircle} ${stepCircleCls(i, currentStepIdx)}`}>
            {i < currentStepIdx ? '✓' : i === currentStepIdx ? '●' : '○'}
          </div>
          <div className={styles.stepContent}>
            {i === currentStepIdx && (
              <span className={styles.pointerBadge}>
                <span className={styles.pointerDot} />
                当前指针
              </span>
            )}
            <div className={styles.stepName}>{n}</div>
            {i === 0 && <div className={styles.stepDesc}>{diagnosisEntries.length}条诊断记录</div>}
            {i === 1 && <div className={styles.stepDesc}>{ap.activeProblems?.length ?? 0}个问题</div>}
          </div>
        </div>
      ))}

      {abilityProfile && (
        <div className={styles.abilitySection}>
          <span className={styles.abilityTitle}>能力画像:</span>
          <div className={styles.abilityGrid}>
            {abilityProfile.syndromes.map(s => (
              <div key={s.syndromeId} className={styles.abilityChip}>
                <span className={styles.abilityName}>{SYNDROME_NAMES[s.syndromeId] || s.syndromeId}</span>
                <span className={styles.abilityBar}>
                  <span className={styles.abilityBarFill} style={{ width: `${Math.min((s.score / 5) * 100, 100)}%` }} />
                </span>
                <span className={styles.abilityScore}>{s.score}</span>
                <span className={trendCls(s.trend)}>{trendIcon(s.trend)}</span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
};
