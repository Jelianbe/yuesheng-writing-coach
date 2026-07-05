/**
 * 教学状态服务 — Sprint 32 (移除 serviceBridge/dual-track)
 *
 * 双轨迁移:
 * - Electron 端: typedInvoke → main handler
 * - Android 端: import shared TeachingStateService + CapacitorSqliteAdapter
 *
 * 依据: dev-docs/tasks/sprint-32-plan.md
 */
import { invoke } from './_invoke';
import { typedOn } from './ipc-client';
import { isCapacitor } from './_platform';
import type { TeachingState } from '../../shared/types/types-teaching';
import type { TeachingStateUpdatedEvent, TeachingStateMasteryEvent } from '../../shared/api-contracts/teaching-state.contract';
import { createStorageAdapter } from '../../shared/storage';
import { TeachingStateService as DirectTeachingStateService } from '../../shared/services/teaching-state.service';

/** Android 端: 延迟初始化 direct service */
let _directService: DirectTeachingStateService | null = null;

async function getDirectService(): Promise<DirectTeachingStateService | null> {
  if (!isCapacitor()) return null;
  if (_directService) return _directService;
  const adapter = createStorageAdapter({ type: 'capacitor-sqlite', dbName: 'yuesheng.db', version: 1 });
  await adapter.initialize();
  _directService = new DirectTeachingStateService(adapter);
  return _directService;
}

export const teachingStateService = {
  /** 获取教学状态 — 失败时返回 null */
  async getState(sessionId: string): Promise<TeachingState | null> {
    if (isCapacitor()) {
      const direct = await getDirectService();
      if (!direct) return null;
      try { return await direct.getBySession(sessionId); }
      catch (err) { console.error('[teaching-state] get failed (direct):', err); return null; }
    }
    return invoke<TeachingState>('teachingState:get', { sessionId }) ?? null;
  },

  /** 更新教学状态 — 失败时返回 null */
  async update(sessionId: string, state: Partial<TeachingState>): Promise<TeachingState | null> {
    if (isCapacitor()) {
      const direct = await getDirectService();
      if (!direct) return null;
      try { return await direct.update(sessionId, state); }
      catch (err) { console.error('[teaching-state] update failed (direct):', err); return null; }
    }
    return invoke<TeachingState>('teachingState:update', { sessionId, state }) ?? null;
  },

  /** 确认教学阶段 — 失败时返回 null */
  async confirmPhase(sessionId: string, phase: string, data?: Record<string, unknown>): Promise<TeachingState | null> {
    if (isCapacitor()) {
      const direct = await getDirectService();
      if (!direct) return null;
      try {
        const existing = await direct.getBySession(sessionId);
        if (!existing) return null;
        return await direct.update(sessionId, { phase, confirmedAt: Date.now() } as Partial<TeachingState>);
      } catch (err) { console.error('[teaching-state] confirmPhase failed (direct):', err); return null; }
    }
    return invoke<TeachingState>('teachingState:confirmPhase', { sessionId, phase, data }) ?? null;
  },

  /** 获取教学提示 — 失败时返回 null */
  async getPrompt(sessionId: string): Promise<string | null> {
    if (isCapacitor()) {
      console.warn('[teaching-state] getPrompt: not supported on Capacitor');
      return null;
    }
    return invoke<string>('teachingState:getPrompt', { sessionId }) ?? null;
  },

  /** 更新摘要 — 失败时返回 null */
  async updateSummary(sessionId: string, summary: string): Promise<TeachingState | null> {
    if (isCapacitor()) {
      console.warn('[teaching-state] updateSummary: not supported on Capacitor');
      return null;
    }
    return invoke<TeachingState>('teachingState:updateSummary', { sessionId, summary }) ?? null;
  },

  /** 监听教学状态更新 — 返回 cleanup 函数 */
  onUpdated(handler: (data: TeachingStateUpdatedEvent) => void): () => void {
    if (isCapacitor()) {
      console.warn('[teaching-state] onUpdated: not supported on Capacitor');
      return () => {};
    }
    return typedOn<TeachingStateUpdatedEvent>('teachingState:updated', handler);
  },

  /** 监听精通门控达成 — 返回 cleanup 函数 */
  onMastery(handler: (data: TeachingStateMasteryEvent) => void): () => void {
    if (isCapacitor()) {
      console.warn('[teaching-state] onMastery: not supported on Capacitor');
      return () => {};
    }
    return typedOn<TeachingStateMasteryEvent>('teachingState:mastery', handler);
  },
};
