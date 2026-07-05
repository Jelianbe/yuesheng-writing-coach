/**
 * StepFeedback.tsx — 第 5 步「修改反馈」
 *
 * 职责：展示 AI 评估结果与反馈，并允许用户修订第二稿。
 *
 * Sprint 25 BL-01 C-3: 迁移自 components_archived/training/flow/StepFeedback.tsx
 * 改造: BEM 全局类名 → CSS Modules styles.xxx (R-019)
 *       类型 import 切到 src/renderer/shared/types-training.ts
 */
import type {
  EvaluationResult,
  ActiveTrainingSession,
} from '../../../shared/types-training';
import styles from './flow.module.css';

interface Props {
  active: ActiveTrainingSession;
  evaluation: EvaluationResult | null;
  userDraft: string;
  onChangeDraft: (v: string) => void;
  onResubmit?: () => void;
}

export function StepFeedback({
  active,
  evaluation,
  userDraft,
  onChangeDraft,
  onResubmit,
}: Props) {
  return (
    <article className={`${styles.flowPanel} ${styles.flowPanelFeedback}`} data-testid="step-feedback">
      <h3 className={styles.flowPanelTitle}>修改反馈</h3>

      {evaluation ? (
        <section className={styles.flowPanelEval}>
          <div className={styles.flowPanelScore}>
            评分：<strong>{evaluation.score ?? '—'}</strong> / 10
          </div>
          <div className={styles.flowPanelImprove}>
            {evaluation.improved ? '✅ 相比原文有改善' : '⚠️ 与原文差异较小'}
          </div>
          <p className={styles.flowPanelFeedback}>{evaluation.feedback}</p>
          {evaluation.nextStep && (
            <p className={styles.flowPanelNext}>下一步建议：{evaluation.nextStep}</p>
          )}
        </section>
      ) : (
        <p className={styles.flowPanelLoading}>评估中…</p>
      )}

      <section className={styles.flowPanelEditor}>
        <h4>修订第二稿</h4>
        <textarea
          className={styles.flowPanelTextarea}
          value={userDraft}
          onChange={(e) => onChangeDraft(e.target.value)}
          rows={10}
          aria-label="第二稿"
        />
        {onResubmit && (
          <button
            className={styles.flowPanelBtn}
            type="button"
            onClick={onResubmit}
            data-testid="resubmit"
          >
            重新提交评估
          </button>
        )}
        <p className={styles.flowPanelAction}>挑战：{active.challengeName}</p>
      </section>
    </article>
  );
}
