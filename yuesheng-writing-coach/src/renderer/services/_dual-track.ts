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

/**
 * Capacitor 平台检测
 *
 * 为什么不用 `!!window.Capacitor`?
 * - @capacitor/core 在 jsdom/普通浏览器环境会**自动注入** `window.Capacitor` 对象(副作用)
 * - 注入的对象存在但平台是 'web',不是真原生
 * - 导致 isCapacitor() 在 jsdom 测试环境误判为 true,触发 CapacitorSqliteAdapter 初始化失败
 *
 * 正确做法:检测 navigator.userAgent,真 Capacitor WebView 包含 'Capacitor' 标识
 * (参考 @capacitor/core 文档: https://capacitorjs.com/docs/core-apis/web#capacitor-isp)
 */
export function isCapacitor(): boolean {
  if (typeof window === 'undefined' || typeof navigator === 'undefined') return false;
  return /Capacitor/i.test(navigator.userAgent || '');
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
