import React, { useCallback, useEffect, useMemo } from 'react';
import { useSessionStore } from '../../../stores/session.store';
import { useChatStore } from '../../../stores/chat.store';
import { useTeachingStateStore } from '../../../stores/teaching-state.store';
import { useRightToolsStore } from '../../../stores/right-tools.store';
import { useTrainingStore, selectCenterMode } from '../../../stores/training.store';
import { useDiagStore } from '../../../stores/diag.store';
import { useConfigStore } from '../../../stores/config.store';
import { useStudentContextStore } from '../../../stores/student-context.store';
import { ChatView } from '../../chat/ChatView';
import { TrainingWorkshop } from '../../training/TrainingWorkshop';
import { Footer } from '../Footer';
import { useDiagnosisFlow } from '../../../hooks/useDiagnosisFlow';
import { RetroSummaryView } from '../../retro/RetroSummaryView';
import styles from './index.module.css';

interface CenterPanelProps {
  collapsedLeft: boolean;
  setCollapsedLeft: (v: boolean) => void;
}

// ===== 会话切换时加载消息的 hook =====

function useSessionMessages(currentSessionId: string | null): void {
  useEffect(() => {
    if (currentSessionId) {
      (async () => {
        const msgs = await useSessionStore.getState().loadMessages(currentSessionId);
        useChatStore.getState().setMessages(msgs);
      })();
    } else {
      useChatStore.getState().setMessages([]);
    }
  }, [currentSessionId]);
}

// ===== 发送消息 handler（含 C-5 mastery 注入）=====

async function handleSendMessage(text: string): Promise<void> {
  let sid = useSessionStore.getState().currentSessionId;
  if (!sid) {
    const s = await useSessionStore.getState().createSession();
    if (!s) return;
    sid = s.id;
  }
  const attitudeLevel = useConfigStore.getState().attitudeLevel;
  const studentContext = useStudentContextStore.getState().toJSON();
  const masteredIds = useTeachingStateStore.getState().masteredSyndromeIds;
  const masterySuffix = masteredIds.length > 0
    ? `\n\n[已精通技法] ${masteredIds.join(', ')}`
    : '';
  useChatStore.getState().sendMessage(text, {
    sessionId: sid,
    attitudeLevel,
    studentContext: studentContext + masterySuffix,
  });
}

// ===== 主组件 =====

