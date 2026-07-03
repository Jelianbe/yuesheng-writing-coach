/**
 * StepExample.tsx — 第 2 步「例证展示」
 *
 * 职责：展示该技法的真实例子，引导用户观察。
 *
 * Sprint 25 BL-01 C-3: 迁移自 components_archived/training/flow/StepExample.tsx
 * 改造: BEM 全局类名 → CSS Modules styles.xxx (R-019)
 *       类型 import 切到 src/renderer/shared/types-training.ts
 */
import type { TrainingFlow } from '../../../shared/types-training';
import styles from './flow.module.css';

interface Props {
  flow: TrainingFlow;
}

export function StepExample({ flow }: Props) {
  const step = flow.steps[1];
  return (
    <article className={`${styles.flowPanel} ${styles.flowPanelExample}`} data-testid="step-example">
      <h3 className={styles.flowPanelTitle}>{step?.name ?? '例证展示'}</h3>
      <div className={styles.flowPanelContent}>
        <p>{step?.instruction}</p>
      </div>
      <p className={styles.flowPanelAction}>建议时长：{step?.estimatedMinutes ?? 5} 分钟</p>
    </article>
  );
}
