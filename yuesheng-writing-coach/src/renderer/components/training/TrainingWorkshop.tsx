/**
 * TrainingWorkshop 训练工坊主面板
 *
 * 三区块布局（V4.0 §4.3）：
 * 区块一：你的常见问题（ErrorCardsSection）
 * 区块二：推荐训练任务（RecommendationsSection）
 * 区块三：近期训练记录（HistorySection）
 *
 * 额外：ProgressTimeline（教学进度时间轴）
 *
 * 步骤式练习（activeTraining 不为 null）：
 *   所有 mode 共享通用三步框架，Step 2 提交后由 AI 评估是否符合约束。
 *   前端不做任何 mode 特定的硬编码校验。添加新 mode 只需改模板 JSON。
 */

import React from 'react';
import type { ErrorCard, TrainingRecommendation, ActiveTrainingSession, TrainingRecord, EvaluationResult } from '../../shared/types';
import { ErrorCardsSection } from './ErrorCardsSection';
import { RecommendationsSection } from './RecommendationsSection';
import { HistorySection } from './HistorySection';
import { ActiveTrainingView } from './ActiveTrainingView';
import { BehaviorDerivationTool } from './BehaviorDerivationTool';
import sharedStyles from './TrainingShared.module.css';

// ===== 类型定义 =====

export interface TrainingWorkshopProps {
  errorCards: ErrorCard[];
  recommendations: TrainingRecommendation[];
  readingDecision: { required: boolean; recommended: boolean; label: string; reason?: string } | null;
  /** M4: 阅读完成横幅标记 */
  readingComplete: boolean;
  activeTraining: ActiveTrainingSession | null;
  history: TrainingRecord[];
  /** AI 提交评估结果（null = 未提交或已清除） */
  submissionResult: { passed: boolean; feedback: string } | null;
  /** 训练评分结果（Evaluator Agent 输出，null = 未评估） */
  evaluationResult: EvaluationResult | null;
  isLoading: boolean;
  error: string | null;
  onStartTraining: (challengeId: string) => void;
  /** B-02: 阅读前置任务 */
  onStartReading: (challengeId: string) => void;
  /** M4: 关闭阅读完成横幅 */
  onDismissReadingComplete: () => void;
  onBackToChat: () => void;
  onSubmitStep: () => void;
  onSkipTraining: () => void;
  onUpdateDraft: (content: string) => void;
  /** X-02: 将训练稿写入编辑器 */
  onSendToEditor?: () => void;
  /** A3: 最近一次训练的评估分数（用于自荐阅读框架） */
  lastEvaluationScore?: number | null;
  /** A3: 最近训练对应的症候 ID（用于匹配阅读材料） */
  lastSyndromeId?: string | null;
}

// ===== ProgressTimeline 子组件 =====

const PHASES = [
  { id: 'diagnosis', label: '诊断' },
  { id: 'teaching', label: '教学' },
  { id: 'validation', label: '验证' },
  { id: 'retro', label: '复盘' },
];

/** 从训练记录推断当前教学阶段 */
function inferActivePhase(history: TrainingRecord[]): { activeId: string; completedIds: Set<string> } {
  const completedIds = new Set<string>();
  if (history.length === 0) return { activeId: 'diagnosis', completedIds };

  // 有完成的训练 = 教学阶段
  const hasCompleted = history.some(r => r.status === 'completed');
  if (!hasCompleted) return { activeId: 'diagnosis', completedIds };

  completedIds.add('diagnosis');
  completedIds.add('teaching');
  // 有验证结果则标记验证完成
  const hasValidation = history.some(r => r.effectiveness != null);
  if (hasValidation) completedIds.add('validation');
  // 历史超过 5 条则标记复盘完成
  if (history.length >= 5) completedIds.add('retro');

  return {
    activeId: hasCompleted ? 'validation' : 'teaching',
    completedIds,
  };
}

