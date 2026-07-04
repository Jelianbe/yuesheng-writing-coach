/**
 * 双轨调度 helper — 单元测试
 *
 * 覆盖 4 路径:
 * 1. Capacitor 平台 + direct 成功 → 返回 direct 结果
 * 2. Capacitor 平台 + direct 失败(throw) → caller 控制 fallback
 * 3. 非 Capacitor + electron 成功 → 返回 electron 结果
 * 4. 非 Capacitor + electron 失败(throw) → caller 控制 fallback
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { isCapacitor, runDualTrack } from '../_dual-track';

describe('isCapacitor', () => {
  const originalWindow = globalThis.window;

  afterEach(() => {
    (globalThis as unknown as { window: unknown }).window = originalWindow;
  });

  it('returns false when window is undefined', () => {
    (globalThis as unknown as { window: unknown }).window = undefined;
    expect(isCapacitor()).toBe(false);
  });

  it('returns false when window.Capacitor is missing', () => {
    (globalThis as unknown as { window: unknown }).window = {};
    expect(isCapacitor()).toBe(false);
  });

  it('returns true when window.Capacitor is present', () => {
    (globalThis as unknown as { window: unknown }).window = { Capacitor: {} };
    expect(isCapacitor()).toBe(true);
  });
});

describe('runDualTrack', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('uses direct handler on Capacitor platform', async () => {
    (globalThis as unknown as { window: unknown }).window = { Capacitor: {} };
    const direct = vi.fn().mockResolvedValue('direct-result');
    const electron = vi.fn().mockResolvedValue('electron-result');

    const result = await runDualTrack('arg', { direct, electron });

    expect(result).toBe('direct-result');
    expect(direct).toHaveBeenCalledWith('arg');
    expect(electron).not.toHaveBeenCalled();
  });

  it('uses electron handler on non-Capacitor platform', async () => {
    (globalThis as unknown as { window: unknown }).window = {};
    const direct = vi.fn().mockResolvedValue('direct-result');
    const electron = vi.fn().mockResolvedValue('electron-result');

    const result = await runDualTrack('arg', { direct, electron });

    expect(result).toBe('electron-result');
    expect(electron).toHaveBeenCalledWith('arg');
    expect(direct).not.toHaveBeenCalled();
  });

  it('lets direct handler control its own fallback (does not downgrade to electron)', async () => {
    (globalThis as unknown as { window: unknown }).window = { Capacitor: {} };
    const direct = vi.fn().mockRejectedValue(new Error('db broken'));
    const electron = vi.fn().mockResolvedValue('electron-result');

    await expect(runDualTrack('arg', { direct, electron })).rejects.toThrow('db broken');
    expect(electron).not.toHaveBeenCalled();
  });

  it('lets electron handler control its own fallback (does not downgrade to direct)', async () => {
    (globalThis as unknown as { window: unknown }).window = {};
    const direct = vi.fn().mockResolvedValue('direct-result');
    const electron = vi.fn().mockRejectedValue(new Error('ipc broken'));

    await expect(runDualTrack('arg', { direct, electron })).rejects.toThrow('ipc broken');
    expect(direct).not.toHaveBeenCalled();
  });

  it('passes args to both handlers', async () => {
    (globalThis as unknown as { window: unknown }).window = {};
    const direct = vi.fn().mockResolvedValue('d');
    const electron = vi.fn().mockResolvedValue('e');

    await runDualTrack({ foo: 1 }, { direct, electron });

    expect(electron).toHaveBeenCalledWith({ foo: 1 });
  });
});
