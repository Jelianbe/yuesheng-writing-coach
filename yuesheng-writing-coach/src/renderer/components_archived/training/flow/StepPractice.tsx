/**
 * StepPractice.tsx — 第 4 步「主动尝试」
 *
 * 职责：让用户应用该技法进行改写练习，复用 activeTraining.userDraft。
 */
import type { ActiveTrainingSession } from '../../../../shared/types/types-training';

interface Props {
  active: ActiveTrainingSession;
  userDraft: string;
  onChangeDraft: (v: string) => void;
}

export function StepPractice({ active, userDraft, onChangeDraft }: Props) {
  return (
    <article className="flow-panel flow-panel--practice" data-testid="step-practice">
      <h3 className="flow-panel__title">主动尝试</h3>

      {active.originalQuote && (
        <section className="flow-panel__quote">
          <h4>原文片段</h4>
          <blockquote>{active.originalQuote}</blockquote>
        </section>
      )}

      {active.constraint && (
        <section className="flow-panel__constraint">
          <h4>约束条件</h4>
          <p>{active.constraint}</p>
        </section>
      )}

      <section className="flow-panel__editor">
        <h4>你的改写</h4>
        <textarea
          className="flow-panel__textarea"
          value={userDraft}
          onChange={(e) => onChangeDraft(e.target.value)}
          placeholder="应用该技法进行改写…"
          rows={10}
          aria-label="改写草稿"
        />
        <p className="flow-panel__action">已输入 {userDraft.length} 字</p>
      </section>
    </article>
  );
}
