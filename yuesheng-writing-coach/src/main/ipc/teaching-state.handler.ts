/**
 * 教学状态 IPC 处理器
 * 负责：注册教学状态相关的 IPC 通道，处理主进程与渲染进程之间的通信
 * 依赖：electron.ipcMain, TeachingStateStore, TeachingStateMachine
 * 安全：仅允许白名单中的通道
 */

import { ipcMain, BrowserWindow } from 'electron';
import Database from 'better-sqlite3';
import { TeachingStateStore } from '../services/teaching-state.store';
import { TeachingState } from '../services/teaching-state.types';
import { DiagnosisMerger } from '../services/diagnosis-merger';
import { apiSuccess, apiError } from '../../renderer/shared/types';
import { IPC_CHANNELS } from '../../shared/constants';
import { ACTION_NAMES, ACTION_GOALS, SYNDROME_NAMES } from '../../shared/mappings';
import { PromptBuilder } from '../services/prompt-builder';
import {
  confirmPhaseComplete,
  getPhaseName,
  getSubphaseName,
  calculatePhaseProgress,
} from '../services/teaching-state-machine';

/** 教学状态存储实例 */
let store: TeachingStateStore | null = null;

/** PromptBuilder 实例 */
let promptBuilder: PromptBuilder | null = null;

/** 主窗口引用 */
let mainWindow: BrowserWindow | null = null;

/**
 * 设置 PromptBuilder 实例
 */
export function setPromptBuilder(builder: PromptBuilder): void {
  promptBuilder = builder;
}

/**
 * 获取 PromptBuilder 实例
 */
export function getPromptBuilder(): PromptBuilder {
  if (!promptBuilder) {
    throw new Error('[TeachingStateIPC] PromptBuilder not initialized. Call setPromptBuilder() first.');
  }
  return promptBuilder;
}

/**
 * 获取教学状态存储实例
 * 需要在 registerTeachingStateHandlers 之前调用 initStore
 */
function getStore(): TeachingStateStore {
  if (!store) {
    throw new Error('[TeachingStateIPC] Store not initialized. Call initStore() first.');
  }
  return store;
}

/**
 * 初始化教学状态存储
 * @param db - better-sqlite3 数据库实例
 */
export function initStore(db: Database.Database): void {
  store = new TeachingStateStore(db);
}

/**
 * 注册 DiagnosisMerger，由 teaching-state.handler 内部提供 getStore 给 DiagnosisMerger
 * 避免将 Store 暴露给外部模块
 */
export function registerDiagnosisMerger(
  setDiagnosisMerger: (merger: DiagnosisMerger) => void,
): void {
  const merger = new DiagnosisMerger(getStore);
  setDiagnosisMerger(merger);
}

/**
 * 提供只读 Store getter 给 PromptLoader
 * （不暴露 Store 实例本身，只提供 getBySession 方法）
 */
export function getStoreForPromptLoader(): { getBySession: (sessionId: string) => unknown } {
  return { getBySession: (sessionId: string) => store?.getBySession(sessionId) };
}

/**
 * 获取教学状态的上下文信息（只读）
 * 用于替代 getStoreInstance 暴露，仅返回需要的字段
 */
export function getTeachingStateContext(sessionId: string): {
  currentPhase: string | null;
  currentSubphase: string | null;
  activeProblems: unknown[];
} | null {
  try {
    const teachingStore = getStore();
    const state = teachingStore.getBySession(sessionId);
    if (!state) return null;
    return {
      currentPhase: state.currentPhase,
      currentSubphase: state.currentSubphase,
      activeProblems: state.activeProblems,
    };
  } catch {
    return null;
  }
}

/**
 * 设置主窗口引用
 */
export function setMainWindow(win: BrowserWindow): void {
  mainWindow = win;
}

/**
 * 注册教学状态相关的 IPC 处理器
 * 应在主进程初始化时调用
 */
