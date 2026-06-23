/**
 * ActiveTrainingView — 训练工坊步骤式练习视图（编排层）
 *
 * 所有 mode 共享通用三步框架，Step 2 提交后由 AI 评估是否符合约束。
 * 前端不做任何 mode 特定的硬编码校验。添加新 mode 只需改模板 JSON。
 *
 * 已拆分子组件：
 * - TrainingHeader: 标题栏 + 进度条
 * - GoalTrackingPanel: SF-002 三级目标追踪
 * - StepIndicatorList: 步骤状态列表
 * - ReadingStepContent: Step 0 阅读内容
 * - RewriteStepContent: Step 1 改写内容（含场景元数据）
 * - EvaluationStepContent: Step 2 评估结果
 */

import React from 'react';
import type { ActiveTrainingSession, EvaluationResult } from '../../shared/types-training';
import { getStructuredTaskForActiveTraining } from '../../shared/structured-tasks';
import sharedStyles from './TrainingShared.module.css';
import { TrainingHeader } from './TrainingHeader';
import { GoalTrackingPanel } from './GoalTrackingPanel';
import { StepIndicatorList } from './StepIndicatorList';
import { ReadingStepContent } from './ReadingStepContent';
import { RewriteStepContent } from './RewriteStepContent';
import { EvaluationStepContent } from './EvaluationStepContent';
import { FiveStepFlow } from './flow/FiveStepFlow';
import styles from './ActiveTrainingView.module.css';

interface ActiveTrainingViewProps {
  activeTraining: ActiveTrainingSession;
  submissionResult: { passed: boolean; feedback: string } | null;
  evaluationResult: EvaluationResult | null;
  isLoading: boolean;
  onBackToChat: () => void;
  onSubmitStep: () => void;
  onSkipTraining: () => void;
  onUpdateDraft: (content: string) => void;
  /** X-02: 将训练稿写入编辑器 */
  onSendToEditor?: () => void;
}

export const ActiveTrainingView: React.FC<ActiveTrainingViewProps> = ({
  activeTraining,
  submissionResult,
  evaluationResult,
  isLoading,
  onBackToChat,
  onSubmitStep,
  onSkipTraining,
  onUpdateDraft,
  onSendToEditor,
}) => {
  // 结构化任务数据（当 challengeId 能映射到 structured-tasks 时可用）
  const structuredTask = React.useMemo(
    () => getStructuredTaskForActiveTraining(activeTraining.challengeId) ?? null,
    [activeTraining.challengeId],
  );

  // S16: 五步流分支 —— 当 flowType === 'flow5' 且 trainingFlow 存在时切换到 FiveStepFlow
  if (activeTraining.flowType === 'flow5' && activeTraining.trainingFlow) {
    return (
      <div className={sharedStyles.trainingContainer}>
        <FiveStepFlow
          active={activeTraining}
          flow={activeTraining.trainingFlow}
          evaluation={evaluationResult}
          onExit={onBackToChat}
        />
      </div>
    );
  }

  return (
    <div className={sharedStyles.trainingContainer}>
      {/* 头部 + 进度条 */}
      <TrainingHeader session={activeTraining} onBackToChat={onBackToChat} />

      {/* 三级目标追踪 */}
      <GoalTrackingPanel session={activeTraining} />

      {/* 步骤内容区 */}
      <div className={styles.stepContentArea}>
        <div className={styles.stepContentInner}>
          {/* 步骤状态列表 */}
          <StepIndicatorList steps={activeTraining.steps} />

          {/* Step 0: 阅读原始文本 / 阅读指导 */}
          {activeTraining.currentStepIndex === 0 && (
            <ReadingStepContent session={activeTraining} />
          )}

          {/* Step 1: 约束改写 / 写下分析 */}
          {activeTraining.currentStepIndex === 1 && (
            <RewriteStepContent
              session={activeTraining}
              structuredTask={structuredTask}
              submissionResult={submissionResult}
              isLoading={isLoading}
              onUpdateDraft={onUpdateDraft}
            />
          )}

          {/* Step 2: 提交评估结果 */}
          {activeTraining.currentStepIndex === 2 && (
            <EvaluationStepContent
              evaluationResult={evaluationResult}
              submissionResult={submissionResult}
              isLoading={isLoading}
              onBackToChat={onBackToChat}
              onSubmitStep={onSubmitStep}
              onSendToEditor={onSendToEditor}
            />
          )}

          {/* 操作按钮（Step 2 已在内嵌出口中，此处隐藏） */}
          {activeTraining.currentStepIndex < 2 && (
            <div className={styles.actionBar}>
              <button onClick={onSkipTraining} className={sharedStyles.trainingSecondaryBtn}>
                {activeTraining.currentStepIndex >= 1 ? '存草稿' : '跳过'}
              </button>
              <button
                onClick={onSubmitStep}
                className={sharedStyles.trainingPrimaryBtn}
                disabled={
                  (activeTraining.currentStepIndex === 1 && !activeTraining.userDraft.trim()) ||
                  isLoading
                }
              >
                {isLoading ? '评估中...' : '继续'}
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
