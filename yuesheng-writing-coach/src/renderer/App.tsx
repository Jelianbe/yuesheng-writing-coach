import React, { useEffect, useState, useCallback, useRef } from 'react';
import { AppShell } from './components/layout/AppShell';
import SoloSidebar from './components/layout/SoloSidebar';
import { RightDrawer } from './components/layout/RightDrawer';
import { AppErrorBoundary } from './components/layout/AppErrorBoundary';
import { AppConfigGate } from './components/layout/AppConfigGate';
import { ConfigPage } from './components/pages/ConfigPage';
import ChatView from './components/chat/ChatView';
import { TrainingWorkshop } from './components/training/TrainingWorkshop';
import DiagnosisPanel from './components/layout/DiagnosisPanel';
import TaskPanel from './components/teaching/TaskPanel';
import AbilityProfilePanel from './components/profile/AbilityProfilePanel';
import GrowthPanel from './components/growth/GrowthPanel';
import SettingsPanel from './components/settings/SettingsPanel';
import SearchPanel from './components/search/SearchPanel';
import ToolsPanel from './components/tools/ToolsPanel';
import ManuscriptPanel from './components/manuscript/ManuscriptPanel';
import { Search, ClipboardCheck, Target, TrendingUp, User, Wrench, ListChecks, BookOpen } from 'lucide-react';
import { useDiagnosisFlow } from './hooks/useDiagnosisFlow';
import { useAppIpcListener } from './hooks/useAppIpcListener';
import { useConfigStore } from './stores/config.store';
import { useDiagStore } from './stores/diag.store';
import { useChatStore } from './stores/chat.store';
import { useSessionStore } from './stores/session.store';
import { useStudentContextStore } from './stores/student-context.store';
import { useTrainingStore } from './stores/training.store';
import { useDrawerStore } from './stores/drawer.store';
import type { ApiConfig, ConnectionTestResult, OnboardingBaseline } from './shared/types';