export function registerTeachingStateHandlers(): void {
  /**
   * 获取教学状态
   */
  ipcMain.handle(
    IPC_CHANNELS.TEACHING_STATE_GET,
    (_event, args: { sessionId: string }) => {
      try {
        const teachingStore = getStore();
        const state = teachingStore.getOrCreate(args.sessionId);
        return apiSuccess({
          ...state,
          phaseName: getPhaseName(state.currentPhase),
          subphaseName: getSubphaseName(state.currentSubphase),
          phaseProgress: calculatePhaseProgress(state.currentPhase, state.currentSubphase),
        });
      } catch (error) {
        console.error('[TeachingStateIPC] TEACHING_STATE_GET error:', error);
        return apiError('Failed to get teaching state');
      }
    },
  );

  /**
   * 更新教学状态
   */
  ipcMain.handle(
    IPC_CHANNELS.TEACHING_STATE_UPDATE,
    (_event, args: { sessionId: string; updates: Partial<Omit<TeachingState, 'sessionId' | 'updatedAt'>> }) => {
      try {
        const teachingStore = getStore();
        const updatedState = teachingStore.update(args.sessionId, args.updates);
        if (!updatedState) {
          return apiError('Teaching state not found');
        }
        return apiSuccess(updatedState);
      } catch (error) {
        console.error('[TeachingStateIPC] TEACHING_STATE_UPDATE error:', error);
        return apiError(String(error));
      }
    },
  );

  /**
   * 用户确认完成当前阶段，推进状态
   */
  ipcMain.handle(
    IPC_CHANNELS.TEACHING_STATE_CONFIRM,
    (_event, args: { sessionId: string }) => {
      try {
        const teachingStore = getStore();
        const oldState = teachingStore.getBySession(args.sessionId);

        if (!oldState) return apiError('Teaching state not found');

        const newState = confirmPhaseComplete(oldState);
        const updated = teachingStore.update(args.sessionId, {
          currentPhase: newState.currentPhase,
          currentSubphase: newState.currentSubphase,
          completedActions: newState.completedActions,
          nextSuggestedActions: newState.nextSuggestedActions,
          lastUserConfirmation: newState.lastUserConfirmation,
        });

        if (!updated) return apiError('Teaching state not found');

        if (mainWindow) {
          mainWindow.webContents.send(IPC_CHANNELS.TEACHING_STATE_UPDATED, {
            oldState,
            newState: updated,
            phaseName: getPhaseName(updated.currentPhase),
            subphaseName: getSubphaseName(updated.currentSubphase),
            phaseProgress: calculatePhaseProgress(updated.currentPhase, updated.currentSubphase),
          });
        }

        return apiSuccess({ oldState, newState: updated });
      } catch (error) {
        console.error('[TeachingStateIPC] TEACHING_STATE_CONFIRM error:', error);
        return apiError(String(error));
      }
    },
  );

  /**
   * 获取 System Prompt 注入内容
   */
  ipcMain.handle(
    IPC_CHANNELS.TEACHING_STATE_GET_PROMPT,
    (_event, args: { sessionId: string }) => {
      try {
        const teachingStore = getStore();
        const state = teachingStore.getOrCreate(args.sessionId);
        const builder = getPromptBuilder();
        const promptContent = builder.buildSystemPrompt(
          state,
          (id: string) => (ACTION_NAMES as Record<string, string>)[id] || id,
          (id: string) => (ACTION_GOALS as Record<string, string>)[id] || '',
          (id: string) => SYNDROME_NAMES[id] || id,
        );
        return apiSuccess(promptContent);
      } catch (error) {
        console.error('[TeachingStateIPC] TEACHING_STATE_GET_PROMPT error:', error);
        return apiError('Failed to get prompt');
      }
    },
  );

  /**
   * 更新诊断摘要
   */
  ipcMain.handle(
    IPC_CHANNELS.TEACHING_STATE_UPDATE_SUMMARY,
    (_event, args: { sessionId: string; newContent: string }) => {
      try {
        const teachingStore = getStore();
        const state = teachingStore.getBySession(args.sessionId);

        if (!state) return apiError('Teaching state not found');

        const builder = getPromptBuilder();
        const newSummary = builder.updateDiagnosisSummary(state.diagnosisSummary, args.newContent);
        const updatedState = teachingStore.update(args.sessionId, { diagnosisSummary: newSummary });
        return apiSuccess(updatedState);
      } catch (error) {
        console.error('[TeachingStateIPC] TEACHING_STATE_UPDATE_SUMMARY error:', error);
        return apiError(String(error));
      }
    },
  );
}

/**
 * 推送教学状态更新到渲染进程
 */
export function pushTeachingStateUpdate(sessionId: string): void {
  if (!mainWindow) return;

  try {
    const teachingStore = getStore();
    const state = teachingStore.getBySession(sessionId);
    if (!state) return;

    mainWindow.webContents.send(IPC_CHANNELS.TEACHING_STATE_UPDATED, {
      ...state,
      phaseName: getPhaseName(state.currentPhase),
      subphaseName: getSubphaseName(state.currentSubphase),
      phaseProgress: calculatePhaseProgress(state.currentPhase, state.currentSubphase),
    });
  } catch (error) {
    console.error('[TeachingStateIPC] pushTeachingStateUpdate error:', error);
  }
}
