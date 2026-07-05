/**
 * FlowStepIndicator.tsx — 五步流步骤指示器
 *
 * 职责：渲染顶部 5 步进度条，点击可跳到已完成步骤。
 * 状态：active / completed / pending
 *
 * Sprint 25 BL-01 C-3: 迁移自 components_archived/training/flow/FlowStepIndicator.tsx
 * 改造: BEM 全局类名 → CSS Modules styles.xxx (R-019)
 *       类型 import 切到 src/renderer/shared/types-training.ts
 */
import type { TrainingFlow } from '../../../shared/types-training';
import styles from './flow.module.css';

interface Props {
  flow: TrainingFlow;
  currentIndex: number; // 0-4
  onJump?: (index: number) => void;
}

function capitalize(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1);
}

export function FlowStepIndicator({ flow, currentIndex, onJump }: Props) {
  const steps = flow.steps.slice(0, 5);
  return (
    <ol className={styles.flowStepIndicator} aria-label="训练进度">
      {steps.map((s, i) => {
        const status =
          i < currentIndex ? 'completed' : i === currentIndex ? 'active' : 'pending';
        const canJump = status === 'completed' && Boolean(onJump);
        const statusClass = styles[`flowStep${capitalize(status)}`];
        return (
          <li
            key={s.stepId ?? i}
            className={`${styles.flowStep} ${statusClass ?? ''}`}
            onClick={canJump ? () => onJump?.(i) : undefined}
            role={canJump ? 'button' : undefined}
            tabIndex={canJump ? 0 : -1}
            data-testid={`flow-step-${i}`}
          >
            <span className={styles.flowStepNum}>{i + 1}</span>
            <span className={styles.flowStepLabel}>{s.name}</span>
          </li>
        );
      })}
    </ol>
  );
}
