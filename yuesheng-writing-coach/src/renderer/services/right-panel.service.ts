/**
 * 右侧面板管理服务
 *
 * 替代 right-panel.actions.ts，提供类型化的面板操作。
 * 所有跨 Store 操作（drawer.store + panel-session.store + chapter.store）
 * 统一通过此服务入口调用，不再直接协调三个 Store。
 */

import { useDrawerStore, type DrawerPanelId } from '../stores/drawer.store';
import { usePanelSessionStore, type PanelSessionType, type PanelSessionData } from '../stores/panel-session.store';
import { useChapterStore } from '../stores/chapter.store';
import {
  TOOL_TO_SESSION_TYPE,
  SESSION_TYPE_TO_TOOL_ID,
  SESSION_DEFAULT_TITLE,
} from '../components/layout/drawer-constants';

export type PanelId =
  | 'search'
  | 'works'
  | 'diagnosis'
  | 'training'
  | 'tasks'
  | 'growth'
  | 'profile'
  | 'tools'
  | '__settings__';

export const rightPanelService = {
  /**
   * 打开工具面板（自动创建/激活会话 + 展开抽屉）
   * @param toolId 面板 ID
   * @param sessionData 可选的会话关联数据
   * @returns 会话 ID
   */
  openTool(toolId: string, sessionData?: PanelSessionData): string {
    const sessionType = (TOOL_TO_SESSION_TYPE[toolId] ?? 'edit') as PanelSessionType;
    const title = SESSION_DEFAULT_TITLE[sessionType] ?? toolId;
    const iconName = '';
    useDrawerStore.getState().openPanel(toolId as DrawerPanelId);
    return usePanelSessionStore.getState().upsertSession(sessionType, title, iconName, sessionData);
  },

  /**
   * 打开章节编辑器（自动打开 works 面板 + 创建编辑会话 + 打开标签页）
   */
  openEditor(chapterId: string, manuscriptTitle: string): void {
    useChapterStore.getState().openTab(chapterId, manuscriptTitle);
    this.openTool('works', { type: 'edit', chapterId } as PanelSessionData);
  },

  /** 打开训练面板（含症候上下文） */
  openTraining(challengeId: string, syndromeId?: string): string {
    return this.openTool('training', { type: 'training', challengeId, syndromeId } as PanelSessionData);
  },

  /** 关闭右侧栏（仅收起面板，不清除会话） */
  close(): void {
    useDrawerStore.getState().closePanel();
  },

  /** 切换面板展开/收起 */
  togglePanel(toolId: string): void {
    useDrawerStore.getState().togglePanel(toolId as DrawerPanelId);
  },

  /** 切换到指定面板（别名，与 togglePanel 行为一致） */
  switchTo(panelId: PanelId | null): void {
    if (panelId) {
      useDrawerStore.getState().openPanel(panelId as DrawerPanelId);
    } else {
      useDrawerStore.getState().closePanel();
    }
  },

  /** 切换会话标签（自动同步 drawer.activePanel） */
  switchSession(sessionId: string): void {
    usePanelSessionStore.getState().switchSession(sessionId);
    const session = usePanelSessionStore.getState().sessions.find(s => s.id === sessionId);
    if (session) {
      const toolId = SESSION_TYPE_TO_TOOL_ID[session.type];
      if (toolId) {
        useDrawerStore.getState().openPanel(toolId as DrawerPanelId);
      }
    }
  },

  /**
   * 移除指定会话（自动联动：若最后一个会话被移除 → 收起抽屉）
   */
  removeSession(sessionId: string): void {
    const { activeSessionId } = usePanelSessionStore.getState();
    const wasActive = sessionId === activeSessionId;

    usePanelSessionStore.getState().removeSession(sessionId);

    const remaining = usePanelSessionStore.getState().sessions;
    if (remaining.length === 0) {
      useDrawerStore.getState().closePanel();
    } else if (wasActive) {
      // 被移除的是激活会话 → 自动切到最后一个
      const last = remaining[remaining.length - 1];
      const toolId = SESSION_TYPE_TO_TOOL_ID[last.type];
      if (toolId) useDrawerStore.getState().openPanel(toolId as DrawerPanelId);
    }
  },
};
