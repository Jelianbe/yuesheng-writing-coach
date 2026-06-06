import React, { useEffect, useState, useCallback, useMemo } from 'react';
import { AppShell } from './components/layout/AppShell';
import { AppHeader } from './components/layout/AppHeader';
import { AppSidebar } from './components/layout/AppSidebar';
import type { SessionItem } from './components/layout/AppSidebar';
import { RightPanel } from './components/panels/RightPanel';
import { ConfigPage } from './components/pages/ConfigPage';
import ChatView from './components/chat/ChatView';
import { TrainingWorkshop } from './components/training/TrainingWorkshop';
import type { AbilityProfile, TeachingState, ApiConfig, ConnectionTestResult } from './shared/types';
import { IPC_CHANNELS } from '../shared/constants';
import {
  PhaseNameMap as PanelPhaseNameMap,
  SubphaseNameMap as PanelSubphaseNameMap,
  ActionNameMap as PanelActionNameMap,
} from './shared/display-names';
import {
  buildRightPanelSteps,
  buildRightPanelNextStep,
  buildRightPanelDiagnoses,
  buildGrowthItems,
  getTimeAgo,
  mapHeaderAttitude,
  getAttitudeMap,
  type GrowthTrendItem,
} from './utils/app-helpers';

// === Store imports ===
import { useDiagnosisFlow } from './hooks/useDiagnosisFlow';
import { useConfigStore } from './stores/config.store';
import { useDiagStore } from './stores/diag.store';
import { useChatStore } from './stores/chat.store';
import { useSessionStore } from './stores/session.store';
import { useTeachingStateStore } from './stores/teaching-state.store';
import { useStudentContextStore } from './stores/student-context.store';
import { useTrainingStore, selectCenterMode } from './stores/training.store';

const MAX_TRENDS_DISPLAY = 4;

