/**
 * 聊天 IPC 处理器
 * 负责：用户消息发送、AI 流式响应、诊断 Agent 调用
 *
 * 新架构：
 *   - Prompt 加载由 PromptLoader 负责
 *   - 消息路由由 MessageRouter 负责
 *   - chat.handler 只负责流程编排
 */

import { BrowserWindow } from 'electron';
import Database from 'better-sqlite3';
import { ApiProxy, type ChatCompletionTool, type AccumulatedToolCall } from '../api-proxy';
import type { ConfigService } from '../services/config.service';
import { SessionService } from '../services/session.service';
import { IPC_CHANNELS, MAX_DIAGNOSIS_HISTORY } from '../../shared/constants';
import type { AttitudeLevel, DiagnosisAnalysis, SyndromeResult, DiagnosisEntry, SeverityLevel } from '../../renderer/shared/types';
import type { SyndromeId } from '../../shared/constants';
import { validatePayload } from './utils/validate-payload';
import { createHandler } from './utils/create-handler';
import { processDiagnosisFromAI } from './diagnosis.handler';
import { markDiagnosisPushed } from './utils/diagnosis-dedup';
import { DiagnosisService } from '../services/diagnosis.service';
import { getMemoryCapsuleService } from '../services/memory-capsule.service';
import { SYNDROME_META, getActionsForSyndrome, SYNDROME_NAMES } from '../../shared/mappings';
import { PromptLoader } from '../services/prompt-loader';
import { CodexEntry } from '../services/codex.service';
import { MessageRouter } from '../services/message-router';
import { StudentModelService } from '../services/student-model.service';
import { TeachingStrategyService, StrategyInput } from '../services/teaching-strategy.service';
import { ProblemPrioritizer } from '../services/problem-prioritizer.service';
import { groupPassagesBySyndrome, getEvidenceForSyndrome } from '../services/evidence-grouping';
import { DisputeTrackerService } from '../services/dispute-tracker.service';
import { ReflectionGateService } from '../services/reflection-gate.service';
import * as path from 'path';
import * as fs from 'fs';
import { promises as fsPromises } from 'fs';

export interface ChatHandlerDeps {
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
  mainWindow: BrowserWindow | null;
  db: Database.Database;
}

let deps: ChatHandlerDeps | null = null;

export function initChatHandlers(d: ChatHandlerDeps): void {
  deps = d;
}

let _apiProxy: ApiProxy | null = null;
let currentAbortController: AbortController | null = null;

export function getApiProxy(): ApiProxy {
  if (!_apiProxy) {
    const config = deps!.configService.getConfig();
    _apiProxy = new ApiProxy(config);
  }
  return _apiProxy;
}

/**
 * 调用 Diagnosis Agent 分析文本
 */
