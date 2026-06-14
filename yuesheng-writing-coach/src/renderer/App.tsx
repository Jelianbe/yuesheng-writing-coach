import React, { useState, useCallback, useEffect } from 'react';
import { AppShell } from './components/layout/AppShell';
import { SoloSidebar } from './components/layout/SoloSidebar';
import { RightDrawer } from './components/layout/RightDrawer';
import { AppErrorBoundary } from './components/layout/AppErrorBoundary';
import { AppConfigGate } from './components/layout/AppConfigGate';
import { ChatView } from './components/chat/ChatView';
import { TrainingWorkshop } from './components/training/TrainingWorkshop';
import { DiagnosisPanel } from './components/layout/DiagnosisPanel';
import { AbilityProfilePanel } from './components/profile/AbilityProfilePanel';
import { GrowthPanel } from './components/growth/GrowthPanel';
import { SettingsPanel } from './components/settings/SettingsPanel';
import { SearchPanel } from './components/search/SearchPanel';
import { ToolsPanel } from './components/tools/ToolsPanel';
import { ManuscriptPanel } from './components/manuscript/ManuscriptPanel';
import { Search, ClipboardCheck, Target, TrendingUp, User, Wrench, BookOpen } from 'lucide-react';
import { useAppController } from './services/useAppController';
import { useDiagnosisFlow } from './hooks/useDiagnosisFlow';
import { useConfigStore } from './stores/config.store';
import { useChatStore } from './stores/chat.store';
import { useDiagStore } from './stores/diag.store';
import { useSessionStore } from './stores/session.store';
import { useStudentContextStore } from './stores/student-context.store';
import { useTrainingStore } from './stores/training.store';
import { rightPanelService } from './services/right-panel.service';
import type { PanelId } from './services/right-panel.service';
import { chatService } from './services/chat.service';
import type { OnboardingBaseline } from './shared/types';

export function App(): React.ReactElement {
  const [showOnboarding, setShowOnboarding] = useState(false);

  // 唯一跨模块编排钩子（替代 useAppIpcListener + 6 store 的跨模块 getState）
  const { fetchGrowthSummary, startEditing, cancelEditing, submitRewrite, editingSyndrome, isSubmitting, lastEvaluation, lastRewrittenText, lastOriginalText, growthLoading, growthSummary, hasHistory, reset: resetDiagnosisFlow } = useDiagnosisFlow(useSessionStore.getState().currentSessionId);
  const { ready } = useAppController({
    setShowOnboarding,
    onStreamEnd: fetchGrowthSummary,
  });

  // Config store — loadConfig 用于启动时加载已持久化的配置
  const { isLoading: isConfigLoading, isConfigured, loadConfig } = useConfigStore();
  const { messages, isLoading: isStreaming } = useChatStore();
  const { currentDiagnosis } = useDiagStore();
  const { currentSessionId, createSession, switchSession } = useSessionStore();
  const { errorCards, recommendations, readingDecision, readingComplete, activeTraining, history, submissionResult, evaluationResult, isLoading, error, bridgeRecommendation, startTraining, startReading, submitStep, skipTraining, updateDraft, dismissBridge, backToChat, sendToEditor, dismissReadingComplete } = useTrainingStore();

  // Event handlers

  // 启动时从主进程加载已持久化的配置
  useEffect(() => {
    loadConfig();
  }, [loadConfig]);

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

  const drawerTools = [
    { id: 'search', icon: Search, label: '全局搜索' },
    { id: 'works', icon: BookOpen, label: '作品' },
    { id: 'diagnosis', icon: ClipboardCheck, label: '作品诊断' },
    { id: 'training', icon: Target, label: '训练工坊' },
    { id: 'growth', icon: TrendingUp, label: '成长记录' },
    { id: 'profile', icon: User, label: '能力画像' },
    { id: 'tools', icon: Wrench, label: '创作工具' },
  ];

  if (!ready) {
    return <div className="app-loading">正在启动...</div>;
  }

  return (
    <AppErrorBoundary>
      <AppConfigGate isConfigLoading={isConfigLoading} isConfigured={isConfigured ?? false} showOnboarding={showOnboarding} onOnboardingComplete={handleOnboardingComplete} onOnboardingSkip={handleOnboardingSkip}>
        <AppShell sidebar={<SoloSidebar />} rightPanel={<RightDrawer tools={drawerTools} onToolClick={t => { rightPanelService.switchTo(t as PanelId); }} panelContent={{ search: <SearchPanel />, works: <ManuscriptPanel />, training: <TrainingWorkshop errorCards={errorCards} recommendations={recommendations} readingDecision={readingDecision} readingComplete={readingComplete} activeTraining={activeTraining} history={history} submissionResult={submissionResult} evaluationResult={evaluationResult} isLoading={isLoading} error={error} onStartTraining={startTraining} onStartReading={startReading} onDismissReadingComplete={dismissReadingComplete} onBackToChat={() => { rightPanelService.close(); backToChat(); }} onSubmitStep={submitStep} onSkipTraining={skipTraining} onUpdateDraft={updateDraft} onSendToEditor={sendToEditor} />, diagnosis: <DiagnosisPanel />, growth: <GrowthPanel />, profile: <AbilityProfilePanel />, tools: <ToolsPanel />, __settings__: <SettingsPanel /> }} />}>
          <div style={{ position: 'relative', height: '100%' }}>
            <ChatView messages={messages} isStreaming={isStreaming} currentSessionId={currentSessionId} currentDiagnosis={currentDiagnosis} editingSyndrome={editingSyndrome} isSubmitting={isSubmitting} lastEvaluation={lastEvaluation} lastOriginalText={lastOriginalText} lastRewrittenText={lastRewrittenText} growthLoading={growthLoading} hasHistory={hasHistory} growthSummary={growthSummary} bridgeRecommendation={bridgeRecommendation} isConfigured={isConfigured ?? false} onSend={handleSendMessage} onStop={handleStop} onStartEditing={(id, ev, n, s) => startEditing(id, ev, n, s)} onSubmitRewrite={submitRewrite} onCancelEditing={cancelEditing} onEnterWorkshopFromBridge={cid => { rightPanelService.openTraining(cid); useTrainingStore.getState().startTraining(cid); }} onDismissBridge={dismissBridge} />
          </div>
        </AppShell>
      </AppConfigGate>
    </AppErrorBoundary>
  );
}
