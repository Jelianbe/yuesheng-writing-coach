/**
 * 流式响应处理器
 *
 * 职责：处理 AI 流式响应，包括普通流和工具调用流
 * 从 chat-orchestrator.service.ts 提取，减少主文件行数
 */

import { BrowserWindow } from 'electron';
import { ApiProxy, type AccumulatedToolCall } from '../../api-proxy';
import { IPC_CHANNELS } from '../../../shared/constants';
import type { DiagnosisAnalysis } from '../../../shared/types/index';
import { toolHandlers, TOOLS_DEFINITIONS } from './chat-tools';

const MAX_TOOL_ROUNDS = 3;

import type { MessageRole } from '../../../shared/types';

export interface StreamHandlerDeps {
  mainWindow: BrowserWindow | null;
  sessionId: string;
  db: any; // Database.Database
  saveMessage: (sessionId: string, role: MessageRole, content: string) => void;
  autoGenerateTitle: (sessionId: string) => void;
  processAIResponse: (response: string, sessionId: string, messageId: string) => void;
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
  let fullResponse = '';

  try {
    if (diagnosisAnalysis && isNarrative) {
      deps.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_DATA, {
        sessionId: deps.sessionId,
        chunk: `\u{1F4CB} 分析摘要：${diagnosisAnalysis.rootCause}\n\n---\n\n`,
      });
    }

    for await (const chunk of proxy.chatStream(messages, abortController.signal)) {
      fullResponse += chunk;
      deps.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_DATA, {
        sessionId: deps.sessionId,
        chunk,
      });
    }

    deps.saveMessage(deps.sessionId, 'assistant', fullResponse);
    deps.autoGenerateTitle(deps.sessionId);

    try {
      deps.processAIResponse(fullResponse, deps.sessionId, messageId);
    } catch (err) {
      console.error('[Chat] Diagnosis processing failed:', err);
    }

    deps.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_END, {
      sessionId: deps.sessionId,
      fullResponse,
      messageId,
    });

    return { success: true, messageId, sessionId: deps.sessionId };
  } catch (error) {
    const isAbort = error instanceof Error && error.name === 'AbortError';
    if (isAbort) {
      console.log(`[Chat] Stream aborted by user, partial=${fullResponse.length}chars`);
      if (fullResponse) {
        deps.saveMessage(deps.sessionId, 'assistant', fullResponse);
      }
      deps.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_END, {
        sessionId: deps.sessionId,
        fullResponse,
        messageId,
        aborted: true,
      });
      return { success: true, messageId, sessionId: deps.sessionId };
    }

    const errorMessage = error instanceof Error ? error.message : '未知错误';
    deps.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_END, {
      sessionId: deps.sessionId,
      fullResponse,
      messageId,
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
  messages: { role: 'system' | 'user' | 'assistant'; content: string; tool_calls?: any[]; tool_call_id?: string }[],
  deps: StreamHandlerDeps,
  abortController: AbortController,
  generateId: () => string,
): Promise<StreamResult> {
  const messageId = generateId();
  let fullResponse = '';

  try {
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

        messages.push({
          role: 'assistant',
          content: null,
          tool_calls: [{ id: tc.id, type: 'function', function: { name: tc.function.name, arguments: tc.function.arguments } }],
        } as any);
        messages.push({ role: 'tool', tool_call_id: tc.id, content: JSON.stringify(result) } as any);
      }
    }

    deps.saveMessage(deps.sessionId, 'assistant', fullResponse);
    deps.autoGenerateTitle(deps.sessionId);

    try {
      deps.processAIResponse(fullResponse, deps.sessionId, messageId);
    } catch (err) {
      console.error('[Chat] Diagnosis processing failed:', err);
    }

    deps.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_END, {
      sessionId: deps.sessionId,
      fullResponse,
      messageId,
    });

    return { success: true, messageId, sessionId: deps.sessionId };
  } catch (error) {
    const isAbort = error instanceof Error && error.name === 'AbortError';
    if (isAbort) {
      console.log(`[ToolCall] Stream aborted by user, partial=${fullResponse.length}chars`);
      if (fullResponse) {
        deps.saveMessage(deps.sessionId, 'assistant', fullResponse);
      }
      deps.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_END, {
        sessionId: deps.sessionId,
        fullResponse,
        messageId,
        aborted: true,
      });
      return { success: true, messageId, sessionId: deps.sessionId };
    }

    const errorMessage = error instanceof Error ? error.message : '未知错误';
    deps.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_END, {
      sessionId: deps.sessionId,
      fullResponse,
      messageId,
      error: errorMessage,
    });
    return { success: false, error: errorMessage };
  }
}