async function callDiagnosisAgent(
  userText: string,
  onChunk?: (chunk: string) => void,
): Promise<DiagnosisAnalysis | null> {
  const proxy = getApiProxy();
  try {
    const promptPath = path.join(__dirname, '../../../resources/prompts/diagnosis-agent-prompt-v1.md');
    let diagnosisPrompt: string;
    try {
      diagnosisPrompt = await fsPromises.readFile(promptPath, 'utf-8');
      // 注入技法库：替换 {{technique_pool}} 占位符
      diagnosisPrompt = injectTechniquePool(diagnosisPrompt);
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

/**
 * 构建记忆胶囊（PE-009）
 *
 * 委托给 MemoryCapsuleService，将最近诊断摘要 + 当前聚焦问题
 * 封装为结构化记忆胶囊，替代原有的纯诊断历史。
 *
 * 策略：最近 3 次诊断摘要 + 当前聚焦 + 教学建议
 */
function formatDiagnosisHistory(diagnoses: DiagnosisEntry[]): string {
  const capsuleService = getMemoryCapsuleService();
  return capsuleService.buildCapsule({ diagnoses, recentCount: 3 });
}

/** 技法库缓存（懒加载） */
let techniquePoolCache: string | null = null;

/**
 * 注入技法库到 Diagnosis Agent Prompt
 *
 * 将 {{technique_pool}} 占位符替换为从 technique-library.json 加载的技法列表
 * 懒加载 + 缓存，避免每次请求都读文件
 */
function injectTechniquePool(prompt: string): string {
  if (!prompt.includes('{{technique_pool}}')) {
    return prompt;
  }

  if (!techniquePoolCache) {
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
      techniquePoolCache = lines.join('\n');
    } catch (err) {
      console.warn('[TechniquePool] Failed to load technique-library.json:', err);
      techniquePoolCache = '（技法库加载失败，请根据症候自行匹配技法）';
    }
  }

  return prompt.replace('{{technique_pool}}', techniquePoolCache);
}

/**
 * 将 DiagnosisAnalysis 转换为 DiagnosisEntry
 */
function analysisToDiagnosisEntry(
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

function generateId(): string {
  return `msg_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
}

/**
 * 构建教学策略指令
 * 整合 Router 三层决策输出
 */
function buildStrategyInstruction(
  diagnosisAnalysis: DiagnosisAnalysis | null,
  attitude: AttitudeLevel,
): string | null {
  if (!deps) return null;

  const proficiency = deps.studentModelService.inferProficiency();
  const cognitiveStyle = deps.studentModelService.inferCognitiveStyle();

  const strategyInput: StrategyInput = {
    proficiency: proficiency.level,
    cognitiveStyle: cognitiveStyle.style,
    topSyndromeCount: diagnosisAnalysis?.syndromeRef.length ?? 0,
    frustrationIndex: 0,
    attitude: attitude,
  };

  const decision = deps.teachingStrategyService.decide(strategyInput);

  let instruction = '---\n## 教学策略指令\n\n';

  // 1. 症候类型入口指令（R-004~R-006）
  if (decision.entryInstruction) {
    instruction += `${decision.entryInstruction}\n\n`;
  }

  // 2. 教学模式
  const modeInstructions: Record<string, string> = {
    scaffolding: '请使用支架模式：给出具体示范和结构化步骤，让用户模仿',
    guiding: '请使用引导模式：用提问引导用户自己发现答案，不给示范',
    challenging: '请使用挑战模式：给出变形条件，要求用户在约束下创作',
  };
  instruction += `- 教学模式：${modeInstructions[decision.mode] ?? decision.mode}\n`;

  // 3. 语气
  const toneInstructions: Record<string, string> = {
    encouraging: '使用鼓励的语气，多肯定用户的进步',
    direct: '使用直接简洁的语气，直击问题核心',
    logical: '使用逻辑化的语气，以推理和结构化方式表达',
    resonant: '使用共鸣的语气，通过案例和情感连接来表达',
  };
  instruction += `- 语气：${toneInstructions[decision.tone] ?? decision.tone}\n`;

  // 4. 步骤序列
  if (decision.parameters?.stepSequence && decision.parameters.stepSequence.length > 0) {
    instruction += '- 建议步骤：' + decision.parameters.stepSequence.map(s => s.stepName).join(' → ') + '\n';
  }

  // 5. 核心模式推荐
  if (decision.parameters?.corePatterns && decision.parameters.corePatterns.length > 0) {
    instruction += `- 核心技法模式：${decision.parameters.corePatterns.join('、')}\n`;
  }

  // 6. 输出格式
  const formatInstructions: Record<string, string> = {
    'problem→cause→evidence→solution': '按照"问题→原因→证据→解决方案"的结构输出',
    'example→feeling→demonstration': '按照"案例→感受→示范"的结构输出',
  };
  if (decision.format && formatInstructions[decision.format]) {
    instruction += `- 输出格式：${formatInstructions[decision.format]}\n`;
  }

  // 7. 最高优先级问题 + 聚焦症候
  let hasPrioritizedInfo = false;
  if (diagnosisAnalysis && diagnosisAnalysis.syndromeRef.length > 0) {
    const syndromesForPrioritization = diagnosisAnalysis.syndromeRef.map(ref => ({
      id: ref,
      name: SYNDROME_NAMES[ref] ?? ref,
      occurrenceCount: 1,
      severityHistory: [SYNDROME_META[ref as SyndromeId]?.severity ?? 'L1'],
    }));

    const prioritized = deps.problemPrioritizer.prioritize(syndromesForPrioritization);
    if (prioritized.length > 0) {
      const top = prioritized[0];
      hasPrioritizedInfo = true;
      instruction += `\n**当前最高优先级问题**：${top.tierLabel} — ${top.syndromeId}（${top.name}）\n`;
      instruction += `行动级别：${top.action === 'must_fix' ? '必须先修复' : top.action === 'priority' ? '优先处理' : '可延后'}\n`;
    }
  }

  // 8. Router 聚焦症候（如果存在且与 prioritizer 不冲突）
  if (decision.targetSyndrome) {
    const focus = decision.targetSyndrome;
    if (!hasPrioritizedInfo) {
      instruction += `\n**本次聚焦**：${focus.targetSyndromeName}\n`;
    }
    if (focus.rationale) {
      instruction += `原因：${focus.rationale}\n`;
    }
  }

  instruction += '\n- 核心原则：一次只说一个问题，聚焦当前最高优先级问题。';

  return instruction;
}

/**
 * 步骤0：检测消息中的章节 ID 引用，自动加载章节正文
 *
 * 支持两种使用方式：
 * 1. 消息纯为 /chapters/{uuid} — 用章节正文完全替换消息
 * 2. 消息中混有 /chapters/{uuid} — 替换引用为正文，保留其余文本
 *
 * 例如：
 *   "/chapters/xxx" → "{正文}"
 *   "/chapters/xxx 能读里面吗" → "{正文} 能读里面吗"
 *   "对比 /chapters/xxx 和 /chapters/yyy" → "对比 {正文1} 和 {正文2}"
 */
function resolveChapterReference(message: string): string {
  const chapterPattern = /\/chapters\/([a-f0-9-]{36})/gi;
  // 先查找所有匹配，只有存在引用时才处理
  const allMatches = Array.from(message.matchAll(chapterPattern));
  if (allMatches.length === 0) return message; // 不包含任何章节引用，原样返回

  let resolved = message;
  const db = deps!.db;

  for (const match of allMatches) {
    const fullMatch = match[0];    // /chapters/{uuid}
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

      console.log(`[ChapterResolve] Resolved chapter "${row.title}" (${chapterContent.length} chars)`);
      resolved = resolved.replace(fullMatch, chapterContent);
    } catch (err) {
      console.error('[ChapterResolve] Failed to load chapter:', err);
      // 加载失败时保持原样，不做替换
    }
  }

  if (resolved !== message) {
    console.log(`[ChapterResolve] Total resolved length: ${resolved.length} chars`);
  }
  return resolved;
}

// ============ Tool Calling (Function Calling) ============

/**
 * 工具处理函数映射表
 * 每个工具名→实际执行函数的映射，由 handleStreamResponseWithTools 调用
 */
const toolHandlers: Record<string, (args: unknown) => Promise<unknown>> = {
  readChapter: async (args) => {
    const { chapterId, titleHint } = args as { chapterId?: string; titleHint?: string };
    const db = deps!.db;

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

/**
 * 工具定义列表（注册给 API）
 */
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

let _toolSupportCache: boolean | null = null;

/**
 * 探测当前模型是否支持 tool calling
 *
 * 三层策略：
 * 1. 白名单 → 直接返回 true（免探测）
 * 2. 黑名单 → 直接返回 false
 * 3. 未知模型 → 发一次 test call 确认
 */
async function probeToolSupport(modelName: string): Promise<boolean> {
  if (_toolSupportCache !== null) return _toolSupportCache;

  const lower = modelName.toLowerCase();
  if (TOOL_BLACKLIST.some(b => lower.includes(b))) {
    _toolSupportCache = false;
    return false;
  }
  if (TOOL_WHITELIST.some(w => lower.includes(w))) {
    _toolSupportCache = true;
    return true;
  }

  // 未知模型：发一次 test call
  try {
    const proxy = getApiProxy();
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
    _toolSupportCache = !!data.choices?.[0]?.message?.tool_calls;
  } catch {
    _toolSupportCache = false;
  }
  return _toolSupportCache;
}

/**
 * 带工具调用的流式响应处理（新入口）
 *
 * 与 handleStreamResponse 独立，互不干扰。
 * 流程：流式读取 → 检测 tool_calls → 执行工具 → 回传结果 → 继续流（最多 MAX_TOOL_ROUNDS 轮）
 */
const MAX_TOOL_ROUNDS = 3;

async function handleStreamResponseWithTools(
  messages: { role: 'system' | 'user' | 'assistant'; content: string }[],
  activeSessionId: string,
): Promise<{ success: boolean; messageId?: string; sessionId?: string; error?: string }> {
  const proxy = getApiProxy();
  const messageId = generateId();
  let fullResponse = '';

  currentAbortController?.abort();
  currentAbortController = new AbortController();

  try {
    for (let round = 0; round <= MAX_TOOL_ROUNDS; round++) {
      let currentRoundText = '';
      const toolCallsInRound: AccumulatedToolCall[] = [];

      for await (const event of proxy.chatStreamWithTools(messages, TOOLS_DEFINITIONS, currentAbortController!.signal)) {
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

      // 没有工具调用 → 最终响应，退出循环
      if (toolCallsInRound.length === 0) break;

      // 通知前端工具调用状态
      for (const tc of toolCallsInRound) {
        deps?.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_TOOL_EXECUTING, {
          toolName: tc.function.name,
          args: tc.function.arguments,
        });
      }

      // 执行工具，结果追加到 messages 供下一轮 API 调用
      for (const tc of toolCallsInRound) {
        const fnName = tc.function.name;
        let args: unknown = {};
        try { args = JSON.parse(tc.function.arguments); } catch { /* 解析失败用空对象 */ }

        const handler = toolHandlers[fnName];
        const result = handler ? await handler(args) : { error: `Unknown tool: ${fnName}` };

        // 构造 assistant tool_call 消息 + tool 结果消息
        messages.push({ role: 'assistant', content: null, tool_calls: [{ id: tc.id, type: 'function', function: { name: tc.function.name, arguments: tc.function.arguments } }] } as any);
        messages.push({ role: 'tool', tool_call_id: tc.id, content: JSON.stringify(result) } as any);
      }

      // 保留完整流式文本到 fullResponse，前后端一致性优先
      // 中间轮次的文本（如"让我看看第六章"）同样入库，避免 DB 与前端不一致

      console.log(`[ToolCall] Round ${round + 1}: ${toolCallsInRound.length} tool(s) executed, continuing stream...`);
    }

    currentAbortController = null;

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
      currentAbortController = null;
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

// ============ CHAT_SEND 子步骤提取 ============

/**
 * 步骤1：调用 DiagnosisAgent 分析内容，保存诊断结果
 */
async function runDiagnosis(
  message: string,
  activeSessionId: string,
): Promise<{ analysis: DiagnosisAnalysis | null; isNarrative: boolean }> {
  if (!deps || !deps.mainWindow) return { analysis: null, isNarrative: true };

  // Diagnosis Agent 内部推理过程不流式输出到聊天窗口
  // 诊断结果通过 diagnosis:update 事件单独推送（见下方 analysisToDiagnosisEntry）
  const analysis = await callDiagnosisAgent(message);

  const isNarrative = analysis?.contentType !== 'non-narrative';

  if (analysis && isNarrative) {
    // DEBUG: log diagnostic agent result
    console.log('[DEBUG] DiagnosisAgent analysis:', JSON.stringify({
      rootCause: analysis.rootCause,
      syndromeRef: analysis.syndromeRef,
      keyPassagesCount: analysis.keyPassages?.length ?? 0,
      confidence: analysis.confidence,
    }));

    // 使用唯一 messageId 避免 UNIQUE(session_id, message_id) 约束冲突
    const tempMessageId = generateId();
    const diagId = deps.diagnosisService.save({
      sessionId: activeSessionId,
      messageId: tempMessageId,
      syndromes: [],
      suggestedActions: [],
      confidence: analysis.confidence ?? 0,
      timestamp: new Date().toISOString(),
    });
    deps.diagnosisService.saveAnalysis(analysis, diagId);
    const entry = analysisToDiagnosisEntry(analysis, activeSessionId, tempMessageId);
    console.log('[DEBUG] DiagnosisEntry:', JSON.stringify({
      sessionId: entry.sessionId,
      syndromesCount: entry.syndromes.length,
      syndromes: entry.syndromes.map(s => s.id),
      actionsCount: entry.suggestedActions.length,
    }));
    deps.mainWindow.webContents.send(IPC_CHANNELS.DIAGNOSIS_UPDATE, entry);
    markDiagnosisPushed(activeSessionId);
  }

  return { analysis, isNarrative };
}

/**
 * 步骤2：构建教学上下文
 */
function prepareTeachingContext(
  diagnosisAnalysis: DiagnosisAnalysis | null,
  activeSessionId: string,
  attitude: AttitudeLevel,
  studentContext?: string,
): { finalPrompt: string; isReflectionGate: boolean } {
  if (!deps) throw new Error('ChatHandler deps not initialized');

  let diagnosisHistory = '';
  const recentDiagnoses = deps.diagnosisService.getRecentBySession(activeSessionId, 3);
  diagnosisHistory = formatDiagnosisHistory(recentDiagnoses);

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
    buildCodexEntries(diagnosisHistory, effectiveStudentContext),
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

  const strategyInstruction = buildStrategyInstruction(diagnosisAnalysis, attitude);
  const extraParts = [reflectionInstruction, strategyInstruction].filter(Boolean);
  const finalPrompt = extraParts.length > 0
    ? `${systemPrompt}\n\n${extraParts.join('\n\n')}`
    : systemPrompt;

  return { finalPrompt, isReflectionGate };
}

/**
 * 构建 Codex 知识条目列表（PE-002）
 * 从现有上下文数据中提取结构化条目
 */
function buildCodexEntries(
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

/**
 * 步骤3：组装消息数组
 */
function buildMessageArray(
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

/**
 * 步骤4：流式响应 + 消息持久化 + 错误处理
 */
async function handleStreamResponse(
  messages: { role: 'system' | 'user' | 'assistant'; content: string }[],
  activeSessionId: string,
  diagnosisAnalysis: DiagnosisAnalysis | null,
  isNarrative: boolean,
): Promise<{ success: boolean; messageId?: string; sessionId?: string; error?: string }> {
  const proxy = getApiProxy();
  const messageId = generateId();
  let fullResponse = '';

  // 创建新的 AbortController 用于 CHAT_STOP
  currentAbortController?.abort(); // 取消上一次残留
  currentAbortController = new AbortController();

  try {
    if (diagnosisAnalysis && isNarrative) {
      deps?.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_DATA, {
        sessionId: activeSessionId,
        chunk: `\u{1F4CB} 分析摘要：${diagnosisAnalysis.rootCause}\n\n---\n\n`,
      });
    }

    for await (const chunk of proxy.chatStream(messages, currentAbortController.signal)) {
      fullResponse += chunk;
      deps?.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_DATA, {
        sessionId: activeSessionId,
        chunk,
      });
    }

    // 正常完成，清除 abort controller
    currentAbortController = null;

    deps!.sessionService.saveMessage(activeSessionId, 'assistant', fullResponse);
    deps!.sessionService.autoGenerateTitle(activeSessionId);

    try {
      processDiagnosisFromAI(fullResponse, activeSessionId, messageId);
    } catch (err) {
      console.error('[Chat] Diagnosis processing failed:', err);
    }

    deps?.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_END, {
      sessionId: activeSessionId,
      fullResponse,
      messageId,
    });

    return { success: true, messageId, sessionId: activeSessionId };
  } catch (error) {
    const isAbort = error instanceof Error && error.name === 'AbortError';
    if (isAbort) {
      // 用户主动中断 — 保留已收到的 partial 内容，不报错
      console.log(`[Chat] Stream aborted by user, partial=${fullResponse.length}chars`);
      currentAbortController = null;
      if (fullResponse) {
        deps!.sessionService.saveMessage(activeSessionId, 'assistant', fullResponse);
      }
      deps?.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_END, {
        sessionId: activeSessionId,
        fullResponse,
        messageId,
        aborted: true,
      });
      return { success: true, messageId, sessionId: activeSessionId };
    }

    const errorMessage = error instanceof Error ? error.message : '未知错误';
    deps?.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_END, {
      sessionId: activeSessionId,
      fullResponse,
      messageId,
      error: errorMessage,
    });
    return { success: false, error: errorMessage };
  }
}

// ============ 主 Handler ============

export function registerChatHandlers(): void {
  if (!deps) throw new Error('ChatHandler deps not injected');

  createHandler(IPC_CHANNELS.CHAT_SEND, async (_event, args) => {
    const validation = validatePayload<{
      message: string;
      sessionId: string;
      history?: { role: string; content: string }[];
      attitudeLevel?: AttitudeLevel;
      studentContext?: string;
    }>(args, {
      required: ['message'],
      types: { message: 'string', sessionId: 'string' },
    });
    if (!validation.valid) {
      throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    }

    if (!deps!.mainWindow) throw new Error('Main window not available');

    let { message, sessionId, history, attitudeLevel, studentContext } = validation.data;

    // 解析章节引用：将 /chapters/{uuid} 替换为实际章节正文
    const resolvedMessage = resolveChapterReference(message);
    if (resolvedMessage !== message) {
      message = resolvedMessage;
      console.log('[ChatSend] Message resolved from chapter reference');
    }

    if (!sessionId) {
      console.error('[ChatSend] Missing sessionId in payload - message will be lost on reload');
      throw new Error('MISSING_SESSION_ID: sessionId is required');
    }
    const activeSessionId = sessionId;
    deps!.sessionService.saveMessage(activeSessionId, 'user', message.trim());

    const userAttitude = attitudeLevel ?? deps!.configService.getConfig().attitudeLevel;

    const isReflectionPhase = false;
    deps!.disputeTracker.checkMessage(activeSessionId, message, isReflectionPhase);
    const attitude = deps!.disputeTracker.getEffectiveAttitude(activeSessionId, userAttitude, isReflectionPhase);

    const { analysis: diagnosisAnalysis, isNarrative } = await runDiagnosis(message, activeSessionId);

    const { finalPrompt, isReflectionGate } = prepareTeachingContext(diagnosisAnalysis, activeSessionId, attitude, studentContext);

    deps!.disputeTracker.checkMessage(activeSessionId, message, isReflectionGate);

    const messages = buildMessageArray(finalPrompt, history, message);

    // 根据模型兼容性选择流式入口
    const useTools = await probeToolSupport(deps!.configService.getConfig().modelName);
    const result = useTools
      ? await handleStreamResponseWithTools(messages, activeSessionId)
      : await handleStreamResponse(messages, activeSessionId, diagnosisAnalysis, isNarrative);
    if (!result.success) throw new Error(result.error || 'Chat send failed');
    return { messageId: result.messageId! };
  });

  // CHAT_STOP: 中断当前流式响应
  createHandler(IPC_CHANNELS.CHAT_STOP, () => {
    if (currentAbortController) {
      currentAbortController.abort();
      currentAbortController = null;
      return { stopped: true };
    }
    return { stopped: false };
  });

  // P-04 Phase 3: 引导分析（调用 AI API，带超时 + 降级）
  createHandler(IPC_CHANNELS.ONBOARDING_ANALYZE, async (_event, args) => {
    const validation = validatePayload<{ text: string }>(args, {
      required: ['text'],
      types: { text: 'string' },
    });
    if (!validation.valid) {
      throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    }
    const text = validation.data.text?.trim() ?? '';
    if (!text) {
      return {
        summary: '没关系，你可以后面再发文字给我看。你现在最想提升哪方面？',
      };
    }

    try {
      const proxy = getApiProxy();
      const timeoutSignal = AbortSignal.timeout(20_000); // 20s 超时

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
      if (!summary) {
        throw new Error('AI returned empty response');
      }
      return { summary };
    } catch (err) {
      console.warn('[onboarding:analyze] AI 分析失败，降级:', err);
      // 降级：返回通用但不敷衍的回复
      return {
        summary: '我看了你的这段文字，有具体的场景和对话，能看出你在认真写。写作的提升是一个持续的过程，你现在最想提升哪方面？我可以在后面的对话中给你针对性的建议。',
      };
    }
  });
}

export function refreshApiProxy(): void {
  const config = deps!.configService.getConfig();
  if (_apiProxy) {
    _apiProxy.updateConfig(config);
  } else {
    _apiProxy = new ApiProxy(config);
  }
}

export { markDiagnosisPushed, wasDiagnosisPushed } from './utils/diagnosis-dedup';
