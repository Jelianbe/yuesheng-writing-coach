/**
 * 公共 invoke 包装器 — Sprint 32
 *
 * 消除所有 service 中重复的 try/catch + 日志。
 *
 * 返回 `Res | null`，不隐藏 null。
 * 调用方通过 `??` 运算符自行决定 fallback：
 *   const sessions = await invoke<SessionInfo[]>('session:list', {}) ?? [];
 *   const session = await invoke<SessionInfo>('session:create', { title }) ?? null;
 *
 * 依据: dev-docs/tasks/sprint-32-plan.md §Phase 1
 */
import { typedInvoke } from './ipc-client';

export async function invoke<Res>(
  channel: string,
  args: Record<string, unknown>,
): Promise<Res | null> {
  try {
    const result = await typedInvoke<Record<string, unknown>, Res>(channel, args);
    if (!result.success) {
      console.error(`[invoke] ${channel}: ${result.error}`);
      return null;
    }
    return result.data ?? null;
  } catch (err) {
    console.error(`[invoke] ${channel} failed:`, err);
    return null;
  }
}
