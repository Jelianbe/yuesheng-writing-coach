/**
 * 聊天编排服务
 *
 * 职责：管理聊天发送/停止的完整流程编排
 * 核心流程通过委托给专职服务实现（单一职责）
 *
 * DI 注册名：'chatOrchestratorService'
 */

import type { BrowserWindow } from 'electron';
import type Database from 'better-sqlite3';
import { ApiProxy } from '../../../api-proxy';
import type { ConfigService } from '../../../shared/services/config.service';
import type { SessionService } from '../../../shared/services/session.service';
import type { AttitudeLevel } from '../../../../shared/types/index';
import type { IDiagnosisDomain } from '../../01-diagnosis';
import type { ITeachingDomain } from '../../03-teaching';
import type { IStudentDomain } from '../../02-prescription/student';
import type { IPromptDomain } from '../../03-teaching/prompt';
import type { MessageRouter } from './message-router';
import { probeToolSupport } from './chat-tools';
import type { StreamHandlerDeps } from './stream-handler';
import type { DiagnosisOrchestratorService } from '../../01-diagnosis/orchestrator/diagnosis-orchestrator.service';
import type { TeachingContextService } from './teaching-context.service';
import type { StreamHandlerService } from './stream-handler.service';
import { truncateChapterContent } from '../prompt/truncation';
// Sprint 20 A-3: 事件订阅 API
import type { OrchestratorEvent } from '../conversation/orchestrator.types';

export interface ChatOrchestratorDeps {
  configService: ConfigService;
  sessionService: SessionService;
  messageRouter: MessageRouter;
  diagnosisDomain: IDiagnosisDomain;
  promptDomain: IPromptDomain;
  studentDomain: IStudentDomain;
  teachingDomain: ITeachingDomain;
  mainWindow: BrowserWindow | null;
  db: Database.Database;
  diagnosisOrchestrator: DiagnosisOrchestratorService;
  teachingContext: TeachingContextService;
  streamHandler: StreamHandlerService;
}

export class ChatOrchestratorService {
  private deps: ChatOrchestratorDeps;
  private apiProxy: ApiProxy | null = null;
  private toolSupportCache: boolean | null = null;
  // Sprint 20 A-3: 事件订阅者列表(教学状态机/审计/未来的 A-4 ChatPage 都从这里订阅)
  private orchestratorEventSubscribers: Set<(e: OrchestratorEvent, sessionId: string) => void> = new Set();

  constructor(deps: ChatOrchestratorDeps) {
    this.deps = deps;
  }

  /**
   * Sprint 20 A-3: 订阅 OrchestratorEvent
   * @param handler 事件处理函数
   * @returns unsubscribe
   */
  onOrchestratorEvent(handler: (e: OrchestratorEvent, sessionId: string) => void): () => void {
    this.orchestratorEventSubscribers.add(handler);
    return () => {
      this.orchestratorEventSubscribers.delete(handler);
    };
  }

  /**
   * Sprint 20 A-3: 派发事件给所有订阅者(handler 异常隔离)
   */
  private emitOrchestratorEvent(event: OrchestratorEvent, sessionId: string): void {
    for (const handler of this.orchestratorEventSubscribers) {
      try {
        handler(event, sessionId);
      } catch (e) {
        console.warn('[ChatOrchestrator] subscriber handler failed:', e);
      }
    }
  }

  /** 设置主窗口（在窗口创建后调用） */
  setMainWindow(win: BrowserWindow | null): void {
    this.deps.mainWindow = win;
  }

  updateApiProxyConfig(): void {
    const config = this.deps.configService.getConfig();
    if (this.apiProxy) {
      this.apiProxy.updateConfig(config);
    } else {
      this.apiProxy = new ApiProxy(config);
    }
  }

  private getApiProxy(): ApiProxy {
    if (!this.apiProxy) {
      const config = this.deps.configService.getConfig();
      this.apiProxy = new ApiProxy(config);
    }
    return this.apiProxy;
  }

  // ─── 公开 API ───

