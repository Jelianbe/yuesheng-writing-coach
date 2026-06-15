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
import { ApiProxy } from '../../api-proxy';
import type { ConfigService } from '../../shared/services/config.service';
import { SessionService } from '../../shared/services/session.service';
import { IPC_CHANNELS, MAX_DIAGNOSIS_HISTORY } from '../../../shared/constants';
import type { AttitudeLevel, DiagnosisAnalysis, SyndromeResult, DiagnosisEntry, SeverityLevel } from '../../../shared/types/index';
import type { SyndromeId } from '../../../shared/constants';
import { markDiagnosisPushed } from '../../ipc/utils/diagnosis-dedup';
import { SYNDROME_META, getActionsForSyndrome } from '../../../shared/mappings';
import type { CodexEntry } from '../prompt/codex.service';
import type { IDiagnosisDomain } from '../diagnosis';
import type { ITeachingDomain } from '../teaching';
import type { IStudentDomain } from '../student';
import type { IPromptDomain } from '../prompt';
import { MessageRouter } from './message-router';
import { groupPassagesBySyndrome, getEvidenceForSyndrome } from '../diagnosis/evidence/evidence-grouping';
import * as path from 'path';
import * as fs from 'fs';
import { promises as fsPromises } from 'fs';
import { probeToolSupport } from './chat-tools';
import { handleStreamResponse, handleStreamResponseWithTools } from './stream-handler';
import type { StreamHandlerDeps } from './stream-handler';

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
}

export class ChatOrchestratorService {
  private deps: ChatOrchestratorDeps;
  private apiProxy: ApiProxy | null = null;
  private currentAbortController: AbortController | null = null;
  private techniquePoolData: Array<{
    id: string;
    name: string;
    source: string;
    difficulty: string;
    category: string;
    applicableSyndromes: string[];
    description: string;
    coreId?: string;
  }> | null = null;
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
    deps.teachingDomain.checkMessage(activeSessionId, message, isReflectionPhase);
    const attitude = deps.teachingDomain.getEffectiveAttitude(activeSessionId, userAttitude, isReflectionPhase);

    const { analysis: diagnosisAnalysis, isNarrative } = await this.runDiagnosis(message, activeSessionId);

    const { finalPrompt, isReflectionGate } = this.prepareTeachingContext(diagnosisAnalysis, activeSessionId, attitude, studentContext);

