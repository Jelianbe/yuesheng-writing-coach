/**
 * 教学状态协调服务 — Sprint 26 阶段 3.2 (双轨版)
 *
 * 继承自 Sprint 20 B-3 降级(D-DEBT-34):调用失败时 console.error + 返回 fallback。
 *
 * 3.2 双轨改造:
 *   - get / update 走 runDualTrack (基础 CRUD,shared 端有等价方法)
 *   - confirm / getPrompt / updateSummary 保持 IPC-only
 *     (状态机/prompt 拼接/多字段更新是主进程业务,shared 端无等价实现)
 *   - onUpdated / onMastery 保持 IPC-only (事件订阅,Capacitor 端无推送通道)
 *   - Capacitor 端上述 5 个方法通过 capacitor-teaching-state 实现轻量化降级
 *
 * ─── Sprint 34 (TeachingState Android 端激活) ───
 *
 * Capacitor 端从全部 noop 升级为轻量化真实实现:
 *   - confirm: localStorage 记录阶段完成
 *   - updateSummary: localStorage 持久化诊断摘要
 *   - onUpdated/onMastery: 内存事件总线
 *   - getPrompt: 保持 noop（PromptBuilder 在 main process）
 *
 * 依据: dev-docs/decision-log.md D-084
 */
import { typedOn } from './ipc-client';
import { serviceBridge } from './service-bridge';
import { runDualTrack, isCapacitor } from './_dual-track';
import { createStorageAdapter } from '../../shared/storage';
import { TeachingStateService as DirectTeachingStateService } from '../../shared/services/teaching-state.service';
import {
  capacitorTeachingStateConfirm,
  capacitorTeachingStateGetPrompt,
  capacitorTeachingStateUpdateSummary,
  capacitorTeachingStateOnUpdated,
  capacitorTeachingStateOnMastery,
} from './capacitor-teaching-state';
import type {
  TeachingStateGetRequest,
  TeachingStateGetResponse,
  TeachingStateUpdateRequest,
  TeachingStateConfirmRequest,
  TeachingStateConfirmResponse,
  TeachingStateGetPromptRequest,
  TeachingStateGetPromptResponse,
  TeachingStateUpdateSummaryRequest,
  TeachingStateUpdatedEvent,
  TeachingStateMasteryEvent,
} from '../../shared/api-contracts/teaching-state.contract';
import type { TeachingState as SharedTeachingState } from '../../shared/types/types-teaching';