function App(): React.ReactElement {
  // Store state
  const { apiKey, baseUrl, modelName, temperature, attitudeLevel, isConfigured, isLoading: isConfigLoading, loadConfig, setApiKey, setBaseUrl, setModelName, setTemperature } = useConfigStore();
  const { currentDiagnosis } = useDiagStore();
  const { messages, isLoading: isStreaming, sendMessage, setError } = useChatStore();
  const { currentSessionId, loadSessions, createSession, switchSession } = useSessionStore();
  const { errorCards, recommendations, activeTraining, history, submissionResult, evaluationResult, isLoading, error, bridgeRecommendation, startTraining, submitStep, skipTraining, updateDraft, dismissBridge, backToChat, sendToEditor } = useTrainingStore();
  const openDrawerPanel = useDrawerStore(s => s.openPanel);

  // Local state & hooks
  const [view, setView] = useState<'main' | 'config'>('main');
  const [showOnboarding, setShowOnboarding] = useState(false);
  const { editingSyndrome, isSubmitting, lastEvaluation, lastRewrittenText, lastOriginalText, growthLoading, growthSummary, hasHistory, startEditing, cancelEditing, submitRewrite, reset: resetDiagnosisFlow } = useDiagnosisFlow(currentSessionId);

  // Data fetching callbacks
  const fetchAbilityProfile = useCallback(async () => { if (currentSessionId && window.electronAPI) await window.electronAPI.invoke('ability:getProfile', { sessionId: currentSessionId }); }, [currentSessionId]);
  const fetchGrowthTrends = useCallback(async () => { if (!currentSessionId || !window.electronAPI) return; try { await window.electronAPI.invoke('growth:getTrends', { sessionId: currentSessionId }); } catch { /* ignore */ } }, [currentSessionId]);
  const fetchGrowthSummary = useCallback(async () => { /* used by IPC listener */ }, []);

  // IPC event listeners
  useAppIpcListener(fetchGrowthSummary, fetchAbilityProfile, fetchGrowthTrends);

  // Init effects
  useEffect(() => { loadConfig(); }, [loadConfig]);
  useEffect(() => { const init = async () => { try { await loadSessions(); const st = useSessionStore.getState(); if (st.sessions.length === 0) setShowOnboarding(true); else if (!st.currentSessionId) await switchSession(st.sessions[0].id); } catch (err) { console.error('[App] init:', err); } }; init(); }, [loadSessions, switchSession]);
  useEffect(() => { useStudentContextStore.getState().load(); }, []);

  // 会话切换同步：当 session.store.currentSessionId 变化时，清空并加载对应聊天消息
  const currentSessionIdRef = useRef(currentSessionId);
  useEffect(() => {
    if (currentSessionId === currentSessionIdRef.current) return;
    currentSessionIdRef.current = currentSessionId;
    // 清空当前消息
    const { clearMessages, setMessages, setLoading } = useChatStore.getState();
    clearMessages();
    setLoading(false);
    // 加载新会话消息
    if (currentSessionId && window.electronAPI) {
      window.electronAPI.invoke('session:getMessages', { sessionId: currentSessionId })
        .then((res: unknown) => {
          const r = res as { success: boolean; data?: Array<{ id: string; role: string; content: string; timestamp: number }> };
          if (r.success && r.data) {
            setMessages(r.data.map(m => ({ id: m.id, role: m.role as 'user' | 'assistant', content: m.content, timestamp: m.timestamp })));
          }
        })
        .catch(() => { /* 新会话无消息是正常的 */ });
    }
  }, [currentSessionId]);

  // Event handlers
  const handleSendMessage = useCallback(async (text: string) => { let sid = currentSessionId; if (!sid) { const s = await createSession(); if (!s) return; sid = s.id; } resetDiagnosisFlow(); sendMessage(text); }, [currentSessionId, createSession, sendMessage, resetDiagnosisFlow]);
  const handleStop = useCallback(() => { try { void window.electronAPI?.invoke('chat:stop', {}); } catch { /* ignore */ } setError('已停止生成'); }, [setError]);
  const handleSaveConfig = useCallback(async (cfg: ApiConfig) => { await setApiKey(cfg.apiKey); await setBaseUrl(cfg.baseUrl); await setModelName(cfg.modelName); await setTemperature(cfg.temperature); }, [setApiKey, setBaseUrl, setModelName, setTemperature]);
  const handleTestConnection = useCallback(async (ak: string, bu: string): Promise<ConnectionTestResult> => { try { return await window.electronAPI?.invoke('config:testConnection', { apiKey: ak, baseUrl: bu }) as ConnectionTestResult; } catch (err) { return { success: false, error: err instanceof Error ? err.message : '连接异常' }; } }, []);
  const handleOnboardingComplete = useCallback(async (baseline: OnboardingBaseline) => { setShowOnboarding(false); const s = await createSession(); if (s) { await switchSession(s.id); try { await window.electronAPI?.invoke('profile:updateBaseline', baseline); } catch { localStorage.setItem('onboarding_baseline', JSON.stringify(baseline)); } } }, [createSession, switchSession]);
  const handleOnboardingSkip = useCallback(async () => { setShowOnboarding(false); const s = await createSession(); if (s) await switchSession(s.id); }, [createSession, switchSession]);

  // Computed
  const drawerTools = [
    { id: 'search', icon: Search, label: '全局搜索' },
    { id: 'works', icon: BookOpen, label: '作品' },
    { id: 'diagnosis', icon: ClipboardCheck, label: '作品诊断' },
    { id: 'training', icon: Target, label: '训练工坊' },
    { id: 'tasks', icon: ListChecks, label: '教学任务' },
    { id: 'growth', icon: TrendingUp, label: '成长记录' },
    { id: 'profile', icon: User, label: '能力画像' },
    { id: 'tools', icon: Wrench, label: '创作工具' },
  ];

  // Build config obj
  const fullConfig = { apiKey: apiKey ?? '', baseUrl: baseUrl ?? '', modelName: modelName ?? '', temperature: temperature ?? 0.7, attitudeLevel: attitudeLevel ?? 'standard', maxTokens: 8192 };

  return (
    <AppErrorBoundary>
      <AppConfigGate isConfigLoading={isConfigLoading} isConfigured={isConfigured ?? false} showOnboarding={showOnboarding} config={fullConfig} onSaveConfig={handleSaveConfig} onTestConnection={handleTestConnection} onOnboardingComplete={handleOnboardingComplete} onOnboardingSkip={handleOnboardingSkip}>
        {view === 'config' ? (
          <div style={{ height: '100vh', width: '100vw', backgroundColor: 'var(--color-bg)', display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
            <ConfigPage config={fullConfig} onSave={handleSaveConfig} onBack={() => setView('main')} onTestConnection={handleTestConnection} />
          </div>
        ) : (
          <AppShell sidebar={<SoloSidebar />} rightPanel={<RightDrawer tools={drawerTools} onToolClick={t => { useDrawerStore.getState().togglePanel(t as any); }} panelContent={{ search: <SearchPanel />, works: <ManuscriptPanel />, training: <TrainingWorkshop errorCards={errorCards} recommendations={recommendations} activeTraining={activeTraining} history={history} submissionResult={submissionResult} evaluationResult={evaluationResult} isLoading={isLoading} error={error} onStartTraining={startTraining} onBackToChat={() => { useDrawerStore.getState().closePanel(); backToChat(); }} onSubmitStep={submitStep} onSkipTraining={skipTraining} onUpdateDraft={updateDraft} onSendToEditor={sendToEditor} />, diagnosis: <DiagnosisPanel />, tasks: <TaskPanel />, growth: <GrowthPanel />, profile: <AbilityProfilePanel />, tools: <ToolsPanel />, __settings__: <SettingsPanel /> }} />}>
              <ChatView messages={messages} isStreaming={isStreaming} currentSessionId={currentSessionId} currentDiagnosis={currentDiagnosis} editingSyndrome={editingSyndrome} isSubmitting={isSubmitting} lastEvaluation={lastEvaluation} lastOriginalText={lastOriginalText} lastRewrittenText={lastRewrittenText} growthLoading={growthLoading} hasHistory={hasHistory} growthSummary={growthSummary} bridgeRecommendation={bridgeRecommendation} onSend={handleSendMessage} onStop={handleStop} onStartEditing={(id, ev, n, s) => startEditing(id, ev, n, s)} onSubmitRewrite={submitRewrite} onCancelEditing={cancelEditing} onEnterWorkshopFromBridge={cid => { void useTrainingStore.getState().startTraining(cid); openDrawerPanel('training'); }} onDismissBridge={dismissBridge} />
          </AppShell>
        )}
      </AppConfigGate>
    </AppErrorBoundary>
  );
}

export default App;
