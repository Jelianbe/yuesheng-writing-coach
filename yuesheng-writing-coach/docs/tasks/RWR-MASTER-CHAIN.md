# RWR → V6.2 统一任务链（Master Chain V2）

> **权威依据**：[V6.2 Shell 计划](../.specify/phase-f-shell-v6.2-task-plan.md)（前端唯一蓝图）
> **设计权威**：[系统重构规格文档](../dev-docs/designs/2026-06-17-system-rewrite-spec.md)
> **前端基线**：`dev-docs/previews/phase-f-shell-v6.2.html`（已审批的完整前端预览）
> **RWR 基点**：`ac60ded`（FB-032 终态，RWR-P1-12 ✅）
>
> **重要声明**：RWR Phase A/F（前端重写任务）已被 V6.2 Shell 计划推翻重构。所有前端工作以 V6.2 Phases G-K 为准。
> **创建日期**：2026-06-17 | **重构日期**：2026-06-19 — RWR 并入 V6.2 主干

---

## 一、已完成（RWR 后端成果 — 完全保留）

以下 RWR 任务为后端/数据/类型层工作，**完全保留**，不受前端重构影响：

| 任务 | 内容 | 涉及文件 |
|:-----|:-----|:---------|
| P0-1 | DB 数据模型扩展 | `021_teaching_progress.sql`（diagnosis.teachingProgress + student_model） |
| P0-2 | progress.store | `stores/progress.store.ts` |
| P0-3 | Store 导出路径统一 | `stores/index.ts`（barrel export）+ 删除旧 rightPanelService |
| P0-4 | 项目 IPC + 项目表 migration | `022_projects.sql` + `ipc/project.ipc.ts` |
| P0-5 | 数据迁移脚本 | `023_data_migration.sql` |
| P1-6 (B-2) | 教学决策记录层 + 诊断联动 progress | `024_teaching_decision_log.sql` + `decision.service.ts` + `diagnosis-processor.ts` + `app-controller.ts` |
| P1-7 (C-1) | studentModel 持久化层（teachingHistory + attitudePreference） | `student-model-service.ts`（+4 方法）+ `types-teaching.ts`（+3 类型） |
| P1-9 (C-3) | 训练反馈回路 + 精通门控 | `teaching-history.contract.ts` + `training.handler.ts`（+emit `teachingState:mastery`）+ `training.actions.ts`（line 266+ 反馈链） |
| P1-10 (C-4) | 教学状态机消费 mastery 事件 | `teaching-state.contract.ts`（+MasteryEvent + api.mastery）+ `teaching-state.service.ts`（+onMastery）+ `teaching-state.store.ts`（+masteredSyndromeIds） |
| P1-11 (C-5) | 精通信息注入 Prompt | `App.tsx`（handleSendMessage 追加 masterySuffix） |
| P1-12 (C-6) | AI 收到 mastery 后的回应对齐 | `yuesheng-prompt-v3.md`（+精通技法处理规则段） |
| P1-5 (B-1) | TeachingProgressBar 逻辑层 + ProgressTimeline | `TeachingProgressBar.tsx` + `ProgressTimeline.tsx` 中的业务逻辑代码 |

---

## 二、RWR 前端任务 — 已被 V6.2 推翻重构

以下 RWR 前端任务 **已被 V6.2 Shell 计划推翻**，不再作为待执行任务。其功能意图由 V6.2 Phases G-K 覆盖：

| RWR 任务 | 状态 | V6.2 替代方案 | 原因 |
|:---------|:----:|:--------------|:-----|
| **P0-6** useRightPanel hook + SettingsPanel | 🔄 **已推翻** | V6.2 J-02 (Zustand Store) + J-04 (IPC 集成层) | V6.2 有全新的 Store 设计和组件树 |
| **P1-1** AppShell 三栏独立布局 | 🔄 **已推翻** | V6.2 J-01 (组件拆分 — `AppShell.tsx` ) | V6.2 shell 布局与 spec §2.1 对齐更精确 |
| **P1-2** SoloSidebar 三标签 | 🔄 **已推翻** | V6.2 J-01 (组件拆分 — `LeftPanel.tsx` + `SessionList.tsx` + `ProjectList.tsx`) | V6.2 左侧栏按 spec §6.1 重新设计 |
| **P1-3** ProjectSelector + InputToolbar + AttitudeIndicator | 🔄 **已推翻** | V6.2 J-01 (组件拆分 — `ChatHeader.tsx` + `ChatInput.tsx` + `AttitudeLights.tsx`) | V6.2 组件按 §13.2 每组件一目录重建 |
| **P1-4** 输入区 1/6 屏高重构 | 🔄 **已推翻** | V6.2 J-01 (`ChatInput.tsx`) + K-01 (交互细节打磨) | V6.2 输入区按 spec §5 完整重建 |
| **P1-5 (B-1)** TeachingProgressBar UI + ProgressTimeline | 🔄 **已推翻** | V6.2 J-01 (UI 部分 → 新 `RightPanel` 子组件) | 业务逻辑保留，UI 层移植到新组件目录 |
| **P1-8 (C-2)** 右侧栏"进步摘要"卡片 | 🔄 **已推翻** | V6.2 J-01 (新 `RightPanel` 组件树) | UI 层在新 RightPanel 中重建 |
| **A-1** SoloSidebar 三标签 [对话][项目][训练] | 🔄 **已推翻** | V6.2 G-01 (会话点击联动) + G-02 (训练历史选中) | V6.2 Phase G 直接实现交互填充 |
| **A-2** 输入区 1/6 屏高重构 | 🔄 **已推翻** | V6.2 G-01~G-05 (交互填充各组件) | V6.2 Phase G 统一处理交互逻辑 |
| **D-1** LearningLogPanel | 🔄 **已推翻** | V6.2 H-03 (学习日志工具) | V6.2 Phase H 训练模块深实现时一并建造 |
| **D-2** IPC 错误处理 + 骨架屏 | 🔄 **已推翻** | V6.2 J-04 (IPC 集成层 — 含错误处理和 loading 状态) | V6.2 集成层直接包含错误处理 |
| **D-3** 空状态全覆盖 + placeholder 轮换 | 🔄 **已推翻** | V6.2 J-01 (各组件自带空状态) + K-01 (交互打磨) | 在组件化过程中自然实现 |
| **E-2** 文件上传 + 分章 | 🔄 **已推翻** | V6.2 G-03 (项目章节联动) + 后续 H 阶段 | 在交互填充阶段实现 |
| **E-4** 全链路验收测试 | 🔄 **已推翻** | V6.2 K-03 (性能优化 + 验收) | V6.2 K 阶段统一收尾 |
| **F-0~F-6** 前端二次重写全部任务 | 🔄 **已推翻** | V6.2 Phases G-K 全部 | V6.2 是已审批的更好方案 |

> **技术说明**：被推翻的任务中，RWR 的后端逻辑代码（如 `decision.service.ts`、`student-model-service.ts`、`teaching-state.service.ts` 等）**不变**。推翻的只是前端 UI 层。

---

## 三、待执行序列（Phase BL 基线修复 → V6.2 Phases G-K 为主干）

> **当前指针 → V6.2 主干链 + 新增 I-07/I-08**（Phases BL→G→I→H→J→K 基础通过门禁。新增后端缺口 I-07 growth:getTrends、I-08 teachingNote:* 待实现。H-03/H-04 扩展为真实后端对接）

---

### Phase BL：代码基线修复（2026-06-19 体检发现）

**设计依据**：2026-06-19 全量体检报告（typecheck + lint + size + circular + test + scan:hardcode）  
**目的**：在进入 V6.2 交互开发前，清除阻塞门禁的关键问题，建立干净的代码基线。  
**DoD**：
- `npm run typecheck` 零错误
- `npm run test` 全绿（环境问题修复）
- 空接口类型规范化
- 文件大小超限项标记或拆分

#### BL-01 修复 tsc 类型错误

| 属性 | 值 |
|:-----|:-----|
| 前置 | 无 |
| 目标 | 修复 2 个 tsc 错误：`App.tsx:22` 未使用 import + `right-panel.store.ts:40` 缺失模块 |
| 涉及文件 | `src/renderer/App.tsx`（删无用 import）+ `src/renderer/stores/right-panel.store.ts`（修复导入路径） |
| DoD | □ `npm run typecheck` 零错误 |

#### BL-02 修复空接口类型（R-019 规范）

| 属性 | 值 |
|:-----|:-----|
| 前置 | 无 |
| 目标 | 6 处 `interface {}` → `Record<string, never>`，消除 ESLint `no-empty-object-type` 错误 |
| 涉及文件 | `growth.contract.ts` / `manuscript.contract.ts` / `project.contract.ts` / `session.contract.ts`（×3） |
| DoD | □ ESLint `no-empty-object-type` 零错误 |

