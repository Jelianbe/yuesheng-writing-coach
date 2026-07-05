/**
 * Chat HandleTurn Bridge — Sprint 20 A-4
 *
 * 桥接 ConversationOrchestrator (主进程) 与 ChatPage (renderer):
 * - Sprint 21 D-1:默认持有 RealOrchestratorAdapter(包装真实 ChatOrchestratorService)
 * - Sprint 20 A-4 阶段持有 MockConversationOrchestrator(现已 @legacy,仅测试桩)
 * - 调用 handleTurn(input) 拿到 AsyncIterable<OrchestratorEvent>
 * - 通过 webContents.send('chat:event', payload) 推送事件流给 renderer
 * - 关联 streamId 让 renderer 区分多轮 turn
 *
 * 错误隔离:推送失败不抛,仅 console.warn 记录
 */

import type { BrowserWindow, WebContents } from 'electron';
import { IPC_CHANNELS } from '../../../../shared/constants';
// Sprint 21 D-1:RealOrchestratorAdapter 取代 MockConversationOrchestrator
import { RealOrchestratorAdapter } from './real-orchestrator-adapter';
// @legacy 兼容路径:MockConversationOrchestrator 仅用于测试桩(无 deps 时回退)
import { MockConversationOrchestrator } from './mock-orchestrator';
import type { ChatOrchestratorService } from '../chat/chat-orchestrator.service';
import type { SkillRegistry } from './skill-registry';
import type { ConversationOrchestrator, HandleTurnInput } from './orchestrator.types';

export class ChatHandleTurnBridge {
  private readonly orchestrator: ConversationOrchestrator;
  private activeStreamIds: Set<string> = new Set();

  /**
   * Sprint 21 D-1:接受 ChatOrchestratorService + 可选 SkillRegistry
   * 默认构造时自动包装为 RealOrchestratorAdapter
   * 旧版"接受任意 orchestrator 实例"接口保留为兼容路径(测试桩场景)
   */
  constructor(orchestrator?: ConversationOrchestrator, deps?: {
    chatOrchestrator: ChatOrchestratorService;
    skillRegistry?: SkillRegistry;
  }) {
    if (orchestrator) {
      // 兼容路径:测试桩(mock 或 自定义 orchestrator)
      this.orchestrator = orchestrator;
    } else if (deps) {
      // Sprint 21 D-1:生产路径,包装真实 ChatOrchestratorService
      this.orchestrator = new RealOrchestratorAdapter(deps.chatOrchestrator, deps.skillRegistry);
    } else {
      // @legacy 兜底:无 deps 时回退 mock(向后兼容老调用方,如未注入 chatOrchestrator)
      this.orchestrator = new MockConversationOrchestrator();
    }
  }

  /** 暴露底层 orchestrator,供测试/查询用 */
  getOrchestrator(): ConversationOrchestrator {
    return this.orchestrator;
  }

  /**
   * 启动一轮 handleTurn,流式推送事件到 webContents
   * @returns streamId 用于关联推送事件
   */
  async startTurn(
    webContents: WebContents | null,
    input: HandleTurnInput,
  ): Promise<{ streamId: string }> {
    const streamId = `stream_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
    this.activeStreamIds.add(streamId);

    // 异步消费事件流(不阻塞 invoke 返回)
    void this.consumeAndEmit(webContents, streamId, input);

    return { streamId };
  }

  /**
   * 启动一轮 handleTurn,流式推送事件到 BrowserWindow
   * (从 mainWindow.webContents 取 webContents 后转发)
   */
  async startTurnToWindow(
    mainWindow: BrowserWindow | null,
    input: HandleTurnInput,
  ): Promise<{ streamId: string }> {
    return this.startTurn(mainWindow && !mainWindow.isDestroyed() ? mainWindow.webContents : null, input);
  }

  /** 停止所有活跃流(供 chat:stop 调用) */
  stopAll(): { stopped: number } {
    const count = this.activeStreamIds.size;
    this.activeStreamIds.clear();
    try {
      this.orchestrator.stopGeneration();
    } catch (e) {
      console.warn('[ChatHandleTurnBridge] stopGeneration failed:', e);
    }
    return { stopped: count };
  }

  /** 当前活跃流数量(供测试) */
  get activeStreamCount(): number {
    return this.activeStreamIds.size;
  }

  private async consumeAndEmit(
    webContents: WebContents | null,
    streamId: string,
    input: HandleTurnInput,
  ): Promise<void> {
    try {
      for await (const event of this.orchestrator.handleTurn(input)) {
        if (!this.activeStreamIds.has(streamId)) break;
        this.emit(webContents, streamId, input.sessionId, event);
        if (event.type === 'done' || event.type === 'error') break;
      }
    } catch (e) {
      console.warn('[ChatHandleTurnBridge] consume failed:', e);
      this.emit(webContents, streamId, input.sessionId, {
        type: 'error',
        payload: { code: 'API_ERROR', message: String(e), retryable: false },
      });
    } finally {
      this.activeStreamIds.delete(streamId);
    }
  }

  private emit(
    webContents: WebContents | null,
    streamId: string,
    sessionId: string,
    event: unknown,
  ): void {
    if (!webContents || webContents.isDestroyed()) return;
    try {
      webContents.send(IPC_CHANNELS.CHAT_EVENT, {
        streamId,
        sessionId,
        event,
      });
    } catch (e) {
      console.warn('[ChatHandleTurnBridge] emit failed:', e);
    }
  }
}
