/**
 * ActiveTrainingView 组件测试
 * 覆盖：三步框架（Step 0 / Step 1 / Step 2）、进度条、操作按钮、评估失败反馈
 */
import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { ActiveTrainingView } from './ActiveTrainingView';
import type { ActiveTrainingSession } from '../../shared/types';

// ===== 工厂数据 =====

const baseSession: ActiveTrainingSession = {
  challengeId: 'CH-001',
  challengeName: '信息硬塞训练',
  challengeDescription: '请用动作替代直接交代设定',
  mode: 'generic',
  steps: [
    { id: 'review', title: '阅读原文', description: '回顾你的写作', status: 'active' },
    { id: 'rewrite', title: '约束改写', description: '动手改写这段内容', status: 'pending' },
    { id: 'submit', title: '提交评估', description: '接收 AI 评估反馈', status: 'pending' },
  ],
  currentStepIndex: 0,
  originalQuote: '他资质平平，只是一个普通的散修。',
  constraint: '不直接交代主角的修为和背景',
  userDraft: '',
  longTermProgress: 0,
};

const defaultHandlers = {
  onBackToChat: vi.fn(),
  onSubmitStep: vi.fn(),
  onSkipTraining: vi.fn(),
  onUpdateDraft: vi.fn(),
};

describe('ActiveTrainingView', () => {
  // ===== 通用 UI =====

  describe('通用 UI', () => {
    it('显示挑战名称和步骤进度', () => {
      render(
        <ActiveTrainingView
          activeTraining={baseSession}
          submissionResult={null}
          evaluationResult={null}
          isLoading={false}
          {...defaultHandlers}
        />
      );
      expect(screen.getByText('信息硬塞训练')).toBeInTheDocument();
      expect(screen.getByText(/步骤 1\/3/)).toBeInTheDocument();
    });

    it('显示进度条', () => {
      const { container } = render(
        <ActiveTrainingView
          activeTraining={baseSession}
          submissionResult={null}
          evaluationResult={null}
          isLoading={false}
          {...defaultHandlers}
        />
      );
      // 进度条的高度为 4px
      const bars = container.querySelectorAll('[style*="height: 4px"]');
      expect(bars.length).toBeGreaterThan(0);
    });

    it('显示步骤列表', () => {
      render(
        <ActiveTrainingView
          activeTraining={baseSession}
          submissionResult={null}
          evaluationResult={null}
          isLoading={false}
          {...defaultHandlers}
        />
      );
      expect(screen.getByText('阅读原文')).toBeInTheDocument();
      expect(screen.getByText('约束改写')).toBeInTheDocument();
      expect(screen.getByText('提交评估')).toBeInTheDocument();
    });

    it('当前步骤显示描述', () => {
      render(
        <ActiveTrainingView
          activeTraining={baseSession}
          submissionResult={null}
          evaluationResult={null}
          isLoading={false}
          {...defaultHandlers}
        />
      );
      expect(screen.getByText('回顾你的写作')).toBeInTheDocument();
    });

    it('非当前步骤不显示描述', () => {
      render(
        <ActiveTrainingView
          activeTraining={baseSession}
          submissionResult={null}
          evaluationResult={null}
          isLoading={false}
          {...defaultHandlers}
        />
      );
      // "动手改写"是 Step 1 的描述，当前 Step 0，不应显示
      expect(screen.queryByText('动手改写这段内容')).toBeNull();
    });

    it('返回按钮调用 onSkipTraining', () => {
      render(
        <ActiveTrainingView
          activeTraining={baseSession}
          submissionResult={null}
          evaluationResult={null}
          isLoading={false}
          {...defaultHandlers}
        />
      );
      fireEvent.click(screen.getByTitle('返回对话'));
      expect(defaultHandlers.onBackToChat).toHaveBeenCalled();
    });

    it('当前为 Step 0 时跳过按钮显示"跳过"', () => {
      render(
        <ActiveTrainingView
          activeTraining={baseSession}
          submissionResult={null}
          evaluationResult={null}
          isLoading={false}
          {...defaultHandlers}
        />
      );
      expect(screen.getByText('跳过')).toBeInTheDocument();
    });
  });

  // ===== Step 0: 阅读原文 =====

  describe('Step 0', () => {
    it('显示原文引用', () => {
      render(
        <ActiveTrainingView
          activeTraining={baseSession}
          submissionResult={null}
          evaluationResult={null}
          isLoading={false}
          {...defaultHandlers}
        />
      );
      expect(screen.getByText(/他资质平平，只是一个普通的散修/)).toBeInTheDocument();
    });

    it('继续按钮推进步骤', () => {
      render(
        <ActiveTrainingView
          activeTraining={baseSession}
          submissionResult={null}
          evaluationResult={null}
          isLoading={false}
          {...defaultHandlers}
        />
      );
      fireEvent.click(screen.getByText('继续'));
      expect(defaultHandlers.onSubmitStep).toHaveBeenCalled();
    });
  });

  // ===== Step 1: 约束改写 =====

  describe('Step 1', () => {
    const step1Session: ActiveTrainingSession = {
      ...baseSession,
      currentStepIndex: 1,
      steps: baseSession.steps.map((s, i) => ({
        ...s,
        status: i === 0 ? 'completed' as const : i === 1 ? 'active' as const : 'pending' as const,
      })),
    };

    it('显示挑战描述和约束条件', () => {
      render(
        <ActiveTrainingView
          activeTraining={step1Session}
          submissionResult={null}
          evaluationResult={null}
          isLoading={false}
          {...defaultHandlers}
        />
      );
      expect(screen.getByText('请用动作替代直接交代设定')).toBeInTheDocument();
      expect(screen.getByText(/不直接交代主角的修为和背景/)).toBeInTheDocument();
    });

    it('显示文本输入框', () => {
      render(
        <ActiveTrainingView
          activeTraining={step1Session}
          submissionResult={null}
          evaluationResult={null}
          isLoading={false}
          {...defaultHandlers}
        />
      );
      expect(screen.getByPlaceholderText('在此输入你的改写...')).toBeInTheDocument();
    });

    it('输入框内容随 userDraft 更新', () => {
      render(
        <ActiveTrainingView
          activeTraining={step1Session}
          submissionResult={null}
          evaluationResult={null}
          isLoading={false}
          {...defaultHandlers}
        />
      );
      const textarea = screen.getByPlaceholderText('在此输入你的改写...') as HTMLTextAreaElement;
      expect(textarea.value).toBe('');
    });

    it('输入框内容变化时调用 onUpdateDraft', () => {
      render(
        <ActiveTrainingView
          activeTraining={step1Session}
          submissionResult={null}
          evaluationResult={null}
          isLoading={false}
          {...defaultHandlers}
        />
      );
      const textarea = screen.getByPlaceholderText('在此输入你的改写...');
      fireEvent.change(textarea, { target: { value: '新的改写' } });
      expect(defaultHandlers.onUpdateDraft).toHaveBeenCalledWith('新的改写');
    });

    it('存草稿按钮在 Step 1 时显示"存草稿"', () => {
      render(
        <ActiveTrainingView
          activeTraining={step1Session}
          submissionResult={null}
          evaluationResult={null}
          isLoading={false}
          {...defaultHandlers}
        />
      );
      expect(screen.getByText('存草稿')).toBeInTheDocument();
    });
  });

  // ===== Step 1: 评估未通过 =====

  describe('Step 1 评估失败', () => {
    const step1Session: ActiveTrainingSession = {
      ...baseSession,
      currentStepIndex: 1,
      userDraft: '改写稿内容',
      steps: baseSession.steps.map((s, i) => ({
        ...s,
        status: i === 0 ? 'completed' as const : i === 1 ? 'active' as const : 'pending' as const,
      })),
    };

    it('评估未通过时显示错误反馈', () => {
      render(
        <ActiveTrainingView
          activeTraining={step1Session}
          submissionResult={{ passed: false, feedback: '改写还不够，缺少具体动作。' }}
          evaluationResult={null}
          isLoading={false}
          {...defaultHandlers}
        />
      );
      expect(screen.getByText('改写还不够，缺少具体动作。')).toBeInTheDocument();
    });

    it('评估未通过时不显示"评估通过"', () => {
      render(
        <ActiveTrainingView
          activeTraining={step1Session}
          submissionResult={{ passed: false, feedback: '还需要改进' }}
          evaluationResult={null}
          isLoading={false}
          {...defaultHandlers}
        />
      );
      expect(screen.queryByText('评估通过')).toBeNull();
    });
  });

  // ===== Step 2: 提交评估结果 =====

  describe('Step 2', () => {
    const step2Session: ActiveTrainingSession = {
      ...baseSession,
      currentStepIndex: 2,
      steps: baseSession.steps.map((s, i) => ({
        ...s,
        status: i < 2 ? 'completed' as const : 'active' as const,
      })),
    };

    it('显示评估通过', () => {
      render(
        <ActiveTrainingView
          activeTraining={step2Session}
          submissionResult={{ passed: true, feedback: '改写很好！' }}
          evaluationResult={null}
          isLoading={false}
          {...defaultHandlers}
        />
      );
      expect(screen.getByText('训练完成！')).toBeInTheDocument();
    });

    it('显示 AI 反馈', () => {
      render(
        <ActiveTrainingView
          activeTraining={step2Session}
          submissionResult={{ passed: true, feedback: '改写很好！' }}
          evaluationResult={null}
          isLoading={false}
          {...defaultHandlers}
        />
      );
      expect(screen.getByText('改写很好！')).toBeInTheDocument();
    });

    it('提交完成按钮触发完成', () => {
      render(
        <ActiveTrainingView
          activeTraining={step2Session}
          submissionResult={{ passed: true, feedback: '做得好' }}
          evaluationResult={null}
          isLoading={false}
          {...defaultHandlers}
        />
      );
      expect(screen.getByText('完成训练')).toBeInTheDocument();
    });
  });

  // ===== 加载状态 =====

  describe('加载状态', () => {
    it('加载中时继续按钮显示"评估中..."', () => {
      render(
        <ActiveTrainingView
          activeTraining={baseSession}
          submissionResult={null}
          evaluationResult={null}
          isLoading={true}
          {...defaultHandlers}
        />
      );
      expect(screen.getByText('评估中...')).toBeInTheDocument();
    });

    it('加载中时继续按钮不可用', () => {
      render(
        <ActiveTrainingView
          activeTraining={baseSession}
          submissionResult={null}
          evaluationResult={null}
          isLoading={true}
          {...defaultHandlers}
        />
      );
      expect(screen.getByText('评估中...')).toBeDisabled();
    });
  });
});
