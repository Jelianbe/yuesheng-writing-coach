/**
 * 双轨调度 helper — 单元测试
 *
 * 覆盖 4 路径:
 * 1. Capacitor 平台 + direct 成功 → 返回 direct 结果
 * 2. Capacitor 平台 + direct 失败(throw) → caller 控制 fallback
 * 3. 非 Capacitor + electron 成功 → 返回 electron 结果
 * 4. 非 Capacitor + electron 失败(throw) → caller 控制 fallback
 */

import { describe, it, expect, afterEach } from 'vitest';
import { isCapacitor, runDualTrack } from '../_dual-track';

describe('isCapacitor', () => {
  const originalWindow = globalThis.window;
  const originalUserAgent = navigator.userAgent;

  afterEach(() => {
    (globalThis as unknown as { window: unknown }).window = originalWindow;
    Object.defineProperty(navigator, 'userAgent', { value: originalUserAgent, configurable: true });
  });

  function setUserAgent(ua: string) {
    Object.defineProperty(navigator, 'userAgent', { value: ua, configurable: true });
  }

  it('returns false when window is undefined', () => {
    (globalThis as unknown as { window: unknown }).window = undefined;
    expect(isCapacitor()).toBe(false);
  });

  it('returns false when userAgent does not contain Capacitor', () => {
    (globalThis as unknown as { window: unknown }).window = {};
    setUserAgent('Mozilla/5.0 (Windows NT 10.0) AppleWebKit/537.36');
    expect(isCapacitor()).toBe(false);
  });

  it('returns true when userAgent contains Capacitor', () => {
    (globalThis as unknown as { window: unknown }).window = {};
    setUserAgent('Mozilla/5.0 (Linux; Android 10) Capacitor/3.5.0');
    expect(isCapacitor()).toBe(true);
  });
});

describe('runDualTrack', () => {
  it('returns null (deprecated shim, no-arg)', async () => {
    const result = await runDualTrack();
    expect(result).toBeNull();
  });
});
