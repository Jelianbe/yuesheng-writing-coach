/**
 * StepPractice.tsx — 第 4 步「主动尝试」
 *
 * 职责：让用户应用该技法进行改写练习，复用 activeTraining.userDraft。
 *
 * Sprint 25 BL-01 C-3: 迁移自 components_archived/training/flow/StepPractice.tsx
 * 改造: BEM 全局类名 → CSS Modules styles.xxx (R-019)
 *       类型 import 切到 src/renderer/shared/types-training.ts
 */
import type { ActiveTrainingSession } from '../../../shared/types-training';
import styles from './flow.module.css';

interface Props {
  active: ActiveTrainingSession;
  userDraft: string;
  onChangeDraft: (v: string) => void;
}

export function StepPractice({ active, userDraft, onChangeDraft }: Props) {
  return (
    <article className={`${styles.flowPanel} ${styles.flowPanelPractice}`} data-testid="step-practice">
      <h3 className={styles.flowPanelTitle}>主动尝试</h3>

      {active.originalQuote && (
        <section className={styles.flowPanelQuote}>
          <h4>原文片段</h4>
          <blockquote>{active.originalQuote}</blockquote>
        </section>
      )}

      {active.constraint && (
        <section className={styles.flowPanelConstraint}>
          <h4>约束条件</h4>
          <p>{active.constraint}</p>
        </section>
      )}

      <section className={styles.flowPanelEditor}>
        <h4>你的改写</h4>
        <textarea
          className={styles.flowPanelTextarea}
          value={userDraft}
          onChange={(e) => onChangeDraft(e.target.value)}
          placeholder="应用该技法进行改写…"
          rows={10}
          aria-label="改写草稿"
        />
        <p className={styles.flowPanelAction}>已输入 {userDraft.length} 字</p>
      </section>
    </article>
  );
}
