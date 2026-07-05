/**
 * _dual-track 向后兼容 shim — Sprint 32
 *
 * 保留此文件以免 10+ 个 store/hook 全部需要迁移。
 * 内部委托给 _platform.ts。
 *
 * 未来 sprint 可逐步将 store/hook 迁移到 _platform.ts 后删除本文件。
 *
 * 依据: dev-docs/tasks/sprint-32-plan.md
 */
export { isCapacitor } from './_platform';

/** @deprecated 在 Sprint 32 已移除,保留为空函数以确保编译 */
export function runDualTrack<T>(): Promise<T | null> {
  return Promise.resolve(null) as Promise<T | null>;
}
