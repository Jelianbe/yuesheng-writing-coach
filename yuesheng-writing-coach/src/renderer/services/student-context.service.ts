/**
 * 学生上下文服务 — Sprint 20 B-2 降级(D-DEBT-34)
 *
 * 重要:本服务载荷包含学生认知风格/信心/挫折计数等敏感数据。
 * 降级策略:调用失败时 console.error + 返回 fallback,不再 throw,
 * 避免 UI 白屏(R-028 防御性编码 + R-027 门禁)。
 *
 * ─── Sprint 26 阶段 3.2 (双轨化决策) ───
 *
 * student-context 业务(认知风格推导/信心更新/JSON 序列化)全部在主进程,
 * 依赖 AI 模型 + 教学状态机。shared 端**无等价 service**。因此本 service
 * **不引入 runDualTrack**,而是:
 *   - 所有方法保持 IPC-only
 *   - Capacitor 端 isCapacitor() 早返回 noop + warn
 *   - 后续 student-context 业务下沉到 shared 时再统一迁移(待 S27+)
 *
 * Capacitor 端已知 trade-off:
 *   - load 降级:无学生上下文,UI 退化
 *   - save 降级:学生状态变更不持久化
 *   - toJSON 降级:无法导出
 *
 * 依据: dev-docs/tasks/sprint-26-phase-3-plan.md §3.2 / D-074
 */

import { typedInvoke } from './ipc-client';
import { isCapacitor } from './_dual-track';
import type { ApiResponse } from '../../shared/api-contracts/base';

const CHANNEL = {
  load: 'studentContext:load' as const,
  save: 'studentContext:save' as const,
  toJSON: 'studentContext:toJSON' as const,
};

/** Capacitor 端无 IPC 通道,统一降级标识 */
function capacitorNoopStudentContext<T>(methodName: string, fallback: T): T {
  console.warn(`[student-context] ${methodName}: not supported on Capacitor (业务全在主进程), returning fallback`);
  return fallback;
}

export const studentContextService = {
  /**
   * 加载学生上下文 — 失败时返回 null(降级)
   *
   * Capacitor 端:降级 noop。
   */
  async load(): Promise<unknown> {
    if (isCapacitor()) return capacitorNoopStudentContext('load', null);
    const result = await typedInvoke<Record<string, never>, unknown>(
      CHANNEL.load,
      {},
    );
    if (!result.success) {
      console.error('[student-context] load failed:', result.error);
      return null;
    }
    return result.data;
  },

  /**
   * 保存学生上下文 — 失败时返回 false(降级)
   *
   * Capacitor 端:降级 noop。
   */
  async save(data: unknown): Promise<boolean> {
    if (isCapacitor()) return capacitorNoopStudentContext('save', false);
    const result = await typedInvoke<{ data: unknown }, void>(
      CHANNEL.save,
      { data },
    ) as ApiResponse<void>;
    if (!result.success) {
      console.error('[student-context] save failed:', result.error);
      return false;
    }
    return true;
  },

  /**
   * 获取学生上下文的 JSON 表示 — 失败时返回 ''(降级)
   *
   * Capacitor 端:降级 noop。
   */
  async toJSON(): Promise<string> {
    if (isCapacitor()) return capacitorNoopStudentContext('toJSON', '');
    const result = await typedInvoke<Record<string, never>, { text: string }>(
      CHANNEL.toJSON,
      {},
    );
    if (!result.success) {
      console.error('[student-context] toJSON failed:', result.error);
      return '';
    }
    return result.data.text;
  },
};