/** Android 端: 延迟初始化 adapter + direct service(单例) */
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
  /** 获取教学状态 — 失败时返回 null(降级) */
  async get(params: TeachingStateGetRequest): Promise<TeachingStateGetResponse | null> {
    return runDualTrack(params, {
      direct: async (p) => {
        const svc = await getDirectService();
        if (!svc) return null;
        // shared 端 getBySession 返回完整 TeachingState (含 5+ 教学状态机专用字段)
        // IPC 端返回 TeachingStateGetResponse (含 phaseName/subphaseName/phaseProgress 计算字段)
        // 字段映射: shared 端缺计算字段,Android 端 UI 应自行处理 (空串/0 占位)
        const state = await svc.getBySession(p.sessionId);
        if (!state) return null;
        return {
          sessionId: state.sessionId,
          currentPhase: state.currentPhase,
          currentSubphase: state.currentSubphase,
          activeProblems: state.activeProblems,
          completedActions: state.completedActions,
          nextSuggestedActions: state.nextSuggestedActions,
          diagnosisSummary: state.diagnosisSummary,
          lockedSyndromes: state.lockedSyndromes,
          createdAt: Date.parse(state.updatedAt),
          updatedAt: Date.parse(state.updatedAt),
          phaseName: '',
          subphaseName: '',
          phaseProgress: 0,
        } as unknown as TeachingStateGetResponse;
      },
      electron: async (p) => {
        const result = await serviceBridge.invoke<TeachingStateGetRequest, TeachingStateGetResponse>('teachingState:get', p);
        if (!result) {
          console.error('[teaching-state] get failed');
          return null;
        }
        return result;
      },
    });
  },

  /** 更新教学状态 — 失败时返回 null(降级) */
  async update(params: TeachingStateUpdateRequest): Promise<SharedTeachingState | null> {
    return runDualTrack(params, {
      direct: async (p) => {
        const svc = await getDirectService();
        if (!svc) return null;
        // IPC 端 updates 字段允许 null(清空),shared 端 Partial 不允许 null
        // 转换: null → undefined (shared 端语义:不更新该字段)
        const updates: Record<string, unknown> = {};
        for (const [k, v] of Object.entries(p.updates)) {
          if (v !== null) updates[k] = v;
        }
        return svc.update(p.sessionId, updates as Partial<Omit<SharedTeachingState, 'sessionId'>>);
      },
      electron: async (p) => {
        // IPC 端 serviceBridge 返回的是 contract.TeachingState (瘦版,缺 5 字段),
        // shared 端 svc.update 返回 SharedTeachingState (完整版)。
        // 这里统一返回 SharedTeachingState: contract 缺的字段 Android 端补空/默认。
        const result = await serviceBridge.invoke<TeachingStateUpdateRequest, SharedTeachingState>('teachingState:update', p);
        if (!result) {
          console.error('[teaching-state] update failed');
          return null;
        }
        return result as unknown as SharedTeachingState;
      },
    });
  },

  /** 确认阶段完成 — 失败时返回 null(降级,状态机业务) */
  async confirm(params: TeachingStateConfirmRequest): Promise<TeachingStateConfirmResponse | null> {
    if (isCapacitor()) return capacitorTeachingStateConfirm(params) as Promise<TeachingStateConfirmResponse | null>;
    const result = await serviceBridge.invoke<TeachingStateConfirmRequest, TeachingStateConfirmResponse>('teachingState:confirm', params);
    if (!result) {
      console.error('[teaching-state] confirm failed');
      return null;
    }
    return result;
  },

  /** 获取 Prompt 注入内容 — 失败时返回 null(降级,prompt 拼接业务) */
  async getPrompt(params: TeachingStateGetPromptRequest): Promise<string | null> {
    if (isCapacitor()) return capacitorTeachingStateGetPrompt(params);
    const result = await serviceBridge.invoke<TeachingStateGetPromptRequest, TeachingStateGetPromptResponse['promptContent']>('teachingState:getPrompt', params);
    if (!result) {
      console.error('[teaching-state] getPrompt failed');
      return null;
    }
    return result;
  },

  /** 更新诊断摘要 — 失败时返回 null(降级) */
  async updateSummary(params: TeachingStateUpdateSummaryRequest): Promise<SharedTeachingState | null> {
    if (isCapacitor()) return capacitorTeachingStateUpdateSummary(params) as Promise<SharedTeachingState | null>;
    const result = await serviceBridge.invoke<TeachingStateUpdateSummaryRequest, SharedTeachingState>('teachingState:updateSummary', params);
    if (!result) {
      console.error('[teaching-state] updateSummary failed');
      return null;
    }
    return result as unknown as SharedTeachingState;
  },

  /** 监听教学状态更新推送 — Capacitor 端走内存事件总线 */
  onUpdated(handler: (data: TeachingStateUpdatedEvent) => void): () => void {
    if (isCapacitor()) return capacitorTeachingStateOnUpdated(handler as (data: unknown) => void);
    return typedOn<TeachingStateUpdatedEvent>('teachingState:updated', handler);
  },

  /**
   * 监听精通门控达成事件(RWR-P1-10 / C-4)
   * - Capacitor 端走内存事件总线
   */
  onMastery(handler: (data: TeachingStateMasteryEvent) => void): () => void {
    if (isCapacitor()) return capacitorTeachingStateOnMastery(handler as (data: unknown) => void);
    return typedOn<TeachingStateMasteryEvent>('teachingState:mastery', handler);
  },
};
