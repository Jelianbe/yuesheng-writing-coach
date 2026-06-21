# dev-docs 真源索引

> 本文档是 AGENTS.md 引用的"真源索引"。聚合项目所有权威文档的入口,标注真实状态。
> 所有路径均已人工核实(2026-06-20)。标注 ⚠️ 的为已知断链,勿盲目引用。
> 维护规则:新增文档请同步登记本索引;删除/移动文档请更新对应条目(R-008 文档同步准则)。

---

## 一、设计权威(What to build)

| 文档 | 路径 | 状态 | 用途 |
|:---|:---|:---:|:---|
| 系统重构规格 | `designs/2026-06-17-system-rewrite-spec.md` | ✅ | **设计权威来源** — 所有实现以此为准(注意:本文档存在内部矛盾,见 §六) |
| 标题栏/右抽屉重设计 | `designs/2026-06-15-titlebar-rightdrawer-redesign.md` | ✅ | V6.2 之前的布局设计,部分已被 spec §2 覆盖 |

## 二、前端视觉基线(What it looks like)

`previews/` 下是 HTML 设计稿迭代史,**最新的不一定是最终采用的**:

| 版本 | 行数 | 状态 | 备注 |
|:---|:---:|:---:|:---|
| `phase-f-shell-v6.2.html` | 1276 | ✅ **当前基线(权威)** | RWR-MASTER-CHAIN 指定的前端基线;契约对齐见 reports/FB20260619-001 |
| `phase-f-shell-v7.html` | 440 | ❌ 尝试失败 | 精简探索方向,放弃 |
| `phase-f-shell-v8.html` | 935 | ❌ 尝试失败 | 使用 Design Tokens V2.0(`--accent:#A07030`),配色偏离基线,未被采纳 |
| v6 / v6.1 / v1~v5 | — | 📦 历史 | 早期迭代,仅留作参考 |

## 三、任务链(What to do, in what order)

| 文档 | 路径 | 状态 | 用途 |
|:---|:---|:---:|:---|
| **RWR 主链(权威)** | `../docs/tasks/RWR-MASTER-CHAIN.md` | ✅ | **当前任务权威** — Phase BL→G→I→H→J→K 全链 |
| 任务总表 | `../docs/tasks/TASK-TABLE.md` | ✅ | 优先级总表 + 状态追踪 |
| 全景依赖图 | `../docs/tasks/TASK-CHAIN.md` | ✅ | 历史已完成任务 + 依赖图 |
| 重写任务明细 | `../docs/tasks/REWRITE-TASK-DETAILS.md` | ⚠️ | RWR 前端任务明细,**已被 V6.2 推翻**,仅历史参考 |
| 蒸馏任务 | `../docs/tasks/D-DISTILLATION-PROMPT.md` | ✅ | 第三次全面蒸馏工作流(D-01~D-07) |

## 四、规格与立项(Why we build it this way)

| 文档 | 路径 | 状态 | 用途 |
|:---|:---|:---:|:---|
| 项目简报 | `../.specify/project-brief.md` | ✅ | 项目立项背景与目标 |
| 宪法规则 | `../.specify/constitution.md` | ✅ | 立项层不可妥协原则 |
| 工作流指南 | `../.specify/WORKFLOW-GUIDE.md` | ✅ | 立项→实施工作流 |
| **V6.2 任务计划(权威)** | `../.specify/phase-f-shell-v6.2-task-plan.md` | ✅ | **前端唯一蓝图** — Phases G-K 任务合集 |

## 五、规则体系(How we behave)

| 文档 | 路径 | 状态 | 用途 |
|:---|:---|:---:|:---|
| AGENTS.md(AI 入口) | `../../AGENTS.md` | ✅ | AI 工具接入第一站 |
| 规则汇总 | `../../.trae/rules/月笙项目开发规则汇总.md` | ✅ | 全部 26 条活跃规则清单 |
| 单条规则 | `../../.trae/rules/R-XXX-*.md` | ✅ | 30 条 R-001~R-030 文件 |
| 项目专有纪律 | `../.trae/rules/project_rules.md` | ⚠️ 未核实 | AGENTS.md 引用,需确认存在 |
| Skill 场景映射 | `skill-mapping.md` | ✅ | 场景→Skill 导航表 |

## 六、已知文档债务(⚠️ 断链与矛盾)

以下条目**已被 AGENTS.md 或任务链引用,但实际不存在或内容自相矛盾**。引用前请核实:

| 问题 | 详情 | 处置 |
|:---|:---|:---|
| ⚠️ **本索引此前不存在** | AGENTS.md 反复引用 `dev-docs/README.md` 作为真源索引,但文件缺失 | **本文档即为补全** |
| ⚠️ `dev-docs/adapters/` 目录不存在 | AGENTS.md 规则索引表引用 `dev-docs/adapters/README.md`(适配器层规范),但目录不存在 | 需补建或从 AGENTS.md 移除引用 |
| ⚠️ spec 内部矛盾 1:态度档位 | §4.4/§8.2 用 `'gentle\|balanced\|direct'`,§5.2 UI 用 `doubao/yuesheng/sensei`;后端契约用 `direct`,新 ui.store 用 `sensei` | 见 reports/FB20260619-001 G-05,待统一 |
| ⚠️ spec 内部矛盾 2:training:createSession | §6.3 引用此 IPC,但 §10.1 清单和 training.contract.ts 均无此通道 | 见 reports/FB20260619-001 G-04 |
| ⚠️ DOC-DEBT-1 决策日志断档 | `docs/decision-log.md` 止于 D-022(2026-06-11),连续多日无记录;V6.2 转向等重大决策未入册 | 需补 D-023+ |

## 七、分析报告(诊断与决策依据)

`../docs/reports/` 下的诊断报告(按时间倒序):

| 报告 | 内容 |
|:---|:---|
| `FB20260619-004-淘金清单与缝合方案.md` | **archived 代码评估 + 最小可运行缝合方案**(当前执行依据) |
| `FB20260619-003-产品形态重定义-分层教学软件.md` | 分层架构定义(新手层/进阶层,后续迭代目标) |
| `FB20260619-002-教学设计偏差对照.md` | V6.2 样板 vs spec §4 的 6 处教学偏差 |
| `FB20260619-001-前后端契约缺口清单.md` | 13 处契约缺口(P0/P1/P2 分级) |
| `FB20260617-016-报告.md` | RWR 误重置事件报告(6/17 事故记录) |
| `daily-health/scan_*.json` | 每日健康扫描(typecheck/lint/size/circular) |

## 八、外部参考

| 文档 | 路径 | 用途 |
|:---|:---|:---|
| 外部参考索引 | `external-references/README.md` | CYS 同学总结 11 篇,Phase I/J/K 执行前阅读 |

## 九、产品哲学速查

- **教练定位**:不替写、不替决定、找根因
- **态度档位**:豆包(默认)/ 月笙如歌 / sensei(待统一用词,见 §六)
- **安全词**:"轻一点"无条件降档
- **详细规则**:`../resources/prompts/yuesheng-prompt-v3.md`(注意:AGENTS.md 引用的是 v4.0.0,但实际文件是 v3)

---

## 十、工程债务清单：V6.2 模板 vs 真实前端

> **核心问题**：当前 `src/renderer/components/` 的前端代码是通过"套改"V6.2 HTML 设计稿拼凑而成，
> **没有以后端真实 IPC 通道和 data contract 为起点**。导致大量 mock 数据、硬编码、假 IPC 调用的残留。
> 后端（IPC handler + store 层）实际上 90% 完整，前端组件层却未能正确消费。
>
> **唯一路线**：以 V6.2 HTML 为**视觉模板**，以后端 IPC contract 为**数据来源**，重写前端组件层。
> 下文列出的所有债务，将在 V6.2 Phases G-K 的重写过程中逐一清除。

### 10.1 V6.2 mock 数据源 vs 后端实现状态

V6.2 HTML 中定义了 **15 个 mock 数据源**，它们的后端实现程度各不相同：

| # | V6.2 mock 数据源 | HTML 行 | 后端 IPC 通道 | 后端 Handler | 契约 | 状态 |
|:-:|:----------------|:-------:|:------------|:------------|:----|:----:|
| 1 | `SESSIONS` | 159 | `session:list` 等 | `session.handler.ts` ✅ | `session.contract.ts` ✅ | **已实现** |
| 2 | `PROJECTS` | 172 | `project:list` 等 | `project.handler.ts` ✅ | `project.contract.ts` ✅ | **已实现** |
| 3 | `TECHNIQUE_CATALOG` | 193 | `training:catalog` | `training.handler.ts` ✅ | `training.contract.ts` ✅ | **已实现** |
| 4 | `TEACHING_STATE` | 245 | `teachingState:get` 等 | `teaching-state.handler.ts` ✅ | `teaching-state.contract.ts` ✅ | **已实现** |
| 5 | `SESSION_MESSAGES` | 260 | `session:getMessages` | `session.handler.ts` ✅ | `session.contract.ts` ✅ | **已实现** |
| 6 | `CURRENT_DIAGNOSIS` | 317 | `diagnosis:query` | `diagnosis.handler.ts` ⚠️ | `diagnosis.contract.ts` ✅ | **已实现(返回格式有差异)** |
| 7 | `ABILITY_PROFILE` | 329 | `ability:getProfile` | `ability-profile.handler.ts` ✅ | `ability.contract.ts` ✅ | **已实现** |
| 8 | `LEARNING_LOG` | 343 | `growth:getTrends` | `growth.handler.ts` ✅ | `growth.contract.ts` ⚠️ | **后端有数据，格式完全不兼容** |
| 9 | `CHAPTER_CONTENT` | 355 | `chapter:get/list` | `manuscript.handler.ts` ⚠️ | `manuscript.contract.ts` ⚠️ | **数据模型错位(见 10.2)** |
| 10 | `教学笔记树` | 1246 | `teachingNote:*` | `teaching-note.handler.ts` ✅ | `teaching-note.contract.ts` ✅ | **已实现** |
| 11 | `ALL_TOOLS` | 536 | — | — | — | 前端工具配置，无需 IPC |
| 12 | `TRAINING_CONTEXTS` | 546 | — | — | — | 前端运行时状态 |
| 13 | `TRAINING_DIALOGUES` | 551 | — | — | — | 纯 mock，需删除 |

