/**
 * Capacitor 诊断模块 — Sprint 32
 *
 * 在 Android/Capacitor 端实现诊断功能的真实降级替代：
 * - query: 从 localStorage 读取最近诊断结果
 * - submitRewrite: 用 LlmClient 调 LLM 评估改写 + 保存消息
 * - getComparison: noop（需要 diagnosis_records 表，未迁移）
 * - onDiagnosisUpdate: 内存事件总线（同 capacitor-chat 模式）
 *
 * 依据: dev-docs/decision-log.md D-081 未做事项 §1
 */

import { LlmClient } from '../../shared/llm/llm-client';
import type {
  DiagnosisQueryRequest,
  DiagnosisQueryResponse,
  DiagnosisSubmitRewriteRequest,
  DiagnosisRewriteEvaluation,
  DiagnosisGetComparisonRequest,
  DiagnosisUpdateEvent,
} from '../../shared/api-contracts/diagnosis.contract';
import { loadConfig } from './capacitor-config';

// ============================================================
// 本地存储 key
// ============================================================

const DIAGNOSIS_STORAGE_KEY = 'yuesheng_diagnosis_cache';
const DIAGNOSIS_HISTORY_KEY = 'yuesheng_diagnosis_history';
const MAX_HISTORY_PER_SESSION = 20;

// ============================================================
// 内存事件总线（与 capacitor-chat 共享模式）
// ============================================================

type EventHandler = (data: unknown) => void;
const eventListeners = new Map<string, Set<EventHandler>>();

function on(event: string, handler: EventHandler): () => void {
  if (!eventListeners.has(event)) eventListeners.set(event, new Set());
  const handlers = eventListeners.get(event);
  if (handlers) handlers.add(handler);
  return () => {
    const current = eventListeners.get(event);
    current?.delete(handler);
  };
}

function emit(event: string, data: unknown): void {
  const handlers = eventListeners.get(event);
  if (handlers) handlers.forEach((h) => h(data));
}

const EVENTS = {
  DIAGNOSIS_UPDATED: 'capacitor:diagnosis:updated',
} as const;

/** 缓存诊断结果到 localStorage（供后续 query 读取） */
function cacheDiagnosisResult(data: DiagnosisUpdateEvent): void {
  try {
    const raw = localStorage.getItem(DIAGNOSIS_STORAGE_KEY);
    const cache: Record<string, DiagnosisUpdateEvent> = raw ? JSON.parse(raw) : {};
    cache[data.sessionId] = data;
    // 保留最近 10 条
    const entries = Object.entries(cache).slice(-10);
    const trimmed = Object.fromEntries(entries);
    localStorage.setItem(DIAGNOSIS_STORAGE_KEY, JSON.stringify(trimmed));
  } catch {
    // localStorage 不可用，静默失败
  }
}

/** 追加诊断快照到历史列表（供 getComparison 读取） */
function appendToHistory(data: DiagnosisUpdateEvent): void {
  try {
    const raw = localStorage.getItem(DIAGNOSIS_HISTORY_KEY);
    const all: Record<string, Array<DiagnosisUpdateEvent & { timestamp: string }>> = raw ? JSON.parse(raw) : {};
    if (!all[data.sessionId]) all[data.sessionId] = [];
    all[data.sessionId].push({ ...data, timestamp: new Date().toISOString() });
    // 保留每个 session 最近 MAX_HISTORY_PER_SESSION 条
    all[data.sessionId] = all[data.sessionId].slice(-MAX_HISTORY_PER_SESSION);
    localStorage.setItem(DIAGNOSIS_HISTORY_KEY, JSON.stringify(all));
  } catch {
    // localStorage 不可用，静默失败
  }
}

// ============================================================
// 公开 API
// ============================================================

/**
 * 查询诊断结果 — 从 localStorage 读取最近缓存的诊断
 * Capacitor 端没有真正的诊断推理，依赖 Electron 端推送的诊断结果。
 * 如果 localStorage 中没有缓存，返回空数组。
 */
export async function capacitorDiagnosisQuery(
  params: DiagnosisQueryRequest,
): Promise<DiagnosisQueryResponse | null> {
  try {
    const raw = localStorage.getItem(DIAGNOSIS_STORAGE_KEY);
    if (!raw) return [];
    const cache: Record<string, DiagnosisUpdateEvent> = JSON.parse(raw);
    const data = cache[params.sessionId];
    if (!data?.entry?.syndromes) return [];
    return data.entry.syndromes.map((s) => ({
      id: s.syndromeId,
      name: s.syndromeId,
      severity: s.severity === 'high' || s.severity === 'critical' ? ('L2' as const)
        : s.severity === 'medium' ? ('L3' as const) : ('L1' as const),
      evidence: s.evidence ? [s.evidence] : [],
      score: 0,
      firstDetected: new Date().toISOString(),
      status: 'active' as const,
      detectionCount: 1,
      missedCount: 0,
      suggestedActions: [],
    }));
  } catch {
    console.warn('[capacitor-diagnosis] query failed, returning empty');
    return [];
  }
}

/**
 * 提交改写评估 — 直调 LLM API 评估改写质量
 * 参考 diagnosis.handler.ts registerMethod('diagnosis:submitRewrite') 逻辑。
 * 会保存一条系统消息到 session（模拟主进程 saveMessage）。
 */
