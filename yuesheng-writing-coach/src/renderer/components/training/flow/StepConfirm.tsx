/**
 * StepConfirm.tsx — 第 3 步「确认理解」
 *
 * 职责：让用户用自己的话复述该技法的核心要点。
 *
 * Sprint 25 BL-01 C-3: 迁移自 components_archived/training/flow/StepConfirm.tsx
 * 改造: BEM 全局类名 → CSS Modules styles.xxx (R-019)
 *       类型 import 切到 src/renderer/shared/types-training.ts
 */
import type { TrainingFlow } from '../../../shared/types-training';
import styles from './flow.module.css';

interface Props {
  flow: TrainingFlow;
  understanding: string;
  onChangeUnderstanding: (v: string) => void;
}

export function StepConfirm({ flow, understanding, onChangeUnderstanding }: Props) {
  const step = flow.steps[2];
  return (
    <article className={`${styles.flowPanel} ${styles.flowPanelConfirm}`} data-testid="step-confirm">
      <h3 className={styles.flowPanelTitle}>{step?.name ?? '确认理解'}</h3>
      <div className={styles.flowPanelContent}>
        <p>{step?.instruction}</p>
      </div>
      <textarea
        className={styles.flowPanelTextarea}
        value={understanding}
        onChange={(e) => onChangeUnderstanding(e.target.value)}
        placeholder="请用你自己的话描述该技法的核心要点（不少于 30 字）"
        rows={5}
        aria-label="理解复述"
      />
      <p className={styles.flowPanelAction}>
        已输入 {understanding.trim().length} 字 · 建议时长：
        {step?.estimatedMinutes ?? 3} 分钟
      </p>
    </article>
  );
}
