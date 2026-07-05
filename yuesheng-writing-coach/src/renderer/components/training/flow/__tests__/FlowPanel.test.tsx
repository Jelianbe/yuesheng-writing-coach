/**
 * FlowPanel UI 单元测试
 * 验证 5 步流的渲染、分支、降级（flowType 缺失时不影响原 3 步流）。
 *
 * Sprint 25 BL-01 C-3: 迁移自 components_archived/training/flow/__tests__/FiveStepFlow.test.tsx
 * 改造: ① 组件名 FiveStepFlow → FlowPanel
 *       ② import 路径指向 V6.2 新位置
 *       ③ vi.mock store 路径 2 层 → 3 层
 * 行为零变更（9 个用例原样保留）
 */
import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import '@testing-library/jest-dom/vitest';
import { FlowPanel } from '../FlowPanel';

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

describe('<FlowPanel />', () => {
  it('渲染 5 步进度条（默认第 1 步激活）', () => {
    render(
      <FlowPanel
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
      <FlowPanel
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
      <FlowPanel
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
      <FlowPanel
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

  it('第 3 步（确认）短文本 < 30 字时禁用「下一步」', async () => {
    // T17-10: 用 user-event 稳定模拟多次 click + state flush
    const user = userEvent.setup();
    render(
      <FlowPanel
        active={makeActive() as never}
        flow={makeFlow() as never}
        evaluation={null}
        onExit={() => {}}
      />,
    );
    await user.click(screen.getByTestId('flow-next')); // → 2
    await user.click(screen.getByTestId('flow-next')); // → 3
    expect(screen.getByTestId('step-confirm')).toBeInTheDocument();
    const ta = screen.getByLabelText('理解复述');
    await user.type(ta, '太短');
    expect(screen.getByTestId('flow-next')).toBeDisabled();
  });

  it('第 3 步（确认）≥ 30 字时启用「下一步」', async () => {
    const user = userEvent.setup();
    render(
      <FlowPanel
        active={makeActive() as never}
        flow={makeFlow() as never}
        evaluation={null}
        onExit={() => {}}
      />,
    );
    await user.click(screen.getByTestId('flow-next'));
    await user.click(screen.getByTestId('flow-next'));
    const ta = screen.getByLabelText('理解复述');
    await user.type(
      ta,
      '这段话讲了反差开篇的核心要点是用角色的反差来制造悬念并吸引读者继续阅读',
    );
    expect(screen.getByTestId('flow-next')).not.toBeDisabled();
  });

  it('第 4 步（尝试）空草稿时「提交评估」禁用', async () => {
    const user = userEvent.setup();
    render(
      <FlowPanel
        active={makeActive({ userDraft: '' }) as never}
        flow={makeFlow() as never}
        evaluation={null}
        onExit={() => {}}
      />,
    );
    await user.click(screen.getByTestId('flow-next'));
    await user.click(screen.getByTestId('flow-next'));
    const ta = screen.getByLabelText('理解复述');
    await user.type(
      ta,
      '用反差开篇能在第一段就让读者好奇人物背后隐藏的复杂故事和命运走向',
    );
    await user.click(screen.getByTestId('flow-next'));
    expect(screen.getByTestId('step-practice')).toBeInTheDocument();
    expect(screen.getByTestId('flow-next')).toBeDisabled();
  });

  it('第 4 步（尝试）有草稿时「提交评估」启用并切到第 5 步', async () => {
    const user = userEvent.setup();
    render(
      <FlowPanel
        active={makeActive({ userDraft: '改写后的版本' }) as never}
        flow={makeFlow() as never}
        evaluation={null}
        onExit={() => {}}
      />,
    );
    await user.click(screen.getByTestId('flow-next'));
    await user.click(screen.getByTestId('flow-next'));
    const ta = screen.getByLabelText('理解复述');
    await user.type(
      ta,
      '用反差开篇能在第一段就让读者好奇人物背后隐藏的复杂故事和命运走向',
    );
    await user.click(screen.getByTestId('flow-next'));
    expect(screen.getByTestId('step-practice')).toBeInTheDocument();
    expect(screen.getByTestId('flow-next')).not.toBeDisabled();
    await user.click(screen.getByTestId('flow-next'));
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
      <FlowPanel
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

  // ---- Sprint 37: 评估结果展示 ----

  it('第 5 步展示评估评分和反馈', async () => {
    const user = userEvent.setup();
    const evaluation = { score: 7, feedback: '改写有一定改善，结构更紧凑', improved: true, nextStep: '尝试更多练习' };
    render(
      <FlowPanel
        active={makeActive({ userDraft: '改写版本' }) as never}
        flow={makeFlow() as never}
        evaluation={evaluation}
        onExit={() => {}}
      />,
    );
    // 快速切到第 5 步
    await user.click(screen.getByTestId('flow-next'));
    await user.click(screen.getByTestId('flow-next'));
    const ta = screen.getByLabelText('理解复述');
    await user.type(
      ta,
      '用反差开篇能在第一段就让读者好奇人物背后隐藏的复杂故事和命运走向',
    );
    await user.click(screen.getByTestId('flow-next'));
    await user.click(screen.getByTestId('flow-next'));
    expect(screen.getByTestId('step-feedback')).toBeInTheDocument();

    // 评估信息展示
    expect(screen.getByText(/评分/)).toBeInTheDocument();
    expect(screen.getByText('7')).toBeInTheDocument();
    expect(screen.getByText(/改写有一定改善/)).toBeInTheDocument();
    expect(screen.getByText(/相比原文有改善/)).toBeInTheDocument();
    expect(screen.getByText(/尝试更多练习/)).toBeInTheDocument();
  });

  it('第 5 步评估为 null 时显示"评估中…"', async () => {
    const user = userEvent.setup();
    render(
      <FlowPanel
        active={makeActive({ userDraft: '改写后的版本' }) as never}
        flow={makeFlow() as never}
        evaluation={null}
        onExit={() => {}}
      />,
    );
    await user.click(screen.getByTestId('flow-next'));
    await user.click(screen.getByTestId('flow-next'));
    const ta = screen.getByLabelText('理解复述');
    await user.type(
      ta,
      '用反差开篇能在第一段就让读者好奇人物背后隐藏的复杂故事和命运走向',
    );
    await user.click(screen.getByTestId('flow-next'));
    await user.click(screen.getByTestId('flow-next'));
    expect(screen.getByTestId('step-feedback')).toBeInTheDocument();
    expect(screen.getByText('评估中…')).toBeInTheDocument();
  });

  // ---- Sprint 37: 边界情况 ----

  it('improved=false 时显示"与原文差异较小"', async () => {
    const user = userEvent.setup();
    const evaluation = { score: 4, feedback: '改写幅度不够', improved: false, nextStep: '尝试更大胆的改写' };
    render(
      <FlowPanel
        active={makeActive({ userDraft: '小改' }) as never}
        flow={makeFlow() as never}
        evaluation={evaluation}
        onExit={() => {}}
      />,
    );
    await user.click(screen.getByTestId('flow-next'));
    await user.click(screen.getByTestId('flow-next'));
    const ta = screen.getByLabelText('理解复述');
    await user.type(
      ta,
      '用反差开篇能在第一段就让读者好奇人物背后隐藏的复杂故事和命运走向',
    );
    await user.click(screen.getByTestId('flow-next'));
    await user.click(screen.getByTestId('flow-next'));

    expect(screen.getByText(/与原文差异较小/)).toBeInTheDocument();
    expect(screen.getByText(/改写幅度不够/)).toBeInTheDocument();
  });
});
