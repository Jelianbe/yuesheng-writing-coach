/**
 * 训练服务 — Sprint 32 (移除 serviceBridge/dual-track)
 *
 * 双轨迁移:
 * - Electron 端: typedInvoke → main handler
 * - Android 端: 暂不支持(无 shared 实现)
 *
 * 依据: dev-docs/tasks/sprint-32-plan.md
 */
import { invoke } from './_invoke';
import { isCapacitor } from './_platform';
import type { TrainingRecord } from '../../shared/types/types-training';

export const trainingService = {
  // ─── 教学目标 ───

  /** 创建教学目标 — 失败时返回 null */
  async createObjective(params: { sessionId: string; title: string; description?: string }): Promise<TrainingRecord | null> {
    if (isCapacitor()) { console.warn('[training] createObjective: not supported on Capacitor'); return null; }
    return invoke<TrainingRecord>('training:createObjective', params as Record<string, unknown>) ?? null;
  },

  /** 获取教学目标列表 — 失败时返回 [] */
  async getObjectives(sessionId: string): Promise<TrainingRecord[]> {
    if (isCapacitor()) { console.warn('[training] getObjectives: not supported on Capacitor'); return []; }
    return (await invoke<TrainingRecord[]>('training:getObjectives', { sessionId })) ?? [];
  },

  // ─── 笔记 ───

  /** 创建训练笔记 — 失败时返回 null */
  async createNote(params: { sessionId: string; content: string; type?: 'teaching' | 'reflection' | 'summary' | 'feedback' }): Promise<TrainingRecord | null> {
    if (isCapacitor()) { console.warn('[training] createNote: not supported on Capacitor'); return null; }
    return invoke<TrainingRecord>('training:createNote', params as Record<string, unknown>) ?? null;
  },

  /** 获取训练笔记列表 — 失败时返回 [] */
  async getNotes(sessionId: string): Promise<TrainingRecord[]> {
    if (isCapacitor()) { console.warn('[training] getNotes: not supported on Capacitor'); return []; }
    return (await invoke<TrainingRecord[]>('training:getNotes', { sessionId })) ?? [];
  },

  // ─── 评估 ───

  /** 创建评估结果 — 失败时返回 null */
  async createEvaluation(params: { sessionId: string; score: number; dimension: string; comment?: string }): Promise<TrainingRecord | null> {
    if (isCapacitor()) { console.warn('[training] createEvaluation: not supported on Capacitor'); return null; }
    return invoke<TrainingRecord>('training:createEvaluation', params as Record<string, unknown>) ?? null;
  },

  /** 获取评估结果列表 — 失败时返回 [] */
  async getEvaluations(sessionId: string): Promise<TrainingRecord[]> {
    if (isCapacitor()) { console.warn('[training] getEvaluations: not supported on Capacitor'); return []; }
    return (await invoke<TrainingRecord[]>('training:getEvaluations', { sessionId })) ?? [];
  },

  // ─── 通用 ───

  /** 获取训练历史 — 失败时返回 [] */
  async getHistory(sessionId: string, type?: string): Promise<TrainingRecord[]> {
    if (isCapacitor()) { console.warn('[training] getHistory: not supported on Capacitor'); return []; }
    return (await invoke<TrainingRecord[]>('training:getHistory', { sessionId, type })) ?? [];
  },

  /** 删除训练记录 — 失败时返回 false */
  async remove(recordId: string): Promise<boolean> {
    if (isCapacitor()) { console.warn('[training] remove: not supported on Capacitor'); return false; }
    const result = await invoke<{ success: true }>('training:delete', { recordId });
    return result !== null;
  },
};