#### BL-03 修复测试环境（better-sqlite3 重编译）

| 属性 | 值 |
|:-----|:-----|
| 前置 | 无 |
| 目标 | `npm rebuild better-sqlite3` 解决 NODE_MODULE_VERSION 不匹配，恢复 3 个测试套件 |
| 涉及文件 | 无（环境修复） |
| DoD | □ `npm run test` 全绿（167+20 全部通过） |

#### BL-04 超限文件评估与标记

| 属性 | 值 |
|:-----|:-----|
| 前置 | 无 |
| 目标 | 7 个 >500 行文件逐项评估：哪些需拆分、哪些可延后（如 `components_archived` 将被 V6.2 取代、测试文件可宽限） |
| 涉及文件 | 7 个超限文件（逐项决定） |
| DoD | □ 超限文件标记为 "待拆分" / "V6.2 重建后自动解决" / "测试文件宽限" |

#### BL-05 硬编码颜色修复

| 属性 | 值 |
|:-----|:-----|
| 前置 | 无 |
| 目标 | 3 处在 `components_archived/training/RecommendationsSection.module.css` 中的硬编码颜色替换为 CSS 变量 |
| 涉及文件 | `RecommendationsSection.module.css` |
| DoD | □ `npm run scan:hardcode` 零警告 |

---

### Phase G：功能填充（让 V6.2 Shell 可交互）

**设计依据**：`.specify/phase-f-shell-v6.2-task-plan.md` §Phase G  
**V6.2 基线**：`dev-docs/previews/phase-f-shell-v6.2.html`（交互填充在此基线基础上进行）  
**DoD**：
- 所有点击操作产生可见的界面响应
- 会话切换正确渲染对应消息
- 项目点击正确展示章节内容
- 技法目录选中后打开子标签详情

#### G-01 会话点击联动

| 属性 | 值 |
|:-----|:-----|
| 前置 | 无（V6.2 Shell 基线已就绪） |
| 目标 | 左侧点击会话 → `chatSessionId` 更新 → 中间栏渲染该会话的对应消息列表 |
| 涉及文件 | `dev-docs/previews/phase-f-shell-v6.2.html`（改）— 添加 JS 交互逻辑 |
| DoD | □ 点击不同会话显示不同消息<br>□ mock 数据体现差异性 |
| 依据 | V6.2 计划 §G-01 |

#### G-02 训练历史选中

| 属性 | 值 |
|:-----|:-----|
| 前置 | G-01 |
| 目标 | [对话] tab 下点击训练项 → 中间栏展示对应训练对话 → header 显示训练名称 |
| 涉及文件 | `dev-docs/previews/phase-f-shell-v6.2.html`（改） |
| DoD | □ 训练项点击展示对应内容<br>□ 训练与常规会话视觉区分 |
| 依据 | V6.2 计划 §G-02 |

#### G-03 项目章节联动

| 属性 | 值 |
|:-----|:-----|
| 前置 | G-01、G-02 |
| 目标 | [项目] tab → 点击项目 → 右侧作品工具打开，展示对应章节内容 |
| 涉及文件 | `dev-docs/previews/phase-f-shell-v6.2.html`（改） |
| DoD | □ 不同章节展示不同正文 mock 内容 |
| 依据 | V6.2 计划 §G-03 |

#### G-04 技法目录子标签展开详情

| 属性 | 值 |
|:-----|:-----|
| 前置 | G-03 |
| 目标 | 子标签点击技法 → 工作区展示技法详情（名称、难度、类别、说明） |
| 涉及文件 | `dev-docs/previews/phase-f-shell-v6.2.html`（改） |
| DoD | □ 技法详情填充有意义的 mock 内容<br>□ 活动子标签高亮 |
| 依据 | V6.2 计划 §G-04 |

#### G-05 右侧工具切换联动

| 属性 | 值 |
|:-----|:-----|
| 前置 | G-04 |
| 目标 | 切换 #toolTabs 标签 → 工作区渲染对应工具内容 |
| 涉及文件 | `dev-docs/previews/phase-f-shell-v6.2.html`（改） |
| DoD | □ 每个工具有基本的占位内容（名称+描述+占位图/表） |
| 依据 | V6.2 计划 §G-05 |

---

### Phase I：后端集成（V6.2 后端缺口填补）

> **设计依据**：`.specify/phase-f-shell-v6.2-task-plan.md` §Phase I  
> **前置条件**: Phase G 完成（了解前端需要哪些数据后，再实现真实IPC调用）
>
> **关键缺口**: 后端分析发现 `training:catalog` handler 缺失、`diagnosis:analyze` 通道不存在、`growth:getTrends` handler 未实现、`teachingNote:*` 通道未设计。
> 其他通道（`session:list`、`session:getMessages`、`config:get`/`config:set`）已就绪。
>
> **外部参考**: 安全加固完成后，需对照 [CYS 同学安全 7 道防线清单](../dev-docs/external-references/CYS同学总结/11.后端安全规范及流程.txt) 逐项验收，确保五道防线（身份认证/权限控制/输入校验/数据归属/注入防护）均通过

**DoD**：
- `training:catalog` 真实数据就绪，按 coreId 分组
- IPC 前端消费路径验证通过
- 诊断 IPC 方案确认
- 配置 IPC 安全加固（config:set 白名单 + teachingState:update 字段校验）
- `growth:getTrends` handler 注册（I-07）
- `teachingNote:*` 通道合约 + handler 就绪（I-08）
- `npm run typecheck` 0 / `npm run test` 全绿

#### I-01 `training:catalog` IPC Handler 实现

| 属性 | 值 |
|:-----|:-----|
| 前置 | 无（独立于前端重构，可并行启动） |
| 目标 | 在 `training.handler.ts` 中新增 `TRAINING_CATALOG` handler，从 `technique-library.json` 读取技法数据，按 coreId 分组后返回。**这是最紧迫的后端缺口** |
| 涉及文件 | `src/main/ipc/training.handler.ts`（+handler）+ `resources/config/technique-library.json`（数据源） |
| 依赖 | 合约层已就绪：`training.contract.ts`（TechniqueCatalogGroup / TrainingCatalogRequest/Response）、`types-training.ts`（TechniqueInfo）、`constants.ts`（TRAINING_CATALOG 通道常量）均已定义 |
| DoD | □ handler 注册：`createHandler(IPC_CHANNELS.TRAINING_CATALOG, ...)`<br>□ 从 technique-library.json 读取并按 coreId 分组<br>□ 返回格式匹配 TrainingCatalogResponse<br>□ 单元测试覆盖：正常返回 + 空数据 + 文件读取失败<br>□ tsc 0 / 测试全绿 |
| 依据 | V6.2 §I-01；后端缺口分析 2026-06-19 |

#### I-02 会话 IPC 前端消费验证

| 属性 | 值 |
|:-----|:-----|
| 前置 | 无（backend 已就绪，仅需验证前端消费路径） |
| 目标 | 验证 `session:list` 和 `session:getMessages` 在前端 V6.2 组件化后的消费路径是否正确 |
| 涉及文件 | `src/renderer/stores/session.store.ts`（验证）+ `src/main/ipc/session.handler.ts`（已实现） |
| DoD | □ session:list 在前端被正确调用<br>□ session:getMessages 在前端被正确调用<br>□ 错误处理符合 spec §13.5 |
| 依据 | V6.2 §I-02；后端分析确认 handler 已就绪 |

#### I-03 诊断 IPC 决策与实现

| 属性 | 值 |
|:-----|:-----|
| 前置 | 需与用户确认方案选择 |
| 目标 | 决策 `diagnosis:analyze` 通道方案：(A) 新增 `diagnosis:analyze` invoke handler；(B) 前端改用已有的 `DIAGNOSIS_QUERY` 查询现有诊断结果 |
| 涉及文件 | 待定（方案决定后确定） |
| DoD | □ 方案确认并落地<br>□ 前端可正确获取诊断数据 |
| 依据 | V6.2 §I-03；后端分析确认通道不存在 |

#### I-04 配置 IPC 前端消费路径确认

| 属性 | 值 |
|:-----|:-----|
| 前置 | 无（已就绪） |
| 目标 | V6.2 设置工具使用 `config:get` / `config:set` 通用通道（而非 `config:getApiKey` / `config:setApiKey`），确认前端消费路径 |
| 涉及文件 | `src/renderer/stores/config.store.ts`（已就绪）|
| DoD | □ 设置工具可读写 API Key<br>□ 符合 R-029 安全规范（API Key 仅在 main process 处理） |
| 依据 | V6.2 §I-04；`config.store.ts` 已正确使用通用通道模式 |

#### I-05 `config:set` 安全加固（SEC-DEBT-1）

