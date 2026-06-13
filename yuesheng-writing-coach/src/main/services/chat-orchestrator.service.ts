/**
 * 聊天编排服务
 *
 * 职责：管理聊天发送/停止的完整流程编排
 * 消除 chat.handler.ts 中的模块级变量（_apiProxy, currentAbortController）
 * 所有依赖通过构造函数注入（DI 容器管理）
 *
 * DI 注册名：'chatOrchestratorService'
 */

import { BrowserWindow } from 'electron';
import Database from 'better-sqlite3';
import { ApiProxy, type ChatCompletionTool, type AccumulatedToolCall } from '../api-proxy';
import type { ConfigService } from './config.service';
import { SessionService } from './session.service';
import { IPC_CHANNELS, MAX_DIAGNOSIS_HISTORY } from '../../shared/constants';
import type { AttitudeLevel, DiagnosisAnalysis, SyndromeResult, DiagnosisEntry, SeverityLevel } from '../../renderer/shared/types';
import type { SyndromeId } from '../../shared/constants';
import { processDiagnosisFromAI } from '../ipc/diagnosis.handler';
import { markDiagnosisPushed } from '../ipc/utils/diagnosis-dedup';
import { DiagnosisService } from './diagnosis.service';
import { getMemoryCapsuleService } from './memory-capsule.service';
import { SYNDROME_META, getActionsForSyndrome } from '../../shared/mappings';
import { PromptLoader } from './prompt-loader';
import type { CodexEntry } from './codex.service';
import { MessageRouter } from './message-router';
import { StudentModelService } from './student-model-service';
import { TeachingStrategyService } from './teaching-strategy.service';
import { ProblemPrioritizer } from './problem-prioritizer.service';
import { groupPassagesBySyndrome, getEvidenceForSyndrome } from './evidence-grouping';
import { DisputeTrackerService } from './dispute-tracker.service';
import { ReflectionGateService } from './reflection-gate.service';
import { StrategyInstructionBuilder } from './strategy-instruction-builder';
import * as path from 'path';
import * as fs from 'fs';
import { promises as fsPromises } from 'fs';

export interface ChatOrchestratorDeps {
  configService: ConfigService;
  sessionService: SessionService;
  diagnosisService: DiagnosisService;
  promptLoader: PromptLoader;
  messageRouter: MessageRouter;
  studentModelService: StudentModelService;
  teachingStrategyService: TeachingStrategyService;
  problemPrioritizer: ProblemPrioritizer;
  disputeTracker: DisputeTrackerService;
  reflectionGate: ReflectionGateService;
  strategyInstructionBuilder: StrategyInstructionBuilder;
  mainWindow: BrowserWindow | null;
  db: Database.Database;
}

// ============ Tool Calling 类型 ============

/** 工具处理函数映射表 */
const toolHandlers: Record<string, (args: unknown, db: Database.Database) => Promise<unknown>> = {
  readChapter: async (args, db) => {
    const { chapterId, titleHint } = args as { chapterId?: string; titleHint?: string };

    if (chapterId) {
      const row = db.prepare('SELECT id, title, content FROM chapters WHERE id = ?').get(chapterId) as
        { id: string; title: string; content: string } | undefined;
      if (!row) return { found: false, error: '章节不存在' };
      return { found: true, title: row.title, content: row.content, wordCount: row.content?.length ?? 0 };
    }

    if (titleHint) {
      const row = db.prepare('SELECT id, title, content FROM chapters WHERE title LIKE ? ORDER BY updated_at DESC LIMIT 1').get(`%${titleHint}%`) as
        { id: string; title: string; content: string } | undefined;
      if (!row) return { found: false, error: '未找到匹配章节', titleHint };
      return { found: true, title: row.title, content: row.content, wordCount: row.content?.length ?? 0 };
    }

    const recent = db.prepare('SELECT id, title, length(content) as wordCount FROM chapters ORDER BY updated_at DESC LIMIT 5').all();
    return { found: false, recentChapters: recent, message: '未指定章节，以下是最近的 5 个章节' };
  },
};

/** 工具定义列表 */
const TOOLS_DEFINITIONS: ChatCompletionTool[] = [
  {
    type: 'function',
    function: {
      name: 'readChapter',
      description: '读取用户已保存的章节内容。当用户提到某个章节、作品、或要求看看/分析/读某段文字时调用。如果用户直接给出 /chapters/{uuid} 格式的引用，提取 chapterId；如果是自然语言描述（如"第六章""昨天写的"），用 titleHint 模糊匹配。',
      parameters: {
        type: 'object',
        properties: {
          chapterId: { type: 'string', description: '章节 UUID' },
          titleHint: { type: 'string', description: '章节标题关键词，用于模糊匹配' },
        },
      },
    },
  },
];

