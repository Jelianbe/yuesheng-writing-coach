# 数据持久化与会话管理 V1.0

## 1. 问题陈述

当前聊天数据仅存在于内存（Zustand）中，刷新后丢失。诊断解析函数存在但未被调用，诊断数据从未生成。会话管理无法建立在空数据库之上。

需要按以下顺序打通全链路：

```
消息落库 → 诊断触发 → 会话管理
```

## 2. 执行阶段

### 阶段 A：数据库建表 + 消息持久化

**目标**：每次对话自动写入 SQLite，刷新后消息不丢失。

#### 数据库迁移（004_create_chat.sql）

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

#### 改动范围

| 文件 | 改动 |
|------|------|
| `src/main/services/session.service.ts` | **新建** — 封装 sessions + messages 的 CRUD |
| `src/main/db/004_create_chat.sql` | **新建** — 迁移 SQL |
| `src/main/index.ts` | 注册新的 migration |
| `src/main/ipc/chat.handler.ts` | 流结束后调用 sessionService.saveMessage() |
| `src/main/ipc/chat.handler.ts` | 首条消息自动生成会话标题 |

### 阶段 B：诊断链路接通

**目标**：AI 回复完成后，自动解析诊断结果并推送到前端。

#### 改动范围

| 文件 | 改动 |
|------|------|
| `src/main/ipc/chat.handler.ts` | 流结束后调用 `processDiagnosisFromAI()` |
| `src/main/ipc/diagnosis.handler.ts` | 确认 `processDiagnosisFromAI` 已正确导出 |
| `src/main/services/diagnosis-parser.ts` | 确保 parseDiagnosisTable 可独立调用 |

### 阶段 C：会话管理 UI

**目标**：左侧边栏显示会话列表，支持新建/切换/删除/自动标题。

#### IPC 通道

| 通道 | 请求 | 响应 |
|------|------|------|
| `session:list` | `{}` | `Session[]`（含 lastMessage 预览） |
| `session:create` | `{}` | `Session` |
| `session:delete` | `{ sessionId }` | `void` |
| `session:rename` | `{ sessionId, title }` | `void` |
| `session:getMessages` | `{ sessionId }` | `ChatMessage[]` |

#### 新增/修改文件

| 文件 | 说明 |
|------|------|
| `src/renderer/stores/session.store.ts` | 新建 — Zustand store |
| `src/renderer/components/SessionSidebar.tsx` | 新建 — 侧栏组件 |
| `src/main/ipc/session.handler.ts` | 新建 — IPC handler |
| `src/preload/index.ts` | 白名单追加 session 通道 |
| `src/renderer/App.tsx` | 集成 SessionSidebar |
| `src/renderer/components/ChatPage.tsx` | 移除旧 header，与新布局对接 |
| `src/renderer/shared/types.ts` | 追加 IPC_CHANNELS + 类型映射 |

## 3. 关键数据流（完成后）

```
用户输入
  → chat.store.sendMessage()
    → IPC chat:send
      → chat.handler.ts
        → 生成 sessionId（无会话时自动创建）
        → sessionService.saveMessage({ role: 'user', ... })  ← 新增
        → ApiProxy.chatStream()
          → chat:stream:data → 前端逐块显示
        → chat:stream:end
          → sessionService.saveMessage({ role: 'assistant', ... })  ← 新增
          → 首条消息自动生成标题  ← 新增
          → processDiagnosisFromAI(fullResponse)  ← 新增（阶段 B）
            → diagnosis:update → 诊断面板更新
```

## 4. 版本记录

| 版本 | 日期 | 变更 |
|------|------|------|
| V1.0 | 2026-06-01 | 初始设计，三个阶段拆分 |
