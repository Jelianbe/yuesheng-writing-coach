# 数据持久化与会话管理 实施计划

> **For agentic workers:** Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 打通消息落库 → 诊断触发 → 会话管理全链路

**架构:** 三阶段递进：A) SQLite 建表+消息持久化 → B) 接通诊断解析链路 → C) 会话管理 UI

**Tech Stack:** better-sqlite3, Electron IPC, Zustand, React

---

## 文件结构

| 类别 | 文件 | 职责 |
|------|------|------|
| 新建 | `src/main/db/004_create_chat.sql` | sessions + messages 建表迁移 |
| 新建 | `src/main/services/session.service.ts` | Session/Messages CRUD 封装 |
| 新建 | `src/main/ipc/session.handler.ts` | 5 个 session IPC 通道 |
| 新建 | `src/renderer/stores/session.store.ts` | 前端会话状态管理 |
| 新建 | `src/renderer/components/SessionSidebar.tsx` | 左侧会话列表 UI |
| 修改 | `src/main/index.ts` | 注册新迁移 + session 服务 |
| 修改 | `src/main/ipc/chat.handler.ts` | 流结束后持久化消息 + 触发诊断 |
| 修改 | `src/main/ipc/diagnosis.handler.ts` | 导出 processDiagnosisFromAI |
| 修改 | `src/preload/index.ts` | 白名单追加 session 通道 |
| 修改 | `src/renderer/App.tsx` | 集成 SessionSidebar |
| 修改 | `src/renderer/stores/chat.store.ts` | 集成 session store（切换会话加载消息） |
| 修改 | `src/renderer/components/ChatPage.tsx` | 移除旧 header 对接新布局 |
| 修改 | `src/renderer/shared/types.ts` | Session 类型 + IPC_CHANNELS + 类型映射 |

---

### 阶段 A — 数据库建表 + 消息持久化

#### Task A1: 创建迁移 SQL + SessionService

**Files:**
- Create: `src/main/db/004_create_chat.sql`
- Create: `src/main/services/session.service.ts`

- [ ] **创建 004_create_chat.sql**

```sql
CREATE TABLE IF NOT EXISTS sessions (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL DEFAULT '新建会话',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS messages (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK(role IN ('user', 'assistant', 'system')),
  content TEXT NOT NULL,
  timestamp INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_messages_session ON messages(session_id, timestamp);
```

- [ ] **创建 SessionService**

```typescript
// src/main/services/session.service.ts
import Database from 'better-sqlite3';

export interface SessionRow {
  id: string;
  title: string;
  created_at: string;
  updated_at: string;
}

export interface MessageRow {
  id: string;
  session_id: string;
  role: 'user' | 'assistant' | 'system';
  content: string;
  timestamp: number;
}

export class SessionService {
  private db: Database.Database;

  constructor(db: Database.Database) {
    this.db = db;
  }

  /** 获取所有会话（按更新时间降序） */
  listSessions(): SessionRow[] {
    return this.db.prepare('SELECT * FROM sessions ORDER BY updated_at DESC').all() as SessionRow[];
  }

  /** 创建新会话 */
  createSession(): SessionRow {
    const id = crypto.randomUUID();
    const now = new Date().toISOString();
    this.db.prepare('INSERT INTO sessions (id, title, created_at, updated_at) VALUES (?, ?, ?, ?)').run(id, '新建会话', now, now);
    return { id, title: '新建会话', created_at: now, updated_at: now };
  }

  /** 删除会话（级联删除消息） */
  deleteSession(sessionId: string): void {
    this.db.prepare('DELETE FROM sessions WHERE id = ?').run(sessionId);
  }

  /** 重命名会话 */
  renameSession(sessionId: string, title: string): void {
    const now = new Date().toISOString();
    this.db.prepare('UPDATE sessions SET title = ?, updated_at = ? WHERE id = ?').run(title, now, sessionId);
  }

  /** 保存消息 */
  saveMessage(sessionId: string, role: 'user' | 'assistant' | 'system', content: string): MessageRow {
    const id = crypto.randomUUID();
    const timestamp = Date.now();
    this.db.prepare('INSERT INTO messages (id, session_id, role, content, timestamp) VALUES (?, ?, ?, ?, ?)').run(id, sessionId, role, content, timestamp);
    // 更新会话 updated_at
    this.db.prepare('UPDATE sessions SET updated_at = ? WHERE id = ?').run(new Date().toISOString(), sessionId);
    return { id, session_id: sessionId, role, content, timestamp };
  }

  /** 获取会话的所有消息（按时间升序） */
  getMessages(sessionId: string): MessageRow[] {
    return this.db.prepare('SELECT * FROM messages WHERE session_id = ? ORDER BY timestamp ASC').all(sessionId) as MessageRow[];
  }

  /** 获取会话的最后一条消息（用于列表预览） */
  getLastMessage(sessionId: string): MessageRow | undefined {
    return this.db.prepare('SELECT * FROM messages WHERE session_id = ? ORDER BY timestamp DESC LIMIT 1').get(sessionId) as MessageRow | undefined;
  }

  /** 首条消息后自动生成标题 */
  autoGenerateTitle(sessionId: string): void {
    const first = this.db.prepare("SELECT content FROM messages WHERE session_id = ? AND role = 'user' ORDER BY timestamp ASC LIMIT 1").get(sessionId) as { content: string } | undefined;
    if (first) {
      const title = first.content.length > 20 ? first.content.slice(0, 20) + '...' : first.content;
      this.renameSession(sessionId, title);
    }
  }

  /** 获取或创建默认会话 */
  getOrCreateDefaultSession(): SessionRow {
    const sessions = this.listSessions();
    if (sessions.length > 0) return sessions[0];
    return this.createSession();
  }
}
```

