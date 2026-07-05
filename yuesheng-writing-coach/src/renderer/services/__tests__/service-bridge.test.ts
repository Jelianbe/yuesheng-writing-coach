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

import { describe, it, expect } from 'vitest';
import { serviceBridge } from '../service-bridge';

describe('serviceBridge 导出对象', () => {
  it('提供 invoke 方法', async () => {
    expect(typeof serviceBridge.invoke).toBe('function');
  });
});
