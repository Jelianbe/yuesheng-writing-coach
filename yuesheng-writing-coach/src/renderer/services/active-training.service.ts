/**
 * 活跃训练服务 — Sprint 32 (移除 serviceBridge/dual-track)
 *
 * 双轨迁移:
 * - Electron 端: typedInvoke → main handler
 * - Android 端: import shared ActiveTrainingService + CapacitorSqliteAdapter
 *
 * 依据: dev-docs/tasks/sprint-32-plan.md
 */
import { invoke } from './_invoke';
import { typedOn } from './ipc-client';
import { isCapacitor } from './_platform';
import type {
  ActiveTrainingGetResponse,
  ActiveTrainingSubmitStepResponse,
  ActiveTrainingUpdateDraftResponse,
  ActiveTrainingUpdatedEvent,
} from '../../shared/api-contracts/active-training.contract';
import { createStorageAdapter } from '../../shared/storage';
import { ActiveTrainingService as DirectActiveTrainingService } from '../../shared/services/active-training.service';

/** Android 端: 延迟初始化 direct service */
let _directService: DirectActiveTrainingService | null = null;

async function getDirectService(): Promise<DirectActiveTrainingService | null> {
  if (!isCapacitor()) return null;
  if (_directService) return _directService;
  const adapter = createStorageAdapter({ type: 'capacitor-sqlite', dbName: 'yuesheng.db', version: 1 });
  await adapter.initialize();
  _directService = new DirectActiveTrainingService(adapter);
  return _directService;
}

export const activeTrainingService = {
  /** 获取当前活跃训练的 sessionId — 失败时返回 null */
  async getCurrent(): Promise<ActiveTrainingGetResponse | null> {
    if (isCapacitor()) {
      const direct = await getDirectService();
      if (!direct) return null;
      try {
        const all = await direct.listActive();
        return all.length > 0 ? all[0] : null;
      } catch (err) { console.error('[active-training] getCurrent failed (direct):', err); return null; }
    }
    return (await invoke<ActiveTrainingGetResponse>('activeTraining:getCurrent', {})) ?? null;
  },

  /** 为用户创建新的活跃训练 — 失败时返回 null */
  async create(sessionId: string, phase: string): Promise<ActiveTrainingGetResponse | null> {
    if (isCapacitor()) {
      const direct = await getDirectService();
      if (!direct) return null;
      try { return await direct.create({ sessionId, phase } as never); }
      catch (err) { console.error('[active-training] create failed (direct):', err); return null; }
    }
    return (await invoke<ActiveTrainingGetResponse>('activeTraining:create', { sessionId, phase })) ?? null;
  },

  /** 更新活跃训练状态 — 失败时返回 null */
  async update(input: { sessionId: string; stepName: string; stepStatus: string }): Promise<ActiveTrainingGetResponse | null> {
    if (isCapacitor()) {
      const direct = await getDirectService();
      if (!direct) return null;
      try { return await direct.update(input.sessionId, { currentStep: input.stepName } as never); }
      catch (err) { console.error('[active-training] update failed (direct):', err); return null; }
    }
    return (await invoke<ActiveTrainingGetResponse>('activeTraining:update', input as Record<string, unknown>)) ?? null;
  },

  /** 获取审计日志 — 失败时返回 [] */
  async getAuditLogs(trainingId: number): Promise<unknown[]> {
    if (isCapacitor()) {
      console.warn('[active-training] getAuditLogs: not supported on Capacitor');
      return [];
    }
    return (await invoke<unknown[]>('activeTraining:getAuditLogs', { trainingId })) ?? [];
  },

  /** 获取近期状态转换 — 失败时返回 [] */
  async getRecentTransitions(trainingId: number): Promise<unknown[]> {
    if (isCapacitor()) {
      console.warn('[active-training] getRecentTransitions: not supported on Capacitor');
      return [];
    }
    return (await invoke<unknown[]>('activeTraining:getRecentTransitions', { trainingId })) ?? [];
  },

  /** 按 sessionId 获取活跃训练 — 失败时返回 null */
  async get(params: { sessionId: string }): Promise<ActiveTrainingGetResponse | null> {
    if (isCapacitor()) {
      const direct = await getDirectService();
      if (!direct) return null;
      try {
        const all = await direct.listActive();
        return (all.find(a => (a as unknown as Record<string, unknown>).sessionId === params.sessionId) as ActiveTrainingGetResponse) ?? null;
      } catch (err) { console.error('[active-training] get failed (direct):', err); return null; }
    }
    return (await invoke<ActiveTrainingGetResponse>('activeTraining:get', params)) ?? null;
  },

  /** 更新草稿内容 — 失败时返回 null */
  async updateDraft(params: { sessionId: string; content: string }): Promise<ActiveTrainingUpdateDraftResponse | null> {
    if (isCapacitor()) {
      console.warn('[active-training] updateDraft: not supported on Capacitor');
      return null;
    }
    return (await invoke<ActiveTrainingUpdateDraftResponse>('activeTraining:updateDraft', params as Record<string, unknown>)) ?? null;
  },

  /** 提交分步回答 — 失败时返回 null */
  async submitStep(params: { sessionId: string; stepId: number; content: string }): Promise<ActiveTrainingSubmitStepResponse | null> {
    if (isCapacitor()) {
      console.warn('[active-training] submitStep: not supported on Capacitor');
      return null;
    }
    return (await invoke<ActiveTrainingSubmitStepResponse>('activeTraining:submitStep', params as Record<string, unknown>)) ?? null;
  },

  /** 订阅活跃训练更新事件 — 返回 cleanup 函数 */
  subscribe(handler: (event: ActiveTrainingUpdatedEvent) => void): () => void {
    if (isCapacitor()) {
      console.warn('[active-training] subscribe: not supported on Capacitor');
      return () => {};
    }
    return typedOn<ActiveTrainingUpdatedEvent>('activeTraining:updated', handler);
  },
};
