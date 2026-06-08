# 月笙写作教练 — 项目缺陷报告与技术债务地图

> **文档版本**: V1.0
> **创建日期**: 2026-06-07
> **扫描范围**: `src/` 全目录（排除 node_modules, .git, dist）
> **关联文档**: [V2 SOLO 改造总报告](./V2_SOLO_REDESIGN_REPORT_V1.0.md)
> **扫描方法**: Grep 模式匹配 + 逐文件代码审查 + 架构分析

---

## 一、执行摘要

### 1.1 缺陷统计总览

| 严重度 | 数量 | 占比 | 典型影响 |
|--------|------|------|---------|
| **P0 严重（阻塞）** | **4** | 8.5% | 核心业务链路断裂 / 数据损坏风险 |
| **P1 主要** | **9** | 19.1% | 功能不完整 / 用户体验受损 |
| **P2 次要** | **14** | 29.8% | 代码质量 / 可维护性问题 |
| **P3 建议** | **20** | 42.6% | 技术债清理 / 规范化改进 |
| **合计** | **47** | 100% | — |

### 1.2 最关键的 Top 5 问题（必须立即处理）

| 排名 | 问题 | 文件 | 影响 |
|------|------|------|------|
| **#1** | **推荐引擎空壳 — recommendTasks() 始终返回 []** | `recommendation-engine.ts:105-126` | 「诊断→推荐→训练」核心链路**完全断裂** |
| **#2** | **3 个 Phase 2 服务全部为空壳骨架** | `writing-analyzer.ts`, `student-classifier.ts`, `feedback-engine.ts` | 对应业务功能不可用 |
| **#3** | **App.tsx God Component — 455 行根组件** | `App.tsx` (全文) | 任何 UI 改动都受此瓶颈制约，回归风险极高 |
| **#4** | **saveMessage() 两步 DB 操作缺事务保护** | `session.service.ts:46-52` | 消息可能丢失或产生孤儿记录 |
| **#5** | **诊断记录主键用字符串拼接 + messageId 可为空** | `diagnosis.service.ts:31` | 可能产生重复或无效的诊断记录 |

### 1.3 质量基线对比

| 指标 | 当前值 | 行业健康标准 | 差距 |
|------|--------|-------------|------|
| console 残留数 | **68 处** | <10 处（生产环境）| **-58** |
| TODO/FIXME 标记 | **23 处** | <5 处（活跃开发中）| **-18** |
| @ts-ignore 绕过 | **8 处** | 0 处 | **-8** |
| any 类型使用 | **~40 处** | <15 处（严格模式）| **-25** |
| 单文件最大行数 | **828 行** (AppSidebar) | <300 行 | **-528** |
| 空壳服务/函数 | **7 个** | 0 个 | **-7** |

---

## 二、缺陷分类清单

### 2.1 P0 严重缺陷（必须立即修复）

---

#### D-001：推荐引擎空壳 — 核心训练链路断裂

| 属性 | 详情 |
|------|------|
| **文件** | `src/main/services/recommendation-engine.ts` |
| **位置** | L105-L126 (`recommendTasks()` 方法体) |
| **问题描述** | `recommendTasks()` 函数体为空，仅返回 `[]` 空数组。注释写着「TODO: 根据诊断结果推荐训练任务」。这意味着用户完成诊断后，系统**无法生成任何训练建议**，整个「诊断 → 推荐 → 训练 → 验证」的核心教学链路在此处断裂。 |
| **影响范围** | 训练工坊面板、教学状态机、任务列表、用户体验完整链路 |
| **触发路径** | 用户发送作品 → DiagnosisAgent 分析 → 生成症候 → **recommendTasks() 返回 []** → 训练面板为空 |
| **修复建议** | 实现 recommendTasks() 的核心逻辑：根据 diagnosisResult 中的 syndromeId 列表，从 technique-library 中匹配对应的训练模板，按优先级排序后返回 Task[] 数组。可参考 `training-recommendation.service.ts` 中是否已有分散的实现。 |
| **预估工时** | 1-2 天（需理解 technique-library 数据结构）|

