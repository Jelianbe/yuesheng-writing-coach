/**
 * 教学状态服务
 * 负责：集中管理 TeachingStateStore、PromptBuilder、MainWindow 等教学状态相关依赖
 * 消除原先 teaching-state.handler.ts 中的模块级变量模式
 * DI 注册名：'teachingStateService'
 *
 * T15-C.4 改造：注入 ability-atlas loader，把教学状态与能力图谱关联。
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

// T15-C.4: 注入能力图谱 loader
import { getAbilitiesBySyndrome } from '../02-prescription/ability-atlas/ability-atlas.loader';

export interface TeachingStateContext {
  currentPhase: string | null;
  currentSubphase: string | null;
  activeProblems: unknown[];
}

export interface TeachingStateReadContext {
  getBySession: (sessionId: string) => TeachingState | null;
}

/** 能力图谱亮点（与活跃症候关联） */
export interface AbilityHighlight {
  syndromeId: string;
  syndromeName?: string;
  abilities: Array<{
    atlasId: string;
    prototypeId?: string;
    name: string;
    category: string;
    level: number;
    trainingFocus: string;
  }>;
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

  /**
   * T15-C.4: 获取与活跃症候关联的能力图谱亮点
   *
   * 遍历当前会话的 activeProblems，提取每个症候对应的能力节点。
   * 用于 ProgressWorkspace 等消费方展示"用户在训练什么能力"。
   */
  getAbilityHighlights(sessionId: string): AbilityHighlight[] {
    try {
      const state = this.getStore().getBySession(sessionId);
      if (!state?.activeProblems) return [];

      const highlights: AbilityHighlight[] = [];
      const seen = new Set<string>(); // 去重 abilityId

      for (const problem of state.activeProblems) {
        // activeProblems 元素是 ActiveProblem 类型：syndromeId 字段实际名为 id（T15-C.6 修复）
        const sid = (problem as { id?: string; syndromeId?: string }).id
          ?? (problem as { syndromeId?: string }).syndromeId;
        const sname = (problem as { syndromeId?: string; name?: string }).name;
        if (!sid) continue;

        const abilities = getAbilitiesBySyndrome(sid);
        if (abilities.length === 0) continue;

        highlights.push({
          syndromeId: sid,
          syndromeName: sname,
          abilities: abilities
            .filter(a => !seen.has(a.atlasId))
            .map(a => {
              seen.add(a.atlasId);
              return {
                atlasId: a.atlasId,
                prototypeId: a.prototypeId,
                name: a.name,
                category: a.category,
                level: a.level,
                trainingFocus: a.trainingFocus,
              };
            }),
        });
      }

      return highlights;
    } catch (e) {
      console.warn('[TeachingStateService] getAbilityHighlights failed:', e);
      return [];
    }
  }

  /**
   * T15-C.4: 获取完整状态（含能力图谱亮点）
   * 在 getFullState 基础上追加 abilityHighlights 字段。
   */
  getFullStateWithAbilities(
    sessionId: string,
  ): ((TeachingState & {
    phaseName: string;
    subphaseName: string;
    phaseProgress: number;
    abilityHighlights: AbilityHighlight[];
  }) | null) {
    const base = this.getFullState(sessionId);
    if (!base) return null;
    return {
      ...base,
      abilityHighlights: this.getAbilityHighlights(sessionId),
    };
  }
}
