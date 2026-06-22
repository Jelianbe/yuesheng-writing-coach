/**
 * panel-bus-bridge.ts — X-01 命令到 store 的路由层
 *
 * AppShell 挂载时调用 setupPanelBus() 一次，把 panelBus 命令路由到具体 store。
 * 这样 LeftPanel / CenterHeader 等子组件只 dispatch 命令，不依赖具体 store。
 */

import { useEffect } from 'react';
import { panelBus, type PanelCommand } from './panel-bus';
import { useRightToolsStore } from '../stores/right-tools.store';
import { useUiStore } from '../stores/ui.store';
import { useSessionStore } from '../stores/session.store';

function handleCommand(cmd: PanelCommand): void {
  switch (cmd.type) {
    case 'open-tool':
      useRightToolsStore.getState().openTool(cmd.toolId);
      break;
    case 'close-tool':
      useRightToolsStore.getState().closeTool(cmd.toolId);
      break;
    case 'set-active-tool':
      useRightToolsStore.getState().setActiveTool(cmd.toolId);
      break;
    case 'open-project-tab':
      useRightToolsStore.getState().openProjectTab(cmd.projectId);
      break;
    case 'close-project-tab':
      useRightToolsStore.getState().closeProjectTab(cmd.projectId);
      break;
    case 'set-active-project-tab':
      useRightToolsStore.getState().setActiveProjectTab(cmd.projectId);
      break;
    case 'clear-project-tabs':
      useRightToolsStore.getState().clearProjectTabs();
      break;
    case 'set-left-tab':
      useUiStore.getState().setLeftTab(cmd.tabId);
      break;
    case 'switch-session':
      useSessionStore.getState().switchSession(cmd.sessionId);
      break;
  }
}

/** 在 AppShell 挂载时调用一次，挂载全局命令路由 */
export function usePanelBusBridge(): void {
  useEffect(() => {
    const unsub = panelBus.subscribe(handleCommand);
    return unsub;
  }, []);
}
