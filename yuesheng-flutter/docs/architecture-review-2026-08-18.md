# 月笙写作教练 · 体系架构梳理（2026-08-18）

> 本文为「架构梳理」只读分析产物，不改任何实现代码。目标：理清现有组件耦合、模块边界，并给出「模块化 / 可替换 / 可扩展」的演进路线。

## 0. 梳理范围与结论摘要

当前「月笙写作教练」由三部分资产构成，它们共同支撑「诊断 → 教学 → 训练 → 素材」的写作教练闭环：

| 资产 | 位置 | 角色 | 状态 |
|:---|:---|:---|:---|
| **Flutter 端** | `yuesheng-flutter/` | 已落地的客户端实现（Riverpod + drift/SQLite） | ✅ 已提交并推送（B-0/A-1/A-2/B-1/A-3） |
| **Electron/React 端** | `yuesheng-writing-coach/` | AGENTS.md 定义的主端（Electron+React18+TS+Zustand+SQLite/Knex） | 规范完整，代码层面未深入对接 |
| **分析处理体系（Agent 知识库）** | `分析处理体系转为Agent提示词/` | 60+ md：PRD、Agent 架构设计、教学动作库、病症识别、训练任务、验证报告 | 语义源（能力定义层） |

**结论**：模块化 / 可替换 / 扩展性**可行**，且已有契约、adapter、强纪律（R-020 循环依赖零容忍、R-019 单文件上限）等良好地基。关键不是「能不能做」，而是「以什么节奏做」——必须契约先行、小步重构，避免为「可替换」而造空中楼阁抽象（参照 A-2 回退 ref_title 死列的教训）。

---

## 1. 当前架构快照

### 1.1 Flutter 端（已实现）

分层（已验证）：

