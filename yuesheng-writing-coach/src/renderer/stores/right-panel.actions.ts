/**
 * right-panel.actions.ts — 右侧栏多 Store 协作协议（X-01）
 *
 * == 协议规则 ==
 * 1. 单点真相（SSOT）：panel-session.store 是"右侧栏打开内容"的唯一状态源。
 *    drawer.store 的 activePanel 由当前活跃会话的类型反推（被动设置，非 SSOT）。
 * 2. 统一入口：所有右侧栏操作必须通过此文件的 action，禁止外部代码直接
 *    协调 drawer.store + panel-session.store + chapter.store。
 *    违反示例：WorkTreePanel 中 4 个独立调用（select/openTab/upsertSession/openPanel）。
 * 3. 自动联动：关闭最后一个会话时自动收起抽屉，切换会话时自动更新 activePanel。
 * 4. 不删除会话：closePanel() 仅收起面板，不清除会话（方便重新打开时恢复）。
 *
 * == 使用示例 ==
 *   rightPanelActions.openEditor(chapterId, msTitle);
 *   rightPanelActions.openTool('training');
 *   rightPanelActions.removeSession(sessionId);
 */

import { useDrawerStore, type DrawerPanelId } from './drawer.store';
import { usePanelSessionStore, type PanelSessionData } from './panel-session.store';
import { useChapterStore } from './chapter.store';
import {
  TOOL_TO_SESSION_TYPE,
  SESSION_TYPE_TO_TOOL_ID,
  SESSION_DEFAULT_TITLE,
  SESSION_LUCIDE_ICON,
} from '../components/layout/drawer-constants';

export const rightPanelActions = {
  /**
   * 打开工具面板（自动创建/激活会话 + 展开抽屉）
   * @param toolId DrawerPanelId（如 'training', 'works', 'diagnosis'）
   * @param sessionData 可选的会话关联数据
   * @returns 会话 ID
   */
  openTool(toolId: string, sessionData?: PanelSessionData): string {
    const sessionType = TOOL_TO_SESSION_TYPE[toolId] ?? 'edit';
    const title = SESSION_DEFAULT_TITLE[sessionType] ?? toolId;
    const iconName = SESSION_LUCIDE_ICON[sessionType]?.name ?? '';

    useDrawerStore.getState().openPanel(toolId as DrawerPanelId);
    return usePanelSessionStore.getState().upsertSession(sessionType, title, iconName, sessionData);
  },

  /**
   * 打开章节编辑器（自动打开 works 面板 + 创建编辑会话 + 打开标签页）
   * @param chapterId 章节 ID
   * @param manuscriptTitle 作品名称（用于标签显示）
   */
  openEditor(chapterId: string, manuscriptTitle: string): void {
    useChapterStore.getState().openTab(chapterId, manuscriptTitle);
    this.openTool('works', { type: 'edit', chapterId });
  },

  /**
   * 打开训练面板（自动展开 + 创建训练会话）
   * @param challengeId 训练挑战 ID
   * @param syndromeId 关联症候 ID
   */
  openTraining(challengeId: string, syndromeId?: string): string {
    return this.openTool('training', { type: 'training', challengeId, syndromeId });
  },

  /**
   * 关闭右侧栏（仅收起面板，不清除会话——下次打开时恢复）
   */
  closePanel(): void {
    useDrawerStore.getState().closePanel();
  },

  /**
   * 切换面板展开/收起（点击同一图标时的行为）
   */
  togglePanel(toolId: string): void {
    useDrawerStore.getState().togglePanel(toolId as DrawerPanelId);
  },

  /**
   * 切换会话标签（自动同步 drawer.activePanel）
   */
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