#### Task A2: 注册迁移 + 挂载 SessionService

**Files:**
- Modify: `src/main/index.ts`

- [ ] **在 initDatabase() 之后添加 004 迁移**

在 `runMigrations(db)` 调用附近添加 004 迁移：

```typescript
// 004: 创建会话和消息表
const chatMigrationPath = app.isPackaged
  ? path.join(process.resourcesPath, 'db/004_create_chat.sql')
  : path.join(app.getAppPath(), 'src/main/db/004_create_chat.sql');
if (fs.existsSync(chatMigrationPath)) {
  const sql = fs.readFileSync(chatMigrationPath, 'utf-8');
  db.exec(sql);
} else {
  console.warn(`[Migration] 004 SQL file not found at: ${chatMigrationPath}`);
}
```

- [ ] **创建 SessionService 实例并导出**

```typescript
import { SessionService } from './services/session.service';

// 在 app.whenReady() 内
const sessionService = new SessionService(db);
```

#### Task A3: chat.handler 消息落库

**Files:**
- Modify: `src/main/ipc/chat.handler.ts`

- [ ] **导入 SessionService**

```typescript
import { SessionService } from '../services/session.service';
```

- [ ] **export 函数接收 sessionService**

在 `registerChatHandlers` 之前添加：
```typescript
let sessionService: SessionService;

export function setSessionService(svc: SessionService): void {
  sessionService = svc;
}
```

- [ ] **在 IPC handler 内持久化消息**

在 `chat:send` handler 中，调用 `ApiProxy.chatStream()` **之前**：
```typescript
// 确保会话存在
const activeSessionId = args.sessionId || sessionService.getOrCreateDefaultSession().id;
// 保存用户消息
const userMsg = sessionService.saveMessage(activeSessionId, 'user', args.message.trim());
```

在 `chat:stream:end` 回调中，保存 AI 回复后：
```typescript
// 保存 AI 回复
sessionService.saveMessage(activeSessionId, 'assistant', fullResponse);
// 自动生成标题（仅首次）
sessionService.autoGenerateTitle(activeSessionId);
```

- [ ] **调整 stream:end 事件推送数据，包含 sessionId**

确保 `chat:stream:end` 推送的 `{ sessionId, fullResponse, messageId }` 中 sessionId 正确。

- [ ] **IPC 响应返回 sessionId**

```typescript
return { success: true, messageId, sessionId: activeSessionId };
```

#### Task A4: 类型补充 + 注册入口

**Files:**
- Modify: `src/renderer/shared/types.ts`
- Modify: `src/main/index.ts`

- [ ] **shared/types.ts 添加 Session 接口**

```typescript
export interface Session {
  id: string;
  title: string;
  createdAt: string;
  updatedAt: string;
  lastMessage?: string;
}
```

- [ ] **main/index.ts 将 sessionService 注入 chat.handler**

```typescript
import { registerChatHandlers, setChatMainWindow, setSessionService } from './ipc/chat.handler';
// ...
const sessionService = new SessionService(db);
setSessionService(sessionService);
```

- [ ] **类型检查**

Run: `npx tsc --noEmit`

---

### 阶段 B — 诊断链路接通

#### Task B1: 导出 processDiagnosisFromAI

**Files:**
- Modify: `src/main/ipc/diagnosis.handler.ts`

- [ ] **确认 `processDiagnosisFromAI` 已导出**

