/**
 * workspace-registry.ts — 右侧栏 workspace 注册表（ADR-002）
 *
 * 设计动机：消除硬编码 WORKSPACE_MAP + ALL_TOOLS，让新增 workspace 只需
 * 1 个新文件 + 1 行自注册 + 1 行 index import。
 *
 * 用法：
 *   1. workspace 文件顶层调 registerWorkspace({...})
 *   2. workspaces-index.ts 触发所有 workspace 的 import
 *   3. RightPanel 用 getAllWorkspaces() / getWorkspace() 访问
 *
 * 测试隔离：调用 resetForTesting() 清空注册表。
 */

import type { ComponentType } from 'react';

export type WorkspaceId = string;

export interface WorkspaceMeta {
  id: WorkspaceId;
  name: string;
  icon: string;
  defaultOpen?: boolean;
}

export interface WorkspaceRegistration extends WorkspaceMeta {
  /**
   * 动态导入工厂。返回 React.lazy 期望的 shape:
   * { default: ComponentType }
   * workspace 文件用 .then() 包装命名导出:
   * () => import('./index').then(m => ({ default: m.Foo }))
   */
  component: () => Promise<{ default: ComponentType }>;
}

const registry = new Map<WorkspaceId, WorkspaceRegistration>();

/**
 * 注册一个 workspace。
 * - 重复 id 仅警告，不抛错（避免静默失败导致难以调试）
 * - 必须在模块顶层调用（副作用式自注册）
 */
export function registerWorkspace(reg: WorkspaceRegistration): void {
  if (registry.has(reg.id)) {
    console.warn(`[WorkspaceRegistry] duplicate id: ${reg.id}`);
    return;
  }
  registry.set(reg.id, reg);
}

export function getWorkspace(id: WorkspaceId): WorkspaceRegistration | undefined {
  return registry.get(id);
}

export function getAllWorkspaces(): WorkspaceRegistration[] {
  return Array.from(registry.values());
}

export function getDefaultOpenWorkspaces(): WorkspaceRegistration[] {
  return getAllWorkspaces().filter(w => w.defaultOpen === true);
}

/** 测试隔离：清空注册表。仅在 vitest beforeEach 中使用。 */
export function resetForTesting(): void {
  registry.clear();
}
