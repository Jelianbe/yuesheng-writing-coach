# 技能引用矩阵（完整 51 个 Skill 索引）

> **来源文件**: [TASK-CHAIN.md](TASK-CHAIN.md) §五 技能引用矩阵（拆出）
> **最后更新**: 2026-06-08
>
> **目的**: 统一管理项目可用 AI Agent Skills，按类别索引、标注关联任务、记录安装状态。后续所有开发任务应优先引用本章节中的 Skill，确保方法论一致性和代码质量。

### 总览

| 类别 | 已安装 | 推荐补充 | 合计 |
|------|:------:|:--------:|:----:|
| **前端 UI / 设计** | 9 | 3 | 12 |
| **工程实践** | 8 | 4 | 12 |
| **写作 / 教学（核心）** | 5 | 2 | 7 |
| **数据库 / 架构** | 2 | 3 | 5 |
| **Electron / 桌面** | 0 | 2 | 2 |
| **测试 / QA** | 1 | 4 | 5 |
| **工作流 / 元技能** | 6 | 2 | 8 |
| **总计** | **31** | **20** | **51** |

---

### A. 前端 UI / 设计类（已安装 9 个）

#### A1. 内置设计 Skills（Trae CN 原生）

| Skill 名称 | 来源 | 安装状态 | 关联任务 | 用途说明 |
|------------|:----:|:--------:|----------|----------|
| **design-spell** | Trae 内置 | ✅ 已有 | V2 全系列 | 前端组件/页面快速生成，React + Tailwind CSS |
| **frontend-design** | Trae 内置 | ✅ 已有 | V2-001~V2-006 | 高质量前端界面，避免 AI 美学模板化 |
| **figma** | Trae 内置 | ✅ 已有 | UI 设计稿→代码实现 | Figma 节点转生产代码 |
| **imagegen-frontend-web** | Trae 内置 | ✅ 已有 | V2 视觉设计参考 | 按区域生成网站设计参考图 |
| **image-to-code** | Trae 内置 | ✅ 已有 | 高保真还原设计稿 | 图片→HTML/CSS/React |
| **impeccable** | Trae 内置 | ✅ 已有 | UI 审查/打磨 | 全面 UI 审查：UX/可访问性/响应式/动画 |
| **high-end-visual-design** | Trae 内置 | ✅ 已有 | 高端视觉风格指导 | 字体/间距/阴影/卡片结构规范 |
| **gpt-taste** | Trae 内置 | ✅ 已有 | GSAP 动画+排版 | 驱动随机化布局、AIDA 页面结构、GSAP ScrollTrigger |
| **web-dev** | Trae 内置 | ✅ 已有 | 新页面从零构建 | 完整 Web 界面（仅在空项目时使用）|

#### A2. 推荐补充

| Skill 名称 | 来源 | 安装命令 | 推荐理由 |
|------------|:----:|----------|----------|
| **react-component-generator** | smallnest/langgraphgo | `npx playbooks add skill smallnest/langgraphgo --skill react-component-generator` | React + TS + Tailwind + Zustand 组件模板库，直接对齐我们技术栈 |
| **design-taste-frontend** | obra/superpowers | `npx skills add obra/superpowers --skill design-taste-frontend` | 反模板化审美，审查现有界面并升级为高级感 |
| **taste-skill (v1)** | obra/superpowers | `npx skills add obra/superpowers --skill design-taste-frontend-v1` | v1 风格保留，用于特定向后兼容场景 |

---

### B. 工程实践类（已安装 8 个）

#### B1. mattpocock 工程核心

| Skill 名称 | 来源 | 安装状态 | 关联任务 | 用途说明 |
|------------|:----:|:--------:|----------|----------|
| **diagnose** | mattpocock/skills | ✅ 已安装 | DB-P0, V2-Bug 修复 | 纪律化诊断循环：硬 bug → 性能 → 架构债务 |
| **improve-codebase-architecture** | mattpocock/skills | ✅ 已安装 | DB-REFACTOR 全系列 | DDD 原则驱动的架构深化，依赖领域语言 |
| **tdd** | mattpocock/skills | ✅ 已安装 | R-013 测试覆盖率 | 红-绿-重构循环，垂直切片驱动 |
| **triage** | mattpocock/skills | ✅ 已安装 | Issue 分流 | Bug/Enhancement × 5 种状态机分流 |
| **review** | mattpocock/skills | ✅ 已安装 | V2-024~027 审查关卡 | 代码审查流程规范 |
| **qa** | mattpocock/skills | ✅ 已安装 | CI/CD 质量保障 | 质量保障全流程 |
| **zoom-out** | mattpocock/skills | ✅ 已安装 | 架构评审 | 从细节跳出来看全局架构视角 |
| **to-prd** | mattpocock/skills | ✅ 已安装 | 需求→PRD | 当前对话综合为 PRD 文档 |

#### B2. 推荐补充

