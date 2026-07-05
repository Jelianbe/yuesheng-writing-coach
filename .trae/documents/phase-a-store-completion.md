# Phase A: 移动端 5 页面 Store 补全与数据对接

> 目标:把 5 个移动端页面的 mock 数据全部替换为真实 Store/Contract 数据,补齐缺失 Store。
> 范围:**仅前端 Store + 页面层**。不涉及主进程、不动 IPC handler、不改 prompt 模板。
> 入口约束:遵循 R-010 最小化范围 / R-019 代码硬上限 / R-021 行为边界(不替写、不顺手重构)。

---

## 1. 当前状态摘要(Phase 1 探索结果)

### Store 现状
| Store | 存在 | 状态 | 关键问题 |
|---|---|---|---|
| `manuscript.store` | ✅ | 已实现 fetchList/select/create/update/remove | ⚠️ `update/remove` 用 `{id}` 字段,Contract 要求 `{manuscriptId}` —— **阻塞 BookshelfPage** |
| `session.store` | ✅ | 已实现 loadSessions/create/switch/loadMessages/delete/rename | ⚠️ `loadSessions` 用 `session:list`,而 `session:listWithMeta` 才有 `lastMessage/relatedWorkTitle` |
| `project.store` | ✅(雏形) | 仅 `fetchList/getById` | ❌ 缺 `create/update/delete`,ProjectSpacePage 大量操作无 store 支撑 |
| `chat.store` | ✅ | sendMessage/appendToLastAssistant 等,经 `chatService` 转发 | ✅ 完整,ChatPage 接入即可 |
| `diag.store` | ✅ | fetchLatestDiagnosis/loadEvidence 等 | ✅ 完整,ChatPage 教学状态侧栏可对接 |
| `training.store` | ✅ | 完整(含 enterRetro) | ✅ 直接对接 training 工作流 |
| `page-stack.store` | ✅ | push/pop/navigateToTab | ✅ 替代 usePageStack hook(hook 不存在) |
| `teaching-state.store` | ✅ | 已存在 | ✅ ChatPage 教学状态侧栏可对接 |
| `ability.store` | ❌ | — | 🔴 需新建 |
| `growth.store` | ❌ | — | 🔴 需新建 |
| `prescription.store` | ❌ | — | 🔴 需新建 |
| `retro.store` | ❌ | — | 🔴 需新建(可从 training.store 迁出 enterRetro) |

### 关键阻塞点
1. **ID 维度陷阱**:`ability/growth/prescription.getStageProgress/retro` 全部用 `sessionId` 而非 `projectId`。
2. **字段名不匹配**:`manuscript.store` 用 `{id}` 调用 update/delete,Contract 期待 `{manuscriptId}`。
3. **ipc 基础设施**:统一改用 `typedInvoke` (在 `services/ipc-client.ts`) 替代 `getInvoke + as` 强转。
4. **usePageStack hook 不存在**:全部改用 `usePageStackStore`(`stores/page-stack.store.ts`)。

---

## 2. 实施顺序(严格执行 5 步)

### 步骤 1:基础设施修复(全先行,影响所有页面)
**目的**:修掉全链路阻塞,后续 4 步只需做"对接"

| # | 任务 | 文件 | 改动 |
|---|---|---|---|
| 1.1 | 修 `manuscript.store` 入参 | `src/renderer/stores/manuscript.store.ts` | `update/remove` 把 `{id}` 改为 `{manuscriptId}`;`create` 把 `description` 改为 `content`(按 contract) |
| 1.2 | 改用 `typedInvoke` | `src/renderer/stores/manuscript.store.ts` `src/renderer/stores/session.store.ts` `src/renderer/stores/project.store.ts` | 替换 `getInvoke() + as` 模式为 `typedInvoke<Req, Res>(channel, payload)`,消除 R-019 `as` 违规 |
| 1.3 | 抽出 `getInvoke` 内部重复代码 | (可选,如有必要) | 三个 store 的 try/catch 模式一致,后续 4 个新 store 直接复用 |

**验收**:`npm run typecheck` 零错误,无新增 `as` 强转。

### 步骤 2:A-1 BookshelfPage 数据对接
**目的**:验证 manuscript.store,最快可交付

