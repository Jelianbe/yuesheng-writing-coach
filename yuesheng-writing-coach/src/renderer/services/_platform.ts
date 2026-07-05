/**
 * 平台检测 — Sprint 32
 *
 * 从 _dual-track.ts 提取的 isCapacitor() 独立模块。
 * Capacitor 平台通过 navigator.userAgent 中的 'Capacitor' 标识检测。
 *
 * 依据: dev-docs/tasks/sprint-32-plan.md
 */

/**
 * Capacitor 平台检测
 * - @capacitor/core 在 jsdom/普通浏览器环境会自动注入 window.Capacitor 对象(副作用)
 * - 注入的对象存在但平台是 'web',不是真原生
 * - 导致 isCapacitor() 在 jsdom 测试环境误判为 true
 * - 正确做法:检测 navigator.userAgent,真 Capacitor WebView 包含 'Capacitor' 标识
 */
export function isCapacitor(): boolean {
  if (typeof window === 'undefined' || typeof navigator === 'undefined') return false;
  return /Capacitor/i.test(navigator.userAgent || '');
}
