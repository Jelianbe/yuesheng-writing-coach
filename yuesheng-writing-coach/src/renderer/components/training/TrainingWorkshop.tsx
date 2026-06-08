/**
 * TrainingWorkshop 训练工坊主面板
 *
 * 三区块布局（V4.0 §4.3）：
 * 区块一：你的常见问题（ErrorCardsSection）
 * 区块二：推荐训练任务（RecommendationsSection）
 * 区块三：近期训练记录（HistorySection）
 *
 * 步骤式练习（activeTraining 不为 null）：
 *   所有 mode 共享通用三步框架，Step 2 提交后由 AI 评估是否符合约束。
 *   前端不做任何 mode 特定的硬编码校验。添加新 mode 只需改模板 JSON。
 */

import React from 'react';
import type { ErrorCard, TrainingRecommendation, ActiveTrainingSession, TrainingRecord, EvaluationResult } from '../../shared/types';
import ErrorCardsSection from './ErrorCardsSection';
import RecommendationsSection from './RecommendationsSection';
import HistorySection from './HistorySection';
import ActiveTrainingView from './ActiveTrainingView';
import BehaviorDerivationTool from './BehaviorDerivationTool';
import {
  containerStyle,
  loadingStyle,
} from './training-styles';

// ===== 类型定义 =====

export interface TrainingWorkshopProps {
  errorCards: ErrorCard[];
  recommendations: TrainingRecommendation[];
  activeTraining: ActiveTrainingSession | null;
  history: TrainingRecord[];
  /** AI 提交评估结果（null = 未提交或已清除） */
  submissionResult: { passed: boolean; feedback: string } | null;
  /** 训练评分结果（Evaluator Agent 输出，null = 未评估） */
  evaluationResult: EvaluationResult | null;
  isLoading: boolean;
  error: string | null;
  onStartTraining: (challengeId: string) => void;
  onBackToChat: () => void;
  onSubmitStep: () => void;
  onSkipTraining: () => void;
  onUpdateDraft: (content: string) => void;
  /** X-02: 将训练稿写入编辑器 */
  onSendToEditor?: () => void;
}

// ===== 主组件 =====

export const TrainingWorkshop: React.FC<TrainingWorkshopProps> = ({
  errorCards,
  recommendations,
  activeTraining,
  history,
  submissionResult,
  evaluationResult,
  isLoading,
  error,
  onStartTraining,
  onBackToChat,
  onSubmitStep,
  onSkipTraining,
  onUpdateDraft,
  onSendToEditor,
}) => {
  /** 点击"开始练习"直接进入训练 */
  const handleStartTrainingClick = React.useCallback((challengeId: string) => {
    onStartTraining(challengeId);
  }, [onStartTraining]);

  /** B4: 根据任务 ID 获取可读名称 */
  const getTaskName = React.useCallback((taskId: string): string | undefined => {
    const match = recommendations.find(r => r.challengeId === taskId);
    return match?.challengeName;
  }, [recommendations]);

  // 加载中（仅首次加载时显示）
  if (isLoading && !activeTraining) {
    return (
      <div style={containerStyle}>
        <div style={loadingStyle} className="animate-fade-in">
          <div style={{ fontSize: '1rem', color: 'var(--text-secondary)' }}>加载中...</div>
        </div>
      </div>
    );
  }

  // 错误状态
  if (error && !activeTraining) {
    return (
      <div style={containerStyle}>
        <div style={loadingStyle} className="animate-fade-in">
          <div style={{ fontSize: '0.875rem', color: '#e74c3c' }}>{error}</div>
        </div>
      </div>
    );
  }

  // 步骤式练习视图
  if (activeTraining) {
    return (
      <div className="animate-fade-in" style={{ height: '100%' }}>
        <ActiveTrainingView
          activeTraining={activeTraining}
          submissionResult={submissionResult}
          evaluationResult={evaluationResult}
          isLoading={isLoading}
          onBackToChat={onBackToChat}
          onSubmitStep={onSubmitStep}
          onSkipTraining={onSkipTraining}
          onUpdateDraft={onUpdateDraft}
          onSendToEditor={onSendToEditor}
        />
      </div>
    );
  }

  // 训练工坊主面板（三区块布局）
  return (
    <div style={containerStyle} className="animate-fade-in">
      {/* 工坊头部 */}
      <div style={{
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'center',
        padding: '16px 24px',
        backgroundColor: 'var(--accent-subtle)',
        borderBottom: '1px solid var(--border)',
      }}>
        <div style={{ fontSize: '1.1rem', fontWeight: 600, color: 'var(--text-primary)' }}>
          训练工坊
        </div>
      </div>

      {/* 三区块内容 */}
      <div style={{ flex: 1, overflow: 'auto', padding: 20 }}>
        <div style={{ maxWidth: 800, margin: '0 auto' }}>
          <ErrorCardsSection
          cards={errorCards}
          recommendations={recommendations}
          onStartTraining={handleStartTrainingClick}
        />
          <RecommendationsSection
            recommendations={recommendations}
            onStartTraining={handleStartTrainingClick}
          />
          <BehaviorDerivationTool />
          <HistorySection
            history={history}
            isLoading={isLoading}
            getTaskName={getTaskName}
          />
        </div>
      </div>
    </div>
  );
};