| 属性 | 值 |
|:-----|:-----|
| 前置 | 无（安全紧急修复，可随时执行） |
| 目标 | 为 `config:set` handler 添加可修改键白名单，阻止 renderer 恶意覆盖 `apiKey` / `baseUrl` 等敏感配置 |
| 涉及文件 | `src/main/ipc/config.handler.ts` |
| DoD | □ 定义可修改配置键白名单<br>□ 非白名单键在 handler 层拒绝处理<br>□ 类型安全：移除 `as any`<br>□ tsc 0 / 测试全绿 |
| 依据 | 2026-06-19 IPC 安全审查 SEC-DEBT-1 |

#### I-06 `teachingState:update` 安全加固（SEC-DEBT-2）

| 属性 | 值 |
|:-----|:-----|
| 前置 | 无（安全紧急修复，可随时执行） |
| 目标 | 为 `teachingState:update` handler 添加字段白名单，替换 `updates: Record<string, unknown>` 为合约类型，移除 `as any` 类型绕过 |
| 涉及文件 | `src/main/ipc/teaching-state.handler.ts` + `src/shared/api-contracts/teaching-state.contract.ts`（若需扩展） |
| DoD | □ 更新合约类型：明确允许更新的字段集合<br>□ handler 层执行字段白名单校验<br>□ 移除 `as any`<br>□ tsc 0 / 测试全绿 |
| 依据 | 2026-06-19 IPC 安全审查 SEC-DEBT-2 |

#### I-07 `growth:getTrends` IPC Handler 实现

| 属性 | 值 |
|:-----|:-----|
| 前置 | 无（独立任务，后端补充） |
| 目标 | `growth:getTrends` 通道已定义 IPC_CHANNELS 和合约但 **handler 未实现**。需在 `diagnosis.handler.ts` 或新建 `growth.handler.ts` 中注册 handler，调用 `growthTrendService.getGrowthSummary()` 返回成长趋势数据 |
| 涉及文件 | `src/main/ipc/`（+handler）+ `src/shared/api-contracts/growth.contract.ts`（已就绪）+ `src/main/services/growth-trend.service.ts`（底层服务已就绪） |
| 依赖 | 合约层已就绪：`GrowthGetTrendsRequest` / `GrowthGetTrendsResponse` / `GrowthTrend` 均已定义 |
| DoD | □ handler 在 ipc-registry.ts 注册<br>□ 返回格式匹配 `{ trends: GrowthTrend[] }`<br>□ 单元测试覆盖：正常返回 + 空数据 + 服务不可用<br>□ tsc 0 / 测试全绿 |
| 依据 | v6.2 HTML 注释 `// IPC 通道 growth:getTrends 未实现，待 backend-architect 补充` |

#### I-08 `teachingNote:*` IPC 通道设计与实现（[记录到教学笔记] 交互）

| 属性 | 值 |
|:-----|:-----|
| 前置 | 需先完成通道设计决策 |
| 目标 | 当前教学笔记工具（TeachingNoteWorkspace）为纯 mock 数据，缺少两段关键链路：<br>1. **前端**：聊天区域的 `[记录到教学笔记]` 按钮 → 调用 IPC → 保存树节点<br>2. **后端**：`teachingNote:record`（创建节点）+ `teachingNote:getTree`（读取树）两个 invoke handler |
| 涉及文件 | `src/main/ipc/`（新建 teaching-note.handler.ts）+ `src/shared/api-contracts/`（新建 teaching-note.contract.ts）+ `src/shared/constants.ts`（+IPC_CHANNELS）+ `src/preload/index.ts`（白名单）+ 聊天组件（+[记录到教学笔记] 按钮） |
| 依赖 | 新建：合约层（TeachingNoteNode / RecordRequest / GetTreeResponse）+ 通道常量 + preload 白名单<br>需要先决定：树结构存储方式（SQLite 表 vs JSON 字段 vs 文件系统） |
| DoD | □ 合约定义完成（节点 id / 项目 id / 父节点 id / label / content / children / createdAt）<br>□ `teachingNote:record` handler 注册：保存节点到数据层<br>□ `teachingNote:getTree` handler 注册：按 projectId 返回完整树<br>□ `[记录到教学笔记]` 按钮在聊天工具栏中可点击（v6.2 HTML 基线参考）<br>□ 教学笔记树展开后展示已记录内容<br>□ preload 白名单包含两个通道<br>□ tsc 0 / 测试全绿 |
| 依据 | v6.2 HTML 记录到教学笔记交互（line 1236~1295）；`system-rewrite-spec.md` §[模板] 按钮功能描述；当前前端 TeachingNoteWorkspace mock 状态 |

---

### Phase H：训练模块深度实现

> **设计依据**：`.specify/phase-f-shell-v6.2-task-plan.md` §Phase H  
> **前置条件**：Phase G 完成（交互基础）+ Phase I 完成（`training:catalog` 真实数据就绪）

**DoD**：
- 技法目录完整操作链路跑通（选技法 → 新建训练 → 训练交互）
- 教学进度工具展示可读数据
- 学习日志通过 IPC 加载真实成长趋势数据（I-07）
- 教学笔记打通 [记录到教学笔记] 全链路（I-08）

#### H-01 技法目录完整流程

| 属性 | 值 |
|:-----|:-----|
| 前置 | G-04（技法目录子标签交互）、I-01（catalog 真实数据） |
| 目标 | 点击技法 → 新建训练会话 → 训练界面展示技法名称/目标/当前 phase/对话区 |
| 涉及文件 | `dev-docs/previews/phase-f-shell-v6.2.html`（改）— 添加训练启动交互 + mock 回复 |
| DoD | □ 选技法→新建训练会话<br>□ 训练界面展示技法名称、目标、当前阶段<br>□ mock 回复体现教练风格 |
| 依据 | V6.2 §H-01；spec §6.3 训练交互流 |

#### H-02 教学进度工具

| 属性 | 值 |
|:-----|:-----|
| 前置 | G-05（工具切换联动）、I-01（真实进度数据） |
| 目标 | PhaseProgress 可视化（进度条/阶段示意）；当前技法进度、总体进度 |
| 涉及文件 | `dev-docs/previews/phase-f-shell-v6.2.html`（改）— 教学进度工具内容 |
| DoD | □ 进度条显示已解决/总数<br>□ 按阶段分组展示<br>□ 当前指针标记 |
| 依据 | V6.2 §H-02；spec §4.2 |

#### H-03 学习日志工具

| 属性 | 值 |
|:-----|:-----|
| 前置 | G-05（工具切换联动）、**I-07（growth:getTrends handler 就绪）** |
| 目标 | 能力倾向聚合展示（柱状图/列表）；训练历史统计。**替换当前 mock 数据，通过 `growth:getTrends` IPC 加载真实成长趋势数据** |
| 涉及文件 | `src/renderer/components/right/workspaces/LearningLogWorkspace/index.tsx`（改 — 对接 IPC）+ `dev-docs/previews/phase-f-shell-v6.2.html`（改）|
| DoD | □ 前端 useEffect 调用 `growth:getTrends` IPC 加载趋势数据<br>□ mock 数据作为 IPC 失败回退<br>□ 展示训练完成记录统计卡片<br>□ 能力倾向视觉聚合（柱状图）<br>□ tsc 0 |
| 依据 | V6.2 §H-03；spec §4.10 |

#### H-04 教学笔记工具

| 属性 | 值 |
|:-----|:-----|
| 前置 | G-05（工具切换联动）、**I-08（teachingNote:* IPC 就绪）** |
| 目标 | 训练记录列表、诊断结果展示、教练建议汇总。**打通 [记录到教学笔记] 全链路：聊天按钮 → IPC → 持久化 → 树展开** |
| 涉及文件 | `src/renderer/components/right/workspaces/TeachingNoteWorkspace/index.tsx`（改 — 对接 IPC + 树展开）+ 聊天工具栏组件（+[记录到教学笔记] 按钮）+ `dev-docs/previews/phase-f-shell-v6.2.html`（改）|
| DoD | □ 训练记录按时间倒序（可从 `training:history` 加载）<br>□ 诊断结果概览展示（可从 `diagnosis:query` 加载）<br>□ 聊天工具栏 `[记录到教学笔记]` 按钮可点击 → 调用 `teachingNote:record`<br>□ 教学笔记树展开后展示已持久化的树节点<br>□ mock 数据作为 IPC 失败回退<br>□ tsc 0 |
| 依据 | V6.2 §H-04；spec §4.11 |

---

### Phase J：React 迁移（V6.2 Shell → React 组件）

