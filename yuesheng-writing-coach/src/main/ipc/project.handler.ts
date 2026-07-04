import { IPC_CHANNELS } from '../../shared/constants';
// Sprint 26 阶段 2:切到 shared/services/project.service.ts(异步 + StorageAdapter)
import type { ProjectService, ProjectInfo } from '../../shared/services/project.service';
import { ProjectNotFoundError } from '../../shared/services/project.service';
import { validatePayload } from './utils/validate-payload';
import { createHandler } from './utils/create-handler';

export interface ProjectHandlerDeps {
  projectService: ProjectService;
}

let deps: ProjectHandlerDeps | null = null;

export function initProjectHandlers(d: ProjectHandlerDeps): void {
  deps = d;
}

export function registerProjectHandlers(): void {
  if (!deps) throw new Error('ProjectHandler deps not injected');
  const d = deps;

  // project:list — 列出所有项目(按 updatedAt DESC)
  createHandler(IPC_CHANNELS.PROJECT_LIST, async () => {
    return d.projectService.listProjects();
  });

  // project:get — 获取单个项目详情
  createHandler(IPC_CHANNELS.PROJECT_GET, async (_event, args) => {
    const validation = validatePayload<{ projectId: string }>(args, {
      required: ['projectId'],
      types: { projectId: 'string' },
    });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    return d.projectService.getProject(validation.data.projectId);
  });

  // project:create — 创建新项目
  createHandler(IPC_CHANNELS.PROJECT_CREATE, async (_event, args) => {
    const validation = validatePayload<{
      name: string;
      description?: string;
      settingTree?: string;
      settingTreeType?: string;
    }>(args, {
      required: ['name'],
      types: { name: 'string', description: 'string', settingTree: 'string', settingTreeType: 'string' },
    });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    return d.projectService.createProject({
      name: validation.data.name,
      description: validation.data.description,
      settingTree: validation.data.settingTree,
      settingTreeType: validation.data.settingTreeType,
    });
  });

  // project:update — 更新项目信息(动态 SET 拼接)
  createHandler(IPC_CHANNELS.PROJECT_UPDATE, async (_event, args) => {
    const validation = validatePayload<{
      projectId: string;
      name?: string;
      description?: string;
      settingTree?: string;
      settingTreeType?: string;
    }>(args, {
      required: ['projectId'],
      types: { projectId: 'string', name: 'string', description: 'string', settingTree: 'string', settingTreeType: 'string' },
    });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    try {
      return await d.projectService.updateProject(validation.data.projectId, {
        name: validation.data.name,
        description: validation.data.description,
        settingTree: validation.data.settingTree,
        settingTreeType: validation.data.settingTreeType,
      });
    } catch (e) {
      if (e instanceof ProjectNotFoundError) {
        throw new Error(`PROJECT_NOT_FOUND: ${e.projectId}`);
      }
      throw e;
    }
  });

  // project:delete — 删除项目
  // 注: sessions/manuscripts 的 project_id 外键尚未建立(RWR-P0-5 处理),
  //    故暂不级联删除关联数据
  createHandler(IPC_CHANNELS.PROJECT_DELETE, async (_event, args) => {
    const validation = validatePayload<{ projectId: string }>(args, {
      required: ['projectId'],
      types: { projectId: 'string' },
    });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    try {
      await d.projectService.deleteProject(validation.data.projectId);
    } catch (e) {
      if (e instanceof ProjectNotFoundError) {
        throw new Error(`PROJECT_NOT_FOUND: ${e.projectId}`);
      }
      throw e;
    }
  });
}

export type { ProjectInfo };