export const CenterPanel: React.FC<CenterPanelProps> = ({
  collapsedLeft, setCollapsedLeft,
}) => {
  const { sessions, currentSessionId, loadSessions, switchSession } = useSessionStore();
  const messages = useChatStore((s) => s.messages);
  const { currentState } = useTeachingStateStore();
  const { openTool } = useRightToolsStore();
  const centerMode = useTrainingStore(selectCenterMode);
  const trainingState = useTrainingStore((s) => ({
    errorCards: s.errorCards,
    recommendations: s.recommendations,
    readingDecision: s.readingDecision,
    readingComplete: s.readingComplete,
    activeTraining: s.activeTraining,
    history: s.history,
    submissionResult: s.submissionResult,
    evaluationResult: s.evaluationResult,
    isLoading: s.isLoading,
    error: s.error ?? null,
    bridgeRecommendation: s.bridgeRecommendation,
    lastEvaluationScore: s.lastEvaluationScore,
    lastSyndromeId: s.lastSyndromeId,
    retroSummary: s.retroSummary,
    retroLoading: s.retroLoading,
  }));
  const myCurrentDiagnosis = useDiagStore((s) => s.currentDiagnosis);
  const isConfigured = useConfigStore((s) => s.isConfigured);

  // F-02: 诊断→修改→评估 流程状态
  const flow = useDiagnosisFlow(currentSessionId);

  // F-01: 会话消息加载
  useSessionMessages(currentSessionId);

  useEffect(() => {
    loadSessions();
  }, [loadSessions]);

  // Auto-select first session
  useEffect(() => {
    if (!currentSessionId && sessions.length > 0) {
      switchSession(sessions[0].id);
    }
  }, [sessions, currentSessionId, switchSession]);

  const currentSession = sessions.find(s => s.id === currentSessionId);

  const handleNewSession = async () => {
    const { createSession } = useSessionStore.getState();
    const s = await createSession();
    if (s) switchSession(s.id);
  };

  // [模板] 按钮（由 Footer 触发，功能在 F-02 后续完善）
  const handleToggleTemplate = useCallback(() => {
    // F-02: wire template panel
  }, []);

  // 桥接卡片 → 进入训练工坊
  const handleEnterWorkshopFromBridge = useCallback((_challengeId: string) => {
    useTrainingStore.getState().enterWorkshop();
  }, []);

  // 关闭桥接卡片
  const handleDismissBridge = useCallback(() => {
    useTrainingStore.getState().dismissBridge();
  }, []);

  // 停止流式生成
  const handleStop = useCallback(() => {
    useChatStore.getState().abortStream();
  }, []);

  // 训练工坊 actions
  const handleStartTraining = useCallback((challengeId: string) => {
    useTrainingStore.getState().startTraining(challengeId);
  }, []);
  const handleStartReading = useCallback((challengeId: string) => {
    useTrainingStore.getState().startReading(challengeId);
  }, []);
  const handleDismissReadingComplete = useCallback(() => {
    useTrainingStore.getState().dismissReadingComplete();
  }, []);
  const handleBackToChat = useCallback(() => {
    useTrainingStore.getState().backToChat();
  }, []);

  const handleSubmitStep = useCallback(() => {
    useTrainingStore.getState().submitStep();
  }, []);
  const handleSkipTraining = useCallback(() => {
    useTrainingStore.getState().skipTraining();
  }, []);
  const handleUpdateDraft = useCallback((content: string) => {
    useTrainingStore.getState().updateDraft(content);
  }, []);
  const handleSendToEditor = useCallback(() => {
    useTrainingStore.getState().sendToEditor();
  }, []);

  // F-02: 诊断编辑 callbacks → useDiagnosisFlow
  const handleStartEditing = useCallback(
    (syndromeId: string, evidence: string[], name: string, severity: string) => {
      flow.startEditing(syndromeId, evidence, name, severity);
    },
    [flow],
  );
  const handleSubmitRewrite = useCallback(
    (text: string) => {
      flow.submitRewrite(text);
    },
    [flow],
  );
  const handleCancelEditing = useCallback(() => {
    flow.cancelEditing();
  }, [flow]);

  // 教学状态标签
  const statusText = React.useMemo(() => {
    if (!currentState?.currentSubphase) return '教学中';
    const LABELS: Record<string, string> = {
      S1: '待诊断', S2: '诊断中', S3: '待训练',
      S4: '训练中', S5: '待回顾', S6: '回顾中', S7: '已完成',
    };
    return LABELS[currentState.currentSubphase] ?? currentState.currentSubphase;
  }, [currentState]);

  // ChatView props — 用 useMemo 避免无关更新
  const isStreaming = useChatStore((s) => s.isLoading);
  const chatViewProps = useMemo(() => ({
    messages,
    isStreaming,
    currentSessionId,
    currentDiagnosis: myCurrentDiagnosis,
    editingSyndrome: flow.editingSyndrome,
    isSubmitting: flow.isSubmitting,
    lastEvaluation: flow.lastEvaluation,
    lastOriginalText: flow.lastOriginalText,
    lastRewrittenText: flow.lastRewrittenText,
    growthLoading: flow.growthLoading,
    hasHistory: flow.hasHistory,
    growthSummary: flow.growthSummary,
    bridgeRecommendation: trainingState.bridgeRecommendation,
    isConfigured,
    onSend: handleSendMessage,
    onStop: handleStop,
    onStartEditing: handleStartEditing,
    onSubmitRewrite: handleSubmitRewrite,
    onCancelEditing: handleCancelEditing,
    onEnterWorkshopFromBridge: handleEnterWorkshopFromBridge,
    onDismissBridge: handleDismissBridge,
  }), [
    messages, isStreaming, myCurrentDiagnosis, currentSessionId,
    flow.editingSyndrome, flow.isSubmitting, flow.lastEvaluation,
    flow.lastOriginalText, flow.lastRewrittenText,
    flow.growthLoading, flow.hasHistory, flow.growthSummary,
    trainingState.bridgeRecommendation, isConfigured,
    handleStop, handleStartEditing, handleSubmitRewrite,
    handleCancelEditing, handleEnterWorkshopFromBridge, handleDismissBridge,
  ]);

  return (
    <div className={styles.wrapper}>
      {/* Header */}
      <header className={styles.header}>
        <div className={styles.headerLeft}>
          {collapsedLeft && (
            <div className={styles.collapsedBar}>
              <div className="w-[26px] h-[26px] rounded bg-[#7A6040] text-white flex items-center justify-center text-[13px] font-bold font-serif flex-shrink-0">月</div>
              <button className={styles.expandBtn} onClick={() => setCollapsedLeft(false)} title="展开">☰</button>
            </div>
          )}
          <button className={styles.projectBtn}>
            <span className={styles.projectBtnArrow}>▼</span>
            <span>我的第一本小说</span>
            <span className={styles.projectBtnArrow}>▾</span>
          </button>
          <span className={styles.statusBadge}>
            <span className={styles.statusDot} />
            <span>{statusText}</span>
          </span>
          {currentSession && (
            <span className={styles.sessionBadge}>{currentSession.title}</span>
          )}
        </div>
        <div className={styles.headerActions}>
          {centerMode === 'training' && (
            <button
              className={styles.headerBackBtn}
              onClick={handleBackToChat}
              title="返回对话"
            >
              ← 返回
            </button>
          )}
          <button className={styles.headerBtn} onClick={handleNewSession} title="新建会话">＋</button>
          <button className={styles.headerBtn} onClick={() => openTool('__settings__')} title="设置">⚙</button>
        </div>
      </header>

      {/* Content */}
      <div className={styles.chatArea}>
        {centerMode === 'retro' ? (
          <RetroSummaryView
            totalTrainingCount={trainingState.retroSummary?.totalTrainingCount ?? 0}
            syndromeCount={trainingState.retroSummary?.syndromeCount ?? 0}
            syndromeSummaries={trainingState.retroSummary?.syndromeSummaries ?? []}
            overallImprovement={trainingState.retroSummary?.overallImprovement ?? 0}
            masteredTechniques={trainingState.retroSummary?.masteredTechniques ?? []}
            recommendedFocus={trainingState.retroSummary?.recommendedFocus ?? []}
            summary={trainingState.retroSummary?.summary ?? ''}
            onBackToChat={handleBackToChat}
            onStartNewTraining={handleBackToChat}
          />
        ) : centerMode === 'training' ? (
          <TrainingWorkshop
            errorCards={trainingState.errorCards}
            recommendations={trainingState.recommendations}
            readingDecision={trainingState.readingDecision}
            readingComplete={trainingState.readingComplete}
            activeTraining={trainingState.activeTraining}
            history={trainingState.history}
            submissionResult={trainingState.submissionResult}
            evaluationResult={trainingState.evaluationResult}
            isLoading={trainingState.isLoading}
            error={trainingState.error}
            onStartTraining={handleStartTraining}
            onStartReading={handleStartReading}
            onDismissReadingComplete={handleDismissReadingComplete}
            onBackToChat={handleBackToChat}
            onSubmitStep={handleSubmitStep}
            onSkipTraining={handleSkipTraining}
            onUpdateDraft={handleUpdateDraft}
            onSendToEditor={handleSendToEditor}
            lastEvaluationScore={trainingState.lastEvaluationScore}
            lastSyndromeId={trainingState.lastSyndromeId}
          />
        ) : !currentSessionId ? (
          <div className={styles.empty}>
            <h2 className={styles.emptyTitle}>开始你的写作之旅</h2>
            <div className={styles.emptyOptions}>
              <button className={styles.emptyOption} onClick={() => handleNewSession()}>
                <span className={styles.emptyOptionIcon}>📝</span>
                <div>
                  <div className={styles.emptyOptionLabel}>我有作品</div>
                  <div className={styles.emptyOptionHint}>直接进入聊天，我会帮你分析</div>
                </div>
              </button>
              <button className={styles.emptyOption} onClick={() => handleNewSession()}>
                <span className={styles.emptyOptionIcon}>🌱</span>
                <div>
                  <div className={styles.emptyOptionLabel}>从头学习</div>
                  <div className={styles.emptyOptionHint}>我引导你搭建世界观和人物</div>
                </div>
              </button>
              <button className={styles.emptyOption} onClick={() => handleNewSession()}>
                <span className={styles.emptyOptionIcon}>💬</span>
                <div>
                  <div className={styles.emptyOptionLabel}>先聊聊</div>
                  <div className={styles.emptyOptionHint}>正常聊天，我在对话中自然引导</div>
                </div>
              </button>
            </div>
          </div>
        ) : (
          <ChatView {...chatViewProps} />
        )}
      </div>

      {/* Footer（仅在对话/复盘模式下显示） */}
      {centerMode !== 'training' && (
        <Footer chatSessionId={currentSessionId} onToggleTemplate={handleToggleTemplate} />
      )}
    </div>
  );
};
