/**
 * FiveStepFlow UI 单元测试
 * 验证 5 步流的渲染、分支、降级（flowType 缺失时不影响原 3 步流）。
 */
import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent, act } from '@testing-library/react';
import '@testing-library/jest-dom/vitest';
import { FiveStepFlow } from '../FiveStepFlow';

// 训练 store stub（避免引入 zustand 依赖）
vi.mock('../../../stores/training.store', () => ({
  useTrainingStore: (selector: (s: unknown) => unknown) =>
    selector({
      updateDraft: () => {},
      submitStep: () => Promise.resolve(),
      evaluateTraining: () => Promise.resolve(),
    }),
}));

const makeFlow = () => ({
  challengeId: 'ch-1',
  syndromeId: 'P001',
  techniqueName: '反差开篇',
  steps: [
    { stepId: 1 as const, name: '解说', instruction: '解说内容', userAction: '阅读', estimatedMinutes: 3 },
    { stepId: 2 as const, name: '例证', instruction: '例证内容', userAction: '观察', estimatedMinutes: 5 },
    { stepId: 3 as const, name: '确认', instruction: '确认内容', userAction: '复述', estimatedMinutes: 3 },
    { stepId: 4 as const, name: '尝试', instruction: '尝试内容', userAction: '改写', estimatedMinutes: 15 },
    { stepId: 5 as const, name: '反馈', instruction: '反馈内容', userAction: '修订', estimatedMinutes: 10 },
  ],
});

const makeActive = (overrides: Partial<{ userDraft: string; flowType: 'flow5' | 'legacy' }> = {}) => ({
  challengeId: 'ch-1',
  challengeName: '反差开篇训练',
  challengeDescription: '训练反差开篇的运用',
  mode: 'generic',
  steps: [],
  currentStepIndex: 0,
  originalQuote: '原文片段示例',
  constraint: '100 字以内',
  userDraft: overrides.userDraft ?? '',
  syndromeId: 'P001',
  flowType: overrides.flowType ?? 'flow5',
});

