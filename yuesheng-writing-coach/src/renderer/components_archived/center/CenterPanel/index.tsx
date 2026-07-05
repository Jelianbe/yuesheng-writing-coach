/**
 * CenterPanel — 中间栏内容区
 *
 * 架构（G-2 后）：
 * - 顶部 Header 由 CenterHeader 子组件渲染（多项目下拉、状态徽章、操作按钮）
 * - 本组件只负责：会话加载、内容区切换（Chat/Training/Editor/Retro/Empty）
 */

import React, { useCallback, useEffect, useMemo } from 'react';
import { useSessionStore } from '../../../stores/session.store';
import { useChatStore } from '../../../stores/chat.store';
import { useTeachingStateStore } from '../../../stores/teaching-state.store';
import { useTrainingStore, selectCenterMode } from '../../../stores/training.store';
import { useDiagStore } from '../../../stores/diag.store';
import { useConfigStore } from '../../../stores/config.store';
import { useStudentContextStore } from '../../../stores/student-context.store';
import { ChatView } from '../../chat/ChatView';
import { TrainingWorkshop } from '../../training/TrainingWorkshop';
import { ManuscriptPanel } from '../../manuscript/ManuscriptPanel';
import { Footer } from '../Footer';
import { CenterHeader } from '../CenterHeader';
import { useDiagnosisFlow } from '../../../hooks/useDiagnosisFlow';
import { RetroSummaryView } from '../../retro/RetroSummaryView';
import { PenLine, Sprout, MessageCircle } from 'lucide-react';
import {
  useCenterSessionId,
  useCenterSessionList,
  useTrainingWorkshopState,
  useBridgeState,
  useRetroState,
} from './selectors';
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
  // T17-7: 拆分为独立 selectors（避免整 store 订阅 + 聚合订阅）
  const currentSessionId = useCenterSessionId();
  const sessions = useCenterSessionList();
  const messages = useChatStore((s) => s.messages);
  const centerMode = useTrainingStore(selectCenterMode);
  const trainingState = useTrainingWorkshopState();
  const bridgeRecommendation = useBridgeState();
  const { retroSummary } = useRetroState();
  const myCurrentDiagnosis = useDiagStore((s) => s.currentDiagnosis);
  const isConfigured = useConfigStore((s) => s.isConfigured);

  // F-02: 诊断→修改→评估 流程状态
  const flow = useDiagnosisFlow(currentSessionId);

  // F-01: 会话消息加载
  useSessionMessages(currentSessionId);

  useEffect(() => {
    useSessionStore.getState().loadSessions();
  }, []);

  // Auto-select first session
  useEffect(() => {
    if (!currentSessionId && sessions.length > 0) {
      useSessionStore.getState().switchSession(sessions[0].id);
    }
  }, [sessions, currentSessionId]);

  // [模板] 按钮（由 Footer 触发，功能在 F-02 后续完善）
  const handleToggleTemplate = useCallback(() => {
    // F-02: wire template panel
  }, []);

  const handleNewSession = useCallback(async () => {
    const { createSession } = useSessionStore.getState();
    const s = await createSession();
    if (s) useSessionStore.getState().switchSession(s.id);
  }, []);

  const handleBackToChat = useCallback(() => {
    useTrainingStore.getState().backToChat();
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
    bridgeRecommendation,
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
    bridgeRecommendation, isConfigured,
    handleStop, handleStartEditing, handleSubmitRewrite,
    handleCancelEditing, handleEnterWorkshopFromBridge, handleDismissBridge,
  ]);

  return (
    <div className={styles.wrapper}>
      {/* G-2: Header 拆为独立子组件 */}
      <CenterHeader
        collapsedLeft={collapsedLeft}
        setCollapsedLeft={setCollapsedLeft}
        centerMode={centerMode}
        onNewSession={handleNewSession}
        onBackToChat={handleBackToChat}
      />

      {/* Content */}
      <div className={styles.chatArea}>
        {centerMode === 'retro' ? (
          <RetroSummaryView
            totalTrainingCount={retroSummary?.totalTrainingCount ?? 0}
            syndromeCount={retroSummary?.syndromeCount ?? 0}
            syndromeSummaries={retroSummary?.syndromeSummaries ?? []}
            overallImprovement={retroSummary?.overallImprovement ?? 0}
            masteredTechniques={retroSummary?.masteredTechniques ?? []}
            recommendedFocus={retroSummary?.recommendedFocus ?? []}
            summary={retroSummary?.summary ?? ''}
            onBackToChat={handleBackToChat}
            onStartNewTraining={handleBackToChat}
          />
        ) : centerMode === 'editor' ? (
          <ManuscriptPanel />
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
                <span className={styles.emptyOptionIcon}><PenLine size={20} aria-hidden /></span>
                <div>
                  <div className={styles.emptyOptionLabel}>我有作品</div>
                  <div className={styles.emptyOptionHint}>直接进入聊天，我会帮你分析</div>
                </div>
              </button>
              <button className={styles.emptyOption} onClick={() => handleNewSession()}>
                <span className={styles.emptyOptionIcon}><Sprout size={20} aria-hidden /></span>
                <div>
                  <div className={styles.emptyOptionLabel}>从头学习</div>
                  <div className={styles.emptyOptionHint}>我引导你搭建世界观和人物</div>
                </div>
              </button>
              <button className={styles.emptyOption} onClick={() => handleNewSession()}>
                <span className={styles.emptyOptionIcon}><MessageCircle size={20} aria-hidden /></span>
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

      {/* Footer（仅在 chat 模式下显示 — training/retro/editor 由各自视图内部负责底部交互） */}
      {centerMode === 'chat' && (
        <Footer chatSessionId={currentSessionId} onToggleTemplate={handleToggleTemplate} />
      )}
    </div>
  );
};
