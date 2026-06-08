/**
 * 聊天 IPC 处理器
 * 负责：用户消息发送、AI 流式响应、诊断 Agent 调用
 *
 * 新架构：
 *   - Prompt 加载由 PromptLoader 负责
 *   - 消息路由由 MessageRouter 负责
 *   - chat.handler 只负责流程编排
 */

import { ipcMain, BrowserWindow } from 'electron';
import { ApiProxy } from '../api-proxy';
import type { ConfigService } from '../services/config.service';
import { SessionService } from '../services/session.service';
import { IPC_CHANNELS, MAX_DIAGNOSIS_HISTORY } from '../../shared/constants';
import type { AttitudeLevel, DiagnosisAnalysis, SyndromeResult, DiagnosisEntry, SeverityLevel } from '../../renderer/shared/types';
import { apiSuccess, apiError } from '../../renderer/shared/types';
import type { SyndromeId } from '../../shared/constants';
import { validatePayload } from './utils/validate-payload';
import { processDiagnosisFromAI } from './diagnosis.handler';
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
}

let deps: ChatHandlerDeps | null = null;

export function initChatHandlers(d: ChatHandlerDeps): void {
  deps = d;
}

let _apiProxy: ApiProxy | null = null;

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
    const promptPath = path.join(__dirname, '../../resources/prompts/diagnosis-agent-prompt-v1.md');
    let diagnosisPrompt: string;
    try {
      diagnosisPrompt = fs.readFileSync(promptPath, 'utf-8');
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
      const techniquePath = path.join(__dirname, '../../resources/config/technique-library.json');
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

  const passagesBySyndrome = groupPassagesBySyndrome(analysis.keyPassages);
  const sharedFallback = analysis.keyPassages.slice(0, MAX_DIAGNOSIS_HISTORY).map(kp => kp.text);

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

// ============ CHAT_SEND 子步骤提取 ============

/**
 * 步骤1：调用 DiagnosisAgent 分析内容，保存诊断结果
 */
async function runDiagnosis(
  message: string,
  activeSessionId: string,
): Promise<{ analysis: DiagnosisAnalysis | null; isNarrative: boolean }> {
  if (!deps || !deps.mainWindow) return { analysis: null, isNarrative: true };

  const analysis = await callDiagnosisAgent(message, (chunk) => {
    deps!.mainWindow!.webContents.send(IPC_CHANNELS.CHAT_STREAM_DATA, {
      sessionId: activeSessionId,
      chunk: `\u{1F50D} ${chunk}`,
    });
  });

  const isNarrative = analysis?.contentType !== 'non-narrative';

  if (analysis && isNarrative) {
    // 先 save 拿到 UUID 主键，再用主键更新 analysis（避免空 messageId 批量覆盖）
    const diagId = deps.diagnosisService.save({
      sessionId: activeSessionId,
      messageId: '',
      syndromes: [],
      suggestedActions: [],
      confidence: analysis.confidence ?? 0,
      timestamp: new Date().toISOString(),
    });
    deps.diagnosisService.saveAnalysis(analysis, diagId);
    const entry = analysisToDiagnosisEntry(analysis, activeSessionId, '');
    deps.mainWindow.webContents.send(IPC_CHANNELS.DIAGNOSIS_UPDATE, entry);
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

  try {
    if (diagnosisAnalysis && isNarrative) {
      deps?.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_DATA, {
        sessionId: activeSessionId,
        chunk: `\u{1F4CB} 分析摘要：${diagnosisAnalysis.rootCause}\n\n---\n\n`,
      });
    }

    for await (const chunk of proxy.chatStream(messages)) {
      fullResponse += chunk;
      deps?.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_DATA, {
        sessionId: activeSessionId,
        chunk,
      });
    }

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
    const errorMessage = error instanceof Error ? error.message : '未知错误';
    deps?.mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_END, {
      sessionId: activeSessionId,
      fullResponse: '',
      messageId,
      error: errorMessage,
    });
    return { success: false, error: errorMessage };
  }
}

// ============ 主 Handler ============

export function registerChatHandlers(): void {
  if (!deps) throw new Error('ChatHandler deps not injected');

  ipcMain.handle(IPC_CHANNELS.CHAT_SEND, async (_event, args) => {
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
      return apiError(`INVALID_PAYLOAD: ${validation.error.message}`);
    }

    if (!deps!.mainWindow) throw new Error('Main window not available');

    const { message, sessionId, history, attitudeLevel, studentContext } = validation.data;
    const activeSessionId = sessionId || deps!.sessionService.getOrCreateDefaultSession().id;
    deps!.sessionService.saveMessage(activeSessionId, 'user', message.trim());

    const userAttitude = attitudeLevel ?? deps!.configService.getConfig().attitudeLevel;

    const isReflectionPhase = false;
    deps!.disputeTracker.checkMessage(activeSessionId, message, isReflectionPhase);
    const attitude = deps!.disputeTracker.getEffectiveAttitude(activeSessionId, userAttitude, isReflectionPhase);

    const { analysis: diagnosisAnalysis, isNarrative } = await runDiagnosis(message, activeSessionId);

    const { finalPrompt, isReflectionGate } = prepareTeachingContext(diagnosisAnalysis, activeSessionId, attitude, studentContext);

    deps!.disputeTracker.checkMessage(activeSessionId, message, isReflectionGate);

    const messages = buildMessageArray(finalPrompt, history, message);

    const result = await handleStreamResponse(messages, activeSessionId, diagnosisAnalysis, isNarrative);
    return result.success ? apiSuccess({ messageId: result.messageId! }) : apiError(result.error || 'Chat send failed');
  });

  // T-019: 引导分析（轻量级，不调用诊断引擎）
  ipcMain.handle('onboarding:analyze', async (_event, args) => {
    const validation = validatePayload<{ text: string }>(args, {
      required: ['text'],
      types: { text: 'string' },
    });
    if (!validation.valid) {
      return apiError(`INVALID_PAYLOAD: ${validation.error.message}`);
    }
    const text = validation.data.text ?? '';
    if (!text.trim()) {
      return apiError('文本为空');
    }
    return apiSuccess({
      summary: `我看了你的这段文字，有几个感觉：\n\n✅ 有具体的场景和角色\n✅ 文字有自己的风格\n⚠️ 有些地方可以再精炼一些\n\n你现在最想提升哪方面？`,
    });
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
