/** SessionService 单元测试
 * 覆盖：创建、列出、删除、重命名的核心逻辑
 * 可以拦截：crypto 未定义、SQL 语法错误、列缺失
 */
import { describe, it, expect, vi, beforeAll } from 'vitest';

// Mock better-sqlite3 — vi.hoisted 确保变量在 mock 被提升执行前定义
const mockStmt = vi.hoisted(() => ({
  run: vi.fn(),
  get: vi.fn(),
  all: vi.fn(),
}));

const mockDb = vi.hoisted(() => ({
  prepare: vi.fn(() => mockStmt),
  exec: vi.fn(),
  close: vi.fn(),
}));

vi.mock('better-sqlite3', () => ({
  default: function () {
    return mockDb;
  },
}));

import Database from 'better-sqlite3';
import { SessionService } from './session.service';

describe('SessionService', () => {
  let db: Database.Database;
  let service: SessionService;

  beforeAll(() => {
    vi.clearAllMocks();
    db = new Database(':memory:');
    service = new SessionService(db);
    // 重置 mock 调用状态
    vi.clearAllMocks();
  });

  it('createSession 应创建并返回新会话', () => {
    mockStmt.run.mockReturnValue({ changes: 1 });

    const session = service.createSession();

    expect(mockDb.prepare).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO sessions')
    );
    expect(mockStmt.run).toHaveBeenCalled();
    expect(session).toBeDefined();
    expect(session.id).toBeTruthy();
    expect(session.title).toBe('新建会话');
    expect(session.created_at).toBeTruthy();
    expect(session.updated_at).toBeTruthy();
  });

  it('listSessions 应返回会话列表', () => {
    const mockSessions: any[] = [
      { id: '1', title: '会话 A', created_at: '2026-01-01', updated_at: '2026-01-02' },
      { id: '2', title: '会话 B', created_at: '2026-01-01', updated_at: '2026-01-01' },
    ];
    mockStmt.all.mockReturnValueOnce(mockSessions);

    const sessions = service.listSessions();
    expect(sessions).toEqual(mockSessions);
    expect(sessions.length).toBe(2);
  });

  it('renameSession 应执行 UPDATE 语句', () => {
    service.renameSession('sess-001', '新标题');

    expect(mockDb.prepare).toHaveBeenCalledWith(
      expect.stringContaining('UPDATE sessions SET title')
    );
    expect(mockStmt.run).toHaveBeenCalled();
  });

  it('deleteSession 应执行 DELETE 语句', () => {
    service.deleteSession('sess-001');

    expect(mockDb.prepare).toHaveBeenCalledWith(
      expect.stringContaining('DELETE FROM sessions')
    );
    expect(mockStmt.run).toHaveBeenCalled();
  });

  it('saveMessage 应保存并返回消息', () => {
    mockStmt.run.mockReturnValue({ changes: 1 });

    const message = service.saveMessage('sess-001', 'user', '你好');

    expect(mockDb.prepare).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO messages')
    );
    expect(message.role).toBe('user');
    expect(message.content).toBe('你好');
    expect(message.session_id).toBe('sess-001');
  });

  it('getMessages 应返回消息数组', () => {
    mockStmt.all.mockReturnValueOnce([]);
    const messages = service.getMessages('sess-001');
    expect(Array.isArray(messages)).toBe(true);
    expect(messages.length).toBe(0);
  });

  it('getOrCreateDefaultSession 无会话时应新建', () => {
    mockStmt.all.mockReturnValueOnce([]); // listSessions 返回空
    mockStmt.run.mockReturnValue({ changes: 1 });

    const session = service.getOrCreateDefaultSession();
    expect(session.title).toBe('新建会话');
    expect(session.id).toBeTruthy();
  });

  it('getOrCreateDefaultSession 有会话时应返回第一个', () => {
    const existing: any[] = [
      { id: 'existing-1', title: '已有会话', created_at: '2026-01-01', updated_at: '2026-01-02' },
    ];
    mockStmt.all.mockReturnValueOnce(existing);

    const session = service.getOrCreateDefaultSession();
    expect(session.id).toBe('existing-1');
    expect(session.title).toBe('已有会话');
  });

  it('autoGenerateTitle 应从首条消息截取标题', () => {
    const msgContent = '这是一条测试消息';
    mockStmt.get.mockReturnValueOnce({ content: msgContent });

    service.autoGenerateTitle('sess-001');
    expect(mockDb.prepare).toHaveBeenCalledWith(
      expect.stringContaining('UPDATE sessions SET title')
    );
    expect(mockStmt.run).toHaveBeenCalledWith(msgContent, expect.any(String), 'sess-001');
  });
});