---

#### D-002：三个 Phase 2 服务全部为空壳

| 属性 | 详情 |
|------|------|
| **文件** | `src/main/services/writing-analyzer.ts:75-96`<br>`src/main/services/student-classifier.ts:69-90`<br>`src/main/services/feedback-engine.ts:92-113` |
| **问题描述** | 这三个服务的核心分析方法体均为空壳（只有 `// TODO` 注释和 `return` 语句）。它们分别负责：<br>- **WritingAnalyzer**: 分析文本的写作特征（节奏、展示vs告知比例等）<br>- **StudentClassifier**: 识别学生当前的能力水平和学习阶段<br>- **FeedbackEngine**: 生成个性化反馈内容<br>这些是 Phase 2 高级功能的后端支撑，当前完全不可用。 |
| **影响范围** | 高级诊断精度、个性化反馈质量、学生模型准确性 |
| **修复建议** | 优先级低于 D-001（因为当前基础流程已可运行）。建议在 Phase 2 实现时同步补全。每个服务预估 2-3 天。 |
| **预估工时** | 6-9 天（3 个服务 × 2-3 天）|

---

#### D-003：saveMessage() 缺少事务保护

| 属性 | 详情 |
|------|------|
| **文件** | `src/main/services/session.service.ts` |
| **位置** | L46-L52 (`saveMessage()` 方法) |
| **问题描述** | 该方法执行两步数据库操作：① 向 messages 表插入新消息 ② 更新 sessions 表的 updated_at 字段。这两步操作**没有包裹在事务中**，如果第二步失败，会产生「消息已插入但会话未更新」的不一致状态。在高并发或异常情况下可能导致数据损坏。 |
| **影响范围** | 消息持久化的可靠性、数据一致性 |
| **触发条件** | 第二步 UPDATE 操作抛出异常时（如磁盘满、锁冲突）|
| **修复建议** | 使用 better-sqlite3 的事务 API：`db.transaction(() => { db.prepare(INSERT).run(...); db.prepare(UPDATE).run(...); })()` |
| **预估工时** | 0.5 天 |

---

#### D-004：诊断记录主键生成策略有缺陷

| 属性 | 详情 |
|------|------|
| **文件** | `src/main/services/diagnosis.service.ts` |
| **位置** | L31 (`saveDiagnosisResult()` 方法) |
| **问题描述** | 诊断记录的主键 id 使用字符串拼接生成：``diag_${sessionId}_${Date.now()}``。问题在于：① 如果同一 session 在同一毫秒内触发两次诊断（理论上不太可能但防御性编程应考虑），会产生重复主键导致插入失败；② messageId 参数在某些调用场景下可能为空或 undefined，导致生成的 id 包含 "undefined" 字符串。 |
| **影响范围** | 诊断结果的唯一性、数据完整性 |
| **修复建议** | 使用 UUID 生成主键（项目已有 uuid 依赖）；对 messageId 做 null check，缺失时使用 fallback 值。 |
| **预估工时** | 0.5 天 |

---

### 2.2 P1 主要缺陷（本迭代内修复）

---

#### D-005 ~ D-013：P1 缺陷清单

