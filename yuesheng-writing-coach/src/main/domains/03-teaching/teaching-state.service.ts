/**
 * 教学状态服务
 * 负责：集中管理 TeachingStateStore、PromptBuilder、MainWindow 等教学状态相关依赖
 * 消除原先 teaching-state.handler.ts 中的模块级变量模式
 * DI 注册名：'teachingStateService'
 */

import type { BrowserWindow } from 'electron';
import type Database from 'better-sqlite3';
import { TeachingStateStore } from './state/teaching-state.store';
import type { TeachingState } from './state/teaching-state.types';
import type { PromptBuilder } from './prompt/prompt-builder';
import {
  confirmPhaseComplete,
  getPhaseName,
  getSubphaseName,
  calculatePhaseProgress,
  downgradeSyndromeSeverity,
} from './state/teaching-state-machine';
import { IPC_CHANNELS } from '../../../shared/constants';

export interface TeachingStateContext {
  currentPhase: string | null;
  currentSubphase: string | null;
  activeProblems: unknown[];
}

export interface TeachingStateReadContext {
  getBySession: (sessionId: string) => TeachingState | null;
}

export class TeachingStateService {
  private store: TeachingStateStore | null = null;
  private promptBuilder: PromptBuilder | null = null;
  private mainWindow: BrowserWindow | null = null;

  /** 初始化存储 */
  initStore(db: Database.Database): void {
    this.store = new TeachingStateStore(db);
  }

  /** 设置 PromptBuilder */
  setPromptBuilder(builder: PromptBuilder): void {
    this.promptBuilder = builder;
  }

  /** 获取 PromptBuilder */
  getPromptBuilder(): PromptBuilder {
    if (!this.promptBuilder) {
      throw new Error('[TeachingStateService] PromptBuilder not initialized.');
    }
    return this.promptBuilder;
  }

  /** 设置主窗口 */
  setMainWindow(win: BrowserWindow): void {
    this.mainWindow = win;
  }

  /** 获取主窗口 */
  getMainWindow(): BrowserWindow | null {
    return this.mainWindow;
  }

  // ─── 存储访问（内部使用） ───

  private getStore(): TeachingStateStore {
    if (!this.store) {
      throw new Error('[TeachingStateService] Store not initialized. Call initStore() first.');
    }
    return this.store;
  }

  // ─── 公开方法 ───

  getOrCreate(sessionId: string): TeachingState {
    return this.getStore().getOrCreate(sessionId);
  }

  getBySession(sessionId: string): TeachingState | null {
    return this.getStore().getBySession(sessionId);
  }

  update(sessionId: string, updates: Partial<Omit<TeachingState, 'sessionId' | 'updatedAt'>>): TeachingState | null {
    return this.getStore().update(sessionId, updates);
  }

  /** 获取只读上下文（给 PromptLoader 用） */
  getReadContext(): TeachingStateReadContext {
    return {
      getBySession: (sessionId: string) => this.getStore().getBySession(sessionId),
    };
  }

  /** 获取教学状态上下文（只读摘要） */
  getContext(sessionId: string): TeachingStateContext | null {
    try {
      const state = this.getStore().getBySession(sessionId);
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

  /** 确认阶段完成，推进状态 */
  confirmPhase(sessionId: string): { oldState: TeachingState; newState: TeachingState } {
    const store = this.getStore();
    const oldState = store.getBySession(sessionId);
    if (!oldState) throw new Error('Teaching state not found');

    const newState = confirmPhaseComplete(oldState);
    store.update(sessionId, {
      currentPhase: newState.currentPhase,
      currentSubphase: newState.currentSubphase,
      completedActions: newState.completedActions,
      nextSuggestedActions: newState.nextSuggestedActions,
      lastUserConfirmation: newState.lastUserConfirmation,
    });
    return { oldState, newState };
  }

  /** 获取阶段名称 */
  getPhaseName(phase: string | null): string {
    return getPhaseName(phase ?? '');
  }

  /** 获取子阶段名称 */
  getSubphaseName(subphase: string | null): string {
    return getSubphaseName(subphase ?? '');
  }

  /** 计算阶段进度 */
  calculatePhaseProgress(currentPhase: string | null, currentSubphase: string | null): number {
    return calculatePhaseProgress(currentPhase ?? '', currentSubphase ?? '');
  }

  /** 降低症候严重度（训练评分触发），自动推送更新到渲染进程 */
  downgradeSeverity(sessionId: string, syndromeId: string, score: number): void {
    try {
      const state = this.getStore().getBySession(sessionId);
      if (!state) return;

      const { activeProblems } = downgradeSyndromeSeverity(state, syndromeId, score);
      this.getStore().update(sessionId, { activeProblems });

      if (this.mainWindow) {
        const updatedState = this.getStore().getBySession(sessionId);
        if (updatedState) {
          this.mainWindow.webContents.send(IPC_CHANNELS.TEACHING_STATE_UPDATED, {
            ...updatedState,
            phaseName: getPhaseName(updatedState.currentPhase ?? ''),
            subphaseName: getSubphaseName(updatedState.currentSubphase ?? ''),
            phaseProgress: calculatePhaseProgress(updatedState.currentPhase ?? '', updatedState.currentSubphase ?? ''),
          });
        }
      }
    } catch (e) {
      console.warn('[TeachingStateService] downgradeSeverity failed:', e);
    }
  }

  /** 获取完整响应（含派生字段） */
  getFullState(sessionId: string): (TeachingState & { phaseName: string; subphaseName: string; phaseProgress: number }) | null {
    try {
      const state = this.getStore().getOrCreate(sessionId);
      return {
        ...state,
        phaseName: getPhaseName(state.currentPhase ?? ''),
        subphaseName: getSubphaseName(state.currentSubphase ?? ''),
        phaseProgress: calculatePhaseProgress(state.currentPhase ?? '', state.currentSubphase ?? ''),
      };
    } catch {
      return null;
    }
  }
}