| Skill 名称 | 来源 | 安装命令 | 推荐理由 |
|------------|:----:|----------|----------|
| **systematic-debugging** | obra/superpowers | `npx skills add obra/superpowers --skill systematic-debugging` | 假设驱动调试循环：观察→假设→测试→验证 |
| **writing-plans** | obra/superpowers | ✅ Trae 内置已有 | 复杂任务的结构化实施计划 |
| **requesting-code-review** | obra/superpowers | `npx skills add obra/superpowers --skill requesting-code-review` | 提交前自审+测试覆盖+PR 描述准备 |
| **verification-before-completion** | obra/superpowers | `npx skills add obra/superpowers --skill verification-before-completion` | 强制完成前验证通过，防止半成品提交 |

---

### C. 写作 / 教学类（核心业务关联，已安装 5 个）

> ⭐ **这是月笙写作教练项目的核心差异化能力来源。**

| Skill 名称 | 来源 | 安装状态 | 关联任务/模块 | 用途说明 |
|------------|:----:|:--------:|---------------|----------|
| **writing-beats** | mattpocock/skills | ✅ 已安装 | P003/P007 症候诊断、训练内容生成 | 叙事节拍分析：将散乱笔记逐 beat 组装为有节奏的叙事文章 |
| **writing-shape** | mattpocock/skills | ✅ 已安装 | 训练系统（Training Agent） | 文章形态塑造：结构、流向、节奏的整体把控 |
| **writing-fragments** | mattpocock/skills | ✅ 已安装 | 诊断引擎（EvidenceRecord 解析） | 文本片段结构分析：识别文本中的独立语义单元 |
| **teach** | mattpocock/skills | ✅ 已安装 | 教学策略路由、State Machine | 教学方法论：如何有效地传授一项认知技能 |
| **ubiquitous-language** | mattpocock/skills | ✅ 已安装 | 类型定义（types.ts）、领域术语统一 | DDD 风格的统一领域语言提取，确保代码与文档术语一致 |

#### C1. 写作 Skills 与教学链路的映射关系

```
用户作品输入
    ↓
[writing-fragments] → 诊断引擎提取文本片段结构（EvidenceRecord）
    ↓
[writing-beats]     → 症候分析识别叙事节拍问题（P003 节奏失衡 / P007 展示而非告知）
    ↓
[teach]             → 教学策略路由选择教学方法
    ↓
[writing-shape]     → 训练任务生成（塑造文章形态）
    ↓
[ubiquitous-language] → 能力画像术语统一（SyndromeId / TrainingType）
```

#### C2. 推荐补充

| Skill 名称 | 来源 | 安装命令 | 推荐理由 |
|------------|:----:|----------|----------|
| **edit-article** | mattpocock/skills | `npx skills add mattpocock/skills --skill edit-article` | 文章编辑优化：重构段落、提升清晰度、收紧 prose |
| **scaffold-exercises** | mattpocock/skills | `npx skills add mattpocock/skills --skill scaffold-exercises` | 练习脚手架：自动生成练习目录（题目/解答/讲解器），直接用于训练任务 |

---

### D. 数据库 / 架构类（已安装 2 个）

| Skill 名称 | 来源 | 安装状态 | 关联任务 | 用途说明 |
|------------|:----:|:--------:|----------|----------|
| **database-schema-design** | aj-geddes/useful-ai-prompts | ❌ 未安装 | DB-REFACTOR 全系列 | 多方言 Schema 设计：PostgreSQL/MySQL/SQLite 适配，规范化+索引策略 |
| **axiom-database-migration** | CharlesWiltgen/Axiom | ❌ 未安装 | DB-P0 迁移安全 | SQLite 安全迁移模式：防数据丢失、FK 约束处理、回滚脚本 |

#### D1. 推荐安装命令

```bash
# 数据库 Schema 设计（支持 SQLite）
npx playbooks add skill aj-geddes/useful-ai-prompts --skill database-schema-design

# SQLite 安全迁移
npx skills add CharlesWiltgen/Axiom/.claude-plugin/plugins/axiom/skills/axiom-database-migration
```

#### D2. 推荐补充

| Skill 名称 | 来源 | 安装命令 | 推荐理由 |
|------------|:----:|----------|----------|
| **db-designer** | timequity/vibe-coder | `npx add-skill https://github.com/timequity/vibe-coder/tree/main/skills/db-designer` | 从功能描述推断 Schema，用户无需写 SQL |
| **drizzle-migrations** | erichowens/some_claude_skills | 见 lobehub | Drizzle ORM + SQLite 迁移最佳实践（如未来迁移到 Drizzle）|

---

### E. Electron / 桌面类（待安装）

> 我们的项目是 Electron + React + TypeScript 桌面应用，此类 Skills 是基础设施保障。

| Skill 名称 | 来源 | 安装状态 | 关联任务 | 用途说明 |
|------------|:----:|:--------:|----------|----------|
| **electron** | terminal-skills | ❌ 未安装 | IPC 重构、安全加固 | Electron 最佳实践：main/renderer 进程通信、contextIsolation、auto-updates |
| **electron-ipc-security-audit** | a5c-ai/babysitter | ❌ 未安装 | 安全审计 | IPC 安全漏洞系统性审计：输入验证、preload 泄露检测 |

#### E1. 推荐安装命令

