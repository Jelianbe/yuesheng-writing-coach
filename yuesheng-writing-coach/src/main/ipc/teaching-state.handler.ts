/**
 * 教学状态 — Sprint 26 阶段 3.5 方案 4a bridge 注册
 *
 * 原 IPC handler 已废弃,改为 registerMethod 走单端点 bridge:invoke。
 * 调用方:`serviceBridge.invoke('teachingState:get' | 'teachingState:update' | ...)`
 *
 * 依赖: TeachingStateService (DI 注入)
 *
 * 保留 export 函数(被 service-config.ts 使用):
 * - getStoreForPromptLoader(): 给 PromptLoader 用的只读 getter
 * - getTeachingStateContext(): @deprecated
 * - pushTeachingStateUpdate(): @deprecated
 *
 * SEC-DEBT-2: 字段白名单保留
 * Sprint 21 E-1: 载荷脱敏保留
 */

import type { TeachingStateService } from '../domains/03-teaching/teaching-state.service';
import { IPC_CHANNELS } from '../../shared/constants';
import { ACTION_NAMES, ACTION_GOALS, SYNDROME_NAMES } from '../../shared/mappings';
import { registerMethod } from '../core/service-bridge';
import type { TeachingStateUpdateRequest } from '../../shared/api-contracts/teaching-state.contract';
import type { PayloadSanitizer } from '../core/payload-sanitizer.service';

const TEACHING_STATE_UPDATABLE_FIELDS = new Set<string>([
  'currentPhase',
  'currentSubphase',
  'activeProblems',
  'completedActions',
  'nextSuggestedActions',
  'diagnosisSummary',
  'lockedSyndromes',
]);

let teachingStateService: TeachingStateService | null = null;

export function initTeachingStateHandler(service: TeachingStateService): void {
  teachingStateService = service;
}

let teachingStateSanitizer: PayloadSanitizer | null = null;

export function setTeachingStateSanitizer(s: PayloadSanitizer): void {
  teachingStateSanitizer = s;
}

function getService(): TeachingStateService {
  if (!teachingStateService) {
    throw new Error('[TeachingStateIPC] TeachingStateService not initialized. Call initTeachingStateHandler() first.');
  }
  return teachingStateService;
}

export function getStoreForPromptLoader(): { getBySession: (sessionId: string) => unknown } {
  const service = getService();
  return { getBySession: (sessionId: string) => service.getBySession(sessionId) };
}

export function getTeachingStateContext(sessionId: string): {
  currentPhase: string | null;
  currentSubphase: string | null;
  activeProblems: unknown[];
} | null {
  try {
    return getService().getContext(sessionId);
  } catch {
    return null;
  }
}

export function registerTeachingStateHandlers(): void {
  registerMethod('teachingState:get', async (args) => {
    const { sessionId } = args as { sessionId: string };
    const fullState = getService().getFullState(sessionId);
    if (!fullState) throw new Error('Teaching state not found');
    return teachingStateSanitizer?.sanitize('teaching-state', fullState) ?? fullState;
  });

  registerMethod('teachingState:update', async (args) => {
    const { sessionId, updates } = args as TeachingStateUpdateRequest;
    const filtered: Record<string, unknown> = {};
    for (const key of Object.keys(updates)) {
      if (TEACHING_STATE_UPDATABLE_FIELDS.has(key)) {
        filtered[key] = (updates as Record<string, unknown>)[key];
      }
    }
    const updated = getService().update(sessionId, filtered);
    if (!updated) throw new Error('Teaching state not found');
    return updated;
  });

  registerMethod('teachingState:confirm', async (args) => {
    const { sessionId } = args as { sessionId: string };
    const service = getService();
    const result = service.confirmPhase(sessionId);
    const mainWindow = service.getMainWindow();
    if (mainWindow) {
      const { newState } = result;
      mainWindow.webContents.send(IPC_CHANNELS.TEACHING_STATE_UPDATED, {
        ...newState,
        phaseName: service.getPhaseName(newState.currentPhase),
        subphaseName: service.getSubphaseName(newState.currentSubphase),
        phaseProgress: service.calculatePhaseProgress(newState.currentPhase, newState.currentSubphase),
      });
    }
    return result;
  });

  registerMethod('teachingState:getPrompt', async (args) => {
    const { sessionId } = args as { sessionId: string };
    const service = getService();
    const state = service.getOrCreate(sessionId);
    const builder = service.getPromptBuilder();
    return builder.buildSystemPrompt(
      state,
      (id: string) => (ACTION_NAMES as Record<string, string>)[id] || id,
      (id: string) => (ACTION_GOALS as Record<string, string>)[id] || '',
      (id: string) => SYNDROME_NAMES[id] || id,
    );
  });

  registerMethod('teachingState:updateSummary', async (args) => {
    const { sessionId, newContent } = args as { sessionId: string; newContent: string };
    const service = getService();
    const state = service.getBySession(sessionId);
    if (!state) throw new Error('Teaching state not found');

    const builder = service.getPromptBuilder();
    const newSummary = builder.updateDiagnosisSummary(state.diagnosisSummary, newContent);
    service.update(sessionId, { diagnosisSummary: newSummary });
    return service.getBySession(sessionId);
  });
}

export function pushTeachingStateUpdate(sessionId: string): void {
  try {
    const service = getService();
    const mainWindow = service.getMainWindow();
    if (!mainWindow) return;

    const state = service.getBySession(sessionId);
    if (!state) return;

    mainWindow.webContents.send(IPC_CHANNELS.TEACHING_STATE_UPDATED, {
      ...state,
      phaseName: service.getPhaseName(state.currentPhase),
      subphaseName: service.getSubphaseName(state.currentSubphase),
      phaseProgress: service.calculatePhaseProgress(state.currentPhase, state.currentSubphase),
    });
  } catch (error) {
    console.error('[TeachingStateIPC] pushTeachingStateUpdate error:', error);
  }
}
