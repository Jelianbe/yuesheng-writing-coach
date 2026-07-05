# 移动端 V1 — IPC 管道改造 + 前端通道规划 + 交互优化方案

> 对齐 mobile-v1-plan.md（移动端 V1 前端重构）的 Phase B/C 范围
> 基于当前 IPC 通道体系（50+ invoke + 6 event）和 5 个移动端页面的就绪度评估
> 状态: Draft | 待审阅

---

## 1. 现状总览

### 1.1 5 页面就绪度

| 页面 | 当前状态 | 就绪度 | 主要差距 |
|:----|:---------|:------:|:---------|
| **BookshelfPage** | Mock 3 书卡 | **90%** | 无实质差距，直接对接现有 Store |
| **ConversationsPage** | Mock 3 对话 | **70%** | `session:listWithMeta` 已注册未用，需增强 `loadSessions` |
| **ProjectSpacePage** | Mock 雷达图+统计 | **40%** | `useProjectStore` 只有 read，缺 create/update/delete |
| **ChatPage** | Mock 气泡+输入栏 | **95%** | 直接对接 chat.service + session.store + diag.store |
| **AppsPage** | Mock 4×4 网格 | **30%** | growth/ability/prescription/retro 均无 Store 封装 |

### 1.2 IPC 通道利用率

- **Invoke 通道**: 50 个已注册 handler, 仅 23 个被前端 Store 消费（46%）
- **Event 通道**: 6 个已注册 handler, 5 个被前端消费（83%）
- **未消费通道**: prescription(×3)、growth(×2)、training(×11 中 10 个未用)、teachingState(除 event 外 5 个没用)、teachingNote(×4)、ability(×1)、retro(×2) = **~27 个通道已就绪但闲置**

### 1.3 关键发现

1. **Handler + Contract 层已就绪** — 后端 IPC 基础设施完善，差距全在前端 Store 封装
2. **page-stack.store 可直接复用** — 移动端导航 Store 已定义好 RootTab 和页面栈
3. **不存在"新建 IPC 通道"的需求** — 所有需要的数据都有对应通道，只是前端未消费
4. **单页 Store 封装密度不均** — chat/manuscript/chapter 高度封装，prescription/growth/ability 为零封装

---

## 2. 改造范围

### Phase A: Store 层补全（填补前端缺口）

#### A-1: BookshelfPage 数据对接（无新增代码）

直接用现有 Store 替换 mock：

| Mock 字段 | 真实数据源 | 操作 |
|:----------|:-----------|:-----|
| 作品卡片列表 | `useManuscriptStore.fetchList()` | 替换 mock 数组 |
| 封面色 | `manuscript.coverColor ?? 默认渐变` | 无 IPC 改动 |
| 书名 / 字数 / 章节数 | `manuscript.title` / `wordCount` / `chapterCount` | 无 IPC 改动 |

#### A-2: ConversationsPage 增强

| 当前 Mock | 真实数据源 | 操作 |
|:----------|:-----------|:-----|
| 标题 | `session.title` | 无 IPC 改动 |
| 摘要 | `session.lastMessage`（新字段） | **需确认 handler 是否返回** |
| 时间 | `session.updatedAt` | 无 IPC 改动 |
| 作品关联 | `session.relatedWorkTitle` | 需 `session:listWithMeta` |

**A-2a**: 增强 `useSessionStore.loadSessions` → 改用 `session:listWithMeta` 通道（已注册，返回 `messagesCount + lastMessageAt + relatedWorkTitle`）

**A-2b**: 新增 `useSessionStore.searchMessages(query)` → 对接 `session:searchMessages`（已注册，无 Store 封装）

#### A-3: ProjectSpacePage 补全

| 当前 Mock | 真实数据源 | 操作 |
|:----------|:-----------|:-----|
| 统计（6 诊断/4 训练/23 天） | `diagnosis:query` + `training:history` | 无 IPC 改动，组合 Store |
| 雷达图数据 | `ability:getProfile` | **新增 Store 封装** |
| CTA 开始学习 | `chat:send`（新建 session + 初始消息） | 无 IPC 改动 |
| 最近学习记录 | `training:history` | **新增 Store 封装** |
| 作品章节列表 | `chapter:list` | 无 IPC 改动 |

**A-3a**: `useProjectStore` 补全 CRUD：
- `createProject(data)` → `project:create`
- `updateProject(id, data)` → `project:update`
- `removeProject(id)` → `project:delete`

**A-3b**: 新增 `useAbilityStore`：
- `fetchProfile(projectId?)` → `ability:getProfile`

