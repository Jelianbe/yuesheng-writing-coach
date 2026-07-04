/**
 * 复盘总结 — Sprint 26 阶段 3.5 方案 4a bridge 注册
 *
 * 原 IPC handler 已废弃,改为 registerMethod 走单端点 bridge:invoke。
 * 调用方:`serviceBridge.invoke('retro:generate' | 'retro:save', ...)`
 *
 * 依赖: RetroService (DI 注入)
 */

import type { RetroService } from '../domains/05-retro/retro.service';
import { validatePayload } from './utils/validate-payload';
import { registerMethod } from '../core/service-bridge';

let retroService: RetroService | null = null;

export function initRetroHandlers(d: { retroService: RetroService }): void {
  retroService = d.retroService;
}

export function registerRetroHandlers(): void {
  registerMethod('retro:generate', async (args) => {
    const validation = validatePayload<{ sessionId: string }>(args, {
      required: ['sessionId'],
      types: { sessionId: 'string' },
    });
    if (!validation.valid) {
      throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    }

    if (!retroService) {
      throw new Error('RetroService not initialized');
    }
    return retroService.generateRetroSummary({ sessionId: validation.data.sessionId });
  });

  registerMethod('retro:save', async (_args) => {
    // MVP: 复盘记录暂存于 teaching_history 表(RetroService 内部处理)
    return { saved: true } satisfies { saved: boolean };
  });
}
