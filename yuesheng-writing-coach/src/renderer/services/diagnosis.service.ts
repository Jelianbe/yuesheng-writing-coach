/**
 * 诊断服务 — Sprint 32 (移除 serviceBridge/dual-track)
 *
 * 双轨迁移:
 * - Electron 端: typedInvoke → main handler
 * - Android 端: 暂不支持(无 shared 实现)
 *
 * 依据: dev-docs/tasks/sprint-32-plan.md
 */
import { invoke } from './_invoke';
import { typedOn } from './ipc-client';
import { isCapacitor } from './_platform';
import type { DiagnosisEntry, DiagnosisUpdateEvent } from '../../shared/api-contracts/diagnosis.contract';

export const diagnosisService = {
  /** 诊断文本 — 失败时返回 null */
  async query(text: string): Promise<DiagnosisEntry | null> {
    if (isCapacitor()) {
      console.warn('[diagnosis] query: not supported on Capacitor');
      return null;
    }
    return invoke<DiagnosisEntry>('diagnosis:query', { text }) ?? null;
  },

  /** 提交改写 — 失败时返回 null */
  async submitRewrite(sessionId: string, original: string, rewritten: string): Promise<{ success: boolean } | null> {
    if (isCapacitor()) {
      console.warn('[diagnosis] submitRewrite: not supported on Capacitor');
      return null;
    }
    return invoke<{ success: boolean }>('diagnosis:submitRewrite', { sessionId, original, rewritten }) ?? null;
  },

  /** 获取改写对比 — 失败时返回 null */
  async getComparison(sessionId: string): Promise<{ originals: string[]; rewrites: string[] } | null> {
    if (isCapacitor()) {
      console.warn('[diagnosis] getComparison: not supported on Capacitor');
      return null;
    }
    return invoke<{ originals: string[]; rewrites: string[] }>('diagnosis:getComparison', { sessionId }) ?? null;
  },

  /** 监听诊断更新 — 返回 cleanup 函数 */
  onDiagnosisUpdate(handler: (data: DiagnosisUpdateEvent) => void): () => void {
    if (isCapacitor()) {
      console.warn('[diagnosis] onDiagnosisUpdate: not supported on Capacitor');
      return () => {};
    }
    return typedOn<DiagnosisUpdateEvent>('diagnosis:updated', handler);
  },
};