查看 `diagnosis.handler.ts` 中是否有 `export function processDiagnosisFromAI`。如果没有，添加导出。

```typescript
export function processDiagnosisFromAI(
  fullResponse: string,
  sessionId: string,
  teachingStateStore: TeachingStateStore,
  mainWindow: BrowserWindow,
): void {
  // ... 现有逻辑
}
```

#### Task B2: chat.handler 流结束后调用诊断

**Files:**
- Modify: `src/main/ipc/chat.handler.ts`

- [ ] **导入 processDiagnosisFromAI**

```typescript
import { processDiagnosisFromAI } from './diagnosis.handler';
```

- [ ] **在 stream:end 回调中调用**

```typescript
// 触发诊断解析
try {
  processDiagnosisFromAI(fullResponse, activeSessionId, teachingStateStore, mainWindow);
} catch (err) {
  console.error('[Chat] Diagnosis processing failed:', err);
}
```

---

### 阶段 C — 会话管理 UI

#### Task C1: IPC handler + Preload 白名单

**Files:**
- Create: `src/main/ipc/session.handler.ts`
- Modify: `src/preload/index.ts`

- [ ] **创建 session.handler.ts**

```typescript
import { ipcMain } from 'electron';
import { IPC_CHANNELS } from '../../renderer/shared/types';
import { SessionService } from '../services/session.service';

let sessionService: SessionService;

export function setSessionService(svc: SessionService): void {
  sessionService = svc;
}

export function registerSessionHandlers(): void {
  ipcMain.handle(IPC_CHANNELS.SESSION_LIST, () => {
    const sessions = sessionService.listSessions();
    return sessions.map(s => ({
      ...s,
      lastMessage: sessionService.getLastMessage(s.id)?.content.slice(0, 50) || undefined,
    }));
  });

  ipcMain.handle(IPC_CHANNELS.SESSION_CREATE, () => {
    return sessionService.createSession();
  });

  ipcMain.handle(IPC_CHANNELS.SESSION_DELETE, (_event, args: { sessionId: string }) => {
    sessionService.deleteSession(args.sessionId);
  });

  ipcMain.handle(IPC_CHANNELS.SESSION_RENAME, (_event, args: { sessionId: string; title: string }) => {
    sessionService.renameSession(args.sessionId, args.title);
  });

  ipcMain.handle(IPC_CHANNELS.SESSION_GET_MESSAGES, (_event, args: { sessionId: string }) => {
    return sessionService.getMessages(args.sessionId);
  });
}
```

- [ ] **Preload 白名单添加通道**

在 `allowedChannels` 中添加：
```
'session:list',
'session:create',
'session:delete',
'session:rename',
'session:getMessages',
```

- [ ] **main/index.ts 注册 session handler**

```typescript
import { registerSessionHandlers, setSessionService as setSessionHandlerService } from './ipc/session.handler';
// ...
setSessionHandlerService(sessionService);
registerSessionHandlers();
```

#### Task C2: shared/types.ts 追加 IPC_CHANNELS + 类型映射

**Files:**
- Modify: `src/renderer/shared/types.ts`

- [ ] **IPC_CHANNELS 追加**

```typescript
SESSION_LIST: 'session:list',
SESSION_CREATE: 'session:create',
SESSION_DELETE: 'session:delete',
SESSION_RENAME: 'session:rename',
SESSION_GET_MESSAGES: 'session:getMessages',
```

- [ ] **IPCRequestMap 追加**

```typescript
[IPC_CHANNELS.SESSION_LIST]: {};
[IPC_CHANNELS.SESSION_CREATE]: {};
[IPC_CHANNELS.SESSION_DELETE]: { sessionId: string };
[IPC_CHANNELS.SESSION_RENAME]: { sessionId: string; title: string };
[IPC_CHANNELS.SESSION_GET_MESSAGES]: { sessionId: string };
```

- [ ] **IPCResponseMap 追加**

```typescript
[IPC_CHANNELS.SESSION_LIST]: Session[];
[IPC_CHANNELS.SESSION_CREATE]: Session;
[IPC_CHANNELS.SESSION_DELETE]: void;
[IPC_CHANNELS.SESSION_RENAME]: void;
[IPC_CHANNELS.SESSION_GET_MESSAGES]: MessageRow[];
```

- [ ] **导出 MessageRow 类型**

```typescript
export interface MessageRow {
  id: string;
  session_id: string;
  role: string;
  content: string;
  timestamp: number;
}
```

#### Task C3: session.store.ts

