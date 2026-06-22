/**
 * 流式响应处理器
 *
 * 职责：处理 AI 流式响应，包括普通流和工具调用流
 * 从 chat-orchestrator.service.ts 提取，减少主文件行数
 *
 * Q-02 增强：
 * - 超时检测（STREAM_TIMEOUT）
 * - 超时时发送中文错误消息
 */

import type { BrowserWindow } from 'electron';
import type Database from 'better-sqlite3';
import type { ApiProxy} from '../../../api-proxy';
import { type AccumulatedToolCall } from '../../../api-proxy';
import { IPC_CHANNELS } from '../../../../shared/constants';
import type { DiagnosisAnalysis, DiagnosisEntry } from '../../../../shared/types/index';
import { toolHandlers, TOOLS_DEFINITIONS } from './chat-tools';

const MAX_TOOL_ROUNDS = 3;

/** Q-02: 流式响应超时阈值（毫秒） */
const STREAM_TIMEOUT_MS = 60_000;

import type { MessageRole } from '../../../../shared/types';
import { getUserFacingErrorMessage } from '../../../../shared/error-codes';

export interface StreamHandlerDeps {
  mainWindow: BrowserWindow | null;
  sessionId: string;
  db: Database.Database;
  saveMessage: (sessionId: string, role: MessageRole, content: string) => void;
  autoGenerateTitle: (sessionId: string) => void;
  processAIResponse: (response: string, sessionId: string, messageId: string) => { diagnosisId: string; diagnosis: DiagnosisEntry } | undefined;
}

export interface StreamResult {
  success: boolean;
  messageId?: string;
  sessionId?: string;
  error?: string;
}

/**
 * 处理普通流式响应（无工具调用）
 */
export async function handleStreamResponse(
  proxy: ApiProxy,
  messages: { role: 'system' | 'user' | 'assistant'; content: string }[],
  deps: StreamHandlerDeps,
  diagnosisAnalysis: DiagnosisAnalysis | null,
  isNarrative: boolean,
  abortController: AbortController,
  generateId: () => string,
): Promise<StreamResult> {
  const messageId = generateId();
  // B-lite: 每个流一个唯一 ID，用于前端流锁(R-02)
  const streamId = generateId();
  let fullResponse = '';

  let timeoutId: ReturnType<typeof setTimeout> | null = null;

  try {
    // Q-02: 超时检测 — STREAM_TIMEOUT_MS 后自动中断
    timeoutId = setTimeout(() => {
      abortController.abort(new DOMException('timeout', 'AbortError'));
    }, STREAM_TIMEOUT_MS);

    if (diagnosisAnalysis && isNarrative) {
      deps.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_DATA, {
        sessionId: deps.sessionId,
        chunk: `\u{1F4CB} 分析摘要：${diagnosisAnalysis.rootCause}\n\n---\n\n`,
        eventType: 'text',
        streamId,
      });
    }

    for await (const chunk of proxy.chatStream(messages, abortController.signal)) {
      fullResponse += chunk;
      deps.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_DATA, {
        sessionId: deps.sessionId,
        chunk,
        eventType: 'text',
        streamId,
      });
    }

    if (timeoutId) clearTimeout(timeoutId);
    deps.saveMessage(deps.sessionId, 'assistant', fullResponse);
    deps.autoGenerateTitle(deps.sessionId);

    // B-lite: 处理诊断后若提取到 JSON，发送 json_block 事件(R-01)
    try {
      const result = deps.processAIResponse(fullResponse, deps.sessionId, messageId);
      if (result?.diagnosis) {
        deps.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_DATA, {
          sessionId: deps.sessionId,
          chunk: `\`\`\`json\n${JSON.stringify(result.diagnosis, null, 2)}\n\`\`\``,
          eventType: 'json_block',
          streamId,
        });
      }
    } catch (err) {
      console.error('[Chat] Diagnosis processing failed:', err);
    }

    deps.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_END, {
      sessionId: deps.sessionId,
      fullResponse,
      messageId,
      streamId,
    });

    return { success: true, messageId, sessionId: deps.sessionId };
  } catch (error) {
    if (timeoutId) clearTimeout(timeoutId);
    const isAbort = error instanceof Error && error.name === 'AbortError';
    if (isAbort) {
      const isTimeout = error instanceof DOMException && error.message === 'timeout';
      if (isTimeout) {
        console.warn(`[Chat] Stream timeout after ${STREAM_TIMEOUT_MS}ms`);
        const errorMessage = getUserFacingErrorMessage('ERR_STREAM_TIMEOUT');
        deps.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_END, {
          sessionId: deps.sessionId,
          fullResponse,
          messageId,
          streamId,
          error: errorMessage,
        });
        return { success: false, error: errorMessage };
      }
      console.log(`[Chat] Stream aborted by user, partial=${fullResponse.length}chars`);
      if (fullResponse) {
        deps.saveMessage(deps.sessionId, 'assistant', fullResponse);
      }
      deps.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_END, {
        sessionId: deps.sessionId,
        fullResponse,
        messageId,
        streamId,
        aborted: true,
      });
      return { success: true, messageId, sessionId: deps.sessionId };
    }

    const errorMessage = getUserFacingErrorMessage(error);
    deps.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_END, {
      sessionId: deps.sessionId,
      fullResponse,
      messageId,
      streamId,
      error: errorMessage,
    });
    return { success: false, error: errorMessage };
  }
}

