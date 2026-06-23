/**
 * StepExample.tsx — 第 2 步「例证展示」
 *
 * 职责：展示该技法的真实例子，引导用户观察。
 */
import type { TrainingFlow } from '../../../../shared/types/types-training';

interface Props {
  flow: TrainingFlow;
}

export function StepExample({ flow }: Props) {
  const step = flow.steps[1];
  return (
    <article className="flow-panel flow-panel--example" data-testid="step-example">
      <h3 className="flow-panel__title">{step?.name ?? '例证展示'}</h3>
      <div className="flow-panel__content">
        <p>{step?.instruction}</p>
      </div>
      <p className="flow-panel__action">建议时长：{step?.estimatedMinutes ?? 5} 分钟</p>
    </article>
  );
}
