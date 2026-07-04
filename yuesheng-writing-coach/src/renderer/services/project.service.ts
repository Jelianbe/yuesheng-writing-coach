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
import { typedInvoke } from './ipc-client';
import { ProjectApi } from '../../shared/api-contracts/project.contract';
import type {
  ProjectInfo,
  ProjectListResponse,
  ProjectGetResponse,
  ProjectCreateResponse,
  ProjectUpdateResponse,
  ProjectDeleteResponse,
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
        const result = await typedInvoke<Record<string, never>, ProjectListResponse>(
          ProjectApi.list.channel,
          {},
        );
        if (!result.success) {
          console.error('[project] list failed:', result.error);
          return [];
        }
        return result.data;
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
        const result = await typedInvoke<{ projectId: string }, ProjectGetResponse>(
          ProjectApi.get.channel,
          { projectId: args.projectId },
        );
        if (!result.success) {
          console.error('[project] getById failed:', result.error);
          return null;
        }
        return result.data;
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
        const result = await typedInvoke<ProjectCreateRequest, ProjectCreateResponse>(
          ProjectApi.create.channel,
          args,
        );
        if (!result.success) {
          console.error('[project] create failed:', result.error);
          return null;
        }
        return result.data;
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
        const result = await typedInvoke<ProjectUpdateRequest, ProjectUpdateResponse>(
          ProjectApi.update.channel,
          {
            projectId: args.projectId,
            name: args.name,
            description: args.description,
            settingTree: args.settingTree,
            settingTreeType: args.settingTreeType,
          },
        );
        if (!result.success) {
          console.error('[project] update failed:', result.error);
          return null;
        }
        return result.data;
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
        const result = await typedInvoke<{ projectId: string }, ProjectDeleteResponse>(
          ProjectApi.delete.channel,
          { projectId: args.projectId },
        );
        if (!result.success) {
          console.error('[project] remove failed:', result.error);
          return false;
        }
        return true;
      },
    });
  },
};