/**
 * 处理带工具调用的流式响应
 */
export async function handleStreamResponseWithTools(
  proxy: ApiProxy,
  messages: { role: 'system' | 'user' | 'assistant' | 'tool'; content: string; tool_calls?: unknown[]; tool_call_id?: string }[],
  deps: StreamHandlerDeps,
  abortController: AbortController,
  generateId: () => string,
): Promise<StreamResult> {
  const messageId = generateId();
  // B-lite: 每个流一个唯一 ID，用于前端流锁(R-02)
  const streamId = generateId();
  let fullResponse = '';

  let timeoutId: ReturnType<typeof setTimeout> | null = null;

  try {
    // Q-02: 超时检测 — STREAM_TIMEOUT_MS 后自动中断
    timeoutId = setTimeout(() => {
      abortController.abort(new DOMException('timeout', 'AbortError'));
    }, STREAM_TIMEOUT_MS);

    for (let round = 0; round <= MAX_TOOL_ROUNDS; round++) {
      let currentRoundText = '';
      const toolCallsInRound: AccumulatedToolCall[] = [];

      for await (const event of proxy.chatStreamWithTools(messages, TOOLS_DEFINITIONS, abortController.signal)) {
        if (event.type === 'text') {
          currentRoundText += event.content;
          fullResponse += event.content;
          deps.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_DATA, {
            sessionId: deps.sessionId,
            chunk: event.content,
            eventType: 'text',
            streamId,
          });
        } else if (event.type === 'tool_calls') {
          toolCallsInRound.push(...event.toolCalls);
        }
      }

      if (toolCallsInRound.length === 0) break;

      for (const tc of toolCallsInRound) {
        deps.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_TOOL_EXECUTING, {
          toolName: tc.function.name,
          args: tc.function.arguments,
        });
      }

      for (const tc of toolCallsInRound) {
        const fnName = tc.function.name;
        let args: unknown = {};
        try {
          args = JSON.parse(tc.function.arguments);
        } catch (e) {
          // JSON解析失败，保持空对象
          console.warn('[stream-handler] Failed to parse tool arguments:', e);
        }

        const handler = toolHandlers[fnName];
        const result = handler ? await handler(args, deps.db) : { error: `Unknown tool: ${fnName}` };

        deps.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_TOOL_EXECUTING, {
          toolName: fnName,
          status: 'end',
        });

        messages.push({
          role: 'assistant',
          content: null as unknown as string,
          tool_calls: [{ id: tc.id, type: 'function', function: { name: tc.function.name, arguments: tc.function.arguments } }],
        });
        messages.push({ role: 'tool', tool_call_id: tc.id, content: JSON.stringify(result) });
      }
    }

    if (timeoutId) clearTimeout(timeoutId);
    deps.saveMessage(deps.sessionId, 'assistant', fullResponse);
    deps.autoGenerateTitle(deps.sessionId);

    // B-lite: 处理诊断后若提取到 JSON，发送 json_block 事件(R-01)
    try {
      const result = deps.processAIResponse(fullResponse, deps.sessionId, messageId);
      if (result?.diagnosis) {
        deps.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_DATA, {
          sessionId: deps.sessionId,
          chunk: `\`\`\`json\n${JSON.stringify(result.diagnosis, null, 2)}\n\`\`\``,
          eventType: 'json_block',
          streamId,
        });
      }
    } catch (err) {
      console.error('[Chat] Diagnosis processing failed:', err);
    }

    deps.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_END, {
      sessionId: deps.sessionId,
      fullResponse,
      messageId,
      streamId,
    });

    return { success: true, messageId, sessionId: deps.sessionId };
  } catch (error) {
    if (timeoutId) clearTimeout(timeoutId);
    const isAbort = error instanceof Error && error.name === 'AbortError';
    if (isAbort) {
      const isTimeout = error instanceof DOMException && error.message === 'timeout';
      if (isTimeout) {
        console.warn(`[ToolCall] Stream timeout after ${STREAM_TIMEOUT_MS}ms`);
        const errorMessage = getUserFacingErrorMessage('ERR_STREAM_TIMEOUT');
        deps.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_END, {
          sessionId: deps.sessionId,
          fullResponse,
          messageId,
          streamId,
          error: errorMessage,
        });
        return { success: false, error: errorMessage };
      }
      console.log(`[ToolCall] Stream aborted by user, partial=${fullResponse.length}chars`);
      if (fullResponse) {
        deps.saveMessage(deps.sessionId, 'assistant', fullResponse);
      }
      deps.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_END, {
        sessionId: deps.sessionId,
        fullResponse,
        messageId,
        streamId,
        aborted: true,
      });
      return { success: true, messageId, sessionId: deps.sessionId };
    }

    const errorMessage = getUserFacingErrorMessage(error);
    deps.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_END, {
      sessionId: deps.sessionId,
      fullResponse,
      messageId,
      streamId,
      error: errorMessage,
    });
    return { success: false, error: errorMessage };
  }
}
