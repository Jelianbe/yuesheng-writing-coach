/**
 * panel-bus 单测（X-01 跨面板协议 / Phase G）
 *
 * 覆盖：
 * - dispatch 向所有订阅者派发命令
 * - subscribe 返回 unsubscribe 函数
 * - 单个 listener 抛错不影响其他 listener
 * - resetForTesting 清空所有订阅
 * - 各种 PanelCommand 类型可被派发
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { panelBus, type PanelCommand } from '../panel-bus';

describe('panel-bus', () => {
  beforeEach(() => {
    panelBus.resetForTesting();
  });

  it('dispatch invokes all subscribers with the command', () => {
    const a = vi.fn();
    const b = vi.fn();
    panelBus.subscribe(a);
    panelBus.subscribe(b);

    const cmd: PanelCommand = { type: 'open-tool', toolId: 'works' };
    panelBus.dispatch(cmd);

    expect(a).toHaveBeenCalledWith(cmd);
    expect(b).toHaveBeenCalledWith(cmd);
  });

  it('subscribe returns an unsubscribe function', () => {
    const a = vi.fn();
    const unsub = panelBus.subscribe(a);

    panelBus.dispatch({ type: 'open-tool', toolId: 'works' });
    expect(a).toHaveBeenCalledTimes(1);

    unsub();

    panelBus.dispatch({ type: 'close-tool', toolId: 'works' });
    expect(a).toHaveBeenCalledTimes(1);
  });

  it('a listener error does not break other listeners', () => {
    const errSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
    const a = vi.fn(() => { throw new Error('boom'); });
    const b = vi.fn();
    panelBus.subscribe(a);
    panelBus.subscribe(b);

    expect(() => panelBus.dispatch({ type: 'open-tool', toolId: 'works' })).not.toThrow();
    expect(a).toHaveBeenCalled();
    expect(b).toHaveBeenCalled();
    expect(errSpy).toHaveBeenCalledWith(
      expect.stringContaining('[panelBus]'),
      expect.any(Error),
    );
    errSpy.mockRestore();
  });

  it('resetForTesting clears all subscribers', () => {
    const a = vi.fn();
    const b = vi.fn();
    panelBus.subscribe(a);
    panelBus.subscribe(b);

    panelBus.resetForTesting();

    panelBus.dispatch({ type: 'open-tool', toolId: 'works' });
    expect(a).not.toHaveBeenCalled();
    expect(b).not.toHaveBeenCalled();
  });

  it('dispatches all command variants', () => {
    const a = vi.fn();
    panelBus.subscribe(a);

    const commands: PanelCommand[] = [
      { type: 'open-tool', toolId: 'works' },
      { type: 'close-tool', toolId: 'training' },
      { type: 'set-active-tool', toolId: 'catalog' },
      { type: 'open-project-tab', projectId: 'p-1' },
      { type: 'close-project-tab', projectId: 'p-1' },
      { type: 'set-active-project-tab', projectId: 'p-2' },
      { type: 'set-active-project-tab', projectId: null },
      { type: 'clear-project-tabs' },
      { type: 'set-left-tab', tabId: 'chat' },
      { type: 'set-left-tab', tabId: 'proj' },
      { type: 'switch-session', sessionId: 's-1' },
    ];

    for (const cmd of commands) {
      panelBus.dispatch(cmd);
    }
    expect(a).toHaveBeenCalledTimes(commands.length);
  });

  it('dispatch with no subscribers is a no-op', () => {
    expect(() =>
      panelBus.dispatch({ type: 'open-tool', toolId: 'works' }),
    ).not.toThrow();
  });
});