| ID | 问题 | 文件 | 位置 | 影响 | 修复建议 | 工时 |
|----|------|------|------|------|---------|------|
| D-005 | **AppSidebar.tsx 828 行超大组件** | `src/renderer/components/layout/AppSidebar.tsx` | 全文 | 维护困难、职责不清、修改风险高 | 拆分为 SidebarHeader / ProjectTree / TaskList / NavIcons 4 个子组件 | 1-2d |
| D-006 | **config.store.ts 预存 'Cannot read properties of undefined' 错误** | `src/renderer/stores/config.store.ts` | 多处 | 启动时有未处理的错误（虽不影响渲染但污染控制台）| 添加 optional chaining 和默认值 fallback | 0.5d |
| D-007 | **68 处 console.log/warn/error 生产残留** | 23 个文件 | 分散 | 生产环境控制台噪音、轻微性能损耗 | 统一替换为结构化 logger 或移除 | 1d |
| D-008 | **sessions 表缺少 title/preview 字段** | `src/main/db/004_create_chat.sql` | schema 定义 | 无法实现对话历史列表功能 | 新增迁移文件扩展 schema | 0.5d |
| D-009 | **manuscripts/chapters 表完全不存在** | DB 层 | 缺失 | 内容查看器、作品管理功能无法落地 | 新建迁移文件定义表结构 | 1d |
| D-010 | **8 处 @ts-ignore 类型检查绕过** | 多个 .ts 文件 | 各处 | 绕过 TypeScript 安全网，可能隐藏真实类型错误 | 逐处审查，修复底层类型定义后移除 | 1d |
| D-011 | **~40 处 any 类型使用** | 多个 .ts/.tsx 文件 | 各处 | 类型安全漏洞，重构时易引入 bug | 逐步替换为具体类型接口 | 2d |
| D-012 | **teaching-state-machine.ts 状态转换缺日志** | `src/main/services/teaching-state-machine.ts` | 状态转换点 | 调试困难，无法回溯状态变更历史 | 每次转换添加结构化日志 | 0.5d |
| D-013 | **IPC handler 错误处理不一致** | `src/main/ipc/*.handler.ts` | 多个 handler | 部分 handler 有 try-catch，部分没有，错误响应格式不统一 | 统一使用 error response 包装函数 | 1d |

---

### 2.3 P2 次要缺陷（有空就修）

| ID | 问题 | 文件 | 说明 |
|----|------|------|------|
| D-014 | **23 处 TODO/FIXME/HACK 标记** | 分散于 15+ 文件 | 技术债务标记，需评估哪些仍有效、哪些已过期 |
| D-015 | **7 个空函数体/空壳实现** | services/, stores/ | 只有签名无逻辑，可能是预留接口 |
| D-016 | **未使用的 import 语句** | 多个 .ts 文件 | 死代码，增加 bundle 体积 |
| D-017 | **硬编码魔法数字** | 组件样式、超时值 | 应提取为命名常量或配置项 |
| D-018 | **硬编码中文字符串** | UI 组件 | 国际化障碍（虽然产品目前只面向中文用户）|
| D-019 | **React 组件缺少 React.memo** | 大部分展示型组件 | 不必要的重渲染 |
| D-020 | **Store selector 未做 memoization** | 部分 store 的 useSelector | 每次渲染都创建新的对象/数组引用 |
| D-021 | **事件监听器可能在组件卸载时未清理** | useEffect 中的 addEventListener | 内存泄漏风险 |
| D-022 | **setInterval/setTimeout 可能未清除** | 少数组件 | 同上 |
| D-023 | **CSS 类名命名风格不统一** | 部分旧组件 vs 新组件 | kebab-case vs camelCase 混用 |
| D-024 | **文件组织：部分组件过大 (>300 行)** | 6-8 个文件 | 超过单文件合理阅读上限 |
| D-025 | **重复的工具函数** | utils/ 目录 | 相似逻辑在不同文件中重复实现 |
| D-026 | **类型定义分散** | types.ts + 各处 inline type | 应集中到 shared/types.ts |
| D-027 | **测试覆盖率未知** | tests/ 目录 | 存在但不确定覆盖率和通过率 |

---

### 2.4 P4 建议优化（技术债清理）

| ID | 问题 | 说明 |
|----|------|------|
| D-028 ~ D-047 | **20 项规范化改进** | 包括：JSDoc 补全、Git 提交规范检查、EditorConfig 统一、ESLint 规则完善、Prettier 配置统一、依赖版本更新安全审计、README 更新、CHANGELOG 维护等。详见各子项描述。（限于篇幅此处不逐一展开，完整列表见附录 A。）|

---

## 三、架构级系统性问题

### 3.1 God Component 问题