**A-3c**: `useTrainingStore` 封装 `training:history`（已有 **部分实现**，需确认 `fetchHistory` action 存在）

#### A-4: ChatPage 数据对接（最小改动）

| 当前 Mock | 真实数据源 | 操作 |
|:----------|:-----------|:-----|
| 欢迎引导 | `useChatStore.guidanceState` | 已有，只需激活 |
| 用户气泡 | `useChatStore.messages` | 已有 |
| 思考中 | `useChatStore.isStreaming` | 已有 |
| 诊断气泡 | `useDiagStore.latestDiagnosis` | 已有 |
| 发送消息 | `chatService.send()` | 已有 |
| 消息历史 | `useSessionStore.loadMessages()` | 已有 |

**A-4**: ChatPage 几乎可以直接用现有 Store 替换 mock。只有**输入栏的工具条**（📝文字/🖼️图片/📄文档/⚙️设定）是纯 UI 占位，功能未实现（D-DEBT-2026-06-25-02）。

#### A-5: AppsPage Store 层补齐

| Mock 网格项 | 数据源 | 操作 |
|:------------|:-------|:-----|
| 成长报告 | `growth:getTrends` + `getGlobalTrends` | **新增 Store 封装** |
| 训练计划 | `prescription:getAllStages` + `getStageProgress` | **新增 Store 封装** |
| 技法库 | `training:catalog` | **新增 Store 封装** |
| 素材库 | `distillation-index.json`（loader 已就绪） | **新增 Store 封装** |
| 结构拆解 | `evidence:getBySyndrome` | 已有 |
| 设定管理 | `manuscript:list` + `config:get` | 已有 |
| 导出作品 | `manuscript:list`（不需要 IPC） | 已有 |

**A-5a**: 新增 `useGrowthStore`：
- `fetchTrends(projectId)` → `growth:getTrends`
- `fetchGlobalTrends()` → `growth:getGlobalTrends`

**A-5b**: 新增 `usePrescriptionStore`：
- `fetchAllStages()` → `prescription:getAllStages`
- `fetchStageProgress(projectId)` → `prescription:getStageProgress`

**A-5c**: `useTrainingStore` 增强 + 封装：
- `fetchCatalog()` → `training:catalog`（已注册）
- `fetchRecommendations(projectId?)` → `training:recommend`（已注册）

**A-5d**: 新增 `useRetroStore`：
- `generateRetro(projectId, sessionId)` → `retro:generate`
- `saveRetro(record)` → `retro:save`

---

### Phase B: IPC 管道优化

#### B-1: 类型化 IPC 调用统一

现状：部分 Store 使用 `getInvoke()` + `IPC_CHANNELS.XXX` 字符串（如 `project.store.ts`），部分使用 `typedInvoke()` + Contract API（如 `chatApi.send()`）。

**目标**：所有 IPC 调用统一使用 Contract 类型 + `typedInvoke()`。

| Store | 当前方式 | 目标方式 |
|:------|:---------|:---------|
| `project.store.ts` | `getInvoke()(IPC_CHANNELS.PROJECT_LIST)` | `ProjectApi.list()` |
| `manuscript.store.ts` | `getInvoke()(IPC_CHANNELS.MS_LIST)` | `ManuscriptApi.list()` |
| 其他 | 混合 | 统一 |

#### B-2: Event 通道注册集中化

现状：App.tsx 中 `useEffect` 直接注册 IPC event listener（`teachingState:updated`、`chat:stream:data` 等 5 个）。

**目标**：建一个 `event-bus.service.ts` 统一管理 event 订阅/取消。

#### B-3: 移动端专用 IPC 通道

目前不需要新增 IPC 通道（50+ 个已覆盖全部需求）。但以下场景需确认：

- **雷达图数据源**：`ability:getProfile` 能否返回五维数值（人物塑造/情节节奏/环境描写/对话设计/叙事视角）？需要验证返回结构
- **成长趋势**：`growth:getTrends` 能否按天/周维度输出图表数据？需要验证返回结构

---

### Phase C: 交互设计优化

#### C-1: 通用的三态骨架

每个移动端页面统一实现：

| 状态 | 组件 | 触发条件 |
|:-----|:-----|:---------|
| 加载中 | Skeleton（灰色脉冲） | Store `loading === true` |
| 空数据 | EmptyState（插画 + 引导操作） | Store `items.length === 0` |
| 错误 | ErrorRetry（错误提示 + 重试按钮） | Store `error !== null` |
| 正常 | 正常内容 | Store `items.length > 0` |

#### C-2: 移动端特有交互

