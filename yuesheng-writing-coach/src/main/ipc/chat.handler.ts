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
import { processDiagnosisFromAI } from './diagnosis.handler';
import { DiagnosisService } from '../services/diagnosis.service';
import { SYNDROME_META, getActionsForSyndrome, SYNDROME_NAMES } from '../../shared/mappings';
import { PromptLoader } from '../services/prompt-loader';
import { MessageRouter } from '../services/message-router';
import { StudentModelService } from '../services/student-model.service';
import { TeachingStrategyService, StrategyInput } from '../services/teaching-strategy.service';
import { ProblemPrioritizer } from '../services/problem-prioritizer.service';
import { groupPassagesBySyndrome, getEvidenceForSyndrome } from '../services/evidence-grouping';
import * as path from 'path';
import * as fs from 'fs';

let mainWindow: BrowserWindow | null = null;
let configService: ConfigService | null = null;
let apiProxy: ApiProxy | null = null;
let promptLoader: PromptLoader | null = null;
let messageRouter: MessageRouter | null = null;
let studentModelService: StudentModelService | null = null;
let teachingStrategyService: TeachingStrategyService | null = null;
let problemPrioritizer: ProblemPrioritizer | null = null;

export function setMainWindow(win: BrowserWindow): void {
  mainWindow = win;
}

export function setConfigService(svc: ConfigService): void {
  configService = svc;
}

export function setPromptLoader(loader: PromptLoader): void {
  promptLoader = loader;
}

export function setMessageRouter(router: MessageRouter): void {
  messageRouter = router;
}

export function setStudentModelService(svc: StudentModelService): void {
  studentModelService = svc;
}

export function setTeachingStrategyService(svc: TeachingStrategyService): void {
  teachingStrategyService = svc;
}

export function setProblemPrioritizer(svc: ProblemPrioritizer): void {
  problemPrioritizer = svc;
}

export function getApiProxy(): ApiProxy {
  if (!apiProxy) {
    const config = configService!.getConfig();
    apiProxy = new ApiProxy(config);
  }
  return apiProxy;
}

/**
 * 调用 Diagnosis Agent 分析文本
 * @param onChunk - 可选的流式回调，每收到一个 chunk 时调用
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

/** 诊断服务实例 */
let diagnosisService: DiagnosisService | null = null;

export function setDiagnosisService(svc: DiagnosisService): void {
  diagnosisService = svc;
}

function getDiagnosisService(): DiagnosisService | null {
  return diagnosisService;
}

/**
 * 格式化历史诊断为简洁摘要，注入 System Prompt
 */
function formatDiagnosisHistory(diagnoses: DiagnosisEntry[]): string {
  if (diagnoses.length === 0) {
    return '本会话尚无历史诊断记录。';
  }

  const lines = diagnoses.map(d => {
    const date = new Date(d.timestamp).toLocaleDateString('zh-CN');
    const syndromesText = d.syndromes
      .slice(0, MAX_DIAGNOSIS_HISTORY)
      .map(s => `${s.name}（${s.severity}）`)
      .join('、');
    return `- ${date}：${syndromesText}`;
  });

  return `## 本会话历史诊断\n\n${lines.join('\n')}\n\n请基于以上诊断历史，关注用户是否反复出现相同问题，或已有进步。`;
}

/**
 * 将 DiagnosisAnalysis 转换为 DiagnosisEntry
 * evidence 按 syndromeRef 分组映射：每个症候取关联的 keyPassages 作为证据
 * 降级策略：如果 AI 未输出 syndromeRef，则所有症候共享前 3 个 keyPassages（向后兼容）
 */
