/**
 * useAppOrchestrator — 应用级编排钩子
 *
 * 封装 App.tsx 中所有 store 订阅、useDiagnosisFlow、useAppController、
 * 事件处理器以及面板内容的组装。重构后 App.tsx 仅使用本钩子返回的值。
 */

import { useState, useCallback, useEffect, useMemo } from 'react';
import { Search, ClipboardCheck, Target, TrendingUp, User, BookOpen } from 'lucide-react';
import type { LucideIcon } from 'lucide-react';

import { useAppController } from '../services/useAppController';
import { useDiagnosisFlow } from './useDiagnosisFlow';
import { useConfigStore } from '../stores/config.store';
import { useChatStore } from '../stores/chat.store';
import { useDiagStore } from '../stores/diag.store';
import { useSessionStore } from '../stores/session.store';
import { useStudentContextStore } from '../stores/student-context.store';
import { useTrainingStore } from '../stores/training.store';
import { rightPanelService } from '../services/right-panel.service';
import type { PanelId } from '../services/right-panel.service';
import { chatService } from '../services/chat.service';
import type { OnboardingBaseline } from '../shared/types';
import { ChatView } from '../components/chat/ChatView';
import { TrainingWorkshop } from '../components/training/TrainingWorkshop';
import { DiagnosisPanel } from '../components/layout/DiagnosisPanel';
import { AbilityProfilePanel } from '../components/profile/AbilityProfilePanel';
import { DiagnosisComparisonView } from '../components/growth/DiagnosisComparisonView';
import { SettingsPanel } from '../components/settings/SettingsPanel';
import { SearchPanel } from '../components/search/SearchPanel';
import { ManuscriptPanel } from '../components/manuscript/ManuscriptPanel';

export interface UseAppOrchestratorResult {
  ready: boolean;
  showOnboarding: boolean;
  isConfigLoading: boolean;
  isConfigured: boolean;
  drawerTools: Array<{ id: string; icon: LucideIcon; label: string }>;
  panelContent: Record<string, React.ReactNode>;
  chatViewProps: Parameters<typeof ChatView>[0];
  handleOnboardingComplete: (baseline: OnboardingBaseline) => Promise<void>;
  handleOnboardingSkip: () => Promise<void>;
  handleToolClick: (toolId: string) => void;
}

