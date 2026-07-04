/**
 * ProjectService — Sprint 26 跨端版
 *
 * 双端共用,接 StorageAdapter:
 * - Electron 端: 用 BetterSqliteAdapter(走主进程,经 IPC)
 * - Android 端: 用 CapacitorSqliteAdapter(走 WebView 直接调用)
 *
 * 关键差异(对比 main/ipc/project.handler.ts 直接 db 访问):
 * - 同步 → 异步
 * - `better-sqlite3.Database` → `StorageAdapter`
 * - 直接 prepare/run/get 改为 `adapter.query()` / `adapter.execute()`
 * - 行→ProjectInfo 投影集中到 service 层(handler 变为薄壳)
 *
 * 表结构(021_projects.sql):
 *   id / name / description / setting_tree / setting_tree_type
 *   created_at / updated_at  -- INTEGER unix 秒
 *
 * 依据: dev-docs/tasks/sprint-26-2-2-plan.md
 */
import type { StorageAdapter } from '../storage/storage-adapter';
import type { DatabaseRow } from '../storage/storage-types';

export interface ProjectRow extends DatabaseRow {
  id: string;
  name: string;
  description: string | null;
  setting_tree: string | null;
  setting_tree_type: string;
  created_at: number;
  updated_at: number;
}

export interface ProjectInfo {
  id: string;
  name: string;
  description: string | null;
  settingTree: string | null;
  settingTreeType: string;
  createdAt: number;
  updatedAt: number;
}

export interface ProjectCreateInput {
  name: string;
  description?: string;
  settingTree?: string;
  settingTreeType?: string;
}

export interface ProjectUpdateInput {
  name?: string;
  description?: string;
  settingTree?: string;
  settingTreeType?: string;
}

export class ProjectNotFoundError extends Error {
  constructor(public readonly projectId: string) {
    super(`PROJECT_NOT_FOUND: ${projectId}`);
    this.name = 'ProjectNotFoundError';
  }
}

export class ProjectService {
  constructor(private readonly adapter: StorageAdapter) {}

  async listProjects(): Promise<ProjectInfo[]> {
    const rows = await this.adapter.query<ProjectRow>(
      'SELECT * FROM projects ORDER BY updated_at DESC',
    );
    return rows.map(rowToProjectInfo);
  }

  async getProject(projectId: string): Promise<ProjectInfo | null> {
    const row = await this.adapter.queryOne<ProjectRow>(
      'SELECT * FROM projects WHERE id = ?',
      [projectId],
    );
    return row ? rowToProjectInfo(row) : null;
  }

  async createProject(input: ProjectCreateInput): Promise<ProjectInfo> {
    const id = this.generateUUID();
    const now = Math.floor(Date.now() / 1000);
    await this.adapter.execute(
      'INSERT INTO projects (id, name, description, setting_tree, setting_tree_type, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        id,
        input.name,
        input.description ?? null,
        input.settingTree ?? null,
        input.settingTreeType ?? 'main',
        now,
        now,
      ],
    );
    return {
      id,
      name: input.name,
      description: input.description ?? null,
      settingTree: input.settingTree ?? null,
      settingTreeType: input.settingTreeType ?? 'main',
      createdAt: now,
      updatedAt: now,
    };
  }

  async updateProject(
    projectId: string,
    input: ProjectUpdateInput,
  ): Promise<ProjectInfo> {
    const now = Math.floor(Date.now() / 1000);
    const sets: string[] = ['updated_at = ?'];
    const values: unknown[] = [now];
    if (input.name !== undefined) {
      sets.push('name = ?');
      values.push(input.name);
    }
    if (input.description !== undefined) {
      sets.push('description = ?');
      values.push(input.description);
    }
    if (input.settingTree !== undefined) {
      sets.push('setting_tree = ?');
      values.push(input.settingTree);
    }
    if (input.settingTreeType !== undefined) {
      sets.push('setting_tree_type = ?');
      values.push(input.settingTreeType);
    }
    values.push(projectId);

    const result = await this.adapter.execute(
      `UPDATE projects SET ${sets.join(', ')} WHERE id = ?`,
      values as Array<string | number | null>,
    );
    if (result.changes === 0) {
      throw new ProjectNotFoundError(projectId);
    }
    const updated = await this.getProject(projectId);
    if (!updated) {
      throw new ProjectNotFoundError(projectId);
    }
    return updated;
  }

  async deleteProject(projectId: string): Promise<void> {
    const result = await this.adapter.execute(
      'DELETE FROM projects WHERE id = ?',
      [projectId],
    );
    if (result.changes === 0) {
      throw new ProjectNotFoundError(projectId);
    }
  }

  private generateUUID(): string {
    return globalThis.crypto.randomUUID();
  }
}

export function rowToProjectInfo(row: ProjectRow): ProjectInfo {
  return {
    id: row.id,
    name: row.name,
    description: row.description ?? null,
    settingTree: row.setting_tree ?? null,
    settingTreeType: row.setting_tree_type ?? 'main',
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}
