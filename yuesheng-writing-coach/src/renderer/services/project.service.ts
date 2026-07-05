/**
 * 项目管理服务 — Sprint 32 (移除 serviceBridge/dual-track)
 *
 * 双轨迁移:
 * - Electron 端: 直接 typedInvoke → main handler
 * - Android 端: import shared ProjectService + CapacitorSqliteAdapter
 *
 * 依据: dev-docs/tasks/sprint-32-plan.md
 */
import { invoke } from './_invoke';
import { isCapacitor } from './_platform';
import type {
  ProjectInfo,
} from '../../shared/api-contracts/project.contract';
import { createStorageAdapter } from '../../shared/storage';
import { ProjectService as DirectProjectService } from '../../shared/services/project.service';

/** Android 端: 延迟初始化 adapter + direct service */
let _directService: DirectProjectService | null = null;

async function getDirectService(): Promise<DirectProjectService | null> {
  if (!isCapacitor()) return null;
  if (_directService) return _directService;

  const adapter = createStorageAdapter({ type: 'capacitor-sqlite', dbName: 'yuesheng.db', version: 1 });
  await adapter.initialize();
  _directService = new DirectProjectService(adapter);
  return _directService;
}

export const projectService = {
  /** 获取项目列表(按 updatedAt DESC) — 失败时返回 [] */
  async list(): Promise<ProjectInfo[]> {
    if (isCapacitor()) {
      const direct = await getDirectService();
      if (!direct) return [];
      try { return await direct.listProjects(); }
      catch (err) { console.error('[project] list failed (direct):', err); return []; }
    }
    return (await invoke<ProjectInfo[]>('project:list', {})) ?? [];
  },

  /** 获取单个项目 — 失败时返回 null */
  async getById(projectId: string): Promise<ProjectInfo | null> {
    if (isCapacitor()) {
      const direct = await getDirectService();
      if (!direct) return null;
      try { return await direct.getProject(projectId); }
      catch (err) { console.error('[project] getById failed (direct):', err); return null; }
    }
    return invoke<ProjectInfo>('project:get', { projectId }) ?? null;
  },

  /** 创建项目 — 失败时返回 null */
  async create(input: { name: string; description?: string; settingTree?: string; settingTreeType?: string }): Promise<ProjectInfo | null> {
    if (isCapacitor()) {
      const direct = await getDirectService();
      if (!direct) return null;
      try { return await direct.createProject(input); }
      catch (err) { console.error('[project] create failed (direct):', err); return null; }
    }
    return invoke<ProjectInfo>('project:create', input as Record<string, unknown>) ?? null;
  },

  /** 更新项目 — 失败时返回 null */
  async update(projectId: string, input: { name?: string; description?: string; settingTree?: string; settingTreeType?: string }): Promise<ProjectInfo | null> {
    if (isCapacitor()) {
      const direct = await getDirectService();
      if (!direct) return null;
      try { return await direct.updateProject(projectId, input); }
      catch (err) { console.error('[project] update failed (direct):', err); return null; }
    }
    return invoke<ProjectInfo>('project:update', { projectId, ...input }) ?? null;
  },

  /** 删除项目 — 失败时返回 false */
  async remove(projectId: string): Promise<boolean> {
    if (isCapacitor()) {
      const direct = await getDirectService();
      if (!direct) return false;
      try { await direct.deleteProject(projectId); return true; }
      catch (err) { console.error('[project] remove failed (direct):', err); return false; }
    }
    const result = await invoke<void>('project:delete', { projectId });
    return result !== null;
  },
};