> **设计依据**：`.specify/phase-f-shell-v6.2-task-plan.md` §Phase J  
> **前置条件**：Phase G + H + I 均完成（交互逻辑和数据流已通过 V6.2 Shell 验证，确保 React 迁移目标明确）
>
> **替换对象**：RWR Phase F（F-0~F-6）全部被此阶段替代
>
> **外部参考**：迁移前请阅读 [CYS 同学前端骨架 6 步法](../dev-docs/external-references/CYS同学总结/6.前端框架搭建规则与流程.txt)，严格按"风格定义→技术选型→目录结构→设计Token→计划文档→骨架实施"的流程执行

**DoD**：
- 主界面组件化完成（按 J-01 组件树）
- Zustand Store 接管状态（按 J-02 Store 设计）
- CSS Modules + Design Tokens 就绪（按 J-03）
- 构建通过（`npm run typecheck && npm run test && npm run lint`）

#### J-01 组件拆分

| 属性 | 值 |
|:-----|:-----|
| 前置 | Phases G/H/I 全部完成 |
| 目标 | 将 V6.2 Shell 拆分为 React 组件树，按 spec §13.2 目录规范（每组件一目录） |
| 组件树 | ```
src/renderer/components/
├── layout/
│   ├── LeftPanel.tsx          # 左栏（对话/项目 tab + 列表）
│   ├── CenterPanel.tsx        # 中间栏（header + 消息 + 输入区）
│   ├── RightPanel.tsx         # 右栏（tool tabs + sub tabs + workspace）
│   └── AppShell.tsx           # 三栏容器 + resize handles
├── left/
│   ├── SessionList.tsx        # 会话列表
│   ├── ProjectList.tsx        # 项目列表
│   └── LeftHeader.tsx         # 月笙图标 + 收起键 + 项目选择
├── center/
│   ├── ChatMessages.tsx       # 消息列表
│   ├── ChatInput.tsx          # 输入框 + 发送
│   └── AttitudeLights.tsx     # 态度灯
├── right/
│   ├── ToolTabs.tsx           # header 标签栏
│   ├── SubTabs.tsx            # 子标签栏
│   ├── ToolGrid.tsx           # 工具网格
│   ├── CatalogWorkspace.tsx   # 技法目录工作区
│   └── WorksWorkspace.tsx     # 作品工作区
``` |
| 涉及文件 | 全部新建，参考 `dev-docs/previews/phase-f-shell-v6.2.html` 的布局和交互逻辑 |
| DoD | □ 所有组件 ≤300 行（R-019）<br>□ CSS Module 引用 var(--xxx)，不定义新变量值<br>□ 无内联样式（R-019）<br>□ 组件树可独立渲染 |
| 依据 | V6.2 §J-01；spec §13.2 |

#### J-02 Zustand Store

| 属性 | 值 |
|:-----|:-----|
| 前置 | J-01（至少完成 AppShell + 三栏组件，Store 定义需与组件消费对齐） |
| 目标 | 为 V6.2 UI 层创建 Zustand Store，接管所有面板状态和交互逻辑 |
| Store 设计 | ```typescript
interface UIStore {
  // 面板状态
  leftCollapsed: boolean;
  rightCollapsed: boolean;
  leftWidth: number;
  rightWidth: number;

  // 左栏
  leftTab: 'chat' | 'proj';
  selectedSessionId: string | null;
  selectedProjectId: string | null;

  // 右栏
  openTools: string[];
  activeToolId: string | null;
  openSubTabs: string[];
  activeSubTabId: string | null;
  showingCatalog: boolean;

  // 中间
  messages: Message[];
  attitude: 'doubao' | 'yuesheng' | 'sensei';
  attitudeLocked: boolean;
}
``` |
| 涉及文件 | `src/renderer/stores/ui.store.ts`（新）+ 与 RWR 已完成的 `progress.store.ts` 等协同 |
| DoD | □ Store action 完整覆盖 J-01 组件树的所有交互<br>□ 与现有 store（progress.store / config.store / session.store）集成正常<br>□ 无纯前端循环依赖（R-020） |
| 依据 | V6.2 §J-02；spec §9 |

#### J-03 CSS Modules + Design Tokens

| 属性 | 值 |
|:-----|:-----|
| 前置 | J-01（需组件目录确定后进行） |
| 目标 | 将 V6.2 Shell 的 `:root` 变量移入 `variables.css`；每个组件对应 `.module.css` |
| 涉及文件 | `src/renderer/styles/variables.css`（更新）+ 各组件 `.module.css`（新建） |
| DoD | □ `panel-trans`、`cscroll`、`small-scroll` 等通用类移入全局<br>□ 每个组件有独立的 `.module.css`<br>□ 引用 spec §12.2 新 token（--left-panel-min-w / --input-area-height / --ease-default 等） |
| 依据 | V6.2 §J-03；spec §12 |

#### J-04 IPC 集成层

| 属性 | 值 |
|:-----|:-----|
| 前置 | I-01~I-04（backend gaps filled）、J-02（Zustand Store 就绪） |
| 目标 | 创建 type-safe IPC 调用 hook（`useIpc`），错误处理和 loading 状态，Electron API 类型声明 |
| 涉及文件 | `src/renderer/hooks/useIpc.ts`（新）+ `src/renderer/types/electron.d.ts`（更新）+ 各组件消费 |
| DoD | □ Type-safe IPC 调用（invoke 入参/返回类型正确）<br>□ IPC 错误静默展示错误占位不弹窗（spec §13.5）<br>□ API 定义中骨架屏 loading 状态（≥300ms 触发）<br>□ preload 白名单完整性验证 |
| 依据 | V6.2 §J-04；spec §13.5 + §13.6 |

---

### Phase K：打磨与收尾

> **设计依据**：`.specify/phase-f-shell-v6.2-task-plan.md` §Phase K  
> **前置条件**：Phase J 全部完成（React 组件化 + Store + IPC 集成层）后
>
> **外部参考**：收尾验收需参照 [CYS 同学验收 7 步法](../dev-docs/external-references/CYS同学总结/10.验收规则与标准及流程.txt) 进行证据驱动验收，按"规则审计→目录责任→模块演练→接口示例→框架复用→运行证据包→真源文档归档"流程执行

**DoD**：
- 预览版 V1.0 可运行
- 所有已知占位功能标记为"待实现"
- 构建门禁全绿

#### K-01 交互细节打磨

| 属性 | 值 |
|:-----|:-----|
| 前置 | J 阶段全部完成 |
| 目标 | 动画过渡优化 + 拖动 resize 体验提升 + 空状态展示 |
| 涉及文件 | 各组件 CSS Module + 交互逻辑微调 |
| DoD | □ 三栏收起/展开动画 200ms ease（spec §2.5）<br>□ 工具标签切换 150ms ease<br>□ 空状态覆盖所有面板（spec §7） |
| 依据 | V6.2 §K-01；spec §2.5 + §7 |

#### K-02 已知缺陷修复

| 属性 | 值 |
|:-----|:-----|
| 前置 | K-01 |
| 目标 | 修复 V6.2 基线已知缺陷：tri-fork 卡片不可点击、发送按钮无效、搜索框无功能、[template] 按钮无操作、中间 header [+][⚙] 无操作 |
| 涉及文件 | 各相关组件 |
| DoD | □ 所有已知缺陷已修复或标记<br>□ 与 spec 按钮功能表（§2.4）对齐 |
| 依据 | V6.2 §K-02；spec §2.4 |

#### K-03 性能优化 + 全局验收

| 属性 | 值 |
|:-----|:-----|
| 前置 | K-02 |
| 目标 | 渲染性能优化（`renderAll` → 增量更新）、大数据量列表虚拟滚动、构建门禁全绿 |
| DoD | □ `npm run typecheck` 0 error<br>□ `npm run test` 全绿<br>□ `npm run lint` 0 error / ≤300 warnings<br>□ 教学闭环手动验证通过<br>□ 与 spec §2.1 ASCII 布局图逐像素对齐<br>□ 用户手动验收签字 |
| 依据 | V6.2 §K-03；spec §15 |

---

### 独立任务（可并行/穿插执行）

以下任务与 V6.2 主干无依赖关系，可随时执行或在收尾阶段处理：

#### X-01 外部项目与技术参考研究（覆盖 spec 附录B/C/D）

| 属性 | 值 |
|:-----|:-----|
| 前置 | 无（可随时做，建议穿插在 G/J 阶段） |
| 目标 | 对 spec 附录B/C 列举的全部外部项目进行系统研究，输出可落地模式参考和选型结论 |
| 涉及文件 | `docs/research/`（新建研究报告） |
| 依据 | spec §附录B、§附录C、§附录D |

分四组子任务，按深度层级排列：

**X-01a 代码级：InkOS + OpenWrite**（技术栈最接近，重点研究）

