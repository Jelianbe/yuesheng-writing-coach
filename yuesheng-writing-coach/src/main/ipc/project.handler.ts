/**
 * 项目管理 — Sprint 26 阶段 3.5 方案 4a bridge 注册
 *
 * 原 IPC handler 已废弃,改为 registerMethod 走单端点 bridge:invoke。
 * 调用方:`serviceBridge.invoke('project:list' | 'project:get' | 'project:create' | 'project:update' | 'project:delete', ...)`
 *
 * 注: 3.4 评估标记为删除候选(纯直调),先迁 bridge 作为过渡收口,后续批次 4 统一删除
 */

import type { ProjectService, ProjectInfo } from '../../shared/services/project.service';
import { ProjectNotFoundError } from '../../shared/services/project.service';
import { validatePayload } from './utils/validate-payload';
import { registerMethod } from '../core/service-bridge';

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

  registerMethod('project:list', async (_args) => {
    return d.projectService.listProjects();
  });

  registerMethod('project:get', async (args) => {
    const validation = validatePayload<{ projectId: string }>(args, {
      required: ['projectId'],
      types: { projectId: 'string' },
    });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    return d.projectService.getProject(validation.data.projectId);
  });

  registerMethod('project:create', async (args) => {
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

  registerMethod('project:update', async (args) => {
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

  registerMethod('project:delete', async (args) => {
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