  /**
   * 发送消息（完整编排流程）
   */
  async sendMessage(args: {
    message: string;
    sessionId: string;
    history?: { role: string; content: string }[];
    attitudeLevel?: AttitudeLevel;
    studentContext?: string;
    /**
     * Sprint 21 D-1: 可选 token 回调,由 RealOrchestratorAdapter 注入以桥接 token 流
     * 不传则走既有 chat:stream IPC 路径(向后兼容)
     */
    onToken?: (chunk: string) => void;
  }): Promise<{ messageId: string }> {
    const { deps } = this;
    if (!deps.mainWindow) throw new Error('Main window not available');

    let { message, sessionId, history, attitudeLevel, studentContext, onToken } = args;

    // 解析章节引用
    const resolvedMessage = this.resolveChapterReference(message);
    if (resolvedMessage !== message) {
      message = resolvedMessage;
    }

    if (!sessionId) {
      console.error('[ChatSend] Missing sessionId in payload - message will be lost on reload');
      throw new Error('MISSING_SESSION_ID: sessionId is required');
    }
    const activeSessionId = sessionId;
    deps.sessionService.saveMessage(activeSessionId, 'user', message.trim());

    const userAttitude = attitudeLevel ?? deps.configService.getConfig().attitudeLevel;

    const isReflectionPhase = false;
    deps.teachingDomain.checkMessage(activeSessionId, message, isReflectionPhase);
    const attitude = deps.teachingDomain.getEffectiveAttitude(activeSessionId, userAttitude, isReflectionPhase);

    // 诊断分析
    const syndromeIds = deps.diagnosisOrchestrator.extractSyndromeIds(activeSessionId);
    const { analysis: diagnosisAnalysis, isNarrative } = await deps.diagnosisOrchestrator.analyze(
      this.getApiProxy(),
      message,
      activeSessionId,
      { syndromeIds },
    );

    // 教学上下文准备
    const { finalPrompt, isReflectionGate } = deps.teachingContext.prepare(
      diagnosisAnalysis,
      activeSessionId,
      attitude,
      studentContext,
    );

    deps.teachingDomain.checkMessage(activeSessionId, message, isReflectionGate);

    const messages = this.buildMessageArray(finalPrompt, history, message);

    // 流式响应
    const proxy = this.getApiProxy();
    const streamDeps = this.createStreamHandlerDeps(activeSessionId, onToken);

    // 根据模型兼容性选择流式入口
    const useTools = await this.probeToolSupport(deps.configService.getConfig().modelName);
    const result = useTools
      ? await deps.streamHandler.handleStreamWithTools(proxy, messages, streamDeps, () => this.generateId())
      : await deps.streamHandler.handleStream(proxy, messages, streamDeps, diagnosisAnalysis, isNarrative, () => this.generateId());

    if (!result.success) throw new Error(result.error || 'Chat send failed');

    // Sprint 20 A-3 试点:emit OrchestratorEvent 给订阅者
    // 试点:sendMessage 完成时发出 intent:none 作为"机制验证"事件
    // 后续 S21+ 将替换为真实 intent 提取(基于 IntentRouter 输出)
    this.emitOrchestratorEvent(
      { type: 'intent', payload: { type: 'none' } },
      activeSessionId,
    );

    return { messageId: result.messageId! };
  }

  /**
   * 停止当前生成
   */
  stopGeneration(): { stopped: boolean } {
    return this.deps.streamHandler.stopGeneration();
  }

  /**
   * Onboarding 分析
   */
  async handleOnboardingAnalyze(text: string): Promise<{ summary: string }> {
    if (!text.trim()) {
      return {
        summary: '没关系，你可以后面再发文字给我看。你现在最想提升哪方面？',
      };
    }

    try {
      const proxy = this.getApiProxy();
      const timeoutSignal = AbortSignal.timeout(20_000);

      const onboardingPrompt = `你是一个专业的写作教练月笙，正在认识一位新用户。

用户发来了一段自己的文字，请你分析：

1. 指出 2 个具体的优点（要具体、有说服力，结合原文举例）
2. 指出 1-2 个温和的可提升点（不说教，不打击）
3. 最后问用户最想提升哪个方面

要求：
- 用温暖、鼓励但真实的教练口吻
- 分析要具体，不要泛泛而谈说"文笔不错"这种没信息量的话
- 不要用格式化列表（不要用 ✅ ⚠️），用自然语言
- 控制在 100-200 字`;

      const messages = [
        { role: 'system' as const, content: onboardingPrompt },
        { role: 'user' as const, content: `这是我写的一段文字：\n\n${text}` },
      ];

      let fullResponse = '';
      for await (const chunk of proxy.chatStream(messages, timeoutSignal)) {
        fullResponse += chunk;
      }

      const summary = fullResponse.trim();
      if (!summary) throw new Error('AI returned empty response');
      return { summary };
    } catch (err) {
      console.warn('[onboarding:analyze] AI 分析失败，降级:', err);
      return {
        summary: '我看了你的这段文字，有具体的场景和对话，能看出你在认真写。写作的提升是一个持续的过程，你现在最想提升哪方面？我可以在后面的对话中给你针对性的建议。',
      };
    }
  }