export async function capacitorDiagnosisSubmitRewrite(
  params: DiagnosisSubmitRewriteRequest,
): Promise<{ evaluation: DiagnosisRewriteEvaluation } | undefined> {
  try {
    const config = await loadConfig();
    if (!config.apiKey) {
      console.warn('[capacitor-diagnosis] submitRewrite: API Key 未配置');
      return undefined;
    }

    const client = new LlmClient({
      apiKey: config.apiKey,
      baseUrl: config.baseUrl,
      modelName: config.modelName,
      temperature: config.temperature,
      maxTokens: config.maxTokens,
    });

    const prompt = `你是一个写作教练。请评估以下改写质量：

原文：「${params.originalText}」
改写后：「${params.rewrittenText}」

请从以下维度评分（1-10 分）：
1. 改善程度：改写是否比原文更好地体现了写作技巧
2. 自然度：改写是否自然流畅
3. 技巧运用：是否恰当运用了目标写作技巧

请以 JSON 格式返回：
{
  "score": <1-10 的整数>,
  "feedback": "<具体的反馈意见>",
  "improved": true/false
}`;

    const result = await client.chat([
      { role: 'system', content: '你是一个专业的写作教练助手。' },
      { role: 'user', content: prompt },
    ]);

    // 尝试解析 LLM 返回的 JSON
    let jsonMatch = result.content.match(/\{[\s\S]*"score"[\s\S]*\}/);
    if (!jsonMatch) {
      // 尝试提取 JSON 块
      jsonMatch = result.content.match(/```(?:json)?\s*([\s\S]*?)```/);
      if (jsonMatch) {
        jsonMatch = [jsonMatch[0], jsonMatch[1]];
      }
    }
    const jsonStr = jsonMatch?.[1] ?? jsonMatch?.[0] ?? result.content;
    const parsed = JSON.parse(jsonStr) as { score: number; feedback: string; improved: boolean };

    const evaluation: DiagnosisRewriteEvaluation = {
      score: parsed.score ?? 5,
      feedback: parsed.feedback ?? '评估完成。',
      improved: parsed.improved ?? false,
      severityAfterUpdate: {},
    };

    // 保存系统消息到 localStorage（模拟 session.saveMessage）
    try {
      const msgKey = `yuesheng_messages_${params.sessionId}`;
      const raw = localStorage.getItem(msgKey);
      const messages: Array<{ role: string; content: string; timestamp: number }> = raw ? JSON.parse(raw) : [];
      messages.push({
        role: 'system',
        content: `[修改原文] 症候: ${params.syndromeId}\n原文: "${params.originalText}"\n修改后: "${params.rewrittenText}"`,
        timestamp: Date.now(),
      });
      localStorage.setItem(msgKey, JSON.stringify(messages));
    } catch {
      // 静默失败
    }

    return { evaluation };
  } catch (err) {
    console.error('[capacitor-diagnosis] submitRewrite failed:', err);
    return undefined;
  }
}

/**
 * 获取诊断对比 — C5-b 降级方案：从 localStorage 历史快照做简化对比
 * 对比最早的 vs 最新的症候 severity 变化。
 */
export async function capacitorDiagnosisGetComparison(
  params: DiagnosisGetComparisonRequest,
): Promise<{ hasHistory: boolean; comparison?: string }> {
  try {
    const raw = localStorage.getItem(DIAGNOSIS_HISTORY_KEY);
    if (!raw) return { hasHistory: false };
    const all: Record<string, Array<DiagnosisUpdateEvent & { timestamp: string }>> = JSON.parse(raw);
    const history = all[params.sessionId];
    if (!history || history.length < 2) return { hasHistory: false };

    const first = history[0];
    const latest = history[history.length - 1];

    const firstSyndromes = first.entry?.syndromes ?? [];
    const latestSyndromes = latest.entry?.syndromes ?? [];

    const lines: string[] = [`诊断对比（${first.timestamp} → ${latest.timestamp}）:`];

    for (const latestS of latestSyndromes) {
      const firstS = firstSyndromes.find((s) => s.syndromeId === latestS.syndromeId);
      if (firstS) {
        if (firstS.severity !== latestS.severity) {
          lines.push(`- ${latestS.syndromeId}: ${firstS.severity} → ${latestS.severity}`);
        }
      } else {
        lines.push(`- ${latestS.syndromeId}: 新增 (${latestS.severity})`);
      }
    }

    for (const firstS of firstSyndromes) {
      if (!latestSyndromes.find((s) => s.syndromeId === firstS.syndromeId)) {
        lines.push(`- ${firstS.syndromeId}: 已消除 (原 ${firstS.severity})`);
      }
    }

    if (lines.length === 1) {
      lines.push('（症候 severity 无变化）');
    }

    return { hasHistory: true, comparison: lines.join('\n') };
  } catch {
    console.warn('[capacitor-diagnosis] getComparison failed, returning noop');
    return { hasHistory: false };
  }
}

/**
 * 注册诊断更新监听 — 替代 IPC typedOn
 * 外部通过 emitDiagnosisUpdate 推送诊断结果。
 */
export function capacitorOnDiagnosisUpdate(
  handler: (data: DiagnosisUpdateEvent) => void,
): () => void {
  return on(EVENTS.DIAGNOSIS_UPDATED, handler as EventHandler);
}

/**
 * 推送诊断更新（供 chat store / orchestrator 在接收 AI 响应后调用）
 * 会同时：
 * 1. 通过事件总线通知订阅者
 * 2. 缓存到 localStorage 供后续 query 读取
 */
export function emitDiagnosisUpdate(data: DiagnosisUpdateEvent): void {
  cacheDiagnosisResult(data);
  appendToHistory(data);
  emit(EVENTS.DIAGNOSIS_UPDATED, data);
}

/** 清除诊断缓存（测试用） */
export function clearDiagnosisCache(): void {
  try {
    localStorage.removeItem(DIAGNOSIS_STORAGE_KEY);
  } catch {
    // 静默
  }
}