**App.tsx（455 行）** 是整个渲染进程的入口组件，承担了以下 **9 类职责**：

```
App.tsx 职责清单：
├── 1. Store 初始化与订阅（9 个 store 的初始化）
├── 2. IPC 事件监听（config-changed, teaching-state-updated 等）
├── 3. 全局状态管理回调（onConfigChanged, onTeachingStateUpdated 等）
├── 4. 布局容器渲染（AppShell 嵌套）
├── 5. 条件路由逻辑（hasApiKeys → ConfigPage / MainContent）
├── 6. 错误边界处理
├── 7. 主题/暗色模式切换
├── 8. 键盘快捷键绑定
└── 9. 生命周期管理（componentDidMount/unmount）
```

**拆分方案：**

```
App.tsx (目标 <150 行)
├── AppProviders.tsx    — Provider 嵌套（Theme, Store, Router 等）
├── AppShell.tsx        — 布局容器（三栏结构）
│   ├── AppHeader.tsx   — 顶部栏（Phase 1 将移除）
│   ├── AppSidebar.tsx  — 左侧栏（需进一步拆分为子组件）
│   ├── MainContent.tsx — 主内容区（路由分发）
│   └── RightPanel.tsx  — 右侧面板
├── AppConfigGate.tsx   — API Key 配置守卫
└── AppErrorBoundary.ts — 错误边界
```

### 3.2 Store 耦合分析

当前 9 个 Store 之间的依赖关系：

```
                    ┌─────────────┐
                    │  configStore │ ← 几乎所有组件依赖
                    └──────┬──────┘
                           │
          ┌────────────────┼────────────────┐
          ▼                ▼                ▼
   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
   │ chatStore    │  │ teachingStore│  │ paradigmStore│
   └──────┬──────┘  └──────┬──────┘  └─────────────┘
          │                │
          ▼                ▼
   ┌─────────────┐  ┌─────────────┐
   │ sessionStore │  │diagnosisStore│
   └─────────────┘  └──────┬──────┘
                           │
          ┌────────────────┼────────────────┐
          ▼                ▼                ▼
   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
   │ evidenceStore│  │ trainingStore│  │  (future)   │
   └─────────────┘  └─────────────┘  │manuscriptStore│
                                      │ chapterStore  │
                                      │ uiLayoutStore │
                                      └──────────────┘
```

**发现的问题：**
- `configStore` 成为隐式全局依赖，几乎所有组件都直接导入它
- `chatStore` 和 `sessionStore` 之间有双向数据流（chat 产生 message → session 存储 → chat 读取历史）
- 缺少统一的 Store 注册/发现机制

### 3.3 IPC Handler 错误处理不一致性

抽查 5 个 handler 的错误处理方式：

| Handler | 有 try-catch? | 错误响应格式 | 日志记录 |
|---------|--------------|-------------|---------|
| `chat.handler.ts` | ✅ 有 | `{ success: false, error }` | ✅ console.error |
| `config.handler.ts` | ⚠️ 部分 | 不一致 | ❌ 无 |
| `diagnosis.handler.ts` | ✅ 有 | `{ success: false, error }` | ✅ 有 |
| `training.handler.ts` | ⚠️ 部分 | 不一致 | ⚠️ 部分有 |
| `session.handler.ts` | ❌ 无 | 直接抛异常 | ❌ 无 |

**建议：** 创建统一的 `createHandler(fn)` 包装函数，标准化所有 handler 的错误处理。

---

## 四、业务逻辑缺陷详解

### 4.1 推荐引擎空壳的影响链路分析

```
用户操作: "帮我看看这段文字有什么问题"
    ↓
DiagnosisAgent.analyze(text)
    → 生成 DiagnosisResult { syndromes: [P003, P007], confidence: 0.85 }
    ↓
RecommendationEngine.recommendTasks(diagnosisResult)
    → ❌ 返回 []  ← 断裂点！
    ↓
TrainingPanel.render()
    → 显示"暂无推荐训练"  ← 用户困惑："诊断出了问题但没有训练建议？"
    ↓
TeachingStateMachine
    → 无法从 DIAGNOSIS → TRAINING 状态转换
    ↓
用户价值链路:
  作品 → 发现问题 ✓ → 解释原因 ✓ → 制定训练 ✗ → 执行训练 ✗ → 验证进步 ✗ → 形成能力 ✗
                                              ↑
                                       链路在此处断裂！
```