**Files:**
- Create: `src/renderer/stores/session.store.ts`

- [ ] **创建 session store**

```typescript
import { create } from 'zustand';
import { Session, MessageRow, IPC_CHANNELS } from '../shared/types';

function getInvoke() {
  return (window as any).electronAPI?.invoke;
}

interface SessionState {
  sessions: Session[];
  currentSessionId: string | null;
  currentMessages: MessageRow[];
  isLoading: boolean;
  loadSessions: () => Promise<void>;
  createSession: () => Promise<Session | null>;
  deleteSession: (sessionId: string) => Promise<void>;
  renameSession: (sessionId: string, title: string) => Promise<void>;
  switchSession: (sessionId: string) => Promise<void>;
  setCurrentSessionId: (id: string | null) => void;
}

export const useSessionStore = create<SessionState>((set, get) => ({
  sessions: [],
  currentSessionId: null,
  currentMessages: [],
  isLoading: false,

  loadSessions: async () => {
    const invoke = getInvoke();
    if (!invoke) return;
    const sessions = await invoke(IPC_CHANNELS.SESSION_LIST);
    set({ sessions });
  },

  createSession: async () => {
    const invoke = getInvoke();
    if (!invoke) return null;
    const session = await invoke(IPC_CHANNELS.SESSION_CREATE);
    const { sessions } = get();
    set({ sessions: [session, ...sessions], currentSessionId: session.id, currentMessages: [] });
    return session;
  },

  deleteSession: async (sessionId: string) => {
    const invoke = getInvoke();
    if (!invoke) return;
    await invoke(IPC_CHANNELS.SESSION_DELETE, { sessionId });
    const { sessions, currentSessionId } = get();
    const filtered = sessions.filter(s => s.id !== sessionId);
    if (currentSessionId === sessionId) {
      const next = filtered[0] || null;
      set({ sessions: filtered, currentSessionId: next ? next.id : null, currentMessages: [] });
      if (next) get().switchSession(next.id);
    } else {
      set({ sessions: filtered });
    }
  },

  renameSession: async (sessionId: string, title: string) => {
    const invoke = getInvoke();
    if (!invoke) return;
    await invoke(IPC_CHANNELS.SESSION_RENAME, { sessionId, title });
    const { sessions } = get();
    set({
      sessions: sessions.map(s => s.id === sessionId ? { ...s, title } : s),
    });
  },

  switchSession: async (sessionId: string) => {
    const invoke = getInvoke();
    if (!invoke) return;
    set({ isLoading: true });
    const messages = await invoke(IPC_CHANNELS.SESSION_GET_MESSAGES, { sessionId });
    set({ currentSessionId: sessionId, currentMessages: messages, isLoading: false });
  },

  setCurrentSessionId: (id: string | null) => set({ currentSessionId: id }),
}));
```

#### Task C4: SessionSidebar 组件

**Files:**
- Create: `src/renderer/components/SessionSidebar.tsx`

- [ ] **创建侧栏组件**

遵循原型设计：顶部"新会话"按钮 + 按日期分组的会话列表 + 悬停删除。

