/**
 * Phase F 占位 App —— 仅保留 store 调用与 handleSendMessage（C-5 mastery 注入）。
 * 真实 UI 将在 F-1~F-5 中按 spec §2.1 三栏布局重建。
 *
 * 旧版 import 列表备份在 __PHASE_F_LEGACY_IMPORTS__ 字符串中,供后续恢复参考:
 *   { AppShell as LegacyAppShell, SoloSidebar, RightDrawer, AppErrorBoundary, AppConfigGate,
 *     ChatView, TrainingWorkshop, ProgressSummary, DiagnosisPanel, AbilityProfilePanel,
 *     DiagnosisComparisonView, SettingsPanel, SearchPanel, ToolsPanel, ManuscriptPanel,
 *     Search, ClipboardCheck, Target, TrendingUp, User, Wrench, BookOpen, BarChart3,
 *     useAppController, useDiagnosisFlow, useConfigStore, useChatStore, useDiagStore,
 *     useSessionStore, useStudentContextStore, useTeachingStateStore, useTrainingStore,
 *     useRightPanelStore, type RightPanelToolId as PanelId, chatService, OnboardingBaseline }
 */
import React, { useEffect, useCallback, useState } from 'react';
import { AppShell } from './components/AppShell';
import { useAppController } from './services/useAppController';
import { useConfigStore } from './stores/config.store';
import { useChatStore } from './stores/chat.store';
import { useSessionStore } from './stores/session.store';
import { useStudentContextStore } from './stores/student-context.store';
import { useTeachingStateStore } from './stores/teaching-state.store';
import type { TeachingState } from './shared/types';

const TOOL_LABELS: Record<string, string> = {
  readChapter: '正在读取章节内容…',
  writeChapter: '正在写入章节内容…',
};

export function App(): React.ReactElement {
  const [showOnboarding, setShowOnboarding] = useState(false);
  const [executingTool, setExecutingTool] = useState<{ name: string } | null>(null);
  const { ready } = useAppController({ setShowOnboarding });
  const { loadConfig } = useConfigStore();

  useEffect(() => {
    loadConfig();
  }, [loadConfig]);

  // I-04: 订阅后端事件推送
  useEffect(() => {
    const cleanups: (() => void)[] = [];

    // teachingState:updated → 更新 store
    if (window.electronAPI?.on) {
      const unsubState = window.electronAPI.on('teachingState:updated', (data: unknown) => {
        useTeachingStateStore.getState().setCurrentState(data as TeachingState);
      });
      cleanups.push(unsubState);

      // teachingState:mastery → 更新精通症候
      const unsubMastery = window.electronAPI.on('teachingState:mastery', (data: unknown) => {
        const evt = data as { syndromeId?: string };
        if (evt?.syndromeId) {
          const store = useTeachingStateStore.getState();
          const updated = [...store.masteredSyndromeIds, evt.syndromeId];
          store.setMasteredSyndromeIds(updated);
        }
      });
      cleanups.push(unsubMastery);

      // chat:tool:executing → AI 工具调用状态
      const unsubTool = window.electronAPI.on('chat:tool:executing', (data: unknown) => {
        const evt = data as { toolName: string; status?: string };
        if (evt.status === 'end') {
          setExecutingTool(null);
        } else {
          setExecutingTool({ name: evt.toolName });
        }
      });
      cleanups.push(unsubTool);

      // chat:stream:data → 追加流式响应片段
      const unsubStream = window.electronAPI.on('chat:stream:data', (data: unknown) => {
        const chunk = data as { content?: string };
        if (chunk?.content) {
          useChatStore.getState().appendToLastAssistant(chunk.content);
        }
      });
      cleanups.push(unsubStream);

      // chat:stream:end → 完成最后一条消息
      const unsubStreamEnd = window.electronAPI.on('chat:stream:end', (data: unknown) => {
        const end = data as { finalContent?: string; error?: string };
        if (end?.finalContent) {
          useChatStore.getState().finalizeLastMessage();
        } else if (end?.error) {
          useChatStore.getState().setError(end.error);
        }
      });
      cleanups.push(unsubStreamEnd);
    }

    return () => { cleanups.forEach(fn => fn()); };
  }, []);

  // 保留 C-5 mastery 注入:F-2 重建 ChatView 时,本段代码移植到 handleSendMessage
  const handleSendMessage = useCallback(async (text: string) => {
    let sid = useSessionStore.getState().currentSessionId;
    if (!sid) {
      const s = await useSessionStore.getState().createSession();
      if (!s) return;
      sid = s.id;
    }
    const attitudeLevel = useConfigStore.getState().attitudeLevel;
    const studentContext = useStudentContextStore.getState().toJSON();
    // RWR-P1-11 / C-5 精通信息注入 Prompt(R-021: 只传 ID 不传 description)
    const masteredIds = useTeachingStateStore.getState().masteredSyndromeIds;
    const masterySuffix = masteredIds.length > 0
      ? `\n\n[已精通技法] ${masteredIds.join(', ')}`
      : '';
    useChatStore.getState().sendMessage(text, { sessionId: sid, attitudeLevel, studentContext: studentContext + masterySuffix });
  }, []);

  if (!ready) {
    return <div className="app-loading">正在启动...</div>;
  }

  // showOnboarding / handleSendMessage 保留供 C-5 迁移使用
  void showOnboarding;
  void handleSendMessage;

  return (
    <>
      <AppShell />
      {executingTool && (
        <div style={{
          position: 'fixed', bottom: 12, left: '50%', transform: 'translateX(-50%)',
          background: '#2C2A28', color: '#E8DCC8', padding: '6px 16px',
          borderRadius: 20, fontSize: 12, zIndex: 9999,
          boxShadow: '0 2px 8px rgba(0,0,0,0.3)',
          display: 'flex', alignItems: 'center', gap: 8,
        }}>
          <span className="tool-executing-dot" />
          {TOOL_LABELS[executingTool.name] || `正在调用工具: ${executingTool.name}…`}
        </div>
      )}
    </>
  );
}
