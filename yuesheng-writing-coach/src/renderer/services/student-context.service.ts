/**
 * 学生上下文服务 — Sprint 32 (移除 serviceBridge/dual-track)
 *
 * 双轨迁移:
 * - Electron 端: typedInvoke → main handler
 * - Android 端: 暂不支持(无 shared 实现)
 *
 * 依据: dev-docs/tasks/sprint-32-plan.md
 */
import { invoke } from './_invoke';
import { isCapacitor } from './_platform';
import type { StudentContextData } from '../../shared/api-contracts/student-context.contract';

export const studentContextService = {
  /** 获取学生上下文 — 失败时返回 null */
  async get(userId: string): Promise<StudentContextData | null> {
    if (isCapacitor()) {
      console.warn('[student-context] get: not supported on Capacitor');
      return null;
    }
    return invoke<StudentContextData>('studentContext:get', { userId }) ?? null;
  },

  /** 更新学生上下文 — 失败时返回 null */
  async update(userId: string, data: Record<string, unknown>): Promise<StudentContextData | null> {
    if (isCapacitor()) {
      console.warn('[student-context] update: not supported on Capacitor');
      return null;
    }
    return invoke<StudentContextData>('studentContext:update', { userId, ...data }) ?? null;
  },

  /** 获取上下文笔记 — 失败时返回 null */
  async getNote(userId: string): Promise<string | null> {
    if (isCapacitor()) {
      console.warn('[student-context] getNote: not supported on Capacitor');
      return null;
    }
    return invoke<string | null>('studentContext:getNote', { userId }) ?? null;
  },
};