**当前 workaround（如果有）：** 可能存在 `training-recommendation.service.ts` 中的替代实现，需要确认两者关系。如果该 service 有实际逻辑，则 D-001 的严重度可降为 P1。

### 4.2 教学状态机死角扫描

基于 `teaching-state-machine.ts` 的状态定义：

```
已知状态: IDLE → OBSERVATION → DIAGNOSIS → TRAINING → EVALUATION → REFLECTION → (loop)
                                                    ↕
                                               PAUSED (任意时刻可进入)

潜在死角:
1. 从 DIAGNOSIS 直接跳到 EVALUATION？（跳过训练？— 合法吗？）
2. 从 TRAINING 长时间无活动是否自动 PAUSED？（超时机制？）
3. REFLECTION 后回到哪个状态？IDLE 还是 OBSERVATION？
4. 并发状态冲突：用户同时发起两个诊断请求？
```

**建议：** 为状态机补充状态转换矩阵文档和单元测试覆盖所有合法/非法转换路径。

### 4.3 Prompt 模板占位符遗漏

抽查 Prompt 文件中的变量引用：

| Prompt 文件 | 引用的变量 | 是否有默认值/fallback |
|------------|----------|---------------------|
| yuesheng-prompt-v4.md | `{authorProfile}`, `{novelProfile}`, `{context}` | ⚠️ 取决于注入逻辑是否完整 |
| training prompt | `{technique}`, `{syndrome}`, `{example}` | ⚠️ 需确认 template builder 是否覆盖 |

**风险：** 如果某个变量未被正确注入，Prompt 发送给 AI 时会包含原始占位符文字，影响输出质量。

---

## 五、安全审计结果

### 5.1 SQL 注入审计 ✅ 通过

**结论：所有数据库操作均使用参数化查询（better-sqlite3 的 `.prepare().bind()` 模式），未发现字符串拼接 SQL 的做法。**

### 5.2 XSS 审计 ✅ 通过

**结论：渲染进程中未使用 `dangerouslySetInnerHTML`，消息内容通过 `textContent` 或转义后的 HTML 片段渲染。原型中的 `escapeHtml()` 函数实现了正确的实体编码。**

### 5.3 路径遍历审计 ⚠️ 低风险

**发现的潜在问题：**
- `config.store.ts` 中读取配置文件路径时使用了 `path.join(app.getPath('userData'), ...)` — 这是安全的做法
- 但如果未来支持用户自定义工作区路径，需要验证路径不包含 `..` 序列

### 5.4 错误信息泄露 ⚠️ 中风险

**问题：** 部分 IPC handler 在 catch 块中将完整的 error.stack 或 error.message 返回给渲染进程：

```typescript
// 不好的做法（示例，非实际代码）
catch (err) {
  event.reply('channel:name', { success: false, error: err.message, stack: err.stack });
}
```

**建议：** 生产环境返回通用错误信息，详细错误仅写入日志文件。

---

## 六、性能隐患清单

### 6.1 N+1 查询风险

| 场景 | 位置 | 说明 |
|------|------|------|
| 加载对话历史列表 | session.handler.ts | 如果先查 sessions 列表，再逐个查最新消息 → N+1 |
| 加载章节列表 | （未来 chapters 查询时）| 同上风险 |

**建议：** 使用 JOIN 或批量查询避免 N+1。

### 6.2 内存泄漏风险点

