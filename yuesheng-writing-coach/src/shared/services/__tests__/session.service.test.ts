/**
 * SessionService 单测 — Sprint 26 阶段 2 (T26-2.1)
 *
 * 覆盖 src/shared/services/session.service.ts(异步 + StorageAdapter 版本)
 * - 使用 BetterSqliteAdapter(:memory:) 跑通(完整 SQL 支持)
 * - 验证 11 个核心方法行为
 *
 * 依据: dev-docs/tasks/sprint-26-2-1-plan.md
 * 决策: D-074
 */
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import Database from 'better-sqlite3';
import { BetterSqliteAdapter } from '../../storage/adapters/better-sqlite.adapter';
import { SessionService } from '../session.service';
import type { StorageAdapter } from '../../storage/storage-adapter';

describe('SessionService — Sprint 26 阶段 2 (BetterSqliteAdapter :memory:)', () => {
  let db: Database.Database;
  let adapter: StorageAdapter;
  let service: SessionService;

  beforeEach(async () => {
    db = new Database(':memory:');
    adapter = new BetterSqliteAdapter({ db, dbName: 'test.db', version: 1 });
    await adapter.initialize();
    service = new SessionService(adapter);
  });

  afterEach(async () => {
    await adapter.close().catch(() => {});
  });

  it('listSessions: 空表应返回空数组', async () => {
    const result = await service.listSessions();
    expect(result).toEqual([]);
  });

  it('createSession: 应创建并返回新会话', async () => {
    const created = await service.createSession();
    expect(created.id).toBeTruthy();
    expect(created.title).toBe('新建会话');
    expect(created.created_at).toBe(created.updated_at);

    const list = await service.listSessions();
    expect(list.length).toBe(1);
    expect(list[0]?.id).toBe(created.id);
  });

  it('renameSession: 应更新 title 和 updated_at', async () => {
    const created = await service.createSession();
    await new Promise((r) => setTimeout(r, 10));
    await service.renameSession(created.id, '新标题');

    const list = await service.listSessions();
    const renamed = list.find((s) => s.id === created.id);
    expect(renamed?.title).toBe('新标题');
    expect(renamed?.updated_at).not.toBe(created.updated_at);
  });

  it('deleteSession: 应从表中删除', async () => {
    const created = await service.createSession();
    await service.deleteSession(created.id);

    const list = await service.listSessions();
    expect(list.find((s) => s.id === created.id)).toBeUndefined();
  });

  it('saveMessage + getMessages: 事务应插入消息并更新会话时间', async () => {
    const created = await service.createSession();
    await new Promise((r) => setTimeout(r, 10));
    const originalUpdatedAt = created.updated_at;

    const msg = await service.saveMessage(created.id, 'user', '你好,世界');
    expect(msg.session_id).toBe(created.id);
    expect(msg.role).toBe('user');
    expect(msg.content).toBe('你好,世界');
    expect(msg.id).toBeTruthy();

    const messages = await service.getMessages(created.id);
    expect(messages.length).toBe(1);
    expect(messages[0]?.id).toBe(msg.id);

    const list = await service.listSessions();
    const refreshed = list.find((s) => s.id === created.id);
    expect(refreshed?.updated_at).not.toBe(originalUpdatedAt);
  });

  it('getMessagesPaged: 应支持分页与 hasMore', async () => {
    const created = await service.createSession();
    for (let i = 0; i < 5; i++) {
      await service.saveMessage(created.id, 'user', `消息 ${i}`);
    }
    const page1 = await service.getMessagesPaged(created.id, 0, 2);
    expect(page1.messages.length).toBe(2);
    expect(page1.total).toBe(5);
    expect(page1.hasMore).toBe(true);

    const page2 = await service.getMessagesPaged(created.id, 2, 2);
    expect(page2.messages.length).toBe(2);
    expect(page2.hasMore).toBe(true);

    const page3 = await service.getMessagesPaged(created.id, 4, 2);
    expect(page3.messages.length).toBe(1);
    expect(page3.hasMore).toBe(false);
  });

  it('getLastMessage: 无消息应返回 null', async () => {
    const created = await service.createSession();
    const last = await service.getLastMessage(created.id);
    expect(last).toBeNull();
  });

  it('getOrCreateDefaultSession: 空表应新建,有表应返回第一个', async () => {
    const first = await service.getOrCreateDefaultSession();
    expect(first).toBeTruthy();

    const second = await service.getOrCreateDefaultSession();
    expect(second.id).toBe(first.id);
  });
});
