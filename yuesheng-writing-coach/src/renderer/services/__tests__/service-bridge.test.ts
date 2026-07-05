/**
 * ServiceBridge (renderer) 单测 — Sprint 29
 *
 * 覆盖:
 * 1. Electron 路径: electronAPI.invoke 成功/失败
 * 2. Capacitor 路径: directFallback 成功/失败（不降级）
 * 3. invokeBridgeElectronOnly 强制走 Electron
 * 4. 边界: 无 electronAPI 且非 Capacitor 抛错、参数透传
 *
 * 依据: dev-docs/tasks/sprint-29-plan.md §阶段 2
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { invokeBridge, invokeBridgeElectronOnly, serviceBridge } from '../service-bridge';

// ─── 辅助: 切换 Capacitor/非 Capacitor 平台 ───

function setNonCapacitorPlatform(): void {
  (globalThis as unknown as { window: unknown }).window = {};
  Object.defineProperty(navigator, 'userAgent', {
    value: 'Mozilla/5.0 (Windows NT 10.0) AppleWebKit/537.36',
    configurable: true,
  });
}

function setCapacitorPlatform(): void {
  (globalThis as unknown as { window: unknown }).window = {};
  Object.defineProperty(navigator, 'userAgent', {
    value: 'Mozilla/5.0 (Linux; Android 10) Capacitor/3.5.0',
    configurable: true,
  });
}

function mockElectronAPI(invokeFn: (ch: string, payload: unknown) => unknown): void {
  (globalThis as unknown as { window: unknown }).window = {
    electronAPI: { invoke: invokeFn, on: vi.fn() },
  };
}

// ─── 保存/恢复全局状态 ───

const originalWindow = globalThis.window;
const originalUserAgent = navigator.userAgent;

beforeEach(() => {
  vi.clearAllMocks();
});

afterEach(() => {
  (globalThis as unknown as { window: unknown }).window = originalWindow;
  Object.defineProperty(navigator, 'userAgent', { value: originalUserAgent, configurable: true });
});

// ─── 测试 ───

describe('invokeBridge — Electron 路径', () => {
  it('走 electronAPI.invoke 成功', async () => {
    setNonCapacitorPlatform();
    mockElectronAPI(vi.fn().mockResolvedValue({ success: true, data: 'electron-ok' }));

    const result = await invokeBridge<string, string>('test:ping', 'hello');
    expect(result).toBe('electron-ok');
  });

  it('electronAPI 返回失败时返回 null', async () => {
    setNonCapacitorPlatform();
    mockElectronAPI(vi.fn().mockResolvedValue({ success: false, error: 'something went wrong' }));

    const result = await invokeBridge<string, string>('test:fail', 'x');
    expect(result).toBeNull();
  });

  it('electronAPI 不可用时返回 null（非 Capacitor 平台）', async () => {
    setNonCapacitorPlatform();
    // 不设 electronAPI
    (globalThis as unknown as { window: unknown }).window = {};

    const result = await invokeBridge<string, string>('test:noapi', 'x');
    expect(result).toBeNull();
  });
});

describe('invokeBridge — Capacitor 路径', () => {
  it('直调 directFallback 成功', async () => {
    setCapacitorPlatform();
    const directFallback = vi.fn().mockResolvedValue('direct-ok');

    const result = await invokeBridge<string, string>('test:direct', 'args', directFallback);
    expect(result).toBe('direct-ok');
    expect(directFallback).toHaveBeenCalledWith('args');
  });

  it('directFallback 失败时返回 null（不降级到 Electron）', async () => {
    setCapacitorPlatform();
    const directFallback = vi.fn().mockRejectedValue(new Error('db broken'));
    // 设了 electronAPI 但 Capacitor 路径不应使用它
    mockElectronAPI(vi.fn().mockResolvedValue({ success: true, data: 'electron-fallback' }));

    const result = await invokeBridge<string, string>('test:direct-fail', 'args', directFallback);
    expect(result).toBeNull();
    expect(directFallback).toHaveBeenCalledWith('args');
  });

  it('不传 directFallback 时返回 null', async () => {
    setCapacitorPlatform();

    const result = await invokeBridge<string, string>('test:nofallback', 'args');
    expect(result).toBeNull();
  });
});

describe('invokeBridgeElectronOnly', () => {
  it('强制走 Electron 路径，无论平台', async () => {
    // 即使在 Capacitor 平台，也走 Electron
    setCapacitorPlatform();
    mockElectronAPI(vi.fn().mockResolvedValue({ success: true, data: 'forced-electron' }));

    const result = await invokeBridgeElectronOnly<string, string>('test:force', 'x');
    expect(result).toBe('forced-electron');
  });

  it('electronAPI 不可用时返回 null', async () => {
    setCapacitorPlatform();
    // 不设 electronAPI
    (globalThis as unknown as { window: unknown }).window = {};

    const result = await invokeBridgeElectronOnly<string, string>('test:noapi', 'x');
    expect(result).toBeNull();
  });
});

describe('参数透传', () => {
  it('Electron 路径参数正确传递', async () => {
    setNonCapacitorPlatform();
    const invokeMock = vi.fn().mockResolvedValue({ success: true, data: null });
    mockElectronAPI(invokeMock);

    await invokeBridge('test:args', { id: 42, name: 'test' });

    expect(invokeMock).toHaveBeenCalledWith(
      expect.any(String),
      { method: 'test:args', args: { id: 42, name: 'test' } },
    );
  });

  it('Capacitor 路径参数正确传递', async () => {
    setCapacitorPlatform();
    const directFallback = vi.fn().mockResolvedValue(null);

    await invokeBridge('test:args', { x: 1 }, directFallback);

    expect(directFallback).toHaveBeenCalledWith({ x: 1 });
  });
});

describe('serviceBridge 导出对象', () => {
  it('提供 invoke 和 invokeElectronOnly 方法', () => {
    expect(typeof serviceBridge.invoke).toBe('function');
    expect(typeof serviceBridge.invokeElectronOnly).toBe('function');
  });
});
