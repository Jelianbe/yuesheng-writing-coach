/**
 * ProjectService 单测 — Sprint 26 阶段 2 (T26-2.2)
 *
 * 覆盖 src/shared/services/project.service.ts(异步 + StorageAdapter 版本)
 * - 使用 BetterSqliteAdapter(:memory:) 跑通(完整 SQL 支持)
 * - 验证 5 个核心方法:listProjects / getProject / createProject / updateProject / deleteProject
 * - 验证 PROJECT_NOT_FOUND 错误语义
 *
 * 依据: dev-docs/tasks/sprint-26-2-2-plan.md
 * 决策: D-074
 */
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import Database from 'better-sqlite3';
import { BetterSqliteAdapter } from '../../storage/adapters/better-sqlite.adapter';
import { ProjectService, ProjectNotFoundError } from '../project.service';
import type { StorageAdapter } from '../../storage/storage-adapter';

describe('ProjectService — Sprint 26 阶段 2 (BetterSqliteAdapter :memory:)', () => {
  let db: Database.Database;
  let adapter: StorageAdapter;
  let service: ProjectService;

  beforeEach(async () => {
    db = new Database(':memory:');
    adapter = new BetterSqliteAdapter({ db, dbName: 'test.db', version: 1 });
    await adapter.initialize();
    service = new ProjectService(adapter);
  });

  afterEach(async () => {
    await adapter.close().catch(() => {});
  });

  it('listProjects: 空表应返回空数组', async () => {
    const result = await service.listProjects();
    expect(result).toEqual([]);
  });

  it('createProject: 应创建并返回带 camelCase 字段的 ProjectInfo', async () => {
    const created = await service.createProject({
      name: '测试项目',
      description: '单元测试项目',
      settingTree: '{"type":"main"}',
      settingTreeType: 'main',
    });
    expect(created.id).toBeTruthy();
    expect(created.name).toBe('测试项目');
    expect(created.description).toBe('单元测试项目');
    expect(created.settingTree).toBe('{"type":"main"}');
    expect(created.settingTreeType).toBe('main');
    expect(typeof created.createdAt).toBe('number');
    expect(typeof created.updatedAt).toBe('number');
    expect(created.createdAt).toBe(created.updatedAt);
  });

  it('getProject: 找到应返回项目,未找到应返回 null', async () => {
    const created = await service.createProject({ name: 'A' });
    const found = await service.getProject(created.id);
    expect(found?.id).toBe(created.id);

    const notFound = await service.getProject('non-existent-id');
    expect(notFound).toBeNull();
  });

  it('updateProject: 应支持部分字段更新 + updatedAt 推进', async () => {
    const created = await service.createProject({ name: '原名' });
    // 等待 1 秒以让 unix 秒时间戳变化
    await new Promise((r) => setTimeout(r, 1100));
    const updated = await service.updateProject(created.id, { name: '新名' });
    expect(updated.name).toBe('新名');
    expect(updated.updatedAt).toBeGreaterThan(created.updatedAt);
  });

  it('updateProject: 找不到项目应抛 ProjectNotFoundError', async () => {
    await expect(
      service.updateProject('non-existent-id', { name: 'X' }),
    ).rejects.toBeInstanceOf(ProjectNotFoundError);
  });

  it('deleteProject: 成功应返回,二次删除应抛 ProjectNotFoundError', async () => {
    const created = await service.createProject({ name: '待删' });
    await service.deleteProject(created.id);
    const all = await service.listProjects();
    expect(all.find((p) => p.id === created.id)).toBeUndefined();

    await expect(service.deleteProject(created.id)).rejects.toBeInstanceOf(ProjectNotFoundError);
  });

  it('listProjects: 应按 updatedAt DESC 排序', async () => {
    const a = await service.createProject({ name: 'A' });
    await new Promise((r) => setTimeout(r, 1100));
    const b = await service.createProject({ name: 'B' });
    await new Promise((r) => setTimeout(r, 1100));
    const c = await service.createProject({ name: 'C' });

    const list = await service.listProjects();
    expect(list.map((p) => p.id)).toEqual([c.id, b.id, a.id]);
  });
});
