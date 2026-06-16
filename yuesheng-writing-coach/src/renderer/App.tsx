import React from 'react';
import { AppShell } from './components/layout/AppShell';
import { SoloSidebar } from './components/layout/SoloSidebar';
import { RightDrawer } from './components/layout/RightDrawer';
import { AppErrorBoundary } from './components/layout/AppErrorBoundary';
import { AppConfigGate } from './components/layout/AppConfigGate';
import { ChatView } from './components/chat/ChatView';
import { useAppOrchestrator } from './hooks/useAppOrchestrator';

export function App(): React.ReactElement {
  const {
    ready, showOnboarding, isConfigLoading, isConfigured,
    drawerTools, panelContent, chatViewProps,
    handleOnboardingComplete, handleOnboardingSkip, handleToolClick,
  } = useAppOrchestrator();

  if (!ready) {
    return <div className="app-loading">正在启动...</div>;
  }

  return (
    <AppErrorBoundary>
      <AppConfigGate
        isConfigLoading={isConfigLoading}
        isConfigured={isConfigured ?? false}
        showOnboarding={showOnboarding}
        onOnboardingComplete={handleOnboardingComplete}
        onOnboardingSkip={handleOnboardingSkip}
      >
        <AppShell
          sidebar={<SoloSidebar />}
          rightPanel={<RightDrawer tools={drawerTools} onToolClick={handleToolClick} panelContent={panelContent} />}
        >
          <div style={{ position: 'relative', height: '100%' }}>
            <ChatView {...chatViewProps} />
          </div>
        </AppShell>
      </AppConfigGate>
    </AppErrorBoundary>
  );
}