- **services/**：`chat_context_builder`（上下文拼装 + 段落锚点）、`chat_service` / `chat_service_send` / `chat_service_diagnosis`（发送/诊断链路）、`mention_parser`（稳定引用解析）、`genui_parser` / `genui_validator`（GenUI 组件）、`skills_training`、`message_card_service`（卡片分派）。
- **widgets/**：`message_bubble`（markdown 渲染）、`reference_picker`（引用选择）、`gen_ui_card` / `gen_ui_quiz`（GenUI 渲染/判分）、`message_card_dispatcher`（8 类卡片分派）。
- **data/**：`database`（drift 生成代码）+ `repositories`（reference_repository 等）。

已落地能力：B-0 markdown、A-1 素材预算止血、A- 2 稳定 ID 引用、B-1 GenUI v1、A-3 选段段落锚点；全量测试 **1793 passed / 14 skipped / 0 failed**。

### 1.2 Electron/React 端

技术栈（来自 AGENTS.md）：Electron + React18 + TS(strict) + Zustand(persist) + SQLite(better-sqlite3/Knex) + Vite + Vitest；主进程 typed IPC（`domain:action` 通道、常量在 `IPC_CHANNELS`）；有 `adapters/` 规范（React/IPC/Zustand/CSS/Test）与 GStack 七阶段流程。

### 1.3 分析处理体系（Agent 知识库）

这是「诊断 / 教学 / 素材 / 训练」四大能力的**语义源**，以提示词形式沉淀：

- `PRD_月笙写作教练_V1.0.md`、`月笙项目开发框架文档.md`
- `月笙系统_Agent架构设计文档_V0.2.md`（能力架构雏形）
- `月笙_核心原则与教学逻辑`、`月笙_教学动作库`（动作 / 话术）
- `月笙_病症识别手册`（诊断维度）、`月笙_训练任务库`、`月笙_真实案例库`
- `月笙_验证报告_*`（验证阶段产物）

DSH 移植的本质，就是把这套「能力语义」落地为 Flutter 端的可执行组件（诊断→DiagnosisCard、教学→GenUI、引用→mention/reference）。

---

## 2. 耦合点与模块边界

| # | 耦合点 | 现状 | 风险 | 建议 |
|:--|:-------|:-----|:-----|:-----|
| C1 | **service 层直接互引** | `chat_service_send` 等直接依赖 repository / parser | 替换数据源/能力时连带改动多 | 依赖倒置：抽「能力接口」，实现可换 |
| C2 | **跨端重复实现** | Electron（TS）与 Flutter（Dart）两套独立实现，逻辑未共享 | 双端行为漂移、维护翻倍 | 只共享**契约/协议**（如 `[YS_*]` 块、JSON schema），不共享实现 |
| C3 | **全量加载 + N+1** | 解析期全量加载 manuscripts+chapters+files；ReferencePicker 串行 N+1（A-5） | 性能/成本 | 合并查询、按需取窗口 |
| C4 | **语义层 ↔ 实现层漂移** | 分析处理体系（文档）与端实现是「文档↔代码」两层，易失同步 | 能力定义与落地不一致 | 建立映射表 + 文档同步（R-017），关键契约单测覆盖 |
| C5 | **能力未抽离为接口** | 诊断/教学/素材/GenUI 仍是「隐式能力」，无显式接口契约（Flutter 侧仅有 IPC/DB 层契约） | 难以替换/扩展新能力 | 定义「能力契约层」+ 注册表 |

**已有正向基础**：`shared/api-contracts/`、`IPC_CHANNELS`、`adapters/` 规范、DSH 移植的四段式（`[YS_*]` parser+validator+service+widget）本身就是「可插拔模块」的最小原型。

---

## 3. 模块化 / 可替换 / 扩展性方案

**核心原则**：契约先行 → adapter 适配 → 依赖倒置 → 渐进重构。

### 3.1 建议的模块边界（能力契约层）

把「能力」从隐式提升为显式接口，UI 只依赖契约：

```
┌───────────────────────────────┐
│       UI 层（Flutter/Electron） │
└───────────────┬───────────────┘
                │ 依赖（契约）
┌───────────────────────────────┐
│       能力契约层（interface）   │  DiagnosisCapability / TeachingCapability
│        MaterialCapability /    │  GenUiCapability / ReferenceCapability
│        ReferenceCapability      │
└───────────────┬───────────────┘
                │ 实现（可替换）
┌───────────────────────────────┐
│  实现 A：Flutter+Riverpod      │  本地端（drift/SQLite）
│  实现 B：Electron+React        │  主端
│  实现 C：云端/DSH 插件（未来）  │  可热插拔
└───────────────────────────────┘
```

每个能力 = 接口 + 当前实现 + （未来可选实现）。新增能力只需实现接口并注册，UI 经契约消费，无需改动。

### 3.2 扩展点（可扩展）

- **新组件/能力**：实现对应 Capability 接口 + 注册到分派器（类比现有 `message_card_dispatcher`）。
- **跨端复用**：共享 `[YS_*]` 协议块 / JSON schema（已在 GenUI 验证），不共享语言级代码。
- **契约测试**：为每个 Capability 写契约测试，作为「替换实现」的护栏（现有全绿门禁是红利）。

### 3.3 渐进路线（小步）

1. **契约骨架**：抽 4~5 个能力接口（Diagnosis/Teaching/Material/GenUi/Reference），附契约测试，**不改实现**。
2. **样板验证**：挑 C3（N+1）或 C1（素材注入）做首个「依赖倒置」重构，验证范式。
3. **铺开**：按真实需求逐个能力接入，绝不一次性大改。

---

## 4. 风险与纪律

- **过度抽象（最高风险）**：每个接口必须有当前真实需求支撑，遵循 R-010 最小范围、R-021 不私造业务语义。A-2 的 `ref_title` 死列教训即「加戏」反例。
- **双端共享边界**：只共享契约，不共享实现（跨语言共享逻辑成本极高）。
- **重构安全网**：现有 `dart analyze` + `flutter test` 全绿，是做接口抽象的安全红利——每次重构后必须保持门禁绿。
- **文档同步**：能力语义（分析处理体系）与落地代码之间需映射，避免漂移（R-017）。

---

## 5. 下一步（待你确认）

- **选项 A（推荐先做）**：产出「能力契约层」骨架（interface + 契约测试），纯只读/新建，不改实现；顺带一份契约↔实现映射表。
- **选项 B**：先对一个样板（A-5 N+1 或 素材注入）做依赖倒置重构，验证「可替换」范式。
- **选项 C**：仅做「文档↔代码」映射文档，先把语义源与落地对照清楚，暂不碰代码。

选定后即可切换到 Craft 模式执行；在此之前本梳理仅作只读分析。
