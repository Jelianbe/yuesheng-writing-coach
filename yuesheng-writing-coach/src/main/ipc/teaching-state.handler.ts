/**
 * 教学状态 IPC 处理器
 * 负责：注册教学状态相关的 IPC 通道，处理主进程与渲染进程之间的通信
 * 依赖：electron.ipcMain, TeachingStateService (DI 注入)
 *
 * 设计说明：
 * - 依赖通过 initTeachingStateHandler() 注入，消除模块级变量（store/promptBuilder/mainWindow）
 * - 内部实现全部委托给 TeachingStateService（DI 容器管理）
 * - 此文件仅负责 IPC 通道注册，不持有业务状态
 */

import { TeachingStateService } from '../domains/teaching/teaching-state.service';
import { IPC_CHANNELS } from '../../shared/constants';
import { ACTION_NAMES, ACTION_GOALS, SYNDROME_NAMES } from '../../shared/mappings';
import { createHandler } from './utils/create-handler';

/** DI 注入的教学状态服务 */
let teachingStateService: TeachingStateService | null = null;

/**
 * 初始化教学状态处理器（DI 注入入口）
 * 必须在 registerTeachingStateHandlers 之前调用
 */
export function initTeachingStateHandler(service: TeachingStateService): void {
  teachingStateService = service;
}

/**
 * 获取教学状态服务实例
 */
function getService(): TeachingStateService {
  if (!teachingStateService) {
    throw new Error('[TeachingStateIPC] TeachingStateService not initialized. Call initTeachingStateHandler() first.');
  }
  return teachingStateService;
}

/**
 * 提供只读 Store getter 给 PromptLoader
 * （不暴露 Store 实例本身，只提供 getBySession 方法）
 */
export function getStoreForPromptLoader(): { getBySession: (sessionId: string) => unknown } {
  const service = getService();
  return { getBySession: (sessionId: string) => service.getBySession(sessionId) };
}

/**
 * 获取教学状态的上下文信息（只读）
 * 用于替代 getStoreInstance 暴露，仅返回需要的字段
 * @deprecated 应通过 TeachingStateService.getContext() 获取
 */
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

/**
 * 注册教学状态相关的 IPC 处理器
 * 应在主进程初始化时调用
 */
export function registerTeachingStateHandlers(): void {
  /**
   * 获取教学状态
   */
  createHandler(
    IPC_CHANNELS.TEACHING_STATE_GET,
    (_event, args: { sessionId: string }) => {
      const fullState = getService().getFullState(args.sessionId);
      if (!fullState) throw new Error('Teaching state not found');
      return fullState;
    },
  );

  /**
   * 更新教学状态
   */
  createHandler(
    IPC_CHANNELS.TEACHING_STATE_UPDATE,
    (_event, args: { sessionId: string; updates: Record<string, unknown> }) => {
      const updated = getService().update(args.sessionId, args.updates as any);
      if (!updated) throw new Error('Teaching state not found');
      return updated;
    },
  );

  /**
   * 用户确认完成当前阶段，推进状态
   */
  createHandler(
    IPC_CHANNELS.TEACHING_STATE_CONFIRM,
    (_event, args: { sessionId: string }) => {
      const service = getService();
      const result = service.confirmPhase(args.sessionId);
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
    },
  );

  /**
   * 获取 System Prompt 注入内容
   */
  createHandler(
    IPC_CHANNELS.TEACHING_STATE_GET_PROMPT,
    (_event, args: { sessionId: string }) => {
      const service = getService();
      const state = service.getOrCreate(args.sessionId);
      const builder = service.getPromptBuilder();
      const promptContent = builder.buildSystemPrompt(
        state,
        (id: string) => (ACTION_NAMES as Record<string, string>)[id] || id,
        (id: string) => (ACTION_GOALS as Record<string, string>)[id] || '',
        (id: string) => SYNDROME_NAMES[id] || id,
      );
      return promptContent;
    },
  );

  /**
   * 更新诊断摘要
   */
  createHandler(
    IPC_CHANNELS.TEACHING_STATE_UPDATE_SUMMARY,
    (_event, args: { sessionId: string; newContent: string }) => {
      const service = getService();
      const state = service.getBySession(args.sessionId);
      if (!state) throw new Error('Teaching state not found');

      const builder = service.getPromptBuilder();
      const newSummary = builder.updateDiagnosisSummary(state.diagnosisSummary, args.newContent);
      service.update(args.sessionId, { diagnosisSummary: newSummary });
      return service.getBySession(args.sessionId);
    },
  );
}

/**
 * 推送教学状态更新到渲染进程
 * @deprecated 应直接通过 TeachingStateService 推送
 */
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

