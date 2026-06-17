/**
 * right-panel.store.ts — 右侧栏多 Store 协作统一入口（X-01 协议）
 *
 * 职责：
 * - 统一协调 drawer.store / panel-session.store / chapter.store 的跨 Store 操作
 * - 替代旧版 right-panel.service.ts（命令式 service 模式 → zustand action 模式）
 * - 组件层不再手动协调三个 Store，所有多 Store 操作走 useRightPanelStore action
 *
 * 状态设计：
 * - 无持久化状态（所有状态从 drawer / panel-session / chapter 三个 store 派生，X-01 SSOT）
 * - 仅包含 8 个 action（与原 rightPanelService 一一对应）
 *
 * 协作协议（X-01）：
 * 1. drawer.store → SSOT：面板开闭状态（activePanel / collapsed）
 * 2. panel-session.store → SSOT：右侧栏打开内容（sessions / activeSessionId）
 * 3. chapter.store → SSOT：编辑器标签（openFiles / openTabMeta）
 *
 * 正确用法：
 *   useRightPanelStore.getState().openTool('training');
 *   useRightPanelStore.getState().openEditor(chapterId, title);
 *   useRightPanelStore.getState().removeSession(sessionId);
 *
 * 错误用法（违反协议 — 手工协调多 Store）：
 *   useDrawerStore.getState().openPanel('works');
 *   usePanelSessionStore.getState().upsertSession('edit', '编辑', '');
 */

import { create } from 'zustand';
import { useDrawerStore, type DrawerPanelId } from './drawer.store';
import {
  usePanelSessionStore,
  type PanelSessionType,
  type PanelSessionData,
} from './panel-session.store';
import { useChapterStore } from './chapter.store';
import {
  TOOL_TO_SESSION_TYPE,
  SESSION_TYPE_TO_TOOL_ID,
  SESSION_DEFAULT_TITLE,
} from '../components/layout/drawer-constants';

/** 与原 rightPanelService.PanelId 一致（包含 settings 与 tools） */
export type RightPanelToolId =
  | 'search'
  | 'works'
  | 'diagnosis'
  | 'training'
  | 'growth'
  | 'profile'
  | 'tools'
  | '__settings__';

interface RightPanelActions {
  /**
   * 打开工具面板（自动创建/激活会话 + 展开抽屉）
   * @param toolId 面板 ID
   * @param sessionData 可选的会话关联数据
   * @returns 会话 ID
   */
  openTool: (toolId: string, sessionData?: PanelSessionData) => string;
  /**
   * 打开章节编辑器（自动打开 works 面板 + 创建编辑会话 + 打开标签页）
   */
  openEditor: (chapterId: string, manuscriptTitle: string) => void;
  /** 打开训练面板（含症候上下文） */
  openTraining: (challengeId: string, syndromeId?: string) => string;
  /** 关闭右侧栏（仅收起面板，不清除会话） */
  close: () => void;
  /** 切换面板展开/收起 */
  togglePanel: (toolId: string) => void;
  /** 切换到指定面板（别名，与 togglePanel 行为一致） */
  switchTo: (panelId: RightPanelToolId | null) => void;
  /** 切换会话标签（自动同步 drawer.activePanel） */
  switchSession: (sessionId: string) => void;
  /**
   * 移除指定会话（自动联动：若最后一个会话被移除 → 收起抽屉）
   */
  removeSession: (sessionId: string) => void;
}

/**
 * 无状态 action store（X-01 协作协议统一入口）
 *
 * 不持有任何 state，所有读写均委托给 drawer / panel-session / chapter 三个 store。
 * 持久化通过原 store 自身完成（panel-session 的 sessions 已通过 component 层级状态维护）。
 *
 * 显式标注 State 为 unknown,避免 create<T>() 推断时报"self-reference"错误。
 */
type RightPanelState = unknown;
export const useRightPanelStore = create<RightPanelState & RightPanelActions>(() => ({
  // === Action 实现（与原 rightPanelService 1:1 对应）===

  openTool: (toolId, sessionData) => {
    const sessionType = (TOOL_TO_SESSION_TYPE[toolId] ?? 'edit') as PanelSessionType;
    const title = SESSION_DEFAULT_TITLE[sessionType] ?? toolId;
    const iconName = '';
    useDrawerStore.getState().openPanel(toolId as DrawerPanelId);
    return usePanelSessionStore
      .getState()
      .upsertSession(sessionType, title, iconName, sessionData);
  },

  openEditor: (chapterId, manuscriptTitle) => {
    useChapterStore.getState().openTab(chapterId, manuscriptTitle);
    // 直接调用底层 store,避免 useRightPanelStore.getState().openTool 内部递归
    useDrawerStore.getState().openPanel('works');
    const sessionType: PanelSessionType = 'edit';
    usePanelSessionStore
      .getState()
      .upsertSession(sessionType, SESSION_DEFAULT_TITLE[sessionType] ?? '编辑', '', {
        type: 'edit',
        chapterId,
      } as PanelSessionData);
  },

  openTraining: (challengeId, syndromeId): string => {
    // 直接调用底层 store,避免 useRightPanelStore.getState().openTool 内部递归
    useDrawerStore.getState().openPanel('training');
    const sessionType: PanelSessionType = 'training';
    return usePanelSessionStore
      .getState()
      .upsertSession(sessionType, SESSION_DEFAULT_TITLE[sessionType] ?? '训练', '', {
        type: 'training',
        challengeId,
        syndromeId,
      } as PanelSessionData);
  },

  close: () => {
    useDrawerStore.getState().closePanel();
  },

  togglePanel: (toolId) => {
    useDrawerStore.getState().togglePanel(toolId as DrawerPanelId);
  },

  switchTo: (panelId) => {
    if (panelId) {
      useDrawerStore.getState().openPanel(panelId as DrawerPanelId);
    } else {
      useDrawerStore.getState().closePanel();
    }
  },

  switchSession: (sessionId) => {
    usePanelSessionStore.getState().switchSession(sessionId);
    const session = usePanelSessionStore.getState().sessions.find((s) => s.id === sessionId);
    if (session) {
      const toolId = SESSION_TYPE_TO_TOOL_ID[session.type];
      if (toolId) {
        useDrawerStore.getState().openPanel(toolId as DrawerPanelId);
      }
    }
  },

  removeSession: (sessionId) => {
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
}));