const ProgressTimeline: React.FC<{ history: TrainingRecord[] }> = ({ history }) => {
  const { activeId, completedIds } = inferActivePhase(history);

  return (
    <div className={sharedStyles.timeline}>
      {PHASES.map((phase, i) => {
        const isActive = phase.id === activeId;
        const isCompleted = completedIds.has(phase.id);
        const isPending = !isActive && !isCompleted;
        return (
          <React.Fragment key={phase.id}>
            <div
              className={`${sharedStyles.timelinePhase} ${
                isActive ? sharedStyles.timelinePhaseActive : ''
              } ${isCompleted ? sharedStyles.timelinePhaseCompleted : ''}`}
              style={{ opacity: isPending ? 0.5 : 1 }}
            >
              <span
                className={`${sharedStyles.timelineDot} ${
                  isActive ? sharedStyles.timelineDotActive : ''
                } ${isCompleted ? sharedStyles.timelineDotCompleted : ''}`}
              />
              <span>{phase.label}</span>
            </div>
            {i < PHASES.length - 1 && (
              <div
                className={`${sharedStyles.timelineConnector} ${
                  isCompleted || isActive ? sharedStyles.timelineConnectorCompleted : ''
                } ${isCompleted ? sharedStyles.timelineConnectorCompleted : ''}`}
              />
            )}
          </React.Fragment>
        );
      })}
    </div>
  );
};

// ===== 主组件 =====

export const TrainingWorkshop: React.FC<TrainingWorkshopProps> = ({
  errorCards,
  recommendations,
  readingDecision,
  readingComplete,
  activeTraining,
  history,
  submissionResult,
  evaluationResult,
  isLoading,
  error,
  onStartTraining,
  onStartReading,
  onDismissReadingComplete,
  onBackToChat,
  onSubmitStep,
  onSkipTraining,
  onUpdateDraft,
  onSendToEditor,
  lastEvaluationScore,
  lastSyndromeId,
}) => {
  /** 点击"开始练习"— 拦截 B-02 阅读决策 */
  const handleStartTrainingClick = React.useCallback((challengeId: string) => {
    if (readingDecision?.required) {
      // B-02 要求必须先阅读
      onStartReading(challengeId);
      return;
    }
    // B-02 推荐阅读或无需阅读 → 直接进入训练
    onStartTraining(challengeId);
  }, [readingDecision, onStartTraining, onStartReading]);

  // 加载中（仅首次加载时显示）
  if (isLoading && !activeTraining) {
    return (
      <div className={sharedStyles.trainingContainer}>
        <div className={`${sharedStyles.trainingLoading} animate-fade-in`}>
          <div className={sharedStyles.loadingText}>加载中...</div>
        </div>
      </div>
    );
  }

  // 错误状态
  if (error && !activeTraining) {
    return (
      <div className={sharedStyles.trainingContainer}>
        <div className={`${sharedStyles.trainingLoading} animate-fade-in`}>
          <div className={sharedStyles.errorText}>{error}</div>
        </div>
      </div>
    );
  }

  // 步骤式练习视图
  if (activeTraining) {
    return (
      <div className={`animate-fade-in ${sharedStyles.activeTrainingView}`}>
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

  // 训练工坊主面板（三区块布局 + 时间轴）
  return (
    <div className={`${sharedStyles.trainingContainer} animate-fade-in`}>
      {/* 工坊头部 */}
      <div className={sharedStyles.workshopHeader}>
        <div className={sharedStyles.workshopHeaderTitle}>训练工坊</div>
      </div>

      {/* Progress Timeline */}
      <ProgressTimeline history={history} />

      {/* M4: 阅读完成横幅 */}
      {readingComplete && (
        <div className={sharedStyles.readingBanner}>
          <span className={sharedStyles.readingBannerText}>
            阅读分析已完成。下面是根据诊断结果调整后的推荐训练任务。
          </span>
          <button
            className={sharedStyles.readingBannerBtn}
            onClick={onDismissReadingComplete}
          >
            知道了
          </button>
        </div>
      )}

      {/* 三区块内容 */}
      <div className={sharedStyles.workshopContent}>
        <div className={sharedStyles.workshopInner}>
          <ErrorCardsSection
          cards={errorCards}
          recommendations={recommendations}
          onStartTraining={handleStartTrainingClick}
        />
          <RecommendationsSection
            recommendations={recommendations}
            onStartTraining={handleStartTrainingClick}
            lastEvaluationScore={lastEvaluationScore ?? undefined}
            lastSyndromeId={lastSyndromeId ?? undefined}
            onStartReading={onStartReading}
          />
          <BehaviorDerivationTool />
          <HistorySection
            history={history}
            isLoading={isLoading}
          />
        </div>
      </div>
    </div>
  );
};
