/**
 * 学生上下文服务
 *
 * 封装学生上下文相关的 IPC 通信和本地管理。
 */

import { typedInvoke } from './ipc-client';
import type { ApiResponse } from '../../shared/api-contracts/base';

const CHANNEL = {
  load: 'studentContext:load' as const,
  save: 'studentContext:save' as const,
  toJSON: 'studentContext:toJSON' as const,
};

export const studentContextService = {
  /** 加载学生上下文 */
  async load(): Promise<unknown> {
    const result = await typedInvoke<Record<string, never>, unknown>(
      CHANNEL.load,
      {},
    );
    if (!result.success) {
      throw new Error(result.error);
    }
    return result.data;
  },

  /** 保存学生上下文 */
  async save(data: unknown): Promise<void> {
    const result = await typedInvoke<{ data: unknown }, void>(
      CHANNEL.save,
      { data },
    ) as ApiResponse<void>;
    if (!result.success) {
      throw new Error(result.error);
    }
  },

  /** 获取学生上下文的 JSON 表示 */
  async toJSON(): Promise<string> {
    const result = await typedInvoke<Record<string, never>, { text: string }>(
      CHANNEL.toJSON,
      {},
    );
    if (!result.success) {
      throw new Error(result.error);
    }
    return result.data.text;
  },
};
