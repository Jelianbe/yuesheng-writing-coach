/**
 * panel-bus.ts — X-01 跨面板协议（Phase G）
 *
 * 设计动机：LeftPanel 与 RightPanel 之间不应直接相互 import store。
 * - 当前：LeftPanel 调用 useRightToolsStore.closeTool('works') 等
 * - 改进：LeftPanel dispatch command，AppShell 路由到目标 store
 *
 * 优点：
 * - 解耦：LeftPanel 不依赖 right-tools.store
 * - 可测试：dispatch + 订阅都可独立测试
 * - 可扩展：未来加 "通知右侧栏" 等新命令只需扩展 PanelCommand
 *
 * 用法：
 *   // LeftPanel:
 *   panelBus.dispatch({ type: 'open-tool', toolId: 'works' });
 *
 *   // AppShell:
 *   useEffect(() => panelBus.subscribe(handleCommand), []);
 *   function handleCommand(cmd: PanelCommand) {
 *     switch (cmd.type) {
 *       case 'open-tool': useRightToolsStore.getState().openTool(cmd.toolId); break;
 *       ...
 *     }
 *   }
 */

export type PanelCommand =
  | { type: 'open-tool'; toolId: string }
  | { type: 'close-tool'; toolId: string }
  | { type: 'set-active-tool'; toolId: string }
  | { type: 'open-project-tab'; projectId: string }
  | { type: 'close-project-tab'; projectId: string }
  | { type: 'set-active-project-tab'; projectId: string | null }
  | { type: 'clear-project-tabs' }
  | { type: 'set-left-tab'; tabId: 'chat' | 'proj' }
  | { type: 'switch-session'; sessionId: string };

type Listener = (cmd: PanelCommand) => void;

const listeners = new Set<Listener>();

export const panelBus = {
  /** Dispatch a command to all subscribers */
  dispatch(cmd: PanelCommand): void {
    for (const l of listeners) {
      try {
        l(cmd);
      } catch (err) {
        console.error('[panelBus] listener error:', err);
      }
    }
  },

  /** Subscribe to all commands. Returns unsubscribe fn. */
  subscribe(listener: Listener): () => void {
    listeners.add(listener);
    return () => listeners.delete(listener);
  },

  /** Test isolation: clear all subscribers */
  resetForTesting(): void {
    listeners.clear();
  },
};