| # | 任务 | 文件 | 改动 |
|---|---|---|---|
| 2.1 | 接入 Store | `src/renderer/pages/BookshelfPage.tsx` | 用 `useManuscriptStore(s => ({ manuscripts: s.manuscripts, loading: s.loading, fetchList: s.fetchList }))`(用 shallow) |
| 2.2 | 替换 mock | `src/renderer/pages/BookshelfPage.tsx` | 删除 `const BOOKS = [...]`,改用 `manuscripts`;加 `useEffect(() => fetchList(), [fetchList])` |
| 2.3 | 字段映射 | `src/renderer/pages/BookshelfPage.tsx` | `manuscript.title/coverColor/chapterCount/wordCount` → UI 字段;渐变由 `coverColor` 动态生成 |
| 2.4 | 加载/空状态 | `src/renderer/pages/BookshelfPage.tsx` | 渲染 `loading` 骨架 + `manuscripts.length === 0` 提示(留 Phase C 优化,本步仅占位) |

**验收**:`npm run typecheck && npm run test`,页面能渲染真实书卡。

### 步骤 3:A-2 ConversationsPage 增强
**目的**:从 listWithMeta 拿 `lastMessage/relatedWorkTitle`,让列表显示最近消息预览

| # | 任务 | 文件 | 改动 |
|---|---|---|---|
| 3.1 | 迁移通道 | `src/renderer/stores/session.store.ts` | `loadSessions` 改用 `IPC_CHANNELS.SESSION_LIST_WITH_META`(用 `typedInvoke<SessionListWithMetaRequest, SessionListWithMetaResponse>`) |
| 3.2 | 扩展类型 | `src/renderer/stores/session.store.ts` | `ChatSession` 增加 `lastMessage?: string / relatedWorkTitle?: string` 可选字段 |
| 3.3 | 页面映射 | `src/renderer/pages/ConversationsPage.tsx` | 列表项展示 `lastMessage` 预览 + `relatedWorkTitle` 副标题;删除对应 mock |
| 3.4 | 新建按钮 | `src/renderer/pages/ConversationsPage.tsx` | 触发 `createSession()` 跳转 chat 页面 |

**验收**:typecheck 通过,对话列表显示 `lastMessage/relatedWorkTitle` 真实数据。

### 步骤 4:A-3 ProjectSpacePage 补全
**目的**:补 project CRUD + 雷达图真实数据 + 章节列表真实数据

| # | 任务 | 文件 | 改动 |
|---|---|---|---|
| 4.1 | 补 project store CRUD | `src/renderer/stores/project.store.ts` | 新增 `createProject(input) / updateProject(id, data) / removeProject(id)`,对接 `IPC_CHANNELS.PROJECT_CREATE/UPDATE/DELETE` |
| 4.2 | 页面接入 store | `src/renderer/pages/ProjectSpacePage.tsx` | 用 `useProjectStore` 拿 `currentProject`(`params.id` 查找),无 store 加载时 `fetchList` |
| 4.3 | 新建 ability store | `src/renderer/stores/ability.store.ts` 🔴 | `fetchProfile(sessionId)` → `AbilityApi.getProfile`,存 `profile: AbilityProfile \| null` |
| 4.4 | 雷达图对接 | `src/renderer/pages/ProjectSpacePage.tsx` | `useAbilityStore` 拉数据,`<RadarChart>` 数据点用 `profile.syndromes` |
| 4.5 | 章节列表 | `src/renderer/pages/ProjectSpacePage.tsx` | **暂时延后**:章节需 `manuscriptId`,而 project.id 不等于 manuscriptId;留 D-DEBT-30 |
| 4.6 | 替换 mock | `src/renderer/pages/ProjectSpacePage.tsx` | 删除 `RADAR_VALUES/CHAPTERS/RECENT_RECORDS` mock,改 store 数据;`RECENT_RECORDS` 暂保留(无对应 store,D-DEBT-31) |

**验收**:typecheck + 页面能渲染项目元数据 + 雷达图来自 ability store。

### 步骤 5:A-4 ChatPage 数据对接
**目的**:激活已有 store,无需新增代码

| # | 任务 | 文件 | 改动 |
|---|---|---|---|
| 5.1 | 接入 session.store | `src/renderer/pages/ChatPage.tsx` | 用 `useSessionStore` 拿 `currentSessionId/loadMessages/switchSession` |
| 5.2 | 接入 chat.service | `src/renderer/pages/ChatPage.tsx` | 发送消息走 `chatService`(已在 chat.store 封装);加载消息走 `loadMessages` |
| 5.3 | 删除 mock | `src/renderer/pages/ChatPage.tsx` | 删除对话气泡/输入栏 mock(需先 Read 一次确认 mock 范围) |
| 5.4 | 教学状态侧栏 | (按需) | 如 ChatPage 有侧栏,对接 `useTeachingStateStore` |

**验收**:ChatPage 能用真实 session 渲染/发送消息。

### 步骤 6:A-5 AppsPage Store 层补齐
**目的**:4 个图标 + 3 个工具全部接真实数据