  // ─── 消息构建 ───

  private buildMessageArray(
    finalPrompt: string,
    history: { role: string; content: string }[] | undefined,
    message: string,
  ): { role: 'system' | 'user' | 'assistant'; content: string }[] {
    const messages: { role: 'system' | 'user' | 'assistant'; content: string }[] = [
      { role: 'system', content: finalPrompt },
    ];

    if (history) {
      for (const msg of history) {
        if (msg.role === 'user' || msg.role === 'assistant') {
          messages.push({ role: msg.role, content: msg.content });
        }
      }
    }

    messages.push({ role: 'user', content: message });
    return messages;
  }

  // ─── 工具调用 ───

  private async probeToolSupport(modelName: string): Promise<boolean> {
    if (this.toolSupportCache !== null) return this.toolSupportCache;
    this.toolSupportCache = await probeToolSupport(modelName, () => this.getApiProxy(), { value: null });
    return this.toolSupportCache;
  }

  // ─── 数据处理 ───

  private resolveChapterReference(message: string): string {
    const chapterPattern = /\/chapters\/([a-f0-9-]{36})/gi;
    const allMatches = Array.from(message.matchAll(chapterPattern));
    if (allMatches.length === 0) return message;

    let resolved = message;
    const db = this.deps.db;

    for (const match of allMatches) {
      const fullMatch = match[0];
      const chapterId = match[1];

      try {
        const row = db.prepare('SELECT id, title, content FROM chapters WHERE id = ?').get(chapterId) as
          { id: string; title: string; content: string } | undefined;

        if (!row) {
          console.warn(`[ChapterResolve] Chapter not found: ${chapterId}`);
          resolved = resolved.replace(fullMatch, `（章节 ${chapterId} 未找到）`);
          continue;
        }

        const chapterContent = row.content?.trim() || '';
        if (!chapterContent) {
          console.warn(`[ChapterResolve] Chapter ${chapterId} has no content`);
          resolved = resolved.replace(fullMatch, `（章节「${row.title}」内容为空）`);
          continue;
        }

        // ADR-003 D 阶段：长文截断（hard-cap + warn）
        const { text: truncatedContent, truncated } = truncateChapterContent(chapterContent, {
          chapterId,
          source: 'chat-orchestrator.resolveChapterReference',
        });
        if (truncated) {
          console.warn(
            `[ChapterResolve] Chapter ${chapterId} truncated: ${chapterContent.length} -> ${truncatedContent.length}`,
          );
        }
        resolved = resolved.replace(fullMatch, truncatedContent);
      } catch (err) {
        console.error('[ChapterResolve] Failed to load chapter:', err);
      }
    }

    return resolved;
  }

  private generateId(): string {
    return `msg_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
  }

  private createStreamHandlerDeps(
    sessionId: string,
    onToken?: (chunk: string) => void,
  ): StreamHandlerDeps {
    const { deps } = this;
    return {
      mainWindow: deps.mainWindow,
      sessionId,
      db: deps.db,
      saveMessage: (sid, role, content) => deps.sessionService.saveMessage(sid, role, content),
      autoGenerateTitle: (sid) => deps.sessionService.autoGenerateTitle(sid),
      processAIResponse: (response, sid, messageId) => deps.diagnosisDomain.processAIResponse(response, sid, messageId),
      onToken,
    };
  }
}