```bash
# Electron 开发最佳实践
npx skills-installer add terminal-skills/electron --client shared

# IPC 安全审计
npx playbooks add skill a5c-ai/babysitter --skill electron-ipc-security-audit
```

---

### F. 测试 / QA 类（已安装 1 个）

| Skill 名称 | 来源 | 安装状态 | 关联任务 | 用途说明 |
|------------|:----:|:--------:|----------|----------|
| **TRAE-code-review** | Trae 内置 | ✅ 已有 | PR/MR 审查 | TRAE 专属代码审查：质量/正确性/最佳实践 |
| **TRAE-security-review** | Trae 内置 | ✅ 已有 | 安全扫描 | 代码安全漏洞扫描 |
| **test-automation-expert** | Subagent 内置 | ✅ 可用 | R-013 | 测试自动化策略：E2E/单元/集成/CI-CD |

#### F1. 推荐补充（来自 QASkills 生态）

| Skill 名称 | 来源 | 安装命令 | 覆盖范围 |
|------------|:----:|----------|----------|
| **playwright-e2e** | qaskills | `npx @qaskills/cli add playwright-e2e` | 端到端浏览器测试（Page Object Model）|
| **vitest-patterns** | qaskills | `npx @qaskills/cli add vitest-patterns` | 单元/集成测试（Vitest，我们的测试框架）|
| **accessibility-testing** | qaskills | `npx @qaskills/cli add accessibility-testing` | WCAG 无障碍测试（axe-core）|
| **performance-testing** | qaskills | `npx @qaskills/cli add performance-testing` | 性能测试（k6/Artillery）|

---

### G. 工作流 / 元技能类（已安装 6 个）

| Skill 名称 | 来源 | 安装状态 | 用途说明 |
|------------|:----:|:--------:|----------|
| **brainstorming** | Trae 内置 | ✅ 已有 | 创意工作前的需求探索和设计前置 |
| **skill-creator** | anthropics/skills | ✅ 可用 | 创建新 Skill 的标准流程 |
| **writing-plans** | obra/superpowers | ✅ 已有 | 复杂任务的结构化计划编写 |
| **grill-with-docs** | mattpocock/skills | ✅ 已安装 | 基于文档深度质询决策合理性 |
| **git-guardrails-claude-code** | mattpocock/skills | ✅ 已安装 | Git 危险操作拦截（push --force 等）|
| **handoff** | mattpocock/skills | ✅ 已安装 | 工作交接文档标准化 |
| **caveman** | mattpocock/skills | ✅ 已安装 | 最简实现优先原则 |

#### G1. 推荐补充

| Skill 名称 | 来源 | 安装命令 | 推荐理由 |
|------------|:----:|----------|----------|
| **find-skills** | vercel-labs/skills | `npx skills add vercel-labs/skills --skill find-skills` | 在对话中动态发现和安装新 Skill |
| **subagent-driven-development** | obra/superpowers | `npx skills add obra/superpowers --skill subagent-driven-development` | 编排专业子代理处理不同任务部分 |

---

### H. 使用指南：何时调用哪个 Skill

#### 场景映射表

| 你想做... | 调用 Skill | 备注 |
|-----------|-----------|------|
| 新建/重构一个前端组件 | `design-spell` → `react-component-generator` | 先设计视觉再写代码 |
| 审查/打磨已有 UI | `impeccable` → `design-taste-frontend` | 两轮审查：规范→审美 |
| 修复一个 Bug | `diagnose` → `systematic-debugging` | 先诊断根因再动手修 |
| 改造数据库 Schema | `database-schema-design` → `axiom-database-migration` | 先设计再安全迁移 |
| 生成训练内容 | `writing-beats` → `teach` → `writing-shape` | 三步流水线 |
| 分析用户文本问题 | `writing-fragments` → diagnose | 片段提取→症候匹配 |
| 写 PRD / 任务文档 | `to-prd` → `writing-plans` | 需求→计划的标准链路 |
| 代码审查 / PR | `review` → `TRAE-code-review` → `requesting-code-review` | 三层审查 |
| 审计 IPC 安全 | `electron-ipc-security-audit` | 安全专项 |
| 补充测试覆盖 | `vitest-patterns` → `tdd` | 测试策略→TDD 执行 |
| 项目交接 | `handoff` → `ubiquitous-language` | 交接文档+术语表 |

#### 优先级规则

```
P0 — 必须调用（核心链路）
├── 写作/教学类：writing-beats / teach / writing-shape / writing-fragments
├── 工程核心：diagnose / improve-codebase-architecture / tdd
└── 前端基础：design-spell / frontend-design

P1 — 强烈推荐（质量保障）
├── 审查：review / impeccable / TRAE-code-review
├── 数据库：database-schema-design / axiom-database-migration
├── 测试：vitest-patterns / test-automation-expert
└── Electron：electron / electron-ipc-security-audit

P2 — 按需调用（效率提升）
├── 规划：writing-plans / zoom-out / to-prd
├── 协作：handoff / grill-with-docs / ubiquitous-language
└── 元技能：brainstorming / find-skills / subagent-driven-development
```