    deps.teachingDomain.checkMessage(activeSessionId, message, isReflectionGate);

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
    filter?: { coreId?: string; syndromeIds?: string[] },
    onChunk?: (chunk: string) => void,
  ): Promise<DiagnosisAnalysis | null> {
    const proxy = this.getApiProxy();
    try {
      const promptPath = path.join(__dirname, '../../../resources/prompts/diagnosis-agent-prompt-v1.md');
      let diagnosisPrompt: string;
      try {
        diagnosisPrompt = await fsPromises.readFile(promptPath, 'utf-8');
        diagnosisPrompt = this.injectTechniquePool(diagnosisPrompt, filter);
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

  private injectTechniquePool(
    prompt: string,
    filter?: { coreId?: string; syndromeIds?: string[] }
  ): string {
    if (!prompt.includes('{{technique_pool}}')) return prompt;

    // 加载技法数据（只加载一次）
    if (!this.techniquePoolData) {
      try {
        const techniquePath = path.join(__dirname, '../../../resources/config/technique-library.json');
        const raw = fs.readFileSync(techniquePath, 'utf-8');
        this.techniquePoolData = JSON.parse(raw) as Array<{
          id: string;
          name: string;
          source: string;
          difficulty: string;
          category: string;
          applicableSyndromes: string[];
          description: string;
          coreId?: string;
        }>;
      } catch (err) {
        console.warn('[TechniquePool] Failed to load technique-library.json:', err);
        return prompt.replace('{{technique_pool}}', '（技法库加载失败，请根据症候自行匹配技法）');
      }
    }

    // 过滤技法
    let filtered = this.techniquePoolData;
    if (filter?.coreId) {
      filtered = filtered.filter(t => t.coreId === filter.coreId);
    }
    if (filter?.syndromeIds && filter.syndromeIds.length > 0) {
      filtered = filtered.filter(t =>
        t.applicableSyndromes.some(s => filter.syndromeIds!.includes(s))
      );
    }

    const lines = filtered.map(t =>
      `- ${t.id} ${t.name}（来源：${t.source}，难度：${t.difficulty}，适用症候：${t.applicableSyndromes.join('/')}）：${t.description}`,
    );
    const poolText = lines.join('\n') || '（无匹配技法）';

    return prompt.replace('{{technique_pool}}', poolText);
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
    this.toolSupportCache = await probeToolSupport(modelName, () => this.getApiProxy(), { value: null });
    return this.toolSupportCache;
  }

  // ─── 教学上下文准备 ───

  private runDiagnosis(
    message: string,
    activeSessionId: string,
  ): Promise<{ analysis: DiagnosisAnalysis | null; isNarrative: boolean }> {
    // 从历史诊断中提取活跃的 syndromeIds 用于技法过滤
    const recentDiagnoses = this.deps.diagnosisDomain.getRecentBySession(activeSessionId, 3);
    const syndromeIdsSet = new Set<string>();
    for (const diag of recentDiagnoses) {
      for (const syndrome of diag.syndromes) {
        syndromeIdsSet.add(syndrome.id);
      }
    }
    const syndromeIds = syndromeIdsSet.size > 0 ? Array.from(syndromeIdsSet) : undefined;

    return this._runDiagnosis(message, activeSessionId, { syndromeIds });
  }

  private async _runDiagnosis(
    message: string,
    activeSessionId: string,
    options?: { syndromeIds?: string[] },
  ): Promise<{ analysis: DiagnosisAnalysis | null; isNarrative: boolean }> {
    const { deps } = this;
    if (!deps || !deps.mainWindow) return { analysis: null, isNarrative: true };

    const analysis = await this.callDiagnosisAgent(message, options);
    const isNarrative = analysis?.contentType !== 'non-narrative';

    if (analysis && isNarrative) {
      const tempMessageId = this.generateId();
      const diagId = deps.diagnosisDomain.save({
        sessionId: activeSessionId,
        messageId: tempMessageId,
        syndromes: [],
        suggestedActions: [],
        confidence: analysis.confidence ?? 0,
        timestamp: new Date().toISOString(),
      });
      deps.diagnosisDomain.saveAnalysis(analysis, diagId);
      const entry = this.analysisToDiagnosisEntry(analysis, activeSessionId, tempMessageId);
      deps.mainWindow.webContents.send(IPC_CHANNELS.DIAGNOSIS_UPDATE, { sessionId: activeSessionId, entry });
      markDiagnosisPushed(activeSessionId);
    }

    return { analysis, isNarrative };
  }

  private formatDiagnosisHistory(diagnoses: DiagnosisEntry[]): string {
    return this.deps.promptDomain.buildCapsule({ diagnoses, recentCount: 3 });
  }

  private prepareTeachingContext(
    diagnosisAnalysis: DiagnosisAnalysis | null,
    activeSessionId: string,
    attitude: AttitudeLevel,
    studentContext?: string,
  ): { finalPrompt: string; isReflectionGate: boolean } {
    const { deps } = this;

    let diagnosisHistory = '';
    const recentDiagnoses = deps.diagnosisDomain.getRecentBySession(activeSessionId, 3);
    diagnosisHistory = this.formatDiagnosisHistory(recentDiagnoses);

    let effectiveStudentContext: string | undefined;
    effectiveStudentContext = deps.studentDomain.toPromptText();
    if (!effectiveStudentContext && studentContext) {
      effectiveStudentContext = studentContext;
    }

    const systemPrompt = deps.promptDomain.loadSystemPrompt(
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
      const gateResult = deps.teachingDomain.shouldTriggerReflection(diagnosisAnalysis);
      if (gateResult.shouldReflect && gateResult.question) {
        isReflectionGate = true;
        reflectionInstruction = deps.teachingDomain.buildReflectionPrompt(gateResult.question, attitude);
      }
    }

    const strategyInstruction = deps.teachingDomain.buildStrategyInstruction(diagnosisAnalysis, attitude);
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

    this.currentAbortController?.abort();
    this.currentAbortController = new AbortController();

    const streamDeps: StreamHandlerDeps = {
      mainWindow: deps.mainWindow,
      sessionId: activeSessionId,
      db: deps.db,
      saveMessage: (sessionId, role, content) => deps.sessionService.saveMessage(sessionId, role, content),
      autoGenerateTitle: (sessionId) => deps.sessionService.autoGenerateTitle(sessionId),
      processAIResponse: (response, sessionId, messageId) => deps.diagnosisDomain.processAIResponse(response, sessionId, messageId),
    };

    try {
      const result = await handleStreamResponse(
        proxy,
        messages,
        streamDeps,
        diagnosisAnalysis,
        isNarrative,
        this.currentAbortController,
        () => this.generateId(),
      );
      this.currentAbortController = null;
      return result;
    } catch (error) {
      this.currentAbortController = null;
      throw error;
    }
  }

  private async handleStreamResponseWithTools(
    messages: { role: 'system' | 'user' | 'assistant'; content: string }[],
    activeSessionId: string,
  ): Promise<{ success: boolean; messageId?: string; sessionId?: string; error?: string }> {
    const proxy = this.getApiProxy();
    const { deps } = this;

    this.currentAbortController?.abort();
    this.currentAbortController = new AbortController();

    const streamDeps: StreamHandlerDeps = {
      mainWindow: deps.mainWindow,
      sessionId: activeSessionId,
      db: deps.db,
      saveMessage: (sessionId, role, content) => deps.sessionService.saveMessage(sessionId, role, content),
      autoGenerateTitle: (sessionId) => deps.sessionService.autoGenerateTitle(sessionId),
      processAIResponse: (response, sessionId, messageId) => deps.diagnosisDomain.processAIResponse(response, sessionId, messageId),
    };

    try {
      const result = await handleStreamResponseWithTools(
        proxy,
        messages,
        streamDeps,
        this.currentAbortController,
        () => this.generateId(),
      );
      this.currentAbortController = null;
      return result;
    } catch (error) {
      this.currentAbortController = null;
      throw error;
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