| 维度 | InkOS | OpenWrite |
|:-----|:------|:----------|
| 技术栈 | TypeScript / Node.js / CLI | React 19 + Hono + D1(SQLite) + Drizzle |
| 核心价值 | 10-Agent 流水线 + 7 真相文件 + 33 维审计 | Codex 系统(角色/地点/设定)、项目级 AI 上下文 |
| 研究重点 | 真相文件机制 → 对应月笙 TeachingDecisionLog + TeachingOutcomeLog；审计-修订闭环 → 教学反馈回路；多模型路由 | Codex UI 布局（左侧列表+右侧详情）；AI 上下文感知注入；项目容器字段设计 |
| 输出 | `docs/research/inkos-architecture.md` | `docs/research/openwrite-codex.md` |

**X-01b 架构级：SoloEnt + 91Writing + NovelWriter English**

| 项目 | 技术栈 | 研究重点 | 输出 |
|:-----|:-------|:---------|:-----|
| SoloEnt AI | Next.js (商业闭源) | "故事宪法"明文化状态文件设计；Rules/Workflows/Skills 三层管线 → 对应月笙教学状态机 | `docs/research/soloent-design.md` |
| 91Writing | Vue 3 + Pinia + Vite | 提示词库系统、写作目标管理、模板化世界观 | `docs/research/91writing-features.md` |
| Novel Writer English | npm / CLI | 8 步创作流程（概念→规格→规划→起草→编辑→审查）；13 项写前清单 | `docs/research/novel-writer-workflow.md` |

**X-01c 参考级：CoachGPT + Khan Academy + Class Companion 教学参考**

