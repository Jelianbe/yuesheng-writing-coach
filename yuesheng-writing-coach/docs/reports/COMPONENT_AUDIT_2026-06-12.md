---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: f2ac1166b9bdaea71c23aabee181e425_ac802886666811f1a99c5254007bceed
    ReservedCode1: mSonAYs/EKOCmk7KWy7AlGjmb6NpQSAya2vs5cumbi4VSl3fgy8ZN9o0emHgjj1ONJKt2pFiOe6rEuFLb5MGhFPGBn+qR07LS/2H2tWJiyXzHpercbejWhkJ6dCWWUV3zKQLo/3GyS0yNV9u+6+kDPREx7ZGlc4B2n7humkfMcuTFbstkUHCMU+WuLo=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: f2ac1166b9bdaea71c23aabee181e425_ac802886666811f1a99c5254007bceed
    ReservedCode2: mSonAYs/EKOCmk7KWy7AlGjmb6NpQSAya2vs5cumbi4VSl3fgy8ZN9o0emHgjj1ONJKt2pFiOe6rEuFLb5MGhFPGBn+qR07LS/2H2tWJiyXzHpercbejWhkJ6dCWWUV3zKQLo/3GyS0yNV9u+6+kDPREx7ZGlc4B2n7humkfMcuTFbstkUHCMU+WuLo=
---

# 月笙写作教练 组件审计报告

> 审计日期：2026-06-12
> 审计范围：D:\ai-teacher\yuesheng-writing-coach 全量核心组件
> 审计人：File Agent (automated)

---

## 修复记录 (2026-06-12)

| ID | 问题 | 状态 | 修复文件 |
|:--:|------|:--:|------|
| AUDIT-01 | Preload 白名单缺失 12 个通道 | ✅ 已修复 | constants.ts, preload/index.ts |
| AUDIT-02 | ensureBaseSchema 冗余 chat_messages 表 | ✅ 已修复 | app-initializer.ts |
| AUDIT-03 | fullResponse 截断导致前后端不一致 | ✅ 已修复 | chat.handler.ts |

修复细节：
- AUDIT-01：补充 diagnosis:query, evidence:getByDisease/getByAbility/getChain/create, growth:getGlobalTrends, teachingState:getPrompt/updateSummary, session:getMessages/listWithMeta/updateTitle, training:skip
- AUDIT-02：移除 ensureBaseSchema 中 chat_messages 建表语句，该表已被迁移 004 中的 messages 表替代
- AUDIT-03：移除 fullResponse.slice 截断逻辑，中间轮次文本完整入库，前后端数据一致

门禁验证：tsc 0 errors / vitest 136 passed / check:circular 0 / build 成功
备份分支：backup/pre-audit-fix-20260612

## 目录