**关键发现**：15 个数据源中，**9 个后端已完整实现**，仅 2 个有结构性问题（#8 LEARNING_LOG 格式不兼容、#9 CHAPTER_CONTENT 模型错位），3 个是纯前端配置。

### 10.2 前后端数据模型错位(高优修复)

| 问题 | V6.2 假设 | 后端现实 | 影响 |
|:----|:----------|:---------|:-----|
| **项目-章节关联缺失** | project 直接拥有 `content` 字段 | project/manuscript/chapter 是三级独立体系 | 作品面板无法通过 projectId 获取章节内容 |
| **学习日志格式不兼容** | 按日期+类型+备注的日志条目 | 按症候的趋势点(score/instances/direction) | 学习日志 UI 完全无法复用后端数据 |
| **诊断返回格式差异** | `diagnosis:query` 返回 `DiagnosisEntry[]` | 实际返回 `TeachingState.activeProblems` | 诊断面板的数据源受限 |

### 10.3 Mock 数据文件残留(P0 — 阻塞清除)

以下 **4 个文件**位于 `src/renderer/shared/`，被组件直接引用。它们**不应存在**——V6.2 HTML 中的 mock 是设计稿的一部分，不是代码依赖：

| 文件 | 被引用于 | 应替换为 |
|:----|:---------|:---------|
| `shared/mock-projects.ts` | LeftPanel / WorksWorkspace / RightPanel | `project:list` IPC 调用 |
| `shared/chapter-content.data.ts` | WorksWorkspace(fallback) | `chapter:list` + `chapter:get` |
| `shared/technique-catalog.data.ts` | CatalogWorkspace(fallback) | `training:catalog` IPC 调用 |
| `shared/training-dialogues.data.ts` | `useStartTraining` hook | 动态生成的训练对话 |

### 10.4 组件内联 mock 数据(P1 — 重构)

以下组件在代码中直接定义了 mock 数据：

| 组件文件 | mock 内容 | 应替换为 |
|:---------|:---------|:---------|
| `hooks/useStartTraining.ts` | 用 `TRAINING_DIALOGUES` 生成假消息注入 chat store | 走 `training:assign` + 真实流式响应 |
| `center/CenterPanel/index.tsx` | `MOCK_PREVIEW_POINTS` 4 条讨论要点 | `teachingNote:getTree` |
| `right/workspaces/TeachingNoteWorkspace/index.tsx` | 9 条硬编码会话 + 1 条完整诊断 | `session:list` + `diagnosis:query` |
| `right/workspaces/LearningLogWorkspace/index.tsx` | `MOCK_LEARNING_LOG` + statCards fallback | `growth:getTrends`(需改造数据格式) |

### 10.5 硬编码颜色(P2 — 批量修复)

- **14 个** `*.module.css` 文件共约 **200+ 处**硬编码十六进制颜色
- **10 个**组件 TSX 文件中共约 **20+ 处**内联颜色
- `variables.css` 已定义完整的 `--accent` / `--text-primary` / `--error` / `--border` / `--success` / `--warning` 等设计 token 体系，但未被使用

唯一的正面案例：`ProgressWorkspace/index.module.css` 少量使用了 `var(--accent)`。
**所有 CSS 的 token 化应作为 V6.2 J-02（Store + Tokens 阶段）的配套任务**，不单独开阶段。

### 10.6 重置方向

基于以上评估，前端重写的正确顺序是：

1. **以 V6.2 HTML 为视觉模板**（不是代码依赖，是视觉参考）
2. **以后端 IPC contract 为数据来源**（`src/shared/api-contracts/*.contract.ts` 是权威）
3. **复用 store 层**（23 个 store 全部完整，无需重写）
4. **活用 archived 组件**（`components_archived/layout/` / `training/` 可直接复活，仅需换 CSS 皮肤）
5. **清除 mock 文件**——shared/ 下 4 个文件在组件重写完成后删除

详细执行路径见 RWR-MASTER-CHAIN.md Phase BL→G→I→H→J→K。

---

**最后更新**:2026-06-20 — 初版补全(修复 AGENTS.md 引用的真源索引缺失;增加工程债务清单 §十)
**维护者**:ZCode | **关联规则**:R-008(文档同步)、R-018(变更溯源)、R-024(AGENTS.md 机制)