```tsx
import React, { useEffect, useCallback } from 'react';
import { useSessionStore } from '../stores/session.store';

function groupByDate(sessions: any[]) {
  const today = new Date();
  const todayStr = today.toISOString().slice(0, 10);
  const yesterdayStr = new Date(today.getTime() - 86400000).toISOString().slice(0, 10);

  const groups: { label: string; sessions: any[] }[] = [];
  const todaySessions = sessions.filter(s => s.created_at?.startsWith(todayStr));
  const yesterdaySessions = sessions.filter(s => s.created_at?.startsWith(yesterdayStr));
  const earlierSessions = sessions.filter(s => {
    const d = s.created_at?.slice(0, 10);
    return d !== todayStr && d !== yesterdayStr;
  });

  if (todaySessions.length) groups.push({ label: '今天', sessions: todaySessions });
  if (yesterdaySessions.length) groups.push({ label: '昨天', sessions: yesterdaySessions });
  if (earlierSessions.length) groups.push({ label: '更早', sessions: earlierSessions });
  return groups;
}

export function SessionSidebar({ collapsed }: { collapsed: boolean }): React.ReactElement {
  const { sessions, currentSessionId, loadSessions, createSession, deleteSession, switchSession } = useSessionStore();

  useEffect(() => {
    loadSessions();
  }, [loadSessions]);

  const groups = groupByDate(sessions);

  const handleDelete = useCallback(async (e: React.MouseEvent, sessionId: string) => {
    e.stopPropagation();
    if (sessions.length <= 1) return;
    await deleteSession(sessionId);
  }, [sessions.length, deleteSession]);

  return (
    <aside className="flex flex-col h-full bg-gray-900">
      <div className="p-3 border-b border-gray-800">
        <button
          onClick={createSession}
          className="w-full py-2 px-3 bg-blue-600 hover:bg-blue-500 text-white text-sm font-medium rounded-lg transition-colors flex items-center justify-center gap-1.5"
        >
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <line x1="12" y1="5" x2="12" y2="19" /><line x1="5" y1="12" x2="19" y2="12" />
          </svg>
          {!collapsed && <span>新会话</span>}
        </button>
      </div>

      <div className="flex-1 overflow-y-auto px-2 py-1">
        {groups.map(group => (
          <div key={group.label}>
            {!collapsed && (
              <div className="text-xs text-gray-500 uppercase tracking-wider px-2 py-2">{group.label}</div>
            )}
            {group.sessions.map(session => (
              <div
                key={session.id}
                onClick={() => switchSession(session.id)}
                className={`flex items-center gap-2 px-3 py-2 rounded-lg cursor-pointer transition-colors group ${
                  session.id === currentSessionId
                    ? 'bg-blue-900/30 text-blue-300 border-l-2 border-blue-500'
                    : 'text-gray-400 hover:bg-gray-800 hover:text-gray-200'
                }`}
              >
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="flex-shrink-0">
                  <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
                </svg>
                {!collapsed && (
                  <>
                    <span className="text-sm truncate flex-1">{session.title}</span>
                    <button
                      onClick={(e) => handleDelete(e, session.id)}
                      className="opacity-0 group-hover:opacity-100 w-5 h-5 flex items-center justify-center rounded hover:bg-red-900/50 text-gray-500 hover:text-red-400 text-xs transition-opacity flex-shrink-0"
                    >✕</button>
                  </>
                )}
              </div>
            ))}
          </div>
        ))}
      </div>
    </aside>
  );
}
```

#### Task C5: App.tsx 集成新布局

**Files:**
- Modify: `src/renderer/App.tsx`

- [ ] **引入 SessionSidebar 和 session.store**

```typescript
import { SessionSidebar } from './components/SessionSidebar';
import { useSessionStore } from './stores/session.store';
```

- [ ] **布局改为 侧栏 + 主区域 + 右面板**

```tsx
// 在顶层组件中添加状态
const [sidebarCollapsed, setSidebarCollapsed] = React.useState(false);

// 布局结构
<div className="flex h-screen bg-gray-950 text-gray-100">
  {/* 侧栏 */}
  <div className={`${sidebarCollapsed ? 'w-16' : 'w-64'} flex-shrink-0 border-r border-gray-800 transition-all`}>
    <SessionSidebar collapsed={sidebarCollapsed} />
  </div>
  {/* 主区域 */}
  <div className="flex-1 flex flex-col">
    {/* ... 现有 ChatPage 内容 ... */}
  </div>
  {/* 右面板 */}
  <DiagnosisPanel />
</div>
```

- [ ] **侧栏折叠按钮**

在侧栏右上角添加折叠按钮。

#### Task C6: ChatPage + ChatStore 对接会话

**Files:**
- Modify: `src/renderer/components/ChatPage.tsx`
- Modify: `src/renderer/stores/chat.store.ts`

- [ ] **ChatPage 移除旧 header，使用 session store 的 currentSessionId**

ChatPage 中的 `sendMessage` 调用应使用 `useSessionStore.getState().currentSessionId`。

- [ ] **chat.store 的 sendMessage 调用时传入 sessionId**

```typescript
const sessionId = useSessionStore.getState().currentSessionId || 'default';
await invoke(IPC_CHANNELS.CHAT_SEND, {
  message: text.trim(),
  sessionId,
  history,
  attitudeLevel,
});
```

- [ ] **初次加载时自动创建/选择第一个会话**

在 App.tsx 的 `useEffect` 中：
```typescript
useEffect(() => {
  const init = async () => {
    await useSessionStore.getState().loadSessions();
    const { sessions, currentSessionId, switchSession } = useSessionStore.getState();
    if (!currentSessionId && sessions.length > 0) {
      switchSession(sessions[0].id);
    }
  };
  init();
}, []);
```

---

### 验证

- [ ] **类型检查**

Run: `npx tsc --noEmit` → 零错误

- [ ] **全量测试**

Run: `npx vitest run` → 全部通过

- [ ] **更新 TASK-CHAIN.md**

新增 T-002 任务记录，标记完成状态。