/** 白名单模型 — 确定支持 tool calling */
const TOOL_WHITELIST = ['deepseek', 'gpt-', 'claude-'];
/** 黑名单模型 — 确定不支持 tool calling */
const TOOL_BLACKLIST = ['llama-2', 'mixtral-8x7b'];

const MAX_TOOL_ROUNDS = 3;

export class ChatOrchestratorService {
  private deps: ChatOrchestratorDeps;
  private apiProxy: ApiProxy | null = null;
  private currentAbortController: AbortController | null = null;
  private techniquePoolCache: string | null = null;
  private toolSupportCache: boolean | null = null;

  constructor(deps: ChatOrchestratorDeps) {
    this.deps = deps;
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
  }): Promise<{ messageId: string }> {
    const { deps } = this;
    if (!deps.mainWindow) throw new Error('Main window not available');

    let { message, sessionId, history, attitudeLevel, studentContext } = args;

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
    deps.disputeTracker.checkMessage(activeSessionId, message, isReflectionPhase);
    const attitude = deps.disputeTracker.getEffectiveAttitude(activeSessionId, userAttitude, isReflectionPhase);

    const { analysis: diagnosisAnalysis, isNarrative } = await this.runDiagnosis(message, activeSessionId);

    const { finalPrompt, isReflectionGate } = this.prepareTeachingContext(diagnosisAnalysis, activeSessionId, attitude, studentContext);

    deps.disputeTracker.checkMessage(activeSessionId, message, isReflectionGate);

    const messages = this.buildMessageArray(finalPrompt, history, message);

    // 根据模型兼容性选择流式入口
    const useTools = await this.probeToolSupport(deps.configService.getConfig().modelName);
    const result = useTools
      ? await this.handleStreamResponseWithTools(messages, activeSessionId)
      : await this.handleStreamResponse(messages, activeSessionId, diagnosisAnalysis, isNarrative);
    if (!result.success) throw new Error(result.error || 'Chat send failed');
    return { messageId: result.messageId! };
  }

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

  // ─── 诊断 Agent ───

  private async callDiagnosisAgent(
    userText: string,
    onChunk?: (chunk: string) => void,
  ): Promise<DiagnosisAnalysis | null> {
    const proxy = this.getApiProxy();
    try {
      const promptPath = path.join(__dirname, '../../../resources/prompts/diagnosis-agent-prompt-v1.md');
      let diagnosisPrompt: string;
      try {
        diagnosisPrompt = await fsPromises.readFile(promptPath, 'utf-8');
        diagnosisPrompt = this.injectTechniquePool(diagnosisPrompt);
      } catch {
        console.warn('[DiagnosisAgent] Prompt file not found, using fallback');
        diagnosisPrompt = '分析以下文本的写作问题，以JSON格式输出结构化的诊断结果。';
      }

      const messages = [
        { role: 'system' as const, content: diagnosisPrompt },
        { role: 'user' as const, content: userText },
      ];

      let fullResponse = '';
      for await (const chunk of proxy.chatStream(messages)) {
        fullResponse += chunk;
        if (onChunk) onChunk(chunk);
      }

      const jsonMatch = fullResponse.match(/\{[\s\S]*\}/);
      if (!jsonMatch) {
        console.warn('[DiagnosisAgent] No JSON found in response');
        return null;
      }

      return JSON.parse(jsonMatch[0]) as DiagnosisAnalysis;
    } catch (err) {
      console.error('[DiagnosisAgent] Failed to analyze:', err);
      return null;
    }
  }

  private injectTechniquePool(prompt: string): string {
    if (!prompt.includes('{{technique_pool}}')) return prompt;

    if (!this.techniquePoolCache) {
      try {
        const techniquePath = path.join(__dirname, '../../../resources/config/technique-library.json');
        const raw = fs.readFileSync(techniquePath, 'utf-8');
        const techniques = JSON.parse(raw) as Array<{
          id: string;
          name: string;
          source: string;
          difficulty: string;
          category: string;
          applicableSyndromes: string[];
          description: string;
        }>;

        const lines = techniques.map(t =>
          `- ${t.id} ${t.name}（来源：${t.source}，难度：${t.difficulty}，适用症候：${t.applicableSyndromes.join('/')}）：${t.description}`,
        );
        this.techniquePoolCache = lines.join('\n');
      } catch (err) {
        console.warn('[TechniquePool] Failed to load technique-library.json:', err);
        this.techniquePoolCache = '（技法库加载失败，请根据症候自行匹配技法）';
      }
    }

    return prompt.replace('{{technique_pool}}', this.techniquePoolCache);
  }

  private analysisToDiagnosisEntry(
    analysis: DiagnosisAnalysis,
    sessionId: string,
    messageId: string,
  ): DiagnosisEntry {
    const allSuggestedActions: string[] = [];

    const keyPassages = analysis.keyPassages ?? [];
    const passagesBySyndrome = groupPassagesBySyndrome(keyPassages);
    const sharedFallback = keyPassages.slice(0, MAX_DIAGNOSIS_HISTORY).map(kp => kp.text);

    const syndromes: SyndromeResult[] = analysis.syndromeRef.map((ref) => {
      const meta = SYNDROME_META[ref as SyndromeId] ?? { name: ref, severity: 'L1' as SeverityLevel };
      const actions = getActionsForSyndrome(ref);
      allSuggestedActions.push(...actions);

      const evidence = getEvidenceForSyndrome(passagesBySyndrome, ref, sharedFallback);

      return {
        id: ref,
        name: meta.name,
        severity: meta.severity,
        evidence,
        score: analysis.confidence,
        suggestedActions: actions,
      };
    });

    const severityOrder = { L3: 0, L2: 1, L1: 2 };
    syndromes.sort((a, b) => severityOrder[a.severity] - severityOrder[b.severity]);

    const uniqueActions = [...new Set(allSuggestedActions)];

    return {
      sessionId,
      messageId,
      syndromes,
      suggestedActions: uniqueActions,
      timestamp: new Date().toISOString(),
      confidence: analysis.confidence,
    };
  }

  // ─── 工具调用 ───

  private async probeToolSupport(modelName: string): Promise<boolean> {
    if (this.toolSupportCache !== null) return this.toolSupportCache;

    const lower = modelName.toLowerCase();
    if (TOOL_BLACKLIST.some(b => lower.includes(b))) {
      this.toolSupportCache = false;
      return false;
    }
    if (TOOL_WHITELIST.some(w => lower.includes(w))) {
      this.toolSupportCache = true;
      return true;
    }

    try {
      const proxy = this.getApiProxy();
      const response = await fetch(`${proxy.getBaseUrl()}/chat/completions`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${proxy.getApiKey()}`,
        },
        body: JSON.stringify({
          model: modelName,
          messages: [{ role: 'user', content: 'hi' }],
          tools: [{ type: 'function', function: { name: 'ping', description: 'ping', parameters: { type: 'object', properties: {} } } }],
          max_tokens: 10,
          stream: false,
        }),
      });
      const data = await response.json();
      this.toolSupportCache = !!data.choices?.[0]?.message?.tool_calls;
    } catch {
      this.toolSupportCache = false;
    }
    return this.toolSupportCache;
  }

  // ─── 教学上下文准备 ───

  private runDiagnosis(
    message: string,
    activeSessionId: string,
  ): Promise<{ analysis: DiagnosisAnalysis | null; isNarrative: boolean }> {
    return this._runDiagnosis(message, activeSessionId);
  }

  private async _runDiagnosis(
    message: string,
    activeSessionId: string,
  ): Promise<{ analysis: DiagnosisAnalysis | null; isNarrative: boolean }> {
    const { deps } = this;
    if (!deps || !deps.mainWindow) return { analysis: null, isNarrative: true };

    const analysis = await this.callDiagnosisAgent(message);
    const isNarrative = analysis?.contentType !== 'non-narrative';

    if (analysis && isNarrative) {
      const tempMessageId = this.generateId();
      const diagId = deps.diagnosisService.save({
        sessionId: activeSessionId,
        messageId: tempMessageId,
        syndromes: [],
        suggestedActions: [],
        confidence: analysis.confidence ?? 0,
        timestamp: new Date().toISOString(),
      });
      deps.diagnosisService.saveAnalysis(analysis, diagId);
      const entry = this.analysisToDiagnosisEntry(analysis, activeSessionId, tempMessageId);
      deps.mainWindow.webContents.send(IPC_CHANNELS.DIAGNOSIS_UPDATE, entry);
      markDiagnosisPushed(activeSessionId);
    }

    return { analysis, isNarrative };
  }

  private formatDiagnosisHistory(diagnoses: DiagnosisEntry[]): string {
    const capsuleService = getMemoryCapsuleService();
    return capsuleService.buildCapsule({ diagnoses, recentCount: 3 });
  }

  private prepareTeachingContext(
    diagnosisAnalysis: DiagnosisAnalysis | null,
    activeSessionId: string,
    attitude: AttitudeLevel,
    studentContext?: string,
  ): { finalPrompt: string; isReflectionGate: boolean } {
    const { deps } = this;

    let diagnosisHistory = '';
    const recentDiagnoses = deps.diagnosisService.getRecentBySession(activeSessionId, 3);
    diagnosisHistory = this.formatDiagnosisHistory(recentDiagnoses);

    let effectiveStudentContext: string | undefined;
    effectiveStudentContext = deps.studentModelService.toPromptText();
    if (!effectiveStudentContext && studentContext) {
      effectiveStudentContext = studentContext;
    }

    const systemPrompt = deps.promptLoader.loadSystemPrompt(
      attitude,
      diagnosisAnalysis,
      diagnosisHistory,
      effectiveStudentContext,
      activeSessionId,
      undefined,
      this.buildCodexEntries(diagnosisHistory, effectiveStudentContext),
      { hasSession: true, hasDiagnosis: !!diagnosisAnalysis },
    ) ?? '你是一个专业的写作教练月笙，帮助用户提升写作水平。';

    let isReflectionGate = false;
    let reflectionInstruction = '';
    if (diagnosisAnalysis) {
      const gateResult = deps.reflectionGate.shouldTriggerReflection(diagnosisAnalysis);
      if (gateResult.shouldReflect && gateResult.question) {
        isReflectionGate = true;
        reflectionInstruction = deps.reflectionGate.buildReflectionPrompt(gateResult.question, attitude);
      }
    }

    const strategyInstruction = deps.strategyInstructionBuilder.build(diagnosisAnalysis, attitude);
    const extraParts = [reflectionInstruction, strategyInstruction].filter(Boolean);
    const finalPrompt = extraParts.length > 0
      ? `${systemPrompt}\n\n${extraParts.join('\n\n')}`
      : systemPrompt;

    return { finalPrompt, isReflectionGate };
  }

  private buildCodexEntries(
    diagnosisHistory: string,
    studentContext?: string,
  ): CodexEntry[] {
    const entries: CodexEntry[] = [];

    if (diagnosisHistory && !diagnosisHistory.includes('暂无历史诊断记录')) {
      entries.push({
        id: 'diagnosis-latest',
        type: 'diagnosis_history',
        content: diagnosisHistory,
        priority: 1,
        label: '诊断历史（记忆胶囊）',
        format: 'structured',
      });
    }

    if (studentContext) {
      entries.push({
        id: 'student-profile',
        type: 'student_profile',
        content: studentContext,
        priority: 3,
        label: '学生画像',
        format: 'compact',
      });
    }

    return entries;
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

  // ─── 流式响应 ───

  private async handleStreamResponse(
    messages: { role: 'system' | 'user' | 'assistant'; content: string }[],
    activeSessionId: string,
    diagnosisAnalysis: DiagnosisAnalysis | null,
    isNarrative: boolean,
  ): Promise<{ success: boolean; messageId?: string; sessionId?: string; error?: string }> {
    const proxy = this.getApiProxy();
    const { deps } = this;
    const messageId = this.generateId();
    let fullResponse = '';

    this.currentAbortController?.abort();
    this.currentAbortController = new AbortController();

    try {
      if (diagnosisAnalysis && isNarrative) {
        deps?.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_DATA, {
          sessionId: activeSessionId,
          chunk: `\u{1F4CB} 分析摘要：${diagnosisAnalysis.rootCause}\n\n---\n\n`,
        });
      }

      for await (const chunk of proxy.chatStream(messages, this.currentAbortController.signal)) {
        fullResponse += chunk;
        deps?.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_DATA, {
          sessionId: activeSessionId, chunk,
        });
      }

      this.currentAbortController = null;

      deps!.sessionService.saveMessage(activeSessionId, 'assistant', fullResponse);
      deps!.sessionService.autoGenerateTitle(activeSessionId);

      try { processDiagnosisFromAI(fullResponse, activeSessionId, messageId); } catch (err) {
        console.error('[Chat] Diagnosis processing failed:', err);
      }

      deps?.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_END, {
        sessionId: activeSessionId, fullResponse, messageId,
      });

      return { success: true, messageId, sessionId: activeSessionId };
    } catch (error) {
      const isAbort = error instanceof Error && error.name === 'AbortError';
      if (isAbort) {
        console.log(`[Chat] Stream aborted by user, partial=${fullResponse.length}chars`);
        this.currentAbortController = null;
        if (fullResponse) {
          deps!.sessionService.saveMessage(activeSessionId, 'assistant', fullResponse);
        }
        deps?.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_END, {
          sessionId: activeSessionId, fullResponse, messageId, aborted: true,
        });
        return { success: true, messageId, sessionId: activeSessionId };
      }

      const errorMessage = error instanceof Error ? error.message : '未知错误';
      deps?.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_END, {
        sessionId: activeSessionId, fullResponse, messageId, error: errorMessage,
      });
      return { success: false, error: errorMessage };
    }
  }

  private async handleStreamResponseWithTools(
    messages: { role: 'system' | 'user' | 'assistant'; content: string }[],
    activeSessionId: string,
  ): Promise<{ success: boolean; messageId?: string; sessionId?: string; error?: string }> {
    const proxy = this.getApiProxy();
    const { deps } = this;
    const messageId = this.generateId();
    let fullResponse = '';

    this.currentAbortController?.abort();
    this.currentAbortController = new AbortController();

    try {
      for (let round = 0; round <= MAX_TOOL_ROUNDS; round++) {
        let currentRoundText = '';
        const toolCallsInRound: AccumulatedToolCall[] = [];

        for await (const event of proxy.chatStreamWithTools(messages, TOOLS_DEFINITIONS, this.currentAbortController!.signal)) {
          if (event.type === 'text') {
            currentRoundText += event.content;
            fullResponse += event.content;
            deps?.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_DATA, {
              sessionId: activeSessionId, chunk: event.content,
            });
          } else if (event.type === 'tool_calls') {
            toolCallsInRound.push(...event.toolCalls);
          }
        }

        if (toolCallsInRound.length === 0) break;

        for (const tc of toolCallsInRound) {
          deps?.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_TOOL_EXECUTING, {
            toolName: tc.function.name, args: tc.function.arguments,
          });
        }

        for (const tc of toolCallsInRound) {
          const fnName = tc.function.name;
          let args: unknown = {};
          try { args = JSON.parse(tc.function.arguments); } catch { /* 空对象 */ }

          const handler = toolHandlers[fnName];
          const result = handler ? await handler(args, deps!.db) : { error: `Unknown tool: ${fnName}` };

          messages.push({ role: 'assistant', content: null, tool_calls: [{ id: tc.id, type: 'function', function: { name: tc.function.name, arguments: tc.function.arguments } }] } as any);
          messages.push({ role: 'tool', tool_call_id: tc.id, content: JSON.stringify(result) } as any);
        }

      }

      this.currentAbortController = null;

      deps!.sessionService.saveMessage(activeSessionId, 'assistant', fullResponse);
      deps!.sessionService.autoGenerateTitle(activeSessionId);

      try { processDiagnosisFromAI(fullResponse, activeSessionId, messageId); } catch (err) {
        console.error('[Chat] Diagnosis processing failed:', err);
      }

      deps?.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_END, {
        sessionId: activeSessionId, fullResponse, messageId,
      });

      return { success: true, messageId, sessionId: activeSessionId };
    } catch (error) {
      const isAbort = error instanceof Error && error.name === 'AbortError';
      if (isAbort) {
        console.log(`[ToolCall] Stream aborted by user, partial=${fullResponse.length}chars`);
        this.currentAbortController = null;
        if (fullResponse) {
          deps!.sessionService.saveMessage(activeSessionId, 'assistant', fullResponse);
        }
        deps?.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_END, {
          sessionId: activeSessionId, fullResponse, messageId, aborted: true,
        });
        return { success: true, messageId, sessionId: activeSessionId };
      }

      const errorMessage = error instanceof Error ? error.message : '未知错误';
      deps?.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_END, {
        sessionId: activeSessionId, fullResponse, messageId, error: errorMessage,
      });
      return { success: false, error: errorMessage };
    }
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

        resolved = resolved.replace(fullMatch, chapterContent);
      } catch (err) {
        console.error('[ChapterResolve] Failed to load chapter:', err);
      }
    }

    return resolved;
  }

  private generateId(): string {
    return `msg_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
  }
}