export function useAppOrchestrator(): UseAppOrchestratorResult {
  // 1. 本地状态
  const [showOnboarding, setShowOnboarding] = useState(false);

  // 2. Store 订阅（保持与 App.tsx 一致的选择粒度）
  const { isLoading: isConfigLoading, isConfigured, loadConfig } = useConfigStore();
  const { messages, isLoading: isStreaming } = useChatStore();
  const { currentDiagnosis } = useDiagStore();
  const { currentSessionId, createSession, switchSession } = useSessionStore();
  const {
    errorCards,
    recommendations,
    readingDecision,
    readingComplete,
    activeTraining,
    history: trainingHistory,
    submissionResult,
    evaluationResult,
    isLoading: trainingLoading,
    error: trainingError,
    bridgeRecommendation,
    lastEvaluationScore,
    lastSyndromeId,
    startTraining,
    startReading,
    submitStep,
    skipTraining,
    updateDraft,
    dismissBridge,
    backToChat,
    sendToEditor,
    dismissReadingComplete,
  } = useTrainingStore();

  // 3. 跨模块编排钩子
  const sessionId = useSessionStore((s) => s.currentSessionId);
  const {
    fetchGrowthSummary,
    startEditing,
    cancelEditing,
    submitRewrite,
    editingSyndrome,
    isSubmitting,
    lastEvaluation,
    lastRewrittenText,
    lastOriginalText,
    growthLoading,
    growthSummary,
    hasHistory,
    reset: resetDiagnosisFlow,
  } = useDiagnosisFlow(sessionId);

  const { ready } = useAppController({
    setShowOnboarding,
    onStreamEnd: fetchGrowthSummary,
  });

  // 4. 启动时加载已持久化的配置
  useEffect(() => {
    loadConfig();
  }, [loadConfig]);

  // 5. 事件处理器
  const handleSendMessage = useCallback(async (text: string) => {
    let sid = useSessionStore.getState().currentSessionId;
    if (!sid) {
      const s = await useSessionStore.getState().createSession();
      if (!s) return;
      sid = s.id;
    }
    resetDiagnosisFlow();
    const attitudeLevel = useConfigStore.getState().attitudeLevel;
    const studentContext = useStudentContextStore.getState().toJSON();
    useChatStore.getState().sendMessage(text, { sessionId: sid, attitudeLevel, studentContext });
  }, [resetDiagnosisFlow]);

  const handleStop = useCallback(async () => {
    let stopped = false;
    try {
      const result = await chatService.stop();
      stopped = result?.stopped ?? false;
    } catch { /* IPC 失败时静默 */ }
    if (stopped) {
      useChatStore.getState().abortStream();
    } else {
      useChatStore.getState().setLoading(false);
    }
  }, []);

  const handleOnboardingComplete = useCallback(async (_baseline: OnboardingBaseline) => {
    setShowOnboarding(false);
    const s = await createSession();
    if (s) await switchSession(s.id);
  }, [createSession, switchSession]);

  const handleOnboardingSkip = useCallback(async () => {
    setShowOnboarding(false);
    const s = await createSession();
    if (s) await switchSession(s.id);
  }, [createSession, switchSession]);

  const handleEnterWorkshopFromBridge = useCallback((challengeId: string) => {
    rightPanelService.openTraining(challengeId);
    useTrainingStore.getState().startTraining(challengeId);
  }, []);

  const handleToolClick = useCallback((toolId: string) => {
    rightPanelService.switchTo(toolId as PanelId);
  }, []);

  // 6. 稳定对象定义
  const drawerTools = useMemo(() => [
    { id: 'search', icon: Search, label: '全局搜索' },
    { id: 'works', icon: BookOpen, label: '作品' },
    { id: 'diagnosis', icon: ClipboardCheck, label: '作品诊断' },
    { id: 'training', icon: Target, label: '训练工坊' },
    { id: 'growth', icon: TrendingUp, label: '诊断对比' },
    { id: 'profile', icon: User, label: '能力画像' },

  ], []);

  const trainingWorkshopProps = useMemo(() => ({
    errorCards,
    recommendations,
    readingDecision,
    readingComplete,
    activeTraining,
    history: trainingHistory,
    submissionResult,
    evaluationResult,
    isLoading: trainingLoading,
    error: trainingError,
    lastEvaluationScore,
    lastSyndromeId,
    onStartTraining: startTraining,
    onStartReading: startReading,
    onDismissReadingComplete: dismissReadingComplete,
    onBackToChat: () => { rightPanelService.close(); backToChat(); },
    onSubmitStep: submitStep,
    onSkipTraining: skipTraining,
    onUpdateDraft: updateDraft,
    onSendToEditor: sendToEditor,
  }), [
    errorCards,
    recommendations,
    readingDecision,
    readingComplete,
    activeTraining,
    trainingHistory,
    submissionResult,
    evaluationResult,
    trainingLoading,
    trainingError,
    lastEvaluationScore,
    lastSyndromeId,
    startTraining,
    startReading,
    dismissReadingComplete,
    backToChat,
    submitStep,
    skipTraining,
    updateDraft,
    sendToEditor,
  ]);

  const panelContent = useMemo(() => ({
    search: <SearchPanel />,
    works: <ManuscriptPanel />,
    training: <TrainingWorkshop {...trainingWorkshopProps} />,
    diagnosis: <DiagnosisPanel />,
    growth: <DiagnosisComparisonView />,
    profile: <AbilityProfilePanel />,

    __settings__: <SettingsPanel />,
  }), [trainingWorkshopProps]);

  const chatViewProps = useMemo(() => ({
    messages,
    isStreaming,
    currentSessionId,
    currentDiagnosis,
    editingSyndrome,
    isSubmitting,
    lastEvaluation,
    lastOriginalText,
    lastRewrittenText,
    growthLoading,
    hasHistory,
    growthSummary,
    bridgeRecommendation,
    isConfigured: isConfigured ?? false,
    onSend: handleSendMessage,
    onStop: handleStop,
    onStartEditing: startEditing,
    onSubmitRewrite: submitRewrite,
    onCancelEditing: cancelEditing,
    onEnterWorkshopFromBridge: handleEnterWorkshopFromBridge,
    onDismissBridge: dismissBridge,
  }), [
    messages,
    isStreaming,
    currentSessionId,
    currentDiagnosis,
    editingSyndrome,
    isSubmitting,
    lastEvaluation,
    lastOriginalText,
    lastRewrittenText,
    growthLoading,
    hasHistory,
    growthSummary,
    bridgeRecommendation,
    isConfigured,
    handleSendMessage,
    handleStop,
    startEditing,
    submitRewrite,
    cancelEditing,
    handleEnterWorkshopFromBridge,
    dismissBridge,
  ]);

  return {
    ready,
    showOnboarding,
    isConfigLoading,
    isConfigured,
    drawerTools,
    panelContent,
    chatViewProps,
    handleOnboardingComplete,
    handleOnboardingSkip,
    handleToolClick,
  };
}