| # | 任务 | 文件 | 改动 |
|---|---|---|---|
| 6.1 | 新建 growth store | `src/renderer/stores/growth.store.ts` 🔴 | `fetchTrends(sessionId) / fetchGlobalTrends()`,对接 `GrowthApi.getTrends/getGlobalTrends` |
| 6.2 | 新建 prescription store | `src/renderer/stores/prescription.store.ts` 🔴 | `fetchAllStages() / fetchStageProgress(sessionId)`,对接 `PrescriptionApi` |
| 6.3 | 新建 retro store | `src/renderer/stores/retro.store.ts` 🔴 | `generate(sessionId) / save(input)`,从 `training.store` 迁出 `enterRetro` 逻辑;`training.store` 改为调用 `retro.store` |
| 6.4 | 改造 AppsPage | `src/renderer/pages/AppsPage.tsx` | 4 图标 → 点击 push 对应详情页(暂无,留 Phase C 路由规划);3 工具 → 触发对应 store action |
| 6.5 | 创建新页面占位 | `src/renderer/pages/{GrowthReportPage,TrainingPlanPage,TechniqueLibraryPage,MaterialLibraryPage}.tsx` | **暂留空壳**(读 params + 显示"数据加载中") |

**验收**:4 个新 store 通过 typecheck,AppsPage 4 图标可点击(后续详情页待 Phase C 补齐)。

---

## 3. 新增技术债(本次 Plan 不解决,登记到 decision-log)

| 编号 | 内容 | 原因 |
|---|---|---|
| D-DEBT-30 | ProjectSpacePage 章节列表 | 需 `manuscriptId` 而 project 概念无对应字段,需先界定 project↔manuscript 关系 |
| D-DEBT-31 | ProjectSpacePage 最近学习记录 | 无对应 store,需新建 `activity.store` 或在 training.store 加 history API |
| D-DEBT-32 | AppsPage 4 详情页(成长报告/训练计划/技法库/素材库) | Phase C 路由设计范围,本步仅占位 |
| D-DEBT-33 | training.store.enterRetro 迁出 | 本次 Plan 第 6.3 步,作为收尾 |
| D-DEBT-34 | getInvoke 内部重复代码抽象 | 5+ store 模式高度一致,但本步先 inline,留后续抽象 |

---

## 4. 假设与决策记录

| # | 假设/决策 | 依据 |
|---|---|---|
| D1 | 不重命名 `ChatSession` 为 `SessionInfo` | 涉及调用方多,本步风险大于收益,留后续 |
| D2 | `manuscript.store` 字段名以 Contract 为准(`manuscriptId/content`) | Contract 已注册且白名单放行,改 store 不会触发主进程变更 |
| D3 | 不新建 `chapter.store` | 当前 5 页面无章节编辑需求,ProjectSpacePage 章节列表留 D-DEBT-30 |
| D4 | `typedInvoke` 全部用 `ApiResponse<TResponse>` 解包 | 与现有 chat.service 模式一致 |
| D5 | 不修 `ChatSession` 内部 `messages: unknown[]` | 类型弱但暂不报错,留后续 |
| D6 | `usePageStackStore` 替代 `usePageStack` hook | 后者不存在,前者已封装好 |
| D7 | 错误处理保持各 store 独立 try/catch | 暂不抽公共 helper,留 D-DEBT-34 |

---

## 5. 门禁与验证

### 每步必跑(局部门禁)
```bash
npm run typecheck  # 零错误
```

### Plan 完成后(总门禁)
```bash
npm run typecheck && npm run test && npm run lint
```

### 手动验证(4 个页面)
- [ ] BookshelfPage:刷新后书卡来自 DB,新建按钮触发 manuscript.create
- [ ] ConversationsPage:列表显示 lastMessage 预览
- [ ] ProjectSpacePage:雷达图数据来自 ability store
- [ ] ChatPage:能加载历史消息,能发送新消息
- [ ] AppsPage:4 图标可点击(后续详情页待 Phase C)

---

## 6. 执行模式

按步骤顺序逐个执行,每完成一步立即跑 `npm run typecheck`。任意一步失败立即暂停,登记 D-DEBT 后切换为咨询模式等用户决策(R-009)。

**不在本 Plan 范围内**(避免范围蔓延):
- Phase B:类型化 IPC 调用统一、event-bus 集中化
- Phase C:三态骨架、下拉刷新、滑动返回、TabBar 冲突、InputBar 占位
- D-DEBT-29:前端审计重跑
- 主进程/数据库/Prompt 任何修改
- 设计稿/图标风格优化
