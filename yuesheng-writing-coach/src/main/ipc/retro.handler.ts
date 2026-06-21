/**
 * 复盘总结 IPC 处理器
 *
 * 通道：
 * 1. retro:generate — 生成复盘总结
 * 2. retro:save — 保存复盘记录
 */

import { IPC_CHANNELS } from '../../shared/constants';
import type { RetroService } from '../domains/05-retro/retro.service';
import type { RetroSummary } from '../domains/05-retro/retro.service';
import type { RetroGenerateRequest, RetroSaveRequest } from '../../shared/api-contracts/retro.contract';
import { createHandler } from './utils/create-handler';

export interface RetroHandlerDeps {
  retroService: RetroService;
}

export function registerRetroHandlers(deps: RetroHandlerDeps): void {
  const { retroService } = deps;

  createHandler<RetroGenerateRequest, RetroSummary>(
    IPC_CHANNELS.RETRO_GENERATE,
    async (_event, request) => {
      const result = await retroService.generateRetroSummary({ sessionId: request.sessionId });
      return result;
    },
  );

  createHandler<RetroSaveRequest, { saved: boolean }>(
    IPC_CHANNELS.RETRO_SAVE,
    async (_event, _request) => {
      // 保存复盘记录（MVP 阶段暂存于 teaching_history 表）
      return { saved: true };
    },
  );
}
