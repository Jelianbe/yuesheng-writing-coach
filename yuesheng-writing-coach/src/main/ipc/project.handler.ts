import crypto from 'node:crypto';
import { IPC_CHANNELS } from '../../shared/constants';
import { validatePayload } from './utils/validate-payload';
import { createHandler } from './utils/create-handler';
import type Database from 'better-sqlite3';
import type { ProjectInfo } from '../../shared/api-contracts/project.contract';

export interface ProjectHandlerDeps {
  db: Database.Database;
}

let deps: ProjectHandlerDeps | null = null;

export function initProjectHandlers(d: ProjectHandlerDeps): void {
  deps = d;
}

/**
 * 数据库行 → ProjectInfo 投影
 * (snake_case → camelCase)
 */
function rowToProjectInfo(row: Record<string, unknown>): ProjectInfo {
  return {
    id: row.id as string,
    name: row.name as string,
    description: (row.description as string | null) ?? null,
    settingTree: (row.setting_tree as string | null) ?? null,
    settingTreeType: (row.setting_tree_type as string) ?? 'main',
    createdAt: row.created_at as number,
    updatedAt: row.updated_at as number,
  };
}

export function registerProjectHandlers(): void {
  if (!deps) throw new Error('ProjectHandler deps not injected');
  const d = deps;

  // project:list — 列出所有项目(按 updatedAt DESC)
  createHandler(IPC_CHANNELS.PROJECT_LIST, () => {
    const rows = d.db.prepare('SELECT * FROM projects ORDER BY updated_at DESC').all() as Record<string, unknown>[];
    return rows.map(rowToProjectInfo);
  });

  // project:get — 获取单个项目详情
  createHandler(IPC_CHANNELS.PROJECT_GET, (_event, args) => {
    const validation = validatePayload<{ projectId: string }>(args, {
      required: ['projectId'],
      types: { projectId: 'string' },
    });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    const row = d.db.prepare('SELECT * FROM projects WHERE id = ?').get(validation.data.projectId) as Record<string, unknown> | undefined;
    return row ? rowToProjectInfo(row) : null;
  });

  // project:create — 创建新项目
  createHandler(IPC_CHANNELS.PROJECT_CREATE, (_event, args) => {
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
    const id = crypto.randomUUID();
    const now = Math.floor(Date.now() / 1000);
    d.db.prepare(
      'INSERT INTO projects (id, name, description, setting_tree, setting_tree_type, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)'
    ).run(
      id,
      validation.data.name,
      validation.data.description ?? null,
      validation.data.settingTree ?? null,
      validation.data.settingTreeType ?? 'main',
      now,
      now,
    );
    const row = d.db.prepare('SELECT * FROM projects WHERE id = ?').get(id) as Record<string, unknown>;
    return rowToProjectInfo(row);
  });

  // project:update — 更新项目信息(动态 SET 拼接)
  createHandler(IPC_CHANNELS.PROJECT_UPDATE, (_event, args) => {
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

    const now = Math.floor(Date.now() / 1000);
    const sets: string[] = ['updated_at = ?'];
    const values: unknown[] = [now];
    if (validation.data.name !== undefined) { sets.push('name = ?'); values.push(validation.data.name); }
    if (validation.data.description !== undefined) { sets.push('description = ?'); values.push(validation.data.description); }
    if (validation.data.settingTree !== undefined) { sets.push('setting_tree = ?'); values.push(validation.data.settingTree); }
    if (validation.data.settingTreeType !== undefined) { sets.push('setting_tree_type = ?'); values.push(validation.data.settingTreeType); }
    values.push(validation.data.projectId);

    const result = d.db.prepare(`UPDATE projects SET ${sets.join(', ')} WHERE id = ?`).run(...values);
    if (result.changes === 0) {
      throw new Error(`PROJECT_NOT_FOUND: ${validation.data.projectId}`);
    }
    const row = d.db.prepare('SELECT * FROM projects WHERE id = ?').get(validation.data.projectId) as Record<string, unknown>;
    return rowToProjectInfo(row);
  });

  // project:delete — 删除项目
  // 注: sessions/manuscripts 的 project_id 外键尚未建立(RWR-P0-5 处理),
  //    故暂不级联删除关联数据
  createHandler(IPC_CHANNELS.PROJECT_DELETE, (_event, args) => {
    const validation = validatePayload<{ projectId: string }>(args, {
      required: ['projectId'],
      types: { projectId: 'string' },
    });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    const result = d.db.prepare('DELETE FROM projects WHERE id = ?').run(validation.data.projectId);
    if (result.changes === 0) {
      throw new Error(`PROJECT_NOT_FOUND: ${validation.data.projectId}`);
    }
    // 响应: void(与 ProjectDeleteResponse = void 一致, R-007 双向绑定)
  });
}