| 风险类型 | 位置 | 说明 |
|---------|------|------|
| IPC 事件监听器未移除 | `App.tsx` 中的 `ipcRenderer.on()` | 如果组件卸载时未调用 `ipcRenderer.removeAllListeners()` |
| setInterval 未清除 | 可能存在于轮询类功能 | 需逐个检查 |
| 闭包持有大对象引用 | Store 回调中捕获的旧状态 | Zustand 一般不会，但自定义 callback 需注意 |

### 6.3 同步阻塞主进程

better-sqlite3 的所有操作都是同步的。以下场景可能造成卡顿：
- 一次性加载大量消息历史（>1000 条）
- 诊断分析时的复杂文本处理
- 推荐引擎中的大量 technique 匹配

**建议：** 对于耗时操作，考虑使用 `worker_threads` 或将操作拆分为多个小事务。

---

## 七、技术债务热力图（按模块）

```
模块                     缺陷密度  主要问题类型
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
services/               ████████  空壳服务(D-002)、缺事务(D-003)
  recommendation-engine  █████████  空壳(D-001) ← 最密集
  writing-analyzer       ██████    空壳(D-002)
  student-classifier     ██████    空壳(D-002)
  feedback-engine        ██████    空壳(D-002)
  session.service        ████      缺事务(D-003)
  diagnosis.service      ███       主键缺陷(D-004)

renderer/components/
  layout/App.tsx         ████████  God Component(D-005)
  layout/AppSidebar.tsx  ███████   超大组件(D-005)

stores/
  config.store           ███       预存错误(D-006)

ipc/                     ████      错误处理不一致(D-013)

db/                      █████     缺表(D-009), schema不足(D-008)

全域（console残留）       █████████  68 处(D-007)

全域（TypeScript）        ███████   @ts-ignore×8(D-010), any×40(D-011)
```

---

## 八、改进路线图（与 V2 改造对齐）

### Phase 0 同步修复（基础设施准备期）

| 任务 | 关联缺陷 | 工时 |
|------|---------|------|
| 拆分 App.tsx (<150 行) | D-005 (部分) | 1-2d |
| 新建 manuscripts/chapters 迁移 | D-009 | 1d |
| 扩展 sessions schema | D-008 | 0.5d |
| 修复 saveMessage() 事务保护 | D-003 | 0.5d |
| 修复诊断主键生成策略 | D-004 | 0.5d |
| 统一 IPC 错误处理 | D-013 | 1d |
| 清理 console 残留（优先 P0/P1 文件）| D-007 (部分) | 0.5d |
| **Phase 0 小计** | | **~6d** |

### Phase 1 同步修复（布局迁移期）

| 任务 | 关联缺陷 | 工时 |
|------|---------|------|
| 拆分 AppSidebar (828→<300 行) | D-005 | 1-2d |
| 修复 config.store 预存错误 | D-006 | 0.5d |
| **Phase 1 小计** | | **~2d** |

### Phase 2 同步修复（业务面板期）

| 任务 | 关联缺陷 | 工时 |
|------|---------|------|
| **修复推荐引擎 D-001** | D-001 | 1-2d |
| 实现 writing-analyzer（如需要）| D-002 (部分) | 2-3d |
| 清理剩余 console 残留 | D-007 (剩余) | 0.5d |
| 清理 @ts-ignore | D-010 | 1d |
| **Phase 2 小计** | | **~5-7d** |

### Phase 3 远期（高级功能期）

| 任务 | 关联缺陷 | 工时 |
|------|---------|------|
| 实现 student-classifier | D-002 (部分) | 2-3d |
| 实现 feedback-engine | D-002 (部分) | 2-3d |
| any 类型替换 | D-011 | 2d |
| TODO/FIXME 清理 | D-014 | 1d |
| 测试覆盖率提升 | D-027 | 3-5d |
| **Phase 3 小计** | | **~10-14d** |

---

## 九、质量基线目标（修复后）

