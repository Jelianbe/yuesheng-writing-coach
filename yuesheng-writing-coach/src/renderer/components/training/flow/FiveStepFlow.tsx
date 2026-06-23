/**
 * FiveStepFlow.tsx — 五步通用训练流容器
 *
 * 职责：组合 FlowStepIndicator + 5 个 Step 面板，持有本地 UI 状态（understanding 草稿）。
 *       复用 training.store 中的 userDraft / evaluationResult / submitStep / evaluate。
 *       不与原 StepIndicatorList 冲突，按 flowType 切换。
 */
import { useState } from 'react';
import type {
  ActiveTrainingSession,
  TrainingFlow,
  EvaluationResult,
} from '../../../../shared/types/types-training';
import { useTrainingStore } from '../../../stores/training.store';
import { FlowStepIndicator } from './FlowStepIndicator';
import { StepExplain } from './StepExplain';
import { StepExample } from './StepExample';
import { StepConfirm } from './StepConfirm';
import { StepPractice } from './StepPractice';
import { StepFeedback } from './StepFeedback';

interface Props {
  active: ActiveTrainingSession;
  flow: TrainingFlow;
  evaluation: EvaluationResult | null;
  onExit: () => void;
}

export function FiveStepFlow({ active, flow, evaluation, onExit }: Props) {
  const [stepIndex, setStepIndex] = useState(0);
  const [understanding, setUnderstanding] = useState('');
  const updateDraft = useTrainingStore((s) => s.updateDraft);
  const submitStep = useTrainingStore((s) => s.submitStep);
  const evaluate = useTrainingStore((s) => s.evaluateTraining);

  const goNext = () => {
    // 用函数式 setState 拿最新 prev，避免闭包陷阱
    setStepIndex((prev) => {
      const nextIndex = prev + 1;
      if (nextIndex > 4) return prev;
      return nextIndex;
    });
    // S16: 第 4 步（尝试）→ 切到第 5 步前自动评估；第 5 步 → 标记完成
    // 评估在异步 microtask 中执行，避免阻塞 UI 切换
    queueMicrotask(() => {
      if (stepIndex === 3) void evaluate();
      if (stepIndex === 4) void submitStep();
    });
  };

  const goPrev = () => {
    if (stepIndex > 0) setStepIndex(stepIndex - 1);
  };

  const canSubmit = (() => {
    if (stepIndex === 2) return understanding.trim().length >= 30;
    if (stepIndex === 3) return active.userDraft.trim().length > 0;
    return true;
  })();

  return (
    <section className="five-step-flow" data-testid="five-step-flow">
      <header className="five-step-flow__header">
        <h2>{active.challengeName}</h2>
        <button type="button" onClick={onExit} data-testid="flow-exit">
          退出训练
        </button>
      </header>

      <FlowStepIndicator
        flow={flow}
        currentIndex={stepIndex}
        onJump={(i) => i < stepIndex && setStepIndex(i)}
      />

      <div className="five-step-flow__body">
        {stepIndex === 0 && <StepExplain flow={flow} />}
        {stepIndex === 1 && <StepExample flow={flow} />}
        {stepIndex === 2 && (
          <StepConfirm
            flow={flow}
            understanding={understanding}
            onChangeUnderstanding={setUnderstanding}
          />
        )}
        {stepIndex === 3 && (
          <StepPractice
            active={active}
            userDraft={active.userDraft}
            onChangeDraft={(v) => updateDraft(v)}
          />
        )}
        {stepIndex === 4 && (
          <StepFeedback
            active={active}
            evaluation={evaluation}
            userDraft={active.userDraft}
            onChangeDraft={(v) => updateDraft(v)}
            onResubmit={() => void evaluate()}
          />
        )}
      </div>

      <footer className="five-step-flow__footer">
        <button
          type="button"
          onClick={goPrev}
          disabled={stepIndex === 0}
          data-testid="flow-prev"
        >
          上一步
        </button>
        {stepIndex < 4 ? (
          <button
            type="button"
            onClick={goNext}
            disabled={!canSubmit}
            data-testid="flow-next"
          >
            {stepIndex === 3 ? '提交评估' : '下一步'}
          </button>
        ) : (
          <button
            type="button"
            onClick={() => void submitStep()}
            data-testid="flow-complete"
          >
            完成训练
          </button>
        )}
      </footer>
    </section>
  );
}