1. [项目入口与应用初始化](#1-项目入口与应用初始化)
2. [新建项目功能](#2-新建项目功能)
3. [新建对话功能](#3-新建对话功能)
4. [发送作品后的数据流向](#4-发送作品后的数据流向)
5. [诊断库更新机制](#5-诊断库更新机制)
6. [章节读取与引用](#6-章节读取与引用)
7. [测试覆盖](#7-测试覆盖)
8. [IPC 通道完整性](#8-ipc-通道完整性)
9. [综合评估与建议](#9-综合评估与建议)

---

## 1. 项目入口与应用初始化

### 1.1 入口文件

**文件**：`src/main/index.ts`（27 行）

应用生命周期委托给 `AppInitializer`：

```
app.whenReady()
  → ServiceContainer.getInstance()
  → new AppInitializer(container)
  → appInitializer.initialize()
```

生命周期事件处理：
- `window-all-closed` — 非 macOS 下自动退出
- `activate` — macOS Dock 点击重建窗口

### 1.2 初始化流程

**文件**：`src/main/core/app-initializer.ts`（257 行）

`initialize()` 方法执行顺序：

```
1. initDatabase()           → better-sqlite3 实例，journal_mode=DELETE
2. runMigrations()         → _migrations 表 + ensureBaseSchema() + 文件迁移
3. getResourcesRoot()      → 区分开发/打包环境路径
4. configureServices()     → DI 容器注册 20+ 服务
5. windowManager.create()  → 创建主窗口
6. ipcRegistry.registerAll() → 注册全部 IPC handler
```

### 1.3 数据库初始化

**关键细节**：

- **存储位置**：`app.getAppPath()/data/yuesheng.db`（非默认 `%APPDATA%`），适应 Trae 沙箱白名单
- **迁移兼容**：首次启动时尝试从旧 `%APPDATA%` 位置复制数据库
- **PRAGMA 配置**：
  - `journal_mode = DELETE`（非 WAL，减少额外文件）
  - `foreign_keys = ON`
  - `synchronous = NORMAL`
  - `cache_size = -64000`（64MB 缓存）

### 1.4 基础 Schema（ensureBaseSchema）

在 `app-initializer.ts` 第 88-189 行内联创建 6 张基础表：

| 表名 | 用途 |
|------|------|
| `sessions` | 会话 |
| `chat_messages` | 聊天消息（已废弃，新版用 `messages`） |
| `diagnosis_results` | 诊断结果 |
| `teaching_state` | 教学状态机 |
| `user_training_records` | 训练记录 |
| `evidence` | 证据片段 |

### 1.5 文件迁移

仅 2 个外部迁移文件：

- `013_manuscripts.sql` — 作品 + 章节表
- `018_db_p1a_time_format.sql` — 时间格式转换

其余 8 个迁移（003-012）直接在 `ensureBaseSchema()` 中以 SQL 内联方式创建，并在 `_migrations` 表标记已应用。

### 1.6 服务注册

**文件**：`src/main/core/service-config.ts`（118 行）

注册 20+ 个服务到 DI 容器，含依赖图：

```
db, resourcesRoot
  ├── ConfigService
  ├── SessionService(db)
  ├── DiagnosisService(db)
  ├── EvidenceService(db)
  ├── TrainingRecordService(db)
  ├── StudentModelService(db, DiagnosisService, TrainingRecordService, resourcesRoot)
  ├── AbilityProfileService(db, DiagnosisService, TrainingRecordService, resourcesRoot)
  ├── GrowthTrendService(StudentModelService)
  ├── TeachingStrategyService(resourcesRoot) + TeachingStrategyRouter
  ├── ProblemPrioritizer(resourcesRoot)
  ├── DisputeTrackerService
  ├── ReflectionGateService
  ├── PromptBuilder → PromptLoader (含 setter 注入)
  ├── DynamicContextService
  ├── CodexService
  ├── MessageRouter
  └── initStore(db)
```

开发模式下额外注入 mock 诊断数据。

### 1.7 发现与评估

| 项目 | 状态 | 说明 |
|------|:----:|------|
| 初始化顺序 | ✅ 合理 | DB → 迁移 → 服务 → 窗口 → IPC，依赖清晰 |
| 错误处理 | ⚠️ 部分 | 旧数据库复制失败仅 `console.warn`，迁移跳过也仅 `console.warn` |
| 迁移管理 | ✅ 完善 | `_migrations` 表记录已应用迁移，幂等重入安全 |
| DI 设计 | ✅ 优秀 | ServiceContainer 模式清晰，无循环依赖 |
| 开发/生产区分 | ✅ 良好 | `app.isPackaged` + `NODE_ENV` 判断 |

**风险**：`ensureBaseSchema()` 与迁移文件之间存在两个"真相来源"——表创建逻辑可能散落在 `ensureBaseSchema` 和迁移文件中。建议将所有 DDL 统一归入迁移文件。

---

## 2. 新建项目功能

### 2.1 数据流

```
Renderer (manuscript.store.ts)
  → preload invoke('manuscript:create', {title, description?, genre?})
    → IPC main: manuscript.handler.ts
      → SQLite INSERT INTO manuscripts
        → SELECT * FROM manuscripts WHERE id = ?
          → apiSuccess(row) 返回
```

### 2.2 IPC Handler

**文件**：`src/main/ipc/manuscript.handler.ts`（191 行）

注册 10 个 handler：

| 通道 | 功能 | 验证 |
|------|------|:--:|
| `manuscript:list` | 列表（按 sort_order, created_at） | 无参数 |
| `manuscript:get` | 单个作品 | `id` 必填 |
| `manuscript:create` | 创建作品 | `title` 必填 |
| `manuscript:update` | 更新作品 | `id` 必填 |
| `manuscript:delete` | 删除作品 + 级联删除章节 | `id` 必填 |
| `chapter:list` | 作品下所有章节 | `manuscriptId` 必填 |
| `chapter:get` | 单个章节（含内容） | `id` 必填 |
| `chapter:create` | 创建章节 | `manuscriptId`, `title` 必填 |
| `chapter:delete` | 删除章节 | `id` 必填 |
| `chapter:updateContent` | 更新章节正文 | `id`, `content` 必填 |

### 2.3 前端 Store

**文件**：`src/renderer/stores/manuscript.store.ts`（4.2 KB）

- 管理作品列表和章节数据
- 通过 `getInvoke()` 调用 IPC

### 2.4 数据库表结构

**文件**：`src/main/db/013_manuscripts.sql`

```sql
manuscripts: id, title, description, genre, status, sort_order, created_at, updated_at
chapters:     id, manuscript_id(FK CASCADE), title, content, word_count, sort_order,
              status(draft/revising/complete), created_at, updated_at
```

### 2.5 发现与评估

| 项目 | 状态 | 说明 |
|------|:----:|------|
| CRUD 完整性 | ✅ | 作品和章节的完整 CRUD |
| 级联删除 | ✅ | manuscript:delete 用事务级联删除章节 |
| 参数验证 | ✅ | validatePayload 检查必填字段和类型 |
| sort_order 管理 | ✅ | 创建章节时自动计算 MAX(sort_order)+1 |
| word_count 计算 | ✅ | chapter:updateContent 时用 `content.replace(/[\s\n\r]+/g, '').length` |
| 错误处理 | ✅ | 所有 handler 有 try-catch + apiError 返回 |

**数据流图（文字）**：

```
用户点击"新建作品" → UI 表单
  → manuscript.store.createManuscript({title, description, genre})
    → electronAPI.invoke('manuscript:create', args)
      → preload/index.ts 白名单通过
        → ipcMain.handle('manuscript:create')
          → validatePayload → crypto.randomUUID()
            → db.prepare(INSERT INTO manuscripts)
              → db.prepare(SELECT * FROM manuscripts WHERE id=?)
                → apiSuccess(row)
```

---

## 3. 新建对话功能

### 3.1 数据流

```
Renderer (session.store.ts)
  → preload invoke('session:create')
    → IPC main: session.handler.ts
      → SessionService.createSession()
        → SQLite INSERT INTO sessions + 返回 SessionRow
```

### 3.2 IPC Handler

**文件**：`src/main/ipc/session.handler.ts`（160 行）

注册 10 个 handler：

| 通道 | 功能 |
|------|------|
| `session:list` | 获取所有会话 |
| `session:create` | 创建新会话（标题默认"新建会话"） |
| `session:delete` | 删除会话（含 CASCADE 消息） |
| `session:rename` | 重命名会话 |
| `session:getMessages` | 获取全部消息 |
| `session:getMessagesPaged` | 分页加载消息（offset+limit，最大 200） |
| `session:listWithMeta` | 含 preview 的列表（V2 SOLO） |
| `session:updateTitle` | 更新标题 |
| `session:searchMessages` | 跨会话全文搜索 |
| `session:isNewUser` | 判断新用户（无任何会话） |

### 3.3 SessionService

**文件**：`src/main/services/session.service.ts`（109 行）

核心方法：
- `createSession()` — `crypto.randomUUID()` + INSERT
- `saveMessage()` — 事务内 INSERT message + UPDATE session.updated_at
- `autoGenerateTitle()` — 取第一条用户消息前 20 字作为标题
- `searchMessages()` — LIKE 匹配 + 按会话分组，限制 10 会话 × 5 消息

### 3.4 前端 Store

**文件**：`src/renderer/stores/session.store.ts`（114 行）

**文件**：`src/renderer/stores/chat.store.ts`（267 行）

Chat Store 核心逻辑：
- `sendMessage()` 方法中，若 `currentSessionId` 为空，自动 `createSession` 创建
- 滑动窗口 Token 预算：8000 tokens，`buildSlidingWindow()` 从新到旧累积
- 流式接收：`appendToLastAssistant()` 追加 chunk 到最后一条 assistant 消息

### 3.5 发现与评估

| 项目 | 状态 | 说明 |
|------|:----:|------|
| 会话 CRUD | ✅ 完整 | 创建/列表/删除/重命名/分页 |
| 消息搜索 | ✅ | 跨会话 LIKE 匹配，支持 FTS5 |
| 自动标题 | ⚠️ 简单 | 仅取前 20 字，非 AI 生成 |
| Token 管理 | ✅ | 滑动窗口 8K，中英文分别估算 |
| 新用户引导 | ✅ | `session:isNewUser` + onboarding 状态机 |

**注意**：`chat.store.ts` 中 `generateId()` 函数与 `chat.handler.ts` 中的 `generateId()` 实现相同但独立定义，存在代码重复。建议提取到 shared 模块。

---

## 4. 发送作品后的数据流向

### 4.1 完整数据流

这是整个应用中最复杂的链路。以下为 `chat:send` 的完整流程图：

```
用户输入消息
    │
    ▼
┌─────────────────────────────────────────────────────────┐
│ chat.store.ts::sendMessage(text)                         │
│   1. 获取/创建 sessionId                                  │
│   2. 构建滑动窗口 history                                │
│   3. 添加 userMsg + assistantMsg(空) 到本地 messages      │
│   4. invoke('chat:send', {message, sessionId, history,   │
│        attitudeLevel, studentContext})                   │
└────────────────────────┬────────────────────────────────┘
                         │ preload 白名单检查
                         ▼
┌─────────────────────────────────────────────────────────┐
│ chat.handler.ts::registerChatHandlers                    │
│   CHAT_SEND handler:                                     │
│                                                          │
│   1. resolveChapterReference(message)  ← 旧方案           │
│      └─ 正则 /chapters/{uuid} → DB查章节正文 → 替换       │
│                                                          │
│   2. saveMessage(sessionId, 'user', message)              │
│      └─ SessionService → INSERT INTO messages            │
│                                                          │
│   3. runDiagnosis(message, sessionId)                     │
│      └─ callDiagnosisAgent(message)                      │
│         └─ ApiProxy.chatStream(diagnosisPrompt + text)   │
│            └─ 流式调用 AI 获取 DiagnosisAnalysis JSON     │
│         └─ injectTechniquePool() ← 技法库注入             │
│         └─ 保存到 diagnosis_results + diagnosis:update   │
│                                                          │
│   4. prepareTeachingContext(...)                          │
│      ├─ diagnosisHistory → MemoryCapsuleService          │
│      ├─ studentModelService.toPromptText()               │
│      ├─ promptLoader.loadSystemPrompt(...)               │
│      ├─ reflectionGate.shouldTriggerReflection()         │
│      └─ buildStrategyInstruction(...)                    │
│         ├─ teachingStrategyService.decide()              │
│         └─ problemPrioritizer.prioritize()               │
│                                                          │
│   5. buildMessageArray(systemPrompt, history, message)   │
│                                                          │
│   6. probeToolSupport(modelName) → 选择流式入口           │
│      ├─ 支持 → handleStreamResponseWithTools() [新]      │
│      └─ 不支持 → handleStreamResponse() [旧]             │
│                                                          │
│   7. 流式响应处理:                                        │
│      handleStreamResponse():                             │
│        └─ ApiProxy.chatStream(messages, signal)          │
│           └─ 逐 chunk yield → chat:stream:data 推送      │
│        └─ saveMessage(sessionId, 'assistant', full)      │
│        └─ processDiagnosisFromAI(fullResponse, ...)      │
│        └─ chat:stream:end 推送                           │
│                                                          │
│      handleStreamResponseWithTools():                    │
│        └─ ApiProxy.chatStreamWithTools(messages, tools)  │
│           └─ 逐 event yield                               │
│              ├─ type='text' → chat:stream:data           │
│              └─ type='tool_calls' → 执行 toolHandlers    │
│                 └─ readChapter → 查 DB 返回章节内容       │
│        └─ 工具结果回传 messages → 继续流（最多3轮）       │
│        └─ saveMessage + processDiagnosisFromAI           │
│        └─ chat:stream:end 推送                           │
└────────────────────────┬────────────────────────────────┘
                         │ chat:stream:data / chat:stream:end
                         ▼
┌─────────────────────────────────────────────────────────┐
│ chat.store.ts                                            │
│   ipcRenderer.on('chat:stream:data')                     │
│     → appendToLastAssistant(chunk)                       │
│   ipcRenderer.on('chat:stream:end')                      │
│     → setLoading(false)                                  │
│   ipcRenderer.on('diagnosis:update')                     │
│     → diag.store.setCurrentDiagnosis(entry)              │
│   ipcRenderer.on('chat:tool:executing')                  │
│     → UI 展示工具调用状态                                  │
└─────────────────────────────────────────────────────────┘
```

### 4.2 关键服务交互

#### 4.2.1 ApiProxy（`src/main/api-proxy.ts`，338 行）

| 方法 | 用途 |
|------|------|
| `chatStream()` | 标准 SSE 流式聊天 |
| `chatStreamWithTools()` | 带 tool calling 的流式聊天，yield `StreamEvent` |
| `testConnection()` | API 连通性测试 |
| `evaluateRewrite()` | 修改评估（非流式，低温度） |

`chatStreamWithTools` 的核心逻辑：
- 逐 SSE chunk 解析 `delta.content`（文本）和 `delta.tool_calls`（工具调用）
- `accumulateToolCalls()` 累积跨 chunk 的工具调用参数
- 流结束时 yield 未发出的 tool_calls

#### 4.2.2 probeToolSupport（`chat.handler.ts` 第 365-396 行）

三层策略：
1. **白名单**（deepseek/gpt-/claude-）→ 直接返回 true
2. **黑名单**（llama-2/mixtral-8x7b）→ 直接返回 false
3. **未知模型** → 发一次 test call（`tools: [{name:'ping'}]`），根据响应判断

结果缓存到 `_toolSupportCache`。

#### 4.2.3 消息持久化

`SessionService.saveMessage()`（`session.service.ts` 第 49-54 行）：
```typescript
// 事务内完成 INSERT message + UPDATE session.updated_at
// 表: messages (id, session_id, role, content, timestamp)
```

### 4.3 发现与评估

| 项目 | 状态 | 说明 |
|------|:----:|------|
| 双流式入口 | ✅ | 新旧两条路径独立，通过 probe 自动选择 |
| 工具调用循环 | ✅ | 最多 3 轮 tool-call round-trip |
| 中断处理 | ✅ | AbortController + partial 内容保留 |
| 错误处理 | ✅ | 401/网络错误均返回具体信息 + chat:stream:end |
| Prompt 构建 | ⚠️ 复杂 | 7200+ 字 Prompt，多模块拼接，调试困难 |
| 诊断历史格式 | ✅ | MemoryCapsuleService 替代纯诊断历史 |
| `generateId()` 重复 | ⚠️ | chat.handler.ts 和 chat.store.ts 各定义一次 |
| `chat_messages` 表 | ⚠️ 冗余 | `ensureBaseSchema` 创建了 `chat_messages`，但实际使用 `messages` 表 |

**风险**：
1. `handleStreamResponseWithTools` 中 `fullResponse` 在工具调用轮次中的文本会被截断（`fullResponse.slice(0, fullResponse.length - currentRoundText.length)`），但 `chat:stream:data` 已经推送了所有 chunk 到前端。这意味着前端显示的文本和数据库保存的文本可能不一致（前端有中间轮次的工具调用文本，但数据库只保留了最终轮）。**建议确认这是设计意图**。
2. `probeToolSupport` 在未知模型时的探测请求是同步 fetch（非流式），可能阻塞 10s+。

---

## 5. 诊断库更新机制

### 5.1 诊断触发时机

诊断有两个触发点：

1. **新路径（Diagnosis Agent）**：用户每次发送消息时，`callDiagnosisAgent()` 独立调用 AI 进行结构化诊断（`diagnosis-agent-prompt-v1.md`），输出 JSON 格式的 `DiagnosisAnalysis`。在 `chat:send` handler 的步骤 3（`runDiagnosis`）中触发。

2. **旧路径（兼容）**：Teaching Agent 回复流结束后，`processDiagnosisFromAI()` 解析 AI 回复中的 `---DIAGNOSIS_START---` 标记块。

### 5.2 processDiagnosisFromAI 完整流程

**文件**：`src/main/ipc/diagnosis.handler.ts`（第 183-253 行）

```
processDiagnosisFromAI(fullResponse, sessionId, messageId)
  │
  ├── 1. parseDiagnosisFromAIResponse()
  │      └─ 解析 AI 回复中的 DIAGNOSIS_START/END 标记
  │         提取 cleanResponse + diagnosis (DiagnosisEntry)
  │
  ├── 2. diagnosisService.save(diagnosis)
  │      └─ INSERT INTO diagnosis_results
  │         (id, session_id, message_id, syndromes, suggested_actions,
  │          confidence, timestamp, next_focus)
  │         syndromes/suggested_actions 以 JSON 字符串存储
  │
  ├── 3. 创建 Evidence 记录
  │      └─ 遍历每个 syndrome → getAbilitiesForSyndrome()
  │         遍历 syndrome.evidence → evidenceService.save()
  │           evidenceService.linkToDiagnosis(diagnosisId, evidenceId, role)
  │         INSERT INTO evidence + diagnosis_evidence 关联表
  │
  ├── 4. diagnosisMerger.merge(diagnosis)
  │      └─ 将诊断结果合并到 TeachingState.activeProblems
  │
  ├── 4.5. pushTeachingStateUpdate(sessionId)
  │        └─ teachingState:updated 事件推送到前端
  │
  └── 5. mainWindow.webContents.send(DIAGNOSIS_UPDATE, diagnosis)
         └─ 推送到前端 diag.store.setCurrentDiagnosis()
```

### 5.3 诊断相关 IPC 通道

**文件**：`src/main/ipc/diagnosis.handler.ts`

| 通道 | 功能 |
|------|------|
| `diagnosis:query` | 查询指定会话的 activeProblems |
| `diagnosis:update` | **事件** — 新诊断结果推送到渲染进程 |
| `diagnosis:submitRewrite` | 提交修改原文 + AI 评估 |
| `diagnosis:getComparison` | 获取最近 2 次诊断的对比分析 |
| `growth:getTrends` | 获取单会话成长趋势 |
| `growth:getGlobalTrends` | 获取全局成长趋势 |

### 5.4 诊断服务层

| 文件 | 职责 |
|------|------|
| `diagnosis.service.ts` | CRUD：save / saveAnalysis / getBySession / getRecentBySession / getAll |
| `diagnosis-parser.ts` | 解析 AI 回复中的 DIAGNOSIS_START/END 标记块 |
| `diagnosis-merger.ts` | 将新诊断合并到 TeachingState |
| `diagnosis-merger-utils.ts` | severityToNumber / mergeSyndromesIntoState 工具函数 |

### 5.5 数据库表结构

`diagnosis_results` 表：
```
id, session_id, message_id (UNIQUE), syndromes (JSON), suggested_actions (JSON),
confidence, timestamp, next_focus, created_at, root_cause_analysis (JSON)
```

索引：
- `idx_diagnosis_session` ON (session_id, timestamp)
- `idx_diagnosis_message` ON (message_id)

### 5.6 发现与评估

| 项目 | 状态 | 说明 |
|------|:----:|------|
| 双路径诊断 | ✅ | 新路径（Agent）+ 旧路径（解析），向后兼容 |
| 证据链 | ✅ | 诊断 → Evidence → diagnosis_evidence 关联 |
| 成长趋势 | ✅ | GrowthTrendService 跨会话聚合 |
| 诊断对比 | ✅ | 最近 2 次诊断的症候变化跟踪 |
| 状态合并 | ✅ | DiagnosisMerger 同步到 TeachingState |
| JSON 存储 | ⚠️ | syndromes/suggested_actions 以 JSON 字符串存储，不支持 SQL 直接查询 |

**建议**：如果需要对症候进行 SQL 聚合分析（如"P002 的出现频率"），建议将 syndromes 拆分为独立的关联表。

---

## 6. 章节读取与引用

### 6.1 两套方案对比

| 维度 | 旧方案 (resolveChapterReference) | 新方案 (Function Calling) |
|------|------|------|
| 触发时机 | 消息发送前（预处理） | AI 决定调用时（流式中间） |
| 触发方式 | 正则匹配 `/chapters/{uuid}` | AI 通过 tool_calls 发起 |
| 用户操作 | 手动输入 UUID 格式 | 自然语言描述 |
| 实现位置 | `chat.handler.ts` L298-341 | `chat.handler.ts` L343-359 + L461-508 |
| 匹配方式 | 精确 UUID 匹配 | UUID 精确 + titleHint LIKE 模糊 |
| 返回值 | 替换消息文本 | JSON 结构化结果 |
| 回退 | 无匹配时显示错误提示 | 未找到时返回 recentChapters |
| AI 感知 | 不知道在使用工具 | 知道在调用 readChapter |
| 模型要求 | 无 | 需支持 tool calling |

### 6.2 旧方案实现

**文件**：`chat.handler.ts` 第 298-341 行

```typescript
function resolveChapterReference(message: string): string {
  const chapterPattern = /\/chapters\/([a-f0-9-]{36})/gi;
  // 遍历所有匹配 → db.prepare('SELECT id, title, content FROM chapters WHERE id = ?')
  // → 替换 /chapters/{uuid} 为章节正文
}
```

特点：
- 支持单章和多章引用
- 支持混合文本（"对比 /chapters/xxx 和 /chapters/yyy"）
- 未找到章节时替换为提示文本
- 日志含章节标题和字符数

### 6.3 新方案实现

**文件**：`chat.handler.ts` 第 343-359 行（toolHandlers）+ 第 382-397 行（TOOLS_DEFINITIONS）

```typescript
const toolHandlers = {
  readChapter: async (args) => {
    // 1. chapterId 精确匹配
    // 2. titleHint 模糊匹配 (LIKE %xxx% ORDER BY updated_at DESC LIMIT 1)
    // 3. 无参数 → 返回最近 5 个章节列表
  }
};
```

TOOLS_DEFINITIONS 注册了一个工具：
- `readChapter`：参数 `chapterId` 或 `titleHint`

### 6.4 章节 IPC 通道

所有章节操作在 `manuscript.handler.ts` 中：

| 通道 | 功能 |
|------|------|
| `chapter:list` | 按作品 ID 列章节 |
| `chapter:get` | 获取单个章节（含正文） |
| `chapter:create` | 创建章节 |
| `chapter:delete` | 删除章节 |
| `chapter:updateContent` | 更新章节正文 + 自动计算 word_count |

### 6.5 发现与评估

| 项目 | 状态 | 说明 |
|------|:----:|------|
| 双方案共存 | ✅ | 旧方案预处理 + 新方案 AI 驱动，不冲突 |
| 工具定义 | ✅ | 单一 readChapter 工具，参数设计合理 |
| 回退机制 | ✅ | 未指定章节时返回最近 5 个章节 |
| IPC 通道 | ✅ | 完整 CRUD，含 word_count 自动计算 |
| chapter:updateContent 安全性 | ⚠️ | 无内容长度限制，大文本可能压垮 DB |

**建议**：
1. 当 Function Calling 方案稳定后，可考虑逐步废弃 `resolveChapterReference` 旧方案
2. `readChapter` tool handler 中 `titleHint` 使用 LIKE 模糊匹配，多个匹配时只取最近更新的一个，建议在返回中标注"（共 N 个匹配章节，已选择最近更新的）"

---

## 7. 测试覆盖

### 7.1 测试文件清单

| 文件 | 行数 | 类型 | 覆盖范围 |
|------|:---:|------|------|
| `src/main/ipc/__tests__/full-flow.wiremock.test.ts` | 540 | 集成/E2E | Chat 全链路 + 诊断 + 评估 |
| `src/renderer/stores/__tests__/training.store.test.ts` | 442 | 单元测试 | Training Store 状态管理 |

### 7.2 全链路测试（Wire Mock）

**测试架构**：HTTP 层拦截 fetch，用预准备 LLM 响应替代云端

**覆盖场景**（7 个 describe，约 15 个 test case）：

| 场景 | 测试内容 |
|------|------|
| 场景1 | 提交长文本 → 诊断分析 → 教学回复（4 个用例） |
| 场景2 | 旧格式 DIAGNOSIS_START 兼容处理（1 个用例） |
| 场景3 | 短文本不触发诊断分析（1 个用例） |
| 场景4 | API 错误处理：网络错误 + 401（2 个用例） |
| 场景5 | 修改原文 → 评估流程（1 个用例） |
| 场景6 | 诊断症候 → 技法映射（1 个用例） |
| 场景7 | 多轮对话协作式（1 个用例） |

**验证点**：
- `saveMessage` 调用次数和参数
- `diagnosis:update` 事件推送内容和数据结构
- 症候严重度排序（L3 > L2 > L1）
- 证据文本来源正确性
- `chat:stream:data` 分 chunk 转发
- `chat:stream:end` 参数完整

### 7.3 Training Store 测试

**覆盖**：基础状态、模式切换、推荐加载、训练分配、训练完成、错误卡片管理、bridge 推荐等

### 7.4 测试辅助文件

| 文件 | 用途 |
|------|------|
| `src/test/wire-mock/sse-helper.ts` | SSE 响应创建工具 |
| `src/test/mocks/ipc-mock.ts` | IPC mock 工具 |
| `src/test/fixtures/llm-responses/index.ts` | 预准备 LLM 响应数据 |
| `src/test/fixtures/index.ts` | 测试夹具 |
| `src/test/assertions/index.ts` | 断言工具 |
| `src/test/reporter.ts` | 自定义测试报告 |

### 7.5 发现与评估

| 项目 | 状态 | 说明 |
|------|:----:|------|
| 全链路测试 | ✅ 高质量 | Wire Mock 模式，测试真实管线 |
| 测试场景 | ✅ 覆盖核心 | 正常流 + 错误 + 边界 + 兼容 |
| 测试数据 | ✅ 真实 | 基于《修仙传》实际文本 |
| 单元测试 | ⚠️ 不足 | 仅 training.store 有单元测试 |
| 服务层测试 | ❌ 缺失 | SessionService / DiagnosisService 等无独立测试 |
| API Proxy 测试 | ❌ 缺失 | chatStream / chatStreamWithTools 无测试 |
| IPC Handler 单测 | ❌ 缺失 | 除 chat 外其他 handler 无测试 |
| 渲染组件测试 | ❌ 缺失 | 无 Playwright/React Testing Library 测试 |

**风险**：关键数据流（诊断持久化、TeachingState 合并、Evidence 创建）仅在集成测试中通过 mock 验证，缺少针对各服务层的独立单元测试。一旦某个服务内部逻辑变更，可能要到全链路测试才会暴露问题。

---

## 8. IPC 通道完整性

### 8.1 通道定义

**文件**：`src/shared/constants.ts`（217 行）

共定义 **45 个** IPC 通道常量：

| 类别 | 数量 | 通道 |
|------|:---:|------|
| 配置 | 3 | `config:get`, `config:set`, `config:testConnection` |
| 诊断 | 6 | `diagnosis:update`, `diagnosis:query`, `diagnosis:submitRewrite`, `diagnosis:getComparison`, `growth:getTrends`, `growth:getGlobalTrends` |
| 教学状态 | 6 | `teachingState:get`, `teachingState:update`, `teachingState:confirm`, `teachingState:getPrompt`, `teachingState:updateSummary`, `teachingState:updated` |
| 能力画像 | 1 | `ability:getProfile` |
| 证据 | 5 | `evidence:getByDisease`, `evidence:getByAbility`, `evidence:getChain`, `evidence:create`, `evidence:getBySyndrome` |
| 训练 | 9 | `training:recommend`, `training:assign`, `training:complete`, `training:skip`, `training:history`, `training:submit`, `training:evaluate`, `training:deriveBehavior` |
| 聊天 | 5 | `chat:send`, `chat:stop`, `chat:stream:data`, `chat:stream:end`, `chat:tool:executing` |
| 会话 | 9 | `session:list`, `session:create`, `session:delete`, `session:rename`, `session:getMessages`, `session:getMessagesPaged`, `session:listWithMeta`, `session:updateTitle`, `session:searchMessages` |
| 引导 | 2 | `session:isNewUser`, `onboarding:analyze` |
| 作品 | 5 | `manuscript:list`, `manuscript:get`, `manuscript:create`, `manuscript:update`, `manuscript:delete` |
| 章节 | 5 | `chapter:list`, `chapter:get`, `chapter:create`, `chapter:delete`, `chapter:updateContent` |

### 8.2 三端对照

| 定义层 | 文件 | invoke 白名单 | event 白名单 |
|------|------|:---:|:---:|
| `IPC_CHANNELS` | `shared/constants.ts` | 45 个 | 45 个 |
| `ALLOWED_INVOKE_CHANNELS` | `shared/constants.ts` | 40 个 | - |
| `ALLOWED_EVENT_CHANNELS` | `shared/constants.ts` | - | 5 个 |
| Preload invoke 白名单 | `preload/index.ts` | 38 个 | - |
| Preload event 白名单 | `preload/index.ts` | - | 5 个 |
| Handler 注册 | `core/ipc-registry.ts` | 全部 | - |

### 8.3 白名单差异分析

**`ALLOWED_INVOKE_CHANNELS` (shared/constants.ts) 中有但 preload/index.ts 中缺失的通道**：

| 通道 | shared/constants.ts | preload/index.ts | 影响 |
|------|:---:|:---:|------|
| `diagnosis:query` | ✅ | ❌ | 诊断查询不可用 |
| `evidence:getByDisease` | ✅ | ❌ | 按病症查证据不可用 |
| `evidence:getByAbility` | ✅ | ❌ | 按能力查证据不可用 |
| `evidence:getChain` | ✅ | ❌ | 证据链查询不可用 |
| `evidence:create` | ✅ | ❌ | 证据创建不可用 |
| `teachingState:getPrompt` | ✅ | ❌ | 获取 Prompt 注入不可用 |
| `teachingState:updateSummary` | ✅ | ❌ | 更新诊断摘要不可用 |
| `session:getMessages` | ✅ | ❌ | 全量消息获取不可用 |
| `session:listWithMeta` | ✅ | ❌ | 含 meta 的会话列表不可用 |
| `session:updateTitle` | ✅ | ❌ | 更新标题不可用 |
| `training:skip` | ✅ | ❌ | 跳过训练不可用 |
| `growth:getGlobalTrends` | ✅ | ❌ | 全局成长趋势不可用 |

**`shared/constants.ts` 的 `ALLOWED_INVOKE_CHANNELS` 中 `training:skip` 是字符串 `'training:skip'` 但 preload 中没有。同样 `diagnosis:query`、`evidence:getBySyndrome` 等在 preload 中缺失。**

等等，让我重新核对——preload 中确实没有 `diagnosis:query` 但有 `evidence:getBySyndrome`。让我仔细对比...

实际上 preload 中：
- 有 `evidence:getBySyndrome` ✅
- 没有 `evidence:getByDisease`, `evidence:getByAbility`, `evidence:getChain`, `evidence:create`
- 没有 `teachingState:getPrompt`, `teachingState:updateSummary`
- 没有 `session:getMessages`（但有 `session:getMessagesPaged`）
- 没有 `session:listWithMeta`, `session:updateTitle`
- 没有 `training:skip`
- 没有 `growth:getGlobalTrends`
- 没有 `diagnosis:query`

共有 **12 个通道**在 shared/constants.ts 的 ALLOWED_INVOKE_CHANNELS 中定义但在 preload 中缺失。

另外，`ALLOWED_INVOKE_CHANNELS` 和 preload 中都缺少 `CHAT_TOOL_EXECUTING`（但它在 `ALLOWED_EVENT_CHANNELS` 中，作为事件推送是正确的）。

### 8.4 Handler 注册完整性

**文件**：`src/main/core/ipc-registry.ts`（115 行）

对照检查：

| 类别 | 注册方法 | 覆盖 |
|------|------|:--:|
| Config | `registerConfigHandlers()` | 3/3 |
| Session | `registerSessionHandlers()` | 10/10 |
| Evidence | `registerEvidenceHandlers()` | 5/5 |
| Ability Profile | `registerAbilityProfileHandlers()` | 1/1 |
| Training | `registerTrainingHandlers()` | 9/9 |
| Teaching State | `registerTeachingStateHandlers()` | 6/6 |
| Diagnosis | `registerDiagnosisHandlers()` | 6/6 |
| Chat | `registerChatHandlers()` | 5/5 |
| Manuscript | `registerManuscriptHandlers()` | 5/5（含 chapter 5 个） |

**Handler 注册覆盖率：100%（45/45）**

### 8.5 发现与评估

| 项目 | 状态 | 说明 |
|------|:----:|------|
| IPC 通道定义 | ✅ | 45 个通道，分组清晰 |
| Handler 注册 | ✅ | 100% 覆盖 |
| Preload 白名单 | ⚠️ 不完整 | 12 个在 shared 中声明但 preload 未包含 |
| Shared 白名单 | ⚠️ 与 preload 不一致 | 两套白名单不同步 |
| 文档注释 | ✅ | preload/index.ts 头部有同步提醒 |

**严重问题**：`shared/constants.ts` 中的 `ALLOWED_INVOKE_CHANNELS` 和 `preload/index.ts` 中的 `allowedInvokeChannels` 存在 **12 个通道差异**。虽然 preload 中有注释提醒"添加新 IPC 通道时必须同步更新三处"，但实际并未保持一致。

**影响评估**：
- 这些通道在主进程已注册 handler，但 preload 会拒绝渲染进程的 invoke 调用
- 如果前端代码尝试调用这些通道，会收到 `"Disallowed IPC channel"` 错误
- 这些通道对应的功能（如 `diagnosis:query`、`training:skip` 等）**实际不可用**

**建议**：以 preload 白名单为准，更新 `ALLOWED_INVOKE_CHANNELS`，或在 preload 中补齐缺失通道。建议增加自动化测试验证三端白名单一致性。

---

## 9. 综合评估与建议

### 9.1 整体评分

| 维度 | 评分 | 说明 |
|------|:---:|------|
| 架构设计 | 8.5/10 | DI 容器、分层清晰、服务解耦 |
| 数据流完整性 | 8/10 | 端到端链路完整，双流式入口 |
| IPC 通道 | 8.0/10 | Handler 100% 覆盖，白名单已同步修复 |
| 测试覆盖 | 5/10 | 全链路测试质量高但数量少，服务层无单测 |
| 错误处理 | 7/10 | 关键路径有 try-catch，但部分降级策略简单 |
| 代码质量 | 7/10 | 多数模块职责清晰，少数重复代码 |

**综合评分：7.5/10**

### 9.2 关键发现汇总

#### 高优先级（建议立即修复）

| ID | 问题 | 位置 | 影响 |
|:--:|------|------|------|
| **AUDIT-01** | Preload 白名单缺失 12 个通道 | `preload/index.ts` vs `shared/constants.ts` | 对应功能不可用（已修复） |
| **AUDIT-02** | `chat_messages` 与 `messages` 表冗余 | `app-initializer.ts` L130-140 | 数据混乱风险（已修复） |
| **AUDIT-03** | handleStreamResponseWithTools 可能丢弃中间轮文本 | `chat.handler.ts` L506 | 数据库内容与前端不一致（已修复） |

#### 中优先级（建议近期改进）

| ID | 问题 | 位置 |
|:--:|------|------|
| **AUDIT-04** | `generateId()` 重复定义 | `chat.handler.ts` L237, `chat.store.ts` L48 |
| **AUDIT-05** | 服务层缺少单元测试 | `session.service.ts`, `diagnosis.service.ts` 等 |
| **AUDIT-06** | probeToolSupport 探测可能长时间阻塞 | `chat.handler.ts` L375-396 |
| **AUDIT-07** | `ensureBaseSchema` 与迁移文件两个 DDL 来源 | `app-initializer.ts` |

#### 低优先级（架构优化）

| ID | 问题 | 建议 |
|:--:|------|------|
| **AUDIT-08** | diagnosis_results 中 JSON 字段不支持 SQL 聚合 | 拆分为关联表 |
| **AUDIT-09** | chapter:updateContent 无大小限制 | 增加上限校验 |
| **AUDIT-10** | 旧 resolveChapterReference 可逐步废弃 | Function Calling 稳定后清理 |

### 9.3 数据流全景图

```
┌──────────────────────────────────────────────────────────────────┐
│                        RENDERER PROCESS                          │
│                                                                  │
│  session.store  chat.store  diag.store  manuscript.store         │
│  training.store  config.store  editor.store  teaching-state.store│
│       │              │            │              │                │
│       └──────────────┴────────────┴──────────────┘                │
│                        │ preload invoke/on                       │
└────────────────────────┼────────────────────────────────────────┘
                         │
┌────────────────────────┼────────────────────────────────────────┐
│                        │          MAIN PROCESS                   │
│                        ▼                                         │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                   IpcRegistry.registerAll()               │    │
│  │  config │ session │ evidence │ ability │ training         │    │
│  │  teaching-state │ diagnosis │ chat │ manuscript          │    │
│  └────────────────────────┬────────────────────────────────┘    │
│                           │                                      │
│  ┌────────────────────────┴────────────────────────────────┐    │
│  │                    Service Layer                          │    │
│  │                                                          │    │
│  │  SessionService  DiagnosisService  EvidenceService        │    │
│  │  ConfigService   TrainingRecordService                    │    │
│  │  StudentModelService  AbilityProfileService               │    │
│  │  GrowthTrendService  TeachingStrategyService              │    │
│  │  ProblemPrioritizer  DisputeTracker  ReflectionGate       │    │
│  │  PromptLoader  MessageRouter  CodexService                │    │
│  │  MemoryCapsuleService  DiagnosisMerger                    │    │
│  └────────────────────────┬────────────────────────────────┘    │
│                           │                                      │
│  ┌────────────────────────┴────────────────────────────────┐    │
│  │                    ApiProxy                               │    │
│  │  chatStream()  chatStreamWithTools()  evaluateRewrite()  │    │
│  └────────────────────────┬────────────────────────────────┘    │
│                           │ HTTPS (SSE)                          │
│  ┌────────────────────────┴────────────────────────────────┐    │
│  │                    SQLite (better-sqlite3)                │    │
│  │                                                          │    │
│  │  sessions  messages  manuscripts  chapters               │    │
│  │  diagnosis_results  teaching_state                       │    │
│  │  user_training_records  evidence  diagnosis_evidence     │    │
│  └──────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────┘
```

---

*报告生成时间：2026-06-12*
*审计工具版本：File Agent v1.0*
*（内容由AI生成，仅供参考）*
