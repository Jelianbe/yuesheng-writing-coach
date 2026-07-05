/**
 * 学生上下文服务 — Sprint 26 阶段 3.5 方案 4a 降级
 *
 * studentContext:load/save/toJSON 这三个通道在 Electron preload 白名单压缩后
 * 未注册到 main process（不在 bridge 方法列表中），因此 Electron 端直接降级为
 * null/false 返回。Capacitor 端保持原有降级行为不变。
 *
 * 依据: dev-docs/tasks/sprint-26-phase-3-plan.md §3.5 方案 4a
 */

import { serviceBridge } from './service-bridge';
import { isCapacitor } from './_dual-track';

/** Capacitor 端无 IPC 通道,统一降级标识 */
function capacitorNoopStudentContext<T>(methodName: string, fallback: T): T {
  console.warn(`[student-context] ${methodName}: not supported on Capacitor (业务全在主进程), returning fallback`);
  return fallback;
}

export const studentContextService = {
  /**
   * 加载学生上下文 — 失败时返回 null(降级)
   *
   * Capacitor 端:降级 noop。
   */
  async load(): Promise<unknown> {
    if (isCapacitor()) return capacitorNoopStudentContext('load', null);
    const result = await serviceBridge.invoke<Record<string, never>, unknown>('studentContext:load', {});
    if (!result) {
      console.error('[student-context] load failed');
      return null;
    }
    return result;
  },

  /**
   * 保存学生上下文 — 失败时返回 false(降级)
   *
   * Capacitor 端:降级 noop。
   */
  async save(data: unknown): Promise<boolean> {
    if (isCapacitor()) return capacitorNoopStudentContext('save', false);
    const result = await serviceBridge.invoke<{ data: unknown }, void>('studentContext:save', { data });
    if (result === null) {
      console.error('[student-context] save failed');
      return false;
    }
    return true;
  },

  /**
   * 获取学生上下文的 JSON 表示 — 失败时返回 ''(降级)
   *
   * Capacitor 端:降级 noop。
   */
  async toJSON(): Promise<string> {
    if (isCapacitor()) return capacitorNoopStudentContext('toJSON', '');
    const result = await serviceBridge.invoke<Record<string, never>, { text: string }>('studentContext:toJSON', {});
    if (!result) {
      console.error('[student-context] toJSON failed');
      return '';
    }
    return result.text;
  },
};
