/**
 * StepConfirm.tsx — 第 3 步「确认理解」
 *
 * 职责：让用户用自己的话复述该技法的核心要点。
 */
import type { TrainingFlow } from '../../../../shared/types/types-training';

interface Props {
  flow: TrainingFlow;
  understanding: string;
  onChangeUnderstanding: (v: string) => void;
}

export function StepConfirm({ flow, understanding, onChangeUnderstanding }: Props) {
  const step = flow.steps[2];
  return (
    <article className="flow-panel flow-panel--confirm" data-testid="step-confirm">
      <h3 className="flow-panel__title">{step?.name ?? '确认理解'}</h3>
      <div className="flow-panel__content">
        <p>{step?.instruction}</p>
      </div>
      <textarea
        className="flow-panel__textarea"
        value={understanding}
        onChange={(e) => onChangeUnderstanding(e.target.value)}
        placeholder="请用你自己的话描述该技法的核心要点（不少于 30 字）"
        rows={5}
        aria-label="理解复述"
      />
      <p className="flow-panel__action">
        已输入 {understanding.trim().length} 字 · 建议时长：
        {step?.estimatedMinutes ?? 3} 分钟
      </p>
    </article>
  );
}