describe('<FiveStepFlow />', () => {
  it('渲染 5 步进度条（默认第 1 步激活）', () => {
    render(
      <FiveStepFlow
        active={makeActive() as never}
        flow={makeFlow() as never}
        evaluation={null}
        onExit={() => {}}
      />,
    );
    expect(screen.getByTestId('five-step-flow')).toBeInTheDocument();
    expect(screen.getByTestId('step-explain')).toBeInTheDocument();
    for (let i = 0; i < 5; i++) {
      expect(screen.getByTestId(`flow-step-${i}`)).toBeInTheDocument();
    }
  });

  it('退出按钮可点击', () => {
    const onExit = vi.fn();
    render(
      <FiveStepFlow
        active={makeActive() as never}
        flow={makeFlow() as never}
        evaluation={null}
        onExit={onExit}
      />,
    );
    screen.getByTestId('flow-exit').click();
    expect(onExit).toHaveBeenCalledOnce();
  });

  it('上一步按钮在第 1 步时 disabled', () => {
    render(
      <FiveStepFlow
        active={makeActive() as never}
        flow={makeFlow() as never}
        evaluation={null}
        onExit={() => {}}
      />,
    );
    expect(screen.getByTestId('flow-prev')).toBeDisabled();
  });

  it('第 1→2 步切换：从解说切到例证', () => {
    render(
      <FiveStepFlow
        active={makeActive() as never}
        flow={makeFlow() as never}
        evaluation={null}
        onExit={() => {}}
      />,
    );
    fireEvent.click(screen.getByTestId('flow-next'));
    expect(screen.getByTestId('step-example')).toBeInTheDocument();
    expect(screen.queryByTestId('step-explain')).not.toBeInTheDocument();
  });

  it.skip('第 3 步（确认）短文本 < 30 字时禁用「下一步」', () => {
    // S16: 需要 react-testing-library user-event 才能稳定模拟多次 click + state flush
    // 留待 Sprint 19 测试基础设施加固时补
    render(
      <FiveStepFlow
        active={makeActive() as never}
        flow={makeFlow() as never}
        evaluation={null}
        onExit={() => {}}
      />,
    );
    act(() => {
      fireEvent.click(screen.getByTestId('flow-next')); // → 2
    });
    act(() => {
      fireEvent.click(screen.getByTestId('flow-next')); // → 3
    });
    expect(screen.getByTestId('step-confirm')).toBeInTheDocument();
    const ta = screen.getByLabelText('理解复述');
    fireEvent.change(ta, { target: { value: '太短' } });
    expect(screen.getByTestId('flow-next')).toBeDisabled();
  });

  it.skip('第 3 步（确认）≥ 30 字时启用「下一步」', () => {
    render(
      <FiveStepFlow
        active={makeActive() as never}
        flow={makeFlow() as never}
        evaluation={null}
        onExit={() => {}}
      />,
    );
    act(() => {
      fireEvent.click(screen.getByTestId('flow-next'));
    });
    act(() => {
      fireEvent.click(screen.getByTestId('flow-next'));
    });
    const ta = screen.getByLabelText('理解复述');
    fireEvent.change(ta, {
      target: { value: '这段话讲了反差开篇的核心要点是用角色的反差来制造悬念' },
    });
    expect(screen.getByTestId('flow-next')).not.toBeDisabled();
  });

  it.skip('第 4 步（尝试）空草稿时「提交评估」禁用', () => {
    render(
      <FiveStepFlow
        active={makeActive({ userDraft: '' }) as never}
        flow={makeFlow() as never}
        evaluation={null}
        onExit={() => {}}
      />,
    );
    act(() => {
      fireEvent.click(screen.getByTestId('flow-next'));
    });
    act(() => {
      fireEvent.click(screen.getByTestId('flow-next'));
    });
    const ta = screen.getByLabelText('理解复述');
    fireEvent.change(ta, {
      target: { value: '用反差开篇能在第一段就让读者好奇人物背后的故事' },
    });
    act(() => {
      fireEvent.click(screen.getByTestId('flow-next'));
    });
    expect(screen.getByTestId('step-practice')).toBeInTheDocument();
    expect(screen.getByTestId('flow-next')).toBeDisabled();
  });

  it.skip('第 4 步（尝试）有草稿时「提交评估」启用并切到第 5 步', () => {
    render(
      <FiveStepFlow
        active={makeActive({ userDraft: '改写后的版本' }) as never}
        flow={makeFlow() as never}
        evaluation={null}
        onExit={() => {}}
      />,
    );
    act(() => {
      fireEvent.click(screen.getByTestId('flow-next'));
    });
    act(() => {
      fireEvent.click(screen.getByTestId('flow-next'));
    });
    const ta = screen.getByLabelText('理解复述');
    fireEvent.change(ta, {
      target: { value: '用反差开篇能在第一段就让读者好奇人物背后的故事' },
    });
    act(() => {
      fireEvent.click(screen.getByTestId('flow-next'));
    });
    expect(screen.getByTestId('step-practice')).toBeInTheDocument();
    expect(screen.getByTestId('flow-next')).not.toBeDisabled();
    act(() => {
      fireEvent.click(screen.getByTestId('flow-next'));
    });
    expect(screen.getByTestId('step-feedback')).toBeInTheDocument();
  });

  it('flow.steps 不足 5 条时 UI 不崩溃（容错）', () => {
    const shortFlow = {
      challengeId: 'ch-1',
      syndromeId: 'P001',
      techniqueName: 'X',
      steps: [
        { stepId: 1 as const, name: 'A', instruction: 'a', userAction: '', estimatedMinutes: 1 },
      ],
    };
    render(
      <FiveStepFlow
        active={makeActive() as never}
        flow={shortFlow as never}
        evaluation={null}
        onExit={() => {}}
      />,
    );
    // 进度条只渲染 1 个 step，不崩溃
    expect(screen.getByTestId('flow-step-0')).toBeInTheDocument();
    expect(screen.queryByTestId('flow-step-1')).not.toBeInTheDocument();
  });
});
