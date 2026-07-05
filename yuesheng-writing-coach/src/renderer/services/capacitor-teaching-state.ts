/**
 * Capacitor 教学状态模块 — Sprint 34
 *
 * 在 Android/Capacitor 端提供教学状态事件的真实降级替代：
 * - onUpdated: 内存事件总线（同 capacitor-chat/diagnosis 模式）
 * - onMastery: 内存事件总线
 * - confirm: localStorage 记录阶段完成确认
 * - updateSummary: localStorage 持久化诊断摘要
 * - getPrompt: 保持 noop（LLM 提示词拼接是主进程核心业务逻辑）
 *
 * 依据: dev-docs/decision-log.md D-084
 */

import { loadConfig } from './capacitor-config';

// ============================================================
// 本地存储 key
// ============================================================

const CONFIRM_STORAGE_KEY = 'yuesheng_teaching_confirm_cache';
const SUMMARY_STORAGE_KEY = 'yuesheng_teaching_summary_cache';

// ============================================================
// 内存事件总线
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
  UPDATED: 'capacitor:teaching-state:updated',
  MASTERY: 'capacitor:teaching-state:mastery',
} as const;

// ============================================================
// 公开 API
// ============================================================

/**
 * 确认阶段完成 — 记录到 localStorage
 * Capacitor 端没有真实状态机，仅作标记记录。
 */
export async function capacitorTeachingStateConfirm(
  params: { sessionId: string },
): Promise<{ oldState: unknown; newState: unknown } | null> {
  try {
    const raw = localStorage.getItem(CONFIRM_STORAGE_KEY);
    const cache: Record<string, number> = raw ? JSON.parse(raw) : {};
    cache[params.sessionId] = Date.now();
    localStorage.setItem(CONFIRM_STORAGE_KEY, JSON.stringify(cache));
    console.warn('[capacitor-teaching-state] confirm: no real state machine, logging only');
    return {
      oldState: { sessionId: params.sessionId },
      newState: { sessionId: params.sessionId, confirmedAt: Date.now() },
    };
  } catch {
    console.warn('[capacitor-teaching-state] confirm: localStorage failed');
    return null;
  }
}

/**
 * 获取 Prompt 注入内容 — C6-b 极简 prompt 方案
 * Android 端无 PromptBuilder + TeachingStateMachine，用固定人设 + 态度档位 + 基础教学原则替代。
 * 不走状态机，教学能力降级但教练人设在。
 */
export async function capacitorTeachingStateGetPrompt(
  _params: { sessionId: string },
): Promise<string | null> {
  try {
    const config = await loadConfig();
    const attitudeLevel = config.attitudeLevel ?? 'yuesheng';

    return `你是月笙写作教练，一个专业的写作辅导者。

## 核心原则
- 你是教练，不是助手。不替用户写句子，不替用户做决定。
- 你的目标是帮助用户学会写作，而不是替代写作。
- 找根因，不治标。

## 态度档位
当前态度: ${attitudeLevel}
- doubao（豆包）: 温和鼓励，适合新手
- yuesheng（月笙如歌）: 专业直接，深度分析
- sensei: 严格师傅风，要求高
安全词: 用户说"轻一点"时无条件降档。

## 教学流程
问→写→诊→教→练→评，当前在 Android 端运行，教学状态机简化模式。`;
  } catch {
    console.warn('[capacitor-teaching-state] getPrompt: loadConfig failed, returning minimal prompt');
    return '你是月笙写作教练。不替用户写，不替用户决定，找根因。';
  }
}

/**
 * 更新诊断摘要 — 保存到 localStorage
 */
export async function capacitorTeachingStateUpdateSummary(
  params: { sessionId: string; newContent: string },
): Promise<unknown | null> {
  try {
    const raw = localStorage.getItem(SUMMARY_STORAGE_KEY);
    const cache: Record<string, { content: string; updatedAt: number }> = raw ? JSON.parse(raw) : {};
    cache[params.sessionId] = { content: params.newContent, updatedAt: Date.now() };
    localStorage.setItem(SUMMARY_STORAGE_KEY, JSON.stringify(cache));
    return { sessionId: params.sessionId, diagnosisSummary: params.newContent };
  } catch {
    console.warn('[capacitor-teaching-state] updateSummary: localStorage failed');
    return null;
  }
}

/**
 * 注册教学状态更新监听 — 替代 IPC typedOn
 */
export function capacitorTeachingStateOnUpdated(
  handler: (data: unknown) => void,
): () => void {
  return on(EVENTS.UPDATED, handler as EventHandler);
}

/**
 * 注册精通门控事件监听 — 替代 IPC typedOn
 */
export function capacitorTeachingStateOnMastery(
  handler: (data: unknown) => void,
): () => void {
  return on(EVENTS.MASTERY, handler as EventHandler);
}

/**
 * 推送教学状态更新（供 chat store / orchestrator 在接收 AI 响应后调用）
 */
export function emitTeachingStateUpdated(data: unknown): void {
  emit(EVENTS.UPDATED, data);
}

/**
 * 推送精通门控事件（供 hook / store 调用）
 */
export function emitMasteryReached(data: unknown): void {
  emit(EVENTS.MASTERY, data);
}

/** 清除教学状态缓存（测试用） */
export function clearTeachingStateCache(): void {
  try {
    localStorage.removeItem(CONFIRM_STORAGE_KEY);
    localStorage.removeItem(SUMMARY_STORAGE_KEY);
  } catch {
    // 静默
  }
}