| 交互 | 优先级 | 方案 |
|:-----|:------:|:-----|
| 下拉刷新（Pull-to-Refresh） | **P1** | 统一 PullToRefresh 包裹器 + Store `refresh()` action |
| 滑动返回（Swipe-back） | **P2** | 简化：iOS 右滑弹窗确认，Android 物理返回键监听 |
| 长按菜单（Context Menu） | **P2** | 作品卡片/对话列表长按弹出 action sheet |
| 轻触反馈 | **P3** | CSS `:active` 缩放 0.97 状态（已有 `--transition-fast`） |
| 页面进场动画 | **P3** | push 时 slide-in-right，pop 时 slide-out-left |

#### C-3: 键盘 + TabBar 冲突（D-DEBT-2026-06-25-03）

| 场景 | 方案 |
|:-----|:-----|
| iOS Safari 键盘弹出 TabBar 上移 | `visualViewport` API 监听高度变化，动态隐藏 TabBar |
| 输入框被键盘遮挡 | `scrollIntoView()` + `padding-bottom: safe-area` |
| Android 返回键关闭键盘 | `window.addEventListener('popstate')` 配合 `document.activeElement.blur()` |

#### C-4: InputBar 功能占位活

ChatPage 输入栏的 4 个工具按钮（📝文字/🖼️图片/📄文档/⚙️设定）—— 当前是纯 UI 占位。

| 按钮 | 预期功能 | 依赖 | 优先级 |
|:-----|:---------|:-----|:------|
| 📝 文字 | 切换文字输入模式（默认） | 无 | P0（始终可用） |
| 🖼️ 图片 | 图片上传/截图 | `file:upload` IPC（需新建） | **P3** |
| 📄 文档 | 引用章节内容 | `chapter:get`（已存在） | **P2** |
| ⚙️ 设定 | 对话配置（态度/风格/专注症候） | `config:set` + `teachingState:update` | **P2** |

---

## 3. 实施路线图

```
Phase A (Store 补全 + 数据对接)         Phase B (管道优化)         Phase C (交互优化)
──────────────────────────────         ────────────────         ────────────────
A-1: BookshelfPage 对接    (0.5d)      B-1: 类型化统一  (0.5d)   C-1: 三态骨架    (1d)
A-2: ConversationsPage     (0.5d)      B-2: Event 集中化 (0.5d)  C-2: 移动交互    (1d)
A-3: ProjectSpacePage      (1d)        B-3: 验证通道     (0.5d)  C-3: 键盘冲突    (1d)
A-4: ChatPage 对接         (0.5d)                                  C-4: InputBar    (0.5d)
A-5: AppsPage              (1d)
                                    ────────────────         ────────────────
                                    ≈ 1.5d                    ≈ 3.5d
≈ 3.5d

执行顺序:
  Phase A → Phase B → Phase C
  (A-1 + A-4 可先做，零风险)
  (A-3 + A-5 需新建 Store，先做设计再编码)
```

---

## 4. 门禁标准 (DoD)

1. `npm run typecheck` 零错误
2. `npm run test` 全绿（新增 Store 测试 ≥ 80% 覆盖率）
3. `npm run lint` 零 error
4. 每个页面至少覆盖加载/空数据/错误/正常 4 种状态
5. 不存在未封装的 IPC `invoke` 调用（全部走 `typedInvoke`）
6. 键盘弹出时 TabBar 自动隐藏
7. 现有桌面端功能零回归

---

## 5. 不做（显式排除）

- ❌ 不新增 IPC 通道（已有 50+ 全覆盖）
- ❌ 不改后端 handler 逻辑（只补前端 Store 封装）
- ❌ 不做完整 E2E 测试（只补 Store 层的单元测试）
- ❌ 不处理桌面端三栏布局
- ❌ 不引入第三方移动端 UI 库
- ❌ 不处理图片上传（📷 按钮标注为 P3）

---

## 6. 风险

| 风险 | 概率 | 影响 | 缓解 |
|:-----|:----:|:----:|:-----|
| `ability:getProfile` 返回结构与雷达图不一致 | 中 | 高 | Phase A 前先验证返回数据 |
| `session:listWithMeta` 缺少某字段 | 低 | 中 | 退回用 `session:list` + 前端聚合 |
| Store 补全时 typecheck 因 Contract 类型不匹配报错 | 中 | 中 | 先读 Contract 再写 Store |
| keyboard + TabBar 冲突在 Electron 中不存在 | 高 | 低 | Electron 不是移动端，此问题只在 iOS Safari 出现，可后延 |