| 项目 | 类型 | 研究重点 | 输出 |
|:-----|:-----|:---------|:-----|
| CoachGPT (SIGIR'25) | 学术论文 | Scaffolding 支架式教学的 Agent 化实现；不替写原则；分步反馈 | `docs/research/coachgpt-scaffolding.md` |
| Khan Academy Writing Coach | 商业产品 | 高亮反馈+交互修订+多轮草稿；教师面板(进步概览) | `docs/research/khan-academy-feedback.md` |
| Class Companion AI | 商业产品 | Rubric 对齐反馈；迭代修订循环；班级共性弱项分析 | `docs/research/class-companion-rubric.md` |

**X-01d 选型级：React 树组件库对比 + 扩展功能备忘**

| 子项 | 内容 | 输出 |
|:-----|:-----|:-----|
| 库选型 | react-arborist / @kingstack/dnd-tree / MUI X Tree View / react-dnd-treeview / react-accessible-treeview 六库对比 | `docs/research/tree-library-selection.md`（含推荐方案：教学笔记树→react-arborist，技法分类→纯CSS递归组件） |
| 扩展备忘 | 附录D 扩展功能（暗黑模式/节点快照/批量引用/自定义模板/快捷键）记录为 `NOT_NOW` 标签 | 附录D 功能清单写入研究笔记 |

**X-01 整体 DoD**：
- □ X-01a~d 各子任务输出独立研究报告
- □ 每项给出明确结论：`直接采用 / 借鉴思路 / 参考即可 / 不采用`
- □ 决策日志记录关键借鉴决策
- □ 选型结论纳入 V6.2 J 阶段组件实现参考

#### X-02 全局清理与遗留评估（原 E-3）

| 属性 | 值 |
|:-----|:-----|
| 前置 | K-03（全部主任务完成后） |
| 目标 | TypeScript 全局清理（`as` / `ts-ignore`）、旧待定任务决策、V4 评估 |
| 涉及文件 | 全局 |
| DoD | □ 所有 `as` 断言清理（除 DOM API 场景）<br>□ 旧待定任务标记为保留 / 关闭 / 外迁<br>□ 决策日志中有记录 |
| 依据 | R-019、决策日志 |

#### X-03 V4.0 Skill 拆分集成（原 RWR-DEBT-1）

| 属性 | 值 |
|:-----|:-----|
| 前置 | K-03（建议在全局清理阶段处理） |
| 目标 | 重构 Prompt 加载链路让 Skill 文件生效：`prompt-loader.ts` 和 `dynamic-context.service.ts` 读取 `resources/prompts/skills/` 下 5 个 Skill 文件<br><br>**参考**：集成方案可参考 [Skill 场景映射表](../dev-docs/skill-mapping.md) 的项目 Skill 说明和组合模式 |
| 涉及文件 | `resources/prompts/skills/`（5 文件已存在）+ `prompt-loader.ts`（改）+ `dynamic-context.service.ts`（改） |
| DoD | □ Skill 文件被代码读取并生效<br>□ 现有 Prompt 行为不退化<br>□ 单元测试覆盖 |
| 依据 | RWR-DEBT-1 |

---

#### D-01 ~ D-07 第三次全面蒸馏（独立工作流 B：内容蒸馏）

> **独立工作流** — 与 V6.2 主干链（Phases G-K）**完全并行，无任何依赖关系**。属于内容/知识层工作，可随时启动。

**设计依据**：`docs/tasks/TASK-TABLE.md` §方向三（第三次全面蒸馏）  
**背景**：当前诊断/技法/教学库的准确性和覆盖率不足以支撑 S2_GUIDE 和 discoverable 判断。需通过第三次蒸馏（网络搜索 + 交叉验证）来提升诊断精度、技法覆盖率和教学库匹配度。

**DoD**：
- □ 100 条真实写作教学案例/素材入库
- □ 症候-技法映射覆盖率缺口报告
- □ 技法库完备性验证报告（89+ 技法 vs 实战需求）
- □ 教学库动作/训练 vs 学员真实卡点验证报告
- □ 反例库 v3.0 更新
- □ 缺口报告（已覆盖/部分/缺失 三档）

| 编号 | 任务梗概 | 前置 | 优先级 |
|:----:|:---------|:----:|:------:|
| D-01 | 网络写作避雷搜索（100 条素材） | 无 | P1 |
| D-02 | 新手错误 → 症候库映射 + 缺口分析 | D-01 | P1 |
| D-03 | 技法库完备性交叉验证 | D-01 | P1 |
| D-04 | 教学库(动作/训练) vs 学员真实卡点 | D-01 | P1 |
| D-05 | 蒸馏结果 → 反例库 v3.0 + 产品输入 | D-02~D-04 | P2 |
| D-06 | 搜索关键词扩展（签约/审稿/AI检测） | D-01 | P1 |
| D-07 | 缺口报告（已覆盖/部分/缺失 三档） | D-02~D-06 | P1 |

**数据流向**：D-01 → D-02/D-03/D-04 并行 → D-05 → D-07（D-06 与 D-02 并行）
**输出目录**：`resources/distillation-versions/v3.1+/`

---

## 四、依赖图

```
Phase BL ──→ Phase G ─── Phase I ──── Phase H ─── Phase J ─── Phase K
  │              │            │             │            │            │
  BL-01          G-01         I-01          H-01         J-01         K-01
  BL-02          │            │             │            │            │
  BL-03          G-02         I-02 (独立)   H-02         J-02         K-02
  BL-04          │            │             │            │            │
  BL-05          G-03         I-03          H-03         J-03         K-03
                 │            │             │            │            │
                 G-04         I-04 (独立)   H-04         J-04
                 │            │
                 G-05         I-05 (安全)
                              │
                              I-06 (安全)
                              │
                              I-07 ──→ H-03
                              │
                              I-08 ──→ H-04
                      独立任务（可并行）：
                      X-01a~d 外部项目与技术参考研究（附录B/C/D）
                      X-02 全局清理（依赖 K-03）
                      X-03 V4.0 Skill 拆分（依赖 K-03）

                      独立工作流 B（完全并行）：
                      D-01~D-07 第三次全面蒸馏
```

### 执行顺序说明

| 顺序 | 阶段 | 理由 |
|:----:|:-----|:------|
| **0th** | Phase BL | 代码基线修复 — 清除门禁阻塞，建立干净基线，再开始交互开发 |
| **1st** | Phase G | V6.2 Shell 交互填充 — 依赖 BL 完成（门禁通过后） |
| **2nd** | Phase I | 后端缺口填补 — `training:catalog` handler 最紧迫；含新增 I-07 (growth:getTrends) + I-08 (teachingNote:*)；与 G 部分并行 |
| **3rd** | Phase H | 训练模块深实现 — 依赖 G（交互就绪）+ I（数据就绪） |
| **4th** | Phase J | React 迁移 — 依赖 G/H/I（交互和数据均通过 Shell 验证，确保迁移目标明确） |
| **5th** | Phase K | 打磨收尾 — 依赖 J（组件化完成） |
| **并行** | Phase D-CONTENT | 蒸馏工作流（D-01~D-07）— 与前端 G-K 完全独立，随时启动 |
| **随时** | X-01a~d | 外部项目与技术参考研究，可穿插任何阶段 |
| **最后** | X-02 + X-03 | 全局清理和债务消除，依赖全部主任务完成 |

---

## 五、执行纪律

1. **先读规格再动手** — 每个 Phase 开始前，重读 `system-rewrite-spec.md` 对应章节 + `.specify/phase-f-shell-v6.2-task-plan.md` 对应小节
2. **以 V6.2 为准** — 前端实现以 `dev-docs/previews/phase-f-shell-v6.2.html` 为视觉基线，以 `.specify/phase-f-shell-v6.2-task-plan.md` 为任务基线
3. **不跳步** — Phase BL → G → I → H → J → K 按序执行，前置未完成不进入下一阶段
4. **不顺手改无关文件** — R-021 约束
5. **交付前跑门禁** — `npm run typecheck && npm run test && npm run lint`
6. **失败回退** — 一个任务超过 2 小时或遇到阻塞，停手问用户
7. **完成标记** — 每个 DoD 项目打 ✅ 后，更新本文档 + TASK-TABLE.md 状态
8. **RWR 前端任务不再执行** — 被 V6.2 推翻的 RWR 前端任务（§二）标记为 🔄 已推翻，不在本文档待执行表中出现
9. **RWR 前端代码可淘金** — J 阶段（React 迁移）和 I 阶段（后端集成）执行前，先检索 RWR 对应前端任务的代码，提取可复用的 TS 逻辑（状态管理、交互逻辑、错误处理模式），并在决策日志中记录"淘金"结果

---

## 六、引用索引

| 引用文件 | 用途 |
|:---------|:-----|
| `.specify/phase-f-shell-v6.2-task-plan.md` | **前端唯一蓝图** — V6.2 Shell 后续建设任务合集 |
| `dev-docs/previews/phase-f-shell-v6.2.html` | **前端视觉基线** — 已审批的完整 HTML 预览 |
| `dev-docs/designs/2026-06-17-system-rewrite-spec.md` | **设计权威来源** — 所有实现以此为准 |
| `docs/tasks/TASK-CHAIN.md` | 全景依赖图 + 历史已完成任务 |
| `docs/tasks/TASK-TABLE.md` | 优先级总表 + 状态追踪 |
| `docs/decision-log.md` | 关键决策历史 |
| `AGENTS.md` | 项目规则入口 |

---

## 七、债务记录

### RWR-DEBT-1: V4.0 Skill 拆分未在代码中集成 → 转入 X-03

- **发现阶段**: C-6 (P1-12)
- **现状**: `resources/prompts/skills/` 下 5 个 Skill 文件已存在但代码不读
- **后续处理**: X-03（全局清理阶段）

### RWR-DEBT-2: 前端实现与 spec 偏差累积 — 已被 V6.2 解决

- **发现阶段**: Phase F 启动评估 — 2026-06-18
- **现状**: RWR Phase F 全部推翻，V6.2 Shell 为全新实现
- **后续处理**: 无需额外处理。V6.2 Phase J（React 迁移）直接从 V6.2 Shell 基线出发

### Backend Gap-1: `training:catalog` Handler 缺失

- **发现阶段**: 2026-06-19 V6.2 后端缺口分析
- **现状**: 合约层已就绪（`training.contract.ts` / `types-training.ts` / `IPC_CHANNELS.TRAINING_CATALOG`），但 `training.handler.ts` 中未注册 handler
- **后续处理**: Phase I-01

### Backend Gap-2: `diagnosis:analyze` 通道不存在

- **发现阶段**: 2026-06-19 V6.2 后端缺口分析
- **现状**: 诊断架构为事件驱动（AI 回复解析后自动推送），非 invoke 模式。需要决策方案。
- **后续处理**: Phase I-03（需用户确认方案）

### Backend Gap-3: `growth:getTrends` Handler 缺失

- **发现阶段**: 2026-06-20 前端 IPC 对接审计
- **现状**: IPC_CHANNELS 常量和 `GrowthGetTrendsRequest`/`GrowthGetTrendsResponse` 合约已定义，`growthTrendService.getGrowthSummary()` 底层服务已就绪，但 **handler 从未注册**。导致 LearningLogWorkspace 无法加载真实成长趋势数据，当前为纯 mock 状态。
- **后续处理**: Phase I-07

### Backend Gap-4: `teachingNote:*` 通道未设计

- **发现阶段**: 2026-06-20 前端 IPC 对接审计
- **现状**: 教学笔记工具（TeachingNoteWorkspace）为纯 mock，[记录到教学笔记] 全链路缺失。无 `teachingNote:record`（保存树节点）和 `teachingNote:getTree`（读取树）通道。无合约、无 handler、无 preload 白名单条目。
- **后续处理**: Phase I-08（需先决策存储方案）

### SEC-DEBT-1: `config:set` 配置写入无白名单 → 高优先级修复

- **发现阶段**: 2026-06-19 IPC 安全审查
- **现状**: `config.handler.ts` 的 CONFIG_SET handler 允许 renderer 修改任意配置键（包括 `apiKey`/`baseUrl`），无键白名单
- **风险**: 受感染 renderer 可覆盖用户 API Key 或劫持配置
- **后续处理**: Phase I（后端集成）期间修复，或紧急独立修补

### SEC-DEBT-2: `teachingState:update` 字段无白名单 → 高优先级修复

- **发现阶段**: 2026-06-19 IPC 安全审查
- **现状**: `teaching-state.handler.ts` 的 TEACHING_STATE_UPDATE handler 使用 `updates: Record<string, unknown>` + `as any` 类型绕过，renderer 可写入任意字段
- **风险**: 受感染 renderer 可打乱教学状态机或注入恶意数据
- **后续处理**: Phase I（后端集成）期间修复，移除 `as any` + 加字段白名单

### SEC-DEBT-3: IPC 三份白名单副本不一致 → 中优先级修复

- **发现阶段**: 2026-06-19 IPC 安全审查
- **现状**: `preload/index.ts`（生效的闸门）、`shared/constants.ts`（ALLOWED_INVOKE_CHANNELS）、`shared/constants.js` 三处白名单内容不完全一致，`constants.ts` 中定义的 56 通道实际不被 preload 引用
- **风险**: 维护时容易产生被遗漏或误加的通道，削弱防御层
- **后续处理**: Phase I（后端集成）期间清理，仅保留 preload 一份事实来源

### SEC-DEBT-4: `training:deriveBehavior` 缺 validatePayload → 低优先级

- **发现阶段**: 2026-06-19 IPC 安全审查
- **现状**: 唯一不调用 validatePayload 的 training handler，缺乏运行时边界防御
- **后续处理**: Phase I-01（实现 `training:catalog` 时一同修复）

### DOC-DEBT-1: 决策日志 8 天未更新 → 中优先级

- **发现阶段**: 2026-06-19 R-018 合规审查
- **现状**: `docs/decision-log.md` 止于 D-022（2026-06-11），连续 8 天无记录；此期间的 V6.2 架构转向、RWR 前端推翻、四方批斗会结论均未记录
- **影响**: 违反 R-018 溯源规范；设计哲学层无正式决策记录
- **后续处理**: 需补充 D-023~D-027（V6.2 决策、RWR 推翻、主干合并、IPC 合约设计等）

### DOC-DEBT-2: 影子功能 4 项无任务文档 → 中优先级

- **发现阶段**: 2026-06-19 R-018 合规审查（TASK-CHAIN.md 自检结果）
- **现状**: PE-004（五步引导链）/ PE-005（约束三明治）/ SF-001（场景元数据面板）/ SF-003/SF-004（节拍诊断）已实现但无任务文档依据
- **后续处理**: 归入 Phase K（打磨收尾）补充文档，或作为独立低优先级任务

### CODE-DEBT-1: 超限文件 7 个 >500 行 → 低优先级（已评估标记）

- **发现阶段**: 2026-06-19 文件大小检查（BL-04）
- **现状**: 4 个测试文件宽限；`chat-orchestrator.service.ts`（618 行→标记 I-02 拆分）；`training.actions.ts`（515 行→标记 J-02 拆分）；`prompt-loader.ts`（511 行→标记 K-03 后清理）
- **后续处理**: 按 Phase 标记在相应阶段拆分

### IDEM-1: IPC 幂等键支持 → 已完成

- **发现阶段**: 2026-06-19, Phase I 完成后的幂等风险评估
- **现状**: **已完成全部两层改造**
  - **层1（createHandler 统一防护）**: `create-handler.ts` 新增 `extractIdempotencyKey()` + LRU 缓存 + TTL 5 秒 + 自动淘汰。请求携带 `idempotencyKey` 在 TTL 内自动去重，无须改任何 handler 业务代码。
  - **层2（前端辅助函数）**: `ipc.ts` 新增 `withIdempotency()` 函数，使用 `crypto.randomUUID()` 自动生成幂等键注入请求参数。
- **使用方式**: `await invoke('training:evaluate', withIdempotency({ trainingId, answer }));`
- **后续处理**: 无需额外处理。各 WRITE-risk store actions 可在后续重构中逐步采用 `withIdempotency()`。

---

## 八、缺口修复（FB20260619-001 契约缺口 + V6.2 额外遗漏）— 全部闭合

> **来源**: FB20260619-001 前后端契约缺口清单 + V6.2 执行复盘  
> **当前指针**: 全部闭合 — 无未完成任务  
> **V6.2 主干链**: Phases BL→G→I→H→J→K 全部通过门禁（typecheck 零错 / 193 测试全绿 / lint 无新增）
>
> **缺口修复最终状态**: 13 个契约缺口 + 6 个额外遗漏 → 9 项已完整修复 ✅、2 项已产品决策 ⏭、3 项已决策暂缓 ⏸
> **最后门禁**: 2026-06-19 — typecheck 零错误, test 193 passed

### 可直接修复（8 项）— 全部 ✅ 已完成

| 任务 | 对应缺口 | 类型 | 优先级 | 状态 | 完成说明 |
|:-----|:---------|:----:|:------:|:----:|:---------|
| **GAP-01** 创建 LearningLogWorkspace | H-03 / G-01 | 新建组件 | P1 | ✅ 已完成 | `right/LearningLogWorkspace/` 已创建，含统计卡片 + 掌握症候 + 进度列表 |
| **GAP-02** 创建 TeachingNoteWorkspace | H-04 | 新建组件 | P1 | ✅ 已完成 | `right/TeachingNoteWorkspace/` 已创建，含诊断摘要 + 训练记录 + 教练建议 |
| **GAP-03** DiagnosisWorkspace 改用 diagnosis:query | G-07 | 修改组件 | P1 | ✅ 已完成 | `fetchLatestDiagnosis()` 挂载时调用 IPC + 订阅 `diagnosis:updated` 事件 |
| **GAP-04** 左右栏拖拽缩放（resize handle） | K-01 | 新功能 | P1 | ✅ 已完成 | AppShell 中 CSS resize + JS mouse drag，min/max 边界约束 |
| **GAP-05** 左栏搜索框组件 | 左栏遗漏 | 新功能 | P2 | ✅ 已完成 | LeftPanel 顶部新增搜索输入框，placeholder 提示 |
| **GAP-06** ToolGrid 卡片集修正为 spec 6 卡 | ToolGrid 偏差 | 修改组件 | P2 | ✅ 已完成 | 6 卡：技法目录/教学进度/学习日志/作品/教学笔记/设置 |
| **GAP-07** teachingState:mastery 白名单补全 | G-12 / SEC-DEBT-3 | 后端修复 | P2 | ✅ 已完成 | constants.ts + event-map.ts 补全白名单映射 |
| **GAP-08** 训练会话短期标记方案 | G-08 | 修改组件 | P2 | ✅ 已完成 | SessionList 用 training:history 反查 + badge 标记 |

### 架构级改造（2 项，已决策暂缓 ⏸）

| 任务 | 对应缺口 | 类型 | 优先级 | 状态 | 说明 |
|:-----|:---------|:----:|:------:|:----:|:-----|
| **GAP-09** 中间栏流式渲染 | G-11 | 架构改造 | P2 | ⏸ 已决策暂缓 | 当前全量拼接可用，不阻塞功能。留作未来 Phase |
| **GAP-10** 虚拟滚动 + 增量更新 | K-03 | 性能优化 | P3 | ⏸ 已决策暂缓 | 当前无性能瓶颈报告。性能优化独立任务 |

### 需产品决策（5 项）— 2 执行/2 跳过/1 待定 ✅

| 任务 | 对应缺口 | 类型 | 优先级 | 状态 | 决策结果 |
|:-----|:---------|:----:|:------:|:----:|:---------|
| **GAP-11** 训练会话创建链路选型 | G-04 | 决策 | P1 | ⏩ 待决策 | — |
| **GAP-12** 态度档位 `sensei` vs `direct` 统一 | G-05 | 决策 | P1 | ✅ 已执行 | 全线统一到 `doubao\|yuesheng\|sensei`，ToneModifiersConfig + dispute-tracker + DEFAULT_TONE_MODIFIERS 同步更新 |
| **GAP-13** 项目三层关系（project→manuscript→chapter） | G-09 | 决策 | P2 | ⏭ 已决策跳过 | 保持平铺，项目模型预留 parentId + type 字段，等 X-01d 树组件选型后再做 |
| **GAP-14** [训练] Tab 归属 | G-10 | 决策 | P2 | ⏭ 已决策跳过 | 不加独立 Tab，训练 badge（蓝色圆角标）已足够区分 |
| **GAP-15** `diagnosis:update` 同名 invoke vs event | G-13 | 决策 | P2 | ✅ 已执行 | 拆分：invoke 保留 `diagnosis:update`，event 改为 `diagnosis:updated`，涉及 13 文件 |

### 完整修复清单（GAP 详情 — 全部完成，保留仅作回溯参考）

#### GAP-01: 创建 LearningLogWorkspace（H-03）

| 属性 | 值 |
|:-----|:-----|
| 问题 | V6.2 Phase H 未完成。学习日志工具被跳过，只创建了 GrowthWorkspace（展示 teaching-state 数据）。但学习日志应展示能力趋势 + 训练统计 |
| 目标 | 在 `right/LearningLogWorkspace/` 新建独立组件，连接 `growth:getTrends` IPC 或 `useProgressStore` |
| 实际完成 | `right/LearningLogWorkspace/index.tsx` + `index.module.css` 已创建：统计卡片（训练总数/完成数/会话数）、已掌握症候列表、按会话分组进度趋势、status chip |
| 门禁 | typecheck ✅ / test 193 ✅ |

#### GAP-02: 创建 TeachingNoteWorkspace（H-04）

| 属性 | 值 |
|:-----|:-----|
| 问题 | V6.2 Phase H 未完成。教学笔记工具从未创建。应展示训练记录列表 + 诊断结果 + 教练建议 |
| 目标 | 在 `right/TeachingNoteWorkspace/` 新建独立组件 |
| 实际完成 | `right/TeachingNoteWorkspace/index.tsx` + `index.module.css` 已创建：诊断摘要区、训练记录按时间倒序列表、教练建议汇总、空状态三档（无诊断/无记录/无建议） |
| 门禁 | typecheck ✅ / test 193 ✅ |

#### GAP-03: DiagnosisWorkspace 改用 IPC（G-07）

| 属性 | 值 |
|:-----|:-----|
| 问题 | DiagnosisWorkspace 从 `useDiagStore.currentDiagnosis` 读取数据，但 store 并不自动调用 `diagnosis:query` IPC |
| 目标 | 挂载时调用 `diagnosis:query({sessionId, limit:1})` 拉取最新诊断；同时订阅 `diagnosis:updated` 事件更新 |
| 实际完成 | `diag.store.fetchLatestDiagnosis()` 挂载 useEffect 时调用；组件监听 `diagnosis:updated` 事件实时更新；三档空状态（无会话/无诊断/有数据） |
| 门禁 | typecheck ✅ / test 193 ✅ |

#### GAP-04: 左右栏拖拽缩放（K-01）

| 属性 | 值 |
|:-----|:-----|
| 问题 | HTML 基线中有 drag resize handle，但 React 迁移时完全丢失 |
| 目标 | 在 AppShell 中添加左右栏 resize handle，支持拖动缩放 |
| 实际完成 | AppShell 中左右各一个 resize handle：CSS `resize` + 方向指示条 + mousedown/mousemove/mouseup 拖动逻辑、min/max 宽度约束 |
| 门禁 | typecheck ✅ / test 193 ✅ |

#### GAP-05: 左栏搜索框

| 属性 | 值 |
|:-----|:-----|
| 问题 | HTML 基线左侧有搜索框占位，React 迁移时从未实现 |
| 目标 | 在 LeftPanel 顶部添加搜索输入框 |
| 实际完成 | LeftPanel 顶部新增搜索输入框，placeholder "搜索会话或项目..."，当前 UI 占位可点击 |
| 门禁 | typecheck ✅ / test 193 ✅ |

#### GAP-06: ToolGrid 卡片修正

| 属性 | 值 |
|:-----|:-----|
| 问题 | 当前 ToolGrid 显示 tab header 的 7 个工具，但 spec 的工具网格是 6 卡 |
| 目标 | 将 ToolGrid 卡片修正为 spec 的 6 卡集 |
| 实际完成 | 6 卡：技法目录/教学进度/学习日志/作品/教学笔记/设置，点击打开对应 workspace |
| 门禁 | typecheck ✅ / test 193 ✅ |

#### GAP-07: teachingState:mastery 白名单（G-12）

| 属性 | 值 |
|:-----|:-----|
| 问题 | `teachingState:mastery` 事件通道在 `ALLOWED_EVENT_CHANNELS` 和 `EventChannelMap` 中均缺失 |
| 目标 | 在 `constants.ts` 和 `event-map.ts` 补全此通道 |
| 实际完成 | constants.ts 已有 `TEACHING_STATE_MASTERY` → event-map.ts 补全白名单映射 |
| 门禁 | typecheck ✅ / test 193 ✅ |

#### GAP-08: 训练会话短期标记（G-08）

| 属性 | 值 |
|:-----|:-----|
| 问题 | 当前无 `kind: 'chat' | 'training'` 字段，无法区分训练会话和普通会话 |
| 目标 | 短期方案：用 `training:history` 返回 recordId 集合反查 |
| 实际完成 | SessionList 加载时调用 `training:history({sessionId})`，无历史记录 → 普通会话 badge，有记录 → 训练会话 badge |
| 门禁 | typecheck ✅ / test 193 ✅ |

#### GAP-09: 中间栏流式渲染（G-11）

| 属性 | 值 |
|:-----|:-----|
| 问题 | React CenterPanel 不支持流式拼接 |
| 决策 | ⏸ 已决策暂缓。当前全量拼接功能可用，不阻塞用户操作。流式渲染作为独立任务留待未来 Phase |
| 来源 | 2026-06-19 用户决策 |

#### GAP-10: 虚拟滚动 + 增量更新（K-03）

| 属性 | 值 |
|:-----|:-----|
| 问题 | 长会话/长工具列表无性能优化 |
| 决策 | ⏸ 已决策暂缓。当前无性能瓶颈报告，留作性能优化独立任务 |
| 来源 | 2026-06-19 用户决策 |

#### GAP-11~15: 决策项执行记录

| 编号 | 缺口 | 决策 | 执行状态 | 说明 |
|:----:|:----:|:-----|:--------:|:-----|
| **GAP-11** | G-04 训练链路 | — | ⏩ 待决策 | — |
| **GAP-12** | G-05 态度档位 | 统一到 `doubao\|yuesheng\|sensei` | ✅ 已执行 | 改 5 文件：ToneModifiersConfig / dispute-tracker / DEFAULT_TONE_MODIFIERS / AttitudeIndicator / tone-modifiers.json |
| **GAP-13** | G-09 项目层级 | 保持平铺，预留字段 | ⏭ 已跳过 | 等项目有三层需求 + 树组件选型 X-01d 后再做 |
| **GAP-14** | G-10 训练Tab | 不加 Tab，训练 badge 足够 | ⏭ 已跳过 | 后续如需筛选，可在列表头加"全部/训练/普通"切换按钮 |
| **GAP-15** | G-13 通道名 | 拆分 invoke/event | ✅ 已执行 | invoke 保留 `diagnosis:update`，event 改为 `diagnosis:updated`，改 13 文件 |

---

## 九、执行纪律

见 §五 执行纪律，保持一致。新增约束：

10. **缺口修复顺序**：可直接修复的 10 项优先执行 → 架构级改造排期 → 需决策项提交用户决策
11. **每项修复完成前跑门禁**：`npm run typecheck && npm run test && npm run lint`
12. **不可顺手修复决策项**：GAP-11~15 在任何其他修复工作中不得连带处理，必须等待用户明确决策

---

## 十、后续优化池（来自 X-01a~c 外部研究）

> **来源**: `docs/reports/FB20260620-001-外部项目研究报告.md`  
> **研究项目**: INKOS + OpenWrite + SoloEnt + 91Writing + NovelWriter + CoachGPT + Khanmigo + Class Companion  
> **创建日期**: 2026-06-20  
> **状态**: 📋 待排期 — 不阻塞 V6.2 主干链（Phases G-K），可随时提入执行

### P0 — 当前阶段必须完成修复（10 项）

| # | 项 | 类型 | 涉及 |
|:--:|:----|:----:|:-----|
| **OPT-01** | 诊断→教学→训练→再诊断闭环验证 | 链路验证 | `teaching-state-machine.ts` → `training-evaluator.ts` → `diagnosis.service.ts` |
| **OPT-02** | 症候锁定→状态推进完整链路 | 功能验证 | `locking.ts` → `reflection-gate.ts` → `severity-utils.ts` |
| **OPT-03** | IPC channel 全覆盖验证（13 handler ↔ 24 store） | 审计修复 | 全部 `.handler.ts` ↔ `.store.ts` |
| **OPT-04** | Right Panel workspaces 可交互性确认 | 功能验证 | `right/workspaces/` → 对应 handler |
| **OPT-05** | 空状态 + 加载态 + 错误态全面覆盖 | UI 补齐 | 全部 panel 组件 |
| **OPT-06** | LLM 回复安全验证层（Khanmigo 设计参考） | 新功能 | `diagnosis-parser.ts` 输出后加规则验证 |
| **OPT-07** | TypeScript 零错误 | 门禁 | `tsc --noEmit` |
| **OPT-08** | Lint 零 error | 门禁 | `eslint --max-warnings 300` |
| **OPT-09** | Vitest 全绿 | 门禁 | `vitest run` |
| **OPT-10** | 循环依赖零容忍 | 门禁 | `madge --circular` |

### P1 — 本阶段高优先级完善（8 项）

| # | 项 | 类型 | 说明 |
|:--:|:----|:----:|:------|
| **OPT-11** | ProjectSettingTree 三栏树集成 + 清理旧树组件 | 改造 | `react-arborist` 已引入，`components_archived/manuscript/` 待清理 |
| **OPT-12** | 三栏收起/展开动画 + 标签切换过渡 | UI 打磨 | LeftPanel/SessionList/CenterPanel/RightPanel 折叠动画 |
| **OPT-13** | 聊天消息分页加载（loadMore） | 功能补齐 | `session.store` 分页加载历史 |
| **OPT-14** | GrowthTrend 图表前端对接 | IPC 连线 | `growth.handler.ts` → `growth` workspace |
| **OPT-15** | TeachingNote 编辑器对接 | IPC 连线 | `teaching-note.handler.ts` → `TeachingNoteWorkspace` |
| **OPT-16** | Training 推荐服务前端集成 | IPC 连线 | `training-recommendation.service.ts` → `training.actions.ts` |
| **OPT-17** | 编辑区自动保存（1.5s debounce + flush） | 功能补齐 | `editor.store.ts` |
| **OPT-18** | Config/AI Provider 设置页面 | 功能补齐 | `config.handler.ts` + `config.store.ts` → 设置 UI |

### P2 — 后续优化（来自外部研究，15 项）

| # | 项 | 来源 | 说明 |
|:--:|:----|:------|:------|
| **OPT-19** | "教学宪法"升级（TeachingDecisionLog → 活文档） | SoloEnt | 宪法与日志分离，运行时可注入 |
| **OPT-20** | 教学质量门禁（37 维度自动审计） | INKOS | 独立的诊断质量审计模块 |
| **OPT-21** | Agent 化教学状态机（诊断/教学/评估拆分） | 91Writing / INKOS | 6 domains → Agent 管线 |
| **OPT-22** | 量化评估指标体系 | Khanmigo | 诊断准确率、用户独立完成率、症候持久度 |
| **OPT-23** | 插件/技能市场架构 | SoloEnt | 引擎层承认局限，生态补充 |
| **OPT-24** | 工具自治模式（输入最小参数 + AI 自动分析） | 91Writing | 降低诊断工具使用门槛 |
| **OPT-25** | Response integrity 检测（反作弊） | Class Companion | 复制粘贴/输入异常检测 |
| **OPT-26** | 申诉机制（学生→AI→教师流程） | Class Companion | 诊断结果异议处理 |
| **OPT-27** | contentCache LRU 容量上限 | NovelWriter | `chapter.store.ts` 优化 |
| **OPT-28** | 纯文本 + SQLite 混合存储 | NovelWriter | 解决文件/DB 双源冲突 |
| **OPT-29** | 内容与元数据分离（真相文件模式） | INKOS | TeachingDecisionLog 结构化 JSON |
| **OPT-30** | A/B 测试框架（参数外置+实验驱动） | Khanmigo | 症候权重/阈值实验 |
| **OPT-31** | 脚手架"微小胜利"反馈 | CoachGPT | 子阶段完成正反馈 |
| **OPT-32** | "不给答案"工程化硬约束 | Khanmigo | 独立验证层 + 安全分类器 |
| **OPT-33** | React 树组件库选型替换（X-01d） | 待完成 | `react-arborist` vs `dnd-kit/sortable` 等