function App(): React.ReactElement {
  // === Store 状态 ===
  const {
    apiKey, baseUrl, modelName, temperature, attitudeLevel,
    isConfigured, isLoading: isConfigLoading, loadConfig,
    setAttitudeLevel: storeSetAttitudeLevel, testConnection,
    setApiKey, setBaseUrl, setModelName, setTemperature,
  } = useConfigStore();

  const { currentDiagnosis } = useDiagStore();
  const chatStore = useChatStore();
  const { messages, isLoading: isStreaming, sendMessage, setError } = chatStore;
  const { sessions, currentSessionId, loadSessions, createSession, deleteSession, switchSession } = useSessionStore();
  const { currentState: teachingState } = useTeachingStateStore();
  const { centerMode, enterWorkshop, backToChat } = useTrainingStore();
  const {
    errorCards, recommendations, activeTraining, history,
    submissionResult, isLoading, error,
    startTraining, submitStep, skipTraining, updateDraft,
  } = useTrainingStore();

  // === 本地状态 ===
  type SidebarPage = 'chat' | 'tasks' | 'training';
  const [view, setView] = useState<'main' | 'config'>('main');
  const [sidebarPage, setSidebarPage] = useState<SidebarPage>('chat');
  const [rightPanelCollapsed, setRightPanelCollapsed] = useState(true);
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);
  const [abilityProfile, setAbilityProfile] = useState<AbilityProfile | null>(null);

  const fetchAbilityProfile = useCallback(async () => {
    if (!currentSessionId || !window.electronAPI) return;
    const profile = await window.electronAPI.invoke('ability:getProfile', { sessionId: currentSessionId }) as AbilityProfile;
    setAbilityProfile(profile);
  }, [currentSessionId]);

  // === 成长趋势 ===
  const [growthTrends, setGrowthTrends] = useState<GrowthTrendItem[]>([]);
  const [growthTrendsLoading, setGrowthTrendsLoading] = useState(false);

  const fetchGrowthTrends = useCallback(async () => {
    if (!currentSessionId) return;
    setGrowthTrendsLoading(true);
    try {
      if (!window.electronAPI) return;
      const result = await window.electronAPI.invoke('growth:getTrends', { sessionId: currentSessionId }) as { trends: GrowthTrendItem[] } | null;
      if (result?.trends) setGrowthTrends(result.trends);
    } finally {
      setGrowthTrendsLoading(false);
    }
  }, [currentSessionId]);

  // === 诊断流程 hook ===
  const {
    editingSyndrome, isSubmitting, lastEvaluation,
    lastRewrittenText, lastOriginalText, growthLoading,
    growthSummary, hasHistory, startEditing, cancelEditing,
    submitRewrite, fetchGrowthSummary, reset: resetDiagnosisFlow,
  } = useDiagnosisFlow(currentSessionId);

  // === 副作用：初始化 ===
  useEffect(() => { loadConfig(); }, [loadConfig]);

  useEffect(() => {
    const init = async () => {
      await loadSessions();
      const state = useSessionStore.getState();
      if (state.sessions.length > 0 && !state.currentSessionId) {
        await switchSession(state.sessions[0].id);
      }
    };
    init();
  }, [loadSessions, switchSession]);

  useEffect(() => { useStudentContextStore.getState().load(); }, []);

  // === IPC 事件监听 ===
  useEffect(() => {
    if (!window.electronAPI) return;

    const cleanups = [
      window.electronAPI.on(IPC_CHANNELS.DIAGNOSIS_UPDATE, (_data: unknown) => {
        const entry = _data as import('./shared/types').DiagnosisEntry;
        const { setCurrentDiagnosis, addToHistory } = useDiagStore.getState();
        setCurrentDiagnosis(entry);
        addToHistory(entry.sessionId, entry);
        if (entry.syndromes.length > 0) {
          useStudentContextStore.getState().updateFromDiagnosis(entry.syndromes);
        }
      }),
      window.electronAPI.on(IPC_CHANNELS.CHAT_STREAM_DATA, (_data: unknown) => {
        const { chunk } = _data as { sessionId: string; chunk: string };
        useChatStore.getState().appendToLastAssistant(chunk);
      }),
      window.electronAPI.on(IPC_CHANNELS.CHAT_STREAM_END, (_data: unknown) => {
        const result = _data as { sessionId: string; fullResponse: string; messageId: string; error?: string };
        const { setLoading, setError: setChatError } = useChatStore.getState();
        if (result.error) setChatError(result.error);
        setLoading(false);
        if (result.fullResponse && result.fullResponse.length > 0) {
          useStudentContextStore.getState().updateFromInteraction('partial');
        }
        fetchGrowthSummary();
        fetchAbilityProfile();
        fetchGrowthTrends();
      }),
      window.electronAPI.on(IPC_CHANNELS.TEACHING_STATE_UPDATED, (_data: unknown) => {
        const teaching = _data as TeachingState & { phaseName: string; subphaseName: string; phaseProgress: number };
        const { setCurrentState } = useTeachingStateStore.getState();
        const { phaseName: _pn, subphaseName: _sn, phaseProgress: _pp, ...rest } = teaching;
        setCurrentState(rest as unknown as TeachingState);
      }),
    ];

    return () => { cleanups.forEach((fn) => fn()); };
  }, [fetchGrowthSummary, fetchAbilityProfile, fetchGrowthTrends]);

  // === 事件处理 ===
  const handleSendMessage = useCallback(async (text: string) => {
    let sessionId = currentSessionId;
    if (!sessionId) {
      const session = await createSession();
      if (!session) return;
      sessionId = session.id;
    }
    resetDiagnosisFlow();
    sendMessage(text);
  }, [currentSessionId, createSession, sendMessage, resetDiagnosisFlow]);

  const handleStop = useCallback(() => {
    try { void window.electronAPI?.invoke('chat:stop', {}); } catch { /* ignore */ }
    setError('已停止生成');
  }, [setError]);

  const handleAttitudeChange = useCallback(async (level: 'gentle' | 'direct' | 'sharp') => {
    await storeSetAttitudeLevel(getAttitudeMap()[level] ?? 'yuesheng');
  }, [storeSetAttitudeLevel]);

  const handleNewSession = useCallback(async () => {
    const session = await createSession();
    if (session) {
      await switchSession(session.id);
      useChatStore.getState().clearMessages();
      useDiagStore.getState().setCurrentDiagnosis(null);
      setAbilityProfile(null);
      setGrowthTrends([]);
    }
  }, [createSession, switchSession]);

  const handleDeleteSession = useCallback(async (sessionId: string) => {
    await deleteSession(sessionId);
  }, [deleteSession]);

  const handleSessionSelect = useCallback(async (sessionId: string) => {
    await switchSession(sessionId);
    const chatMessages = useSessionStore.getState().currentMessages
      .filter((m) => m.role === 'user' || m.role === 'assistant')
      .map((m) => ({ id: m.id, role: m.role as 'user' | 'assistant', content: m.content, timestamp: m.timestamp }));
    useChatStore.getState().setMessages(chatMessages);
    useDiagStore.getState().setCurrentDiagnosis(null);
    resetDiagnosisFlow();
    setAbilityProfile(null);
    setGrowthTrends([]);
    fetchAbilityProfile();
    fetchGrowthTrends();
  }, [switchSession, resetDiagnosisFlow, fetchAbilityProfile, fetchGrowthTrends]);

  const handleSaveConfig = useCallback(async (config: ApiConfig) => {
    await setApiKey(config.apiKey);
    await setBaseUrl(config.baseUrl);
    await setModelName(config.modelName);
    await setTemperature(config.temperature);
  }, [setApiKey, setBaseUrl, setModelName, setTemperature]);

  const handleTestConnection = useCallback(
    async (apiKeyStr: string, baseUrlStr: string): Promise<ConnectionTestResult> => {
      try {
        return await window.electronAPI?.invoke(IPC_CHANNELS.CONFIG_TEST_CONNECTION, { apiKey: apiKeyStr, baseUrl: baseUrlStr }) as ConnectionTestResult;
      } catch (err) {
        return { success: false, error: err instanceof Error ? err.message : '连接异常' };
      }
    }, []);

  // === 计算属性 ===
  const sessionItems: SessionItem[] = useMemo(
    () => sessions.map((s) => ({ id: s.id, title: s.title, tags: [], timeAgo: getTimeAgo(s.updatedAt) })),
    [sessions, getTimeAgo],
  );

  const growthItems = useMemo(
    () => buildGrowthItems(growthTrends, MAX_TRENDS_DISPLAY),
    [growthTrends],
  );

  const headerAttitude = mapHeaderAttitude(attitudeLevel);

  // === 加载中 ===
  if (isConfigLoading) {
    return (
      <div className="h-screen w-screen bg-[var(--color-bg)] flex items-center justify-center">
        <div className="text-center">
          <div className="w-12 h-12 rounded-[var(--radius-lg)] bg-surface-secondary flex items-center justify-center mx-auto mb-4 animate-pulse-custom">
            <svg className="w-6 h-6 text-accent-primary animate-spin" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <path d="M21 12a9 9 0 11-6.219-8.56" />
            </svg>
          </div>
          <p className="text-sm text-text-secondary">加载中...</p>
        </div>
      </div>
    );
  }

  // === 配置页 ===
  // === 配置页 ===
  if (view === 'config') {
    return (
      <div className="h-screen w-screen bg-[var(--color-bg)] flex flex-col">
        <ConfigPage
          config={{ apiKey, baseUrl, modelName, temperature, attitudeLevel, maxTokens: 8192 }}
          onSave={handleSaveConfig}
          onBack={() => setView('main')}
          onTestConnection={handleTestConnection}
        />
      </div>
    );
  }

  if (!isConfigured) {
    return (
      <div className="h-screen w-screen bg-[var(--color-bg)] flex items-center justify-center">
        <div className="w-full max-w-lg">
          <ConfigPage
            config={{ apiKey, baseUrl, modelName, temperature, attitudeLevel, maxTokens: 8192 }}
            onSave={handleSaveConfig}
            onBack={() => {}}
            onTestConnection={handleTestConnection}
          />
        </div>
      </div>
    );
  }

  // === 主应用 ===
  return (
    <AppShell
      header={
        <AppHeader
          title={currentSessionId ? sessions.find((s) => s.id === currentSessionId)?.title : undefined}
          currentModel={modelName}
          attitude={headerAttitude}
          onAttitudeChange={handleAttitudeChange}
          onOpenSettings={() => setView('config')}
        />
      }
      sidebar={
        <AppSidebar
          sessions={sessionItems}
          activeSessionId={currentSessionId ?? ''}
          onSelectSession={handleSessionSelect}
          onNewSession={handleNewSession}
          onEnterWorkshop={enterWorkshop}
          collapsed={sidebarCollapsed}
          onToggleCollapse={() => setSidebarCollapsed(!sidebarCollapsed)}
        />
      }
      rightPanel={
        <RightPanel
          collapsed={rightPanelCollapsed}
          onToggleCollapse={() => setRightPanelCollapsed(!rightPanelCollapsed)}
          currentPhase={PanelPhaseNameMap[teachingState?.currentPhase ?? ''] || teachingState?.currentPhase || ''}
          currentSubphase={PanelSubphaseNameMap[teachingState?.currentSubphase ?? ''] || teachingState?.currentSubphase || ''}
          steps={buildRightPanelSteps(teachingState, PanelSubphaseNameMap)}
          nextStep={buildRightPanelNextStep(teachingState, PanelActionNameMap)}
          diagnoses={buildRightPanelDiagnoses(currentDiagnosis)}
          growthItems={growthItems}
        />
      }
    >
      {centerMode === 'chat' ? (
        <ChatView
          messages={messages}
          isStreaming={isStreaming}
          currentSessionId={currentSessionId}
          currentDiagnosis={currentDiagnosis}
          editingSyndrome={editingSyndrome}
          isSubmitting={isSubmitting}
          lastEvaluation={lastEvaluation}
          lastOriginalText={lastOriginalText}
          lastRewrittenText={lastRewrittenText}
          growthLoading={growthLoading}
          hasHistory={hasHistory}
          growthSummary={growthSummary}
          onSend={handleSendMessage}
          onStop={handleStop}
          onStartEditing={(id, ev, n, s) => startEditing(id, ev, n, s)}
          onSubmitRewrite={submitRewrite}
          onCancelEditing={cancelEditing}
        />
      ) : (
        <TrainingWorkshop
          errorCards={errorCards}
          recommendations={recommendations}
          activeTraining={activeTraining}
          history={history}
          submissionResult={submissionResult}
          isLoading={isLoading}
          error={error}
          onStartTraining={startTraining}
          onBackToChat={backToChat}
          onSubmitStep={submitStep}
          onSkipTraining={skipTraining}
          onUpdateDraft={updateDraft}
        />
      )}
    </AppShell>
  );
}

export default App;
