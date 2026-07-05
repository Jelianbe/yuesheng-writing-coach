/**
 * StepExplain.tsx — 第 1 步「解说技法」
 *
 * 职责：展示该技法的核心定义与作用。用户只需阅读 + 点击「下一步」。
 *
 * Sprint 25 BL-01 C-3: 迁移自 components_archived/training/flow/StepExplain.tsx
 * 改造: BEM 全局类名 → CSS Modules styles.xxx (R-019)
 *       类型 import 切到 src/renderer/shared/types-training.ts
 */
import type { TrainingFlow } from '../../../shared/types-training';
import styles from './flow.module.css';

interface Props {
  flow: TrainingFlow;
}

export function StepExplain({ flow }: Props) {
  const step = flow.steps[0];
  return (
    <article className={`${styles.flowPanel} ${styles.flowPanelExplain}`} data-testid="step-explain">
      <h3 className={styles.flowPanelTitle}>{step?.name ?? '解说技法'}</h3>
      <div className={styles.flowPanelContent}>
        <p>{step?.instruction}</p>
      </div>
      <p className={styles.flowPanelAction}>建议时长：{step?.estimatedMinutes ?? 3} 分钟</p>
    </article>
  );
}