function analysisToDiagnosisEntry(
  analysis: DiagnosisAnalysis,
  sessionId: string,
  messageId: string,
): DiagnosisEntry {
  const allSuggestedActions: string[] = [];

  // 按 syndromeRef 分组 keyPassages
  const passagesBySyndrome = groupPassagesBySyndrome(analysis.keyPassages);
  // 降级 fallback：共享前 MAX_DIAGNOSIS_HISTORY 个
  const sharedFallback = analysis.keyPassages.slice(0, MAX_DIAGNOSIS_HISTORY).map(kp => kp.text);

  const syndromes: SyndromeResult[] = analysis.syndromeRef.map((ref) => {
    const meta = SYNDROME_META[ref as SyndromeId] ?? { name: ref, severity: 'L1' as SeverityLevel };
    const actions = getActionsForSyndrome(ref);
    allSuggestedActions.push(...actions);

    // 按症候取证据
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

  // 去重合并所有动作
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
 * 根据学生模型和当前诊断结果，生成教学策略和优先级指令
 */
function buildStrategyInstruction(
  diagnosisAnalysis: DiagnosisAnalysis | null,
): string | null {
  if (!teachingStrategyService || !problemPrioritizer || !studentModelService) {
    return null;
  }

  // === 第一步：从学生模型获取结构化数据 ===
  const proficiency = studentModelService.inferProficiency();
  const cognitiveStyle = studentModelService.inferCognitiveStyle();

  const strategyInput: StrategyInput = {
    proficiency: proficiency.level,
    cognitiveStyle: cognitiveStyle.style,
    topSyndromeCount: diagnosisAnalysis?.syndromeRef.length ?? 0,
    frustrationIndex: 0, // 后续可扩展行为信号追踪
  };

  // === 第二步：获取教学策略决策 ===
  const decision = teachingStrategyService.decide(strategyInput);

  // === 第三步：对当前诊断的症候进行优先级排序 ===
  let prioritizedInstruction = '';
  if (diagnosisAnalysis && diagnosisAnalysis.syndromeRef.length > 0) {
    const syndromesForPrioritization = diagnosisAnalysis.syndromeRef.map(ref => ({
      id: ref,
      name: SYNDROME_NAMES[ref] ?? ref,
      occurrenceCount: 1,
      severityHistory: [SYNDROME_META[ref as SyndromeId]?.severity ?? 'L1'],
    }));

    const prioritized = problemPrioritizer.prioritize(syndromesForPrioritization);
    if (prioritized.length > 0) {
      const top = prioritized[0];
      prioritizedInstruction = `\n\n**当前最高优先级问题**：${top.tierLabel} — ${top.syndromeId}（${top.name}）\n`;
      prioritizedInstruction += `行动级别：${top.action === 'must_fix' ? '必须先修复' : top.action === 'priority' ? '优先处理' : '可延后'}\n`;
      prioritizedInstruction += `请在本轮对话中聚焦于此问题。`;
    }
  }

  // === 第四步：组装策略指令 ===
  const modeInstructions: Record<string, string> = {
    scaffolding: '请使用支架模式：给出具体示范和结构化步骤，让用户模仿',
    guiding: '请使用引导模式：用提问引导用户自己发现答案，不给示范',
    challenging: '请使用挑战模式：给出变形条件，要求用户在约束下创作',
  };

  const toneInstructions: Record<string, string> = {
    encouraging: '使用鼓励的语气，多肯定用户的进步',
    direct: '使用直接简洁的语气，直击问题核心',
    logical: '使用逻辑化的语气，以推理和结构化方式表达',
    resonant: '使用共鸣的语气，通过案例和情感连接来表达',
  };

  const formatInstructions: Record<string, string> = {
    'problem→cause→evidence→solution': '按照"问题→原因→证据→解决方案"的结构输出',
    'example→feeling→demonstration': '按照"案例→感受→示范"的结构输出',
  };

  let instruction = '---\n## 教学策略指令\n\n';
  instruction += `- 教学模式：${modeInstructions[decision.mode] ?? decision.mode}\n`;
  instruction += `- 语气：${toneInstructions[decision.tone] ?? decision.tone}\n`;
  if (decision.format && formatInstructions[decision.format]) {
    instruction += `- 输出格式：${formatInstructions[decision.format]}\n`;
  }
  instruction += '- 核心原则：一次只说一个问题，聚焦当前最高优先级问题。';
  instruction += prioritizedInstruction;

  return instruction;
}

let sessionService: SessionService;

export function setSessionService(svc: SessionService): void {
  sessionService = svc;
}

// ============ CHAT_SEND 子步骤提取 ============

/**
 * 步骤1：调用 DiagnosisAgent 分析内容，保存诊断结果
 */
async function runDiagnosis(
  message: string,
  activeSessionId: string,
): Promise<{ analysis: DiagnosisAnalysis | null; isNarrative: boolean }> {
  if (!mainWindow) return { analysis: null, isNarrative: true };

  const analysis = await callDiagnosisAgent(message, (chunk) => {
    mainWindow!.webContents.send(IPC_CHANNELS.CHAT_STREAM_DATA, {
      sessionId: activeSessionId,
      chunk: `\u{1F50D} ${chunk}`,
    });
  });

  const isNarrative = analysis?.contentType !== 'non-narrative';

  if (analysis && isNarrative) {
    const diagSvc = getDiagnosisService();
    if (diagSvc) {
      diagSvc.saveAnalysis(analysis, activeSessionId, '');
    }
    const entry = analysisToDiagnosisEntry(analysis, activeSessionId, '');
    mainWindow.webContents.send(IPC_CHANNELS.DIAGNOSIS_UPDATE, entry);
  }

  return { analysis, isNarrative };
}

/**
 * 步骤2：构建教学上下文（诊断历史 + 学生模型 + System Prompt + 策略指令）
 */
function prepareTeachingContext(
  diagnosisAnalysis: DiagnosisAnalysis | null,
  activeSessionId: string,
  attitude: AttitudeLevel,
  studentContext?: string,
): { finalPrompt: string } {
  let diagnosisHistory = '';
  const diagSvc = getDiagnosisService();
  if (diagSvc) {
    const recentDiagnoses = diagSvc.getRecentBySession(activeSessionId, MAX_DIAGNOSIS_HISTORY);
    diagnosisHistory = formatDiagnosisHistory(recentDiagnoses);
  }

  let effectiveStudentContext: string | undefined;
  if (studentModelService) {
    effectiveStudentContext = studentModelService.toPromptText();
  } else if (studentContext) {
    effectiveStudentContext = studentContext;
  }

  const systemPrompt = promptLoader?.loadSystemPrompt(
    attitude,
    diagnosisAnalysis,
    diagnosisHistory,
    effectiveStudentContext,
    activeSessionId,
  ) ?? '你是一个专业的写作教练月笙，帮助用户提升写作水平。';

  const strategyInstruction = buildStrategyInstruction(diagnosisAnalysis);
  const finalPrompt = strategyInstruction ? `${systemPrompt}\n\n${strategyInstruction}` : systemPrompt;

  return { finalPrompt };
}

/**
 * 步骤3：组装消息数组（System Prompt + 历史 + 当前消息）
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
      mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_DATA, {
        sessionId: activeSessionId,
        chunk: `\u{1F4CB} 分析摘要：${diagnosisAnalysis.rootCause}\n\n---\n\n`,
      });
    }

    for await (const chunk of proxy.chatStream(messages)) {
      fullResponse += chunk;
      mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_DATA, {
        sessionId: activeSessionId,
        chunk,
      });
    }

    sessionService.saveMessage(activeSessionId, 'assistant', fullResponse);
    sessionService.autoGenerateTitle(activeSessionId);

    try {
      processDiagnosisFromAI(fullResponse, activeSessionId, messageId);
    } catch (err) {
      console.error('[Chat] Diagnosis processing failed:', err);
    }

    mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_END, {
      sessionId: activeSessionId,
      fullResponse,
      messageId,
    });

    return { success: true, messageId, sessionId: activeSessionId };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : '未知错误';
    mainWindow?.webContents.send(IPC_CHANNELS.CHAT_STREAM_END, {
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
  ipcMain.handle(IPC_CHANNELS.CHAT_SEND, async (_event, args: {
    message: string;
    sessionId: string;
    history?: { role: string; content: string }[];
    attitudeLevel?: AttitudeLevel;
    studentContext?: string;
  }) => {
    if (!mainWindow) throw new Error('Main window not available');

    const { message, sessionId, history, attitudeLevel, studentContext } = args;
    const activeSessionId = sessionId || sessionService.getOrCreateDefaultSession().id;
    sessionService.saveMessage(activeSessionId, 'user', message.trim());

    const attitude = attitudeLevel ?? configService!.getConfig().attitudeLevel;

    // 步骤1：诊断分析
    const { analysis: diagnosisAnalysis, isNarrative } = await runDiagnosis(message, activeSessionId);

    // 步骤2：教学上下文
    const { finalPrompt } = prepareTeachingContext(diagnosisAnalysis, activeSessionId, attitude, studentContext);

    // 步骤3：消息组装
    const messages = buildMessageArray(finalPrompt, history, message);

    // 步骤4：流式响应
    const result = await handleStreamResponse(messages, activeSessionId, diagnosisAnalysis, isNarrative);
    return result.success ? apiSuccess({ messageId: result.messageId! }) : apiError(result.error || 'Chat send failed');
  });
}

export function refreshApiProxy(): void {
  const config = configService!.getConfig();
  if (apiProxy) {
    apiProxy.updateConfig(config);
  } else {
    apiProxy = new ApiProxy(config);
  }
}
