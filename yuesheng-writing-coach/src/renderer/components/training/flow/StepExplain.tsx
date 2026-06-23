/**
 * StepExplain.tsx — 第 1 步「解说技法」
 *
 * 职责：展示该技法的核心定义与作用。用户只需阅读 + 点击「下一步」。
 */
import type { TrainingFlow } from '../../../../shared/types/types-training';

interface Props {
  flow: TrainingFlow;
}

export function StepExplain({ flow }: Props) {
  const step = flow.steps[0];
  return (
    <article className="flow-panel flow-panel--explain" data-testid="step-explain">
      <h3 className="flow-panel__title">{step?.name ?? '解说技法'}</h3>
      <div className="flow-panel__content">
        <p>{step?.instruction}</p>
      </div>
      <p className="flow-panel__action">建议时长：{step?.estimatedMinutes ?? 3} 分钟</p>
    </article>
  );
}
