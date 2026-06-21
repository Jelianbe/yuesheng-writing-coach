/**
 * TeachingNoteWorkspace — 教学笔记工作区（GAP-02 / H-04）
 *
 * 数据源：trainingStore（训练记录）、teachingStateStore（教学状态）。
 *
 * 用法:
 * ```tsx
 * <TeachingNoteWorkspace />
 * ```
 */
import { useMemo } from 'react';
import { useTrainingStore, selectTrainingHistory } from '@/stores/training.store';
import { useTeachingStateStore } from '@/stores/teaching-state.store';
import styles from './index.module.css';

// ===== 子组件 =====

function DiagnosisSummary(): JSX.Element {
  const currentState = useTeachingStateStore((s) => s.currentState);
  const sessionId = currentState?.sessionId ?? null;
  const activeProblems = currentState?.activeProblems ?? [];
  const diagnosisSummary = currentState?.diagnosisSummary ?? null;

  return (
    <div className={`${styles.card} ${styles.diagnosisCard}`}>
      <h4 className={styles.sectionTitle}>诊断结果摘要</h4>
      {diagnosisSummary ? (
        <p className={styles.noteDetail}>{diagnosisSummary}</p>
      ) : (
        <p className={styles.noteDetail}>暂无诊断摘要</p>
      )}
      <p className={styles.noteDetail}>
        活跃问题数：{activeProblems.length} 个
      </p>
      <p className={styles.noteDetail}>
        当前会话：{sessionId ? '进行中' : '未选择'}
      </p>
    </div>
  );
}

function CoachSuggestions(): JSX.Element {
  const currentState = useTeachingStateStore((s) => s.currentState);
  const nextSuggestedActions = currentState?.nextSuggestedActions ?? [];
  const currentPhase = currentState?.currentPhase ?? null;

  const suggestions = useMemo(() => {
    const items: Array<{ area: string; text: string }> = [];
    if (nextSuggestedActions.length > 0) {
      items.push({
        area: '建议动作',
        text: `当前阶段"${currentPhase ?? '未知'}"推荐执行：${nextSuggestedActions.join('、')}。`,
      });
    }
    return items;
  }, [nextSuggestedActions, currentPhase]);

  return (
    <div className={styles.card}>
      <h4 className={styles.sectionTitle}>教练建议</h4>
      {suggestions.map((s, i) => (
        <div key={i} className={styles.suggestionItem}>
          <div className={styles.suggestionLabel}>{s.area}</div>
          <p className={styles.suggestionText}>{s.text}</p>
        </div>
      ))}
    </div>
  );
}

// ===== 主组件 =====

export function TeachingNoteWorkspace(): JSX.Element {
  const history = useTrainingStore(selectTrainingHistory);

  const hasNoData = history.length === 0;

  if (hasNoData) {
    return (
      <div className={styles.container}>
        <div className={styles.header}>
          <h3 className={styles.title}>教学笔记</h3>
        </div>
        <div className={styles.emptyState}>
          <span className={styles.emptyIcon} aria-hidden="true">{'\uD83D\uDCDD'}</span>
          <p className={styles.emptyText}>暂无教学笔记数据</p>
        </div>
      </div>
    );
  }

  return (
    <div className={styles.container}>
      <div className={styles.header}>
        <h3 className={styles.title}>教学笔记</h3>
      </div>

      <div className={styles.scrollArea}>
        {/* 诊断结果摘要 */}
        <DiagnosisSummary />

        {/* 训练记录 */}
        <section aria-label="训练记录">
          <h4 className={styles.sectionTitle}>
            训练记录（{history.length} 条）
          </h4>
          {history.map((record) => (
            <div key={record.id} className={styles.card}>
              <h5 className={styles.noteTitle}>
                {record.challengeName ?? `训练 ${record.id.slice(0, 8)}`}
              </h5>
              <p className={styles.noteDetail}>
                {record.status === 'completed' ? '已完成' :
                 record.status === 'in_progress' ? '进行中' :
                 record.status === 'assigned' ? '已分配' :
                 record.status === 'skipped' ? '已跳过' : record.status}
                {record.score != null ? ` · 得分 ${record.score}` : ''}
              </p>
            </div>
          ))}
          {history.length === 0 && (
            <p className={styles.noteDetail}>暂无训练记录</p>
          )}
        </section>

        {/* 教练建议 */}
        <CoachSuggestions />
      </div>
    </div>
  );
}
