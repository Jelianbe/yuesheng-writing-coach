/**
 * 项目管理服务 — Sprint 26 阶段 3.4 (Z-1: 调用方迁移)
 *
 * 双轨实现(用 _dual-track.ts helper 统一调度):
 * - Electron 端: 走 typedInvoke → main 进程 → better-sqlite3(保留旧 IPC 路径)
 * - Android/Capacitor 端: 直接 import ProjectService + CapacitorSqliteAdapter
 *
 * 平台检测: 通过 navigator.userAgent('Capacitor' 标识)区分
 * 失败处理: 各 handler 独立 try/catch,失败时返回 caller 提供的 fallback
 *
 * 依据: dev-docs/tasks/sprint-26-phase-3-plan.md §3.4 / D-074
 */
import { serviceBridge } from './service-bridge';
import type {
  ProjectInfo,
  ProjectListResponse,
  ProjectGetResponse,
  ProjectCreateResponse,
  ProjectUpdateResponse,
  ProjectCreateRequest,
  ProjectUpdateRequest,
} from '../../shared/api-contracts/project.contract';
import { createStorageAdapter } from '../../shared/storage';
import { ProjectService as DirectProjectService } from '../../shared/services/project.service';
import { runDualTrack, isCapacitor } from './_dual-track';

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
    return runDualTrack(undefined, {
      direct: async () => {
        const direct = await getDirectService();
        if (!direct) return [];
        try {
          return await direct.listProjects();
        } catch (err) {
          console.error('[project] list failed (direct):', err);
          return [];
        }
      },
      electron: async () => {
        const result = await serviceBridge.invoke<Record<string, never>, ProjectListResponse>('project:list', {});
        if (!result) {
          console.error('[project] list failed');
          return [];
        }
        return result;
      },
    });
  },

  /** 获取单个项目 — 失败时返回 null */
  async getById(projectId: string): Promise<ProjectInfo | null> {
    return runDualTrack({ projectId }, {
      direct: async (args) => {
        const direct = await getDirectService();
        if (!direct) return null;
        try {
          return await direct.getProject(args.projectId);
        } catch (err) {
          console.error('[project] getById failed (direct):', err);
          return null;
        }
      },
      electron: async (args) => {
        const result = await serviceBridge.invoke<{ projectId: string }, ProjectGetResponse>('project:get', { projectId: args.projectId });
        if (!result) {
          console.error('[project] getById failed');
          return null;
        }
        return result;
      },
    });
  },

  /** 创建项目 — 失败时返回 null */
  async create(input: ProjectCreateRequest): Promise<ProjectInfo | null> {
    return runDualTrack(input, {
      direct: async (args) => {
        const direct = await getDirectService();
        if (!direct) return null;
        try {
          return await direct.createProject({
            name: args.name,
            description: args.description,
            settingTree: args.settingTree,
            settingTreeType: args.settingTreeType,
          });
        } catch (err) {
          console.error('[project] create failed (direct):', err);
          return null;
        }
      },
      electron: async (args) => {
        const result = await serviceBridge.invoke<ProjectCreateRequest, ProjectCreateResponse>('project:create', args);
        if (!result) {
          console.error('[project] create failed');
          return null;
        }
        return result;
      },
    });
  },

  /** 更新项目 — 失败时返回 null */
  async update(projectId: string, input: Omit<ProjectUpdateRequest, 'projectId'>): Promise<ProjectInfo | null> {
    return runDualTrack({ projectId, ...input }, {
      direct: async (args) => {
        const direct = await getDirectService();
        if (!direct) return null;
        try {
          return await direct.updateProject(args.projectId, {
            name: args.name,
            description: args.description,
            settingTree: args.settingTree,
            settingTreeType: args.settingTreeType,
          });
        } catch (err) {
          console.error('[project] update failed (direct):', err);
          return null;
        }
      },
      electron: async (args) => {
        const result = await serviceBridge.invoke<ProjectUpdateRequest, ProjectUpdateResponse>('project:update', {
          projectId: args.projectId,
          name: args.name,
          description: args.description,
          settingTree: args.settingTree,
          settingTreeType: args.settingTreeType,
        });
        if (!result) {
          console.error('[project] update failed');
          return null;
        }
        return result;
      },
    });
  },

  /** 删除项目 — 失败时返回 false */
  async remove(projectId: string): Promise<boolean> {
    return runDualTrack({ projectId }, {
      direct: async (args) => {
        const direct = await getDirectService();
        if (!direct) return false;
        try {
          await direct.deleteProject(args.projectId);
          return true;
        } catch (err) {
          console.error('[project] remove failed (direct):', err);
          return false;
        }
      },
      electron: async (args) => {
        const result = await serviceBridge.invoke<{ projectId: string }, void>('project:delete', { projectId: args.projectId });
        if (result === null) {
          console.error('[project] remove failed');
          return false;
        }
        return true;
      },
    });
  },
};
