/**
 * 流式响应服务
 *
 * 职责：管理 AI 流式响应的发送、中断和完成流程
 * 封装 AbortController 管理，委托 stream-handler.ts 处理具体流式逻辑
 * 从 chat-orchestrator.service.ts 提取，减少主文件职责
 *
 * DI 注册名：'streamHandlerService'
 */

import type { ApiProxy } from '../../../api-proxy';
import type { DiagnosisAnalysis } from '../../../../shared/types/index';
import { handleStreamResponse, handleStreamResponseWithTools, type StreamHandlerDeps, type StreamResult } from './stream-handler';

export class StreamHandlerService {
  private currentAbortController: AbortController | null = null;

  /**
   * 停止当前生成
   */
  stopGeneration(): { stopped: boolean } {
    if (this.currentAbortController) {
      this.currentAbortController.abort();
      this.currentAbortController = null;
      return { stopped: true };
    }
    return { stopped: false };
  }

  /**
   * 处理普通流式响应（无工具调用）
   */
  async handleStream(
    proxy: ApiProxy,
    messages: { role: 'system' | 'user' | 'assistant'; content: string }[],
    deps: StreamHandlerDeps,
    diagnosisAnalysis: DiagnosisAnalysis | null,
    isNarrative: boolean,
    generateId: () => string,
  ): Promise<StreamResult> {
    this.currentAbortController?.abort();
    this.currentAbortController = new AbortController();

    try {
      const result = await handleStreamResponse(
        proxy,
        messages,
        deps,
        diagnosisAnalysis,
        isNarrative,
        this.currentAbortController,
        generateId,
      );
      this.currentAbortController = null;
      return result;
    } catch (error) {
      this.currentAbortController = null;
      throw error;
    }
  }

  /**
   * 处理带工具调用的流式响应
   */
  async handleStreamWithTools(
    proxy: ApiProxy,
    messages: { role: 'system' | 'user' | 'assistant'; content: string; tool_calls?: unknown[]; tool_call_id?: string }[],
    deps: StreamHandlerDeps,
    generateId: () => string,
  ): Promise<StreamResult> {
    this.currentAbortController?.abort();
    this.currentAbortController = new AbortController();

    try {
      const result = await handleStreamResponseWithTools(
        proxy,
        messages,
        deps,
        this.currentAbortController,
        generateId,
      );
      this.currentAbortController = null;
      return result;
    } catch (error) {
      this.currentAbortController = null;
      throw error;
    }
  }
}