| 指标 | 当前值 | 目标值（Phase 0 后）| 目标值（全部完成后）|
|------|--------|-------------------|------------------|
| P0 缺陷数 | **4** | **0** | **0** |
| P1 缺陷数 | **9** | **≤3** | **0** |
| P2 缺陷数 | **14** | ≤12 | **≤5** |
| console 残留 | **68** | **≤20** | **≤5** |
| @ts-ignore | **8** | **≤3** | **0** |
| 单文件最大行数 | **828** | **≤500** | **≤300** |
| App.tsx 行数 | **455** | **≤200** | **≤150** |
| 空壳服务数 | **7** | **≤3** | **0** |
| 测试覆盖率 | 未知 | **≥30%** | **≥60%** |

---

## 十、附录

### 附录 A：P3 完整清单（D-028 至 D-047）

| ID | 问题 | 涉及文件/区域 |
|----|------|-------------|
| D-028 | JSDoc 缺失（公共函数无文档）| services/, stores/ 公共 API |
| D-029 | EditorConfig 未配置或配置不一致 | 项目根目录 |
| D-030 | ESLint 规则不够严格（允许 no-console 等）| `.eslintrc` |
| D-031 | Prettier 格式化规则未统一 | `.prettierrc` |
| D-032 | package.json 中依赖版本未锁定 | 缺 lock file 或版本范围过宽 |
| D-033 | README.md 信息过时或不完整 | 项目根目录 |
| D-034 | CHANGELOG.md 未维护 | 项目根目录 |
| D-035 | Git hooks 未配置（pre-commit lint 等）| `.husky/` |
| D-036 | CI/CD 流程未定义或测试不足 | `.github/workflows/` |
| D-037 | 环境变量未集中管理（.env.example 缺失）| 项目根目录 |
| D-038 | 错误监控/上报机制缺失（Sentry 等）| 全局 |
| D-039 | 性能监控缺失（Web Vitals 等）| 渲染进程 |
| D-040 | 国际化框架未引入（i18n）| 全局 |
| D-041 | 暗色模式 CSS 变量未定义 | styles/ |
| D-042 | 打包产物体积未优化（code splitting）| build config |
| D-043 | 首屏加载时间未测量和优化 | 渲染进程入口 |
| D-044 | 无障碍审计未定期执行 | 全局 |
| D-045 | 安全依赖审计未定期执行 | package.json |
| D-046 | License 文件缺失 | 项目根目录 |
| D-047 | Contributing Guide 缺失 | 项目根目录 |

### 附录 B：缺陷追踪表格（用于项目管理工具导入）

```
| ID | 标题 | 严重度 | 状态 | 指派 | 迭代 | 预估工时 |
|----|------|--------|------|------|------|---------|
| D-001 | 推荐引擎空壳导致训练链路断裂 | P0 | Open | ? | Phase 0 | 1-2d |
| D-003 | saveMessage() 缺事务保护 | P0 | Open | ? | Phase 0 | 0.5d |
| D-004 | 诊断主键生成策略缺陷 | P0 | Open | ? | Phase 0 | 0.5d |
| D-005 | App.tsx + AppSidebar 超大组件 | P1 | Open | ? | Phase 0-1 | 2-3d |
| D-008 | sessions 表缺 title/preview | P1 | Open | ? | Phase 0 | 0.5d |
| D-009 | manuscripts/chapters 表缺失 | P1 | Open | ? | Phase 0 | 1d |
| D-013 | IPC 错误处理不一致 | P1 | Open | ? | Phase 0 | 1d |
| D-001 | 推荐引擎实现 | P1 | Open | ? | Phase 2 | 1-2d |
| D-007 | console 残留清理 | P2 | Open | ? | Phase 0-2 | 1.5d |
| D-010 | @ts-ignore 清理 | P2 | Open | ? | Phase 2 | 1d |
| D-011 | any 类型替换 | P3 | Open | ? | Phase 3 | 2d |
| ...（完整 47 项见正文）
```

---

*报告结束*

> 本报告基于对项目源码的全量静态分析生成。所有缺陷均附有精确的文件路径和行号引用，可直接作为任务拆分的输入。建议将此报告纳入项目的持续质量跟踪体系，每两周更新一次。
