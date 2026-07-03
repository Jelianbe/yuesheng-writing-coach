/**
 * 学生上下文服务 — Sprint 20 B-2 降级(D-DEBT-34)
 *
 * 重要:本服务载荷包含学生认知风格/信心/挫折计数等敏感数据。
 * 降级策略:调用失败时 console.error + 返回 fallback,不再 throw,
 * 避免 UI 白屏(R-028 防御性编码 + R-027 门禁)。
 */

import { typedInvoke } from './ipc-client';
import type { ApiResponse } from '../../shared/api-contracts/base';

const CHANNEL = {
  load: 'studentContext:load' as const,
  save: 'studentContext:save' as const,
  toJSON: 'studentContext:toJSON' as const,
};

export const studentContextService = {
  /** 加载学生上下文 — 失败时返回 null(降级) */
  async load(): Promise<unknown> {
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

  /** 保存学生上下文 — 失败时返回 false(降级) */
  async save(data: unknown): Promise<boolean> {
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

  /** 获取学生上下文的 JSON 表示 — 失败时返回 ''(降级) */
  async toJSON(): Promise<string> {
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
