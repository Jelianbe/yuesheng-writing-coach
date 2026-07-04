/**
 * 双轨调度 helper — Sprint 26 阶段 3.1
 *
 * 平台检测: `window.Capacitor`(由 @capacitor/core 注入 WebView)
 * - 命中: 走 direct(Android 端直连 StorageAdapter)
 * - 未命中: 走 electron(Electron 端 IPC → main → better-sqlite3)
 *
 * 失败处理: caller 负责(helper 不做降级,Capacitor 端 direct 失败不会降级到 electron,
 *          因为架构上不可能成功 — Capacitor 端没有 IPC 通道)
 *
 * 依据: dev-docs/tasks/sprint-26-phase-3-plan.md §3.1
 */

/** Capacitor 平台检测 */
export function isCapacitor(): boolean {
  if (typeof window === 'undefined') return false;
  return !!(window as unknown as { Capacitor?: unknown }).Capacitor;
}

/**
 * 双轨调度 — 互不降级
 *
 * @param args 透传给 direct + electron 的参数
 * @param handlers direct + electron 两个 handler,各自返回 TResult(可包含 fallback)
 * @returns TResult(handler 内部已处理失败)
 */
export async function runDualTrack<TArgs, TResult>(
  args: TArgs,
  handlers: {
    direct: (args: TArgs) => Promise<TResult>;
    electron: (args: TArgs) => Promise<TResult>;
  },
): Promise<TResult> {
  if (isCapacitor()) {
    return handlers.direct(args);
  }
  return handlers.electron(args);
}
