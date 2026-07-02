/**
 * StepFeedback.tsx — 第 5 步「修改反馈」
 *
 * 职责：展示 AI 评估结果与反馈，并允许用户修订第二稿。
 */
import type { EvaluationResult, ActiveTrainingSession } from '../../../../shared/types/types-training';

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
    <article className="flow-panel flow-panel--feedback" data-testid="step-feedback">
      <h3 className="flow-panel__title">修改反馈</h3>

      {evaluation ? (
        <section className="flow-panel__eval">
          <div className="flow-panel__score">
            评分：<strong>{evaluation.score ?? '—'}</strong> / 10
          </div>
          <div className="flow-panel__improve">
            {evaluation.improved ? '✅ 相比原文有改善' : '⚠️ 与原文差异较小'}
          </div>
          <p className="flow-panel__feedback">{evaluation.feedback}</p>
          {evaluation.nextStep && (
            <p className="flow-panel__next">下一步建议：{evaluation.nextStep}</p>
          )}
        </section>
      ) : (
        <p className="flow-panel__loading">评估中…</p>
      )}

      <section className="flow-panel__editor">
        <h4>修订第二稿</h4>
        <textarea
          className="flow-panel__textarea"
          value={userDraft}
          onChange={(e) => onChangeDraft(e.target.value)}
          rows={10}
          aria-label="第二稿"
        />
        {onResubmit && (
          <button
            className="flow-panel__btn"
            type="button"
            onClick={onResubmit}
            data-testid="resubmit"
          >
            重新提交评估
          </button>
        )}
        <p className="flow-panel__action">挑战：{active.challengeName}</p>
      </section>
    </article>
  );
}
