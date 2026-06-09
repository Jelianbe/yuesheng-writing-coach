# 月笙项目 Skill 清单与场景映射

> **版本**: V2.0 | **更新日期**: 2026-06-09 | **来源**: `npx skills list` + `npx @qaskills/cli list` 实际扫描
>
> 本文档是 [R-030 反馈处理工作流](../../.trae/rules/R-030-反馈处理工作流.md) Step 1 的 Skill 关联依据。

---

## 一、总览

| 维度 | 数量 |
|------|------|
| npx skills（`.agents/skills/`） | 33 |
| qaskills（`.trae/rules/`） | 3 |
| **合计** | **36** |

---

## 二、已安装 Skill 完整清单

### 2.1 领域技能（写作教学核心链路）

| Skill 名称 | 安装路径 | 触发场景 | 项目关联 |
|-----------|---------|---------|---------|
| `teach` | `.agents/skills/teach` | 教学内容生成、训练设计 | 教学策略路由、技法库消费 |
| `diagnose` | `.agents/skills/diagnose` | 写作问题识别、症候分析 | 诊断引擎、诊断解析器 |
| `writing-beats` | `.agents/skills/writing-beats` | 写作节拍/节奏分析 | writing-analyzer |
| `writing-fragments` | `.agents/skills/writing-fragments` | 文本片段拆解/重组 | 证据分组、证据服务 |
| `writing-shape` | `.agents/skills/writing-shape` | 文本结构形态判断 | 学生分类器 |
| `edit-article` | `.agents/skills/edit-article` | 文章编辑建议 | M-2 改写功能 |
| `scaffold-exercises` | `.agents/skills/scaffold-exercises` | 练习脚手架生成 | 训练工作坊 |

### 2.2 前端开发

| Skill 名称 | 安装路径 | 触发场景 | 项目关联 |
|-----------|---------|---------|---------|
| `react-component-generator` | `.agents/skills/react-component-generator` | React 组件创建 | UI 组件开发 |
| `design-an-interface` | `.agents/skills/design-an-interface` | 界面设计 | Paradigm A/B UI 改造 |
| `prototype` | `.agents/skills/prototype` | 快速原型验证 | 新交互方案验证 |

### 2.3 数据层

| Skill 名称 | 安装路径 | 触发场景 | 项目关联 |
|-----------|---------|---------|---------|
| `database-schema-design` | `.agents/skills/database-schema-design` | 数据库表结构设计 | SQLite 迁移、新表设计 |

### 2.4 测试与质量保障

| Skill 名称 | 安装路径 | 来源 | 触发场景 | 项目关联 |
|-----------|---------|------|---------|---------|
| `tdd` | `.agents/skills/tdd` | npx | 测试驱动开发 | 38 个测试文件的维护与扩展 |
| `qa` | `.agents/skills/qa` | npx | 质量保障流程 | CI/CD 质量门禁 |
| `systematic-debugging` | `.agents/skills/systematic-debugging` | npx | 系统化调试 | Bug 排查（R-023） |
| `playwright-e2e` | `.trae/rules/playwright-e2e` | qaskills | E2E 测试 | 全流程端到端验证 |
| `desktop-app-testing` | `.trae/rules/desktop-app-testing` | qaskills | Electron 桌面应用测试 | IPC flow / 窗口管理 / 自动更新测试 |
| `accessibility-auditor` | `.trae/rules/accessibility-auditor` | qaskills | WCAG 2.1 AA 无障碍审计 | UI 改造阶段合规检查 |

### 2.5 架构与工程实践

| Skill 名称 | 安装路径 | 触发场景 | 项目关联 |
|-----------|---------|---------|---------|
| `improve-codebase-architecture` | `.agents/skills/improve-codebase-architecture` | 架构改进 | 模块化重构、循环依赖治理(R-020) |
| `request-refactor-plan` | `.agents/skills/request-refactor-plan` | 重构方案规划 | RightDrawer 拆分等重构任务 |
| `subagent-driven-development` | `.agents/skills/subagent-driven-development` | 子代理协作开发 | 复杂多文件改动 |
| `verification-before-completion` | `.agents/skills/verification-before-completion` | 完成前验证 | R-027 代码质量门禁 |
| `zoom-out` | `.agents/skills/zoom-out` | 全局视角审视 | TASK-CHAIN 决策点 |

### 2.6 代码审查与安全

| Skill 名称 | 安装路径 | 触发场景 | 项目关联 |
|-----------|---------|---------|---------|
| `review` | `.agents/skills/review` | 通用代码审查 | PR/MR 审查 |
| `requesting-code-review` | `.agents/skills/requesting-code-review` | 发起审查请求 | R-027 门禁流程 |
| `git-guardrails-claude-code` | `.agents/skills/git-guardrails-claude-code` | Git 规范守护 | R-016 提交规范、R-006 回退机制 |
| `grill-with-docs` | `.agents/skills/grill-with-docs` | 基于文档的深度审查 | R-018 变更溯源、R-008 文档同步 |

### 2.7 项目管理与沟通

| Skill 名称 | 安装路径 | 触发场景 | 项目关联 |
|-----------|---------|---------|---------|
| `handoff` | `.agents/skills/handoff` | 任务交接 | TASK-CHAIN 任务衔接 |
| `to-issues` | `.agents/skills/to-issues` | 问题转 Issue | BUG 跟踪 |
| `to-prd` | `.agents/skills/to-prd` | 需求转 PRD | 功能需求文档化 |
| `triage` | `.agents/skills/triage` | 问题分类与优先级 | 反馈预分类（R-030 Step -1） |
| `ubiquitous-language` | `.agents/skills/ubiquitous-language` | 统一术语体系 | 项目术语一致性 |
| `caveman` | `.agents/skills/caveman` | 最简方案优先 | R-010 最小化范围 |
| `find-skills` | `.agents/skills/find-skills` | 发现适用 skill | 技能检索 |
| `setup-matt-pocock-skills` | `.agents/skills/setup-matt-pocock-skills` | TypeScript 类型体操 | 复杂类型定义 |

### 2.8 通用/综合

| Skill 名称 | 安装路径 | 触发场景 | 项目关联 |
|-----------|---------|---------|---------|
| `vibe-coder` | `.agents/skills/vibe-coder` | 从想法到产品 MVP | 快速原型验证（含 db-designer） |

---

## 三、场景 → Skill 映射速查表

> 用于 R-030 Step 1 的 Skill 关联环节。

| 项目场景 | 推荐 Skill（主→辅） | 备注 |
|---------|-------------------|------|
| **新建 React 组件** | react-component-generator → design-an-interface | 含类型定义、样式、测试 |
| **数据库迁移/改表** | database-schema-design | SQLite 特化，配合项目 migration 目录 |
| **诊断逻辑修改** | diagnose → writing-* (beats/fragments/shape) | 症候引擎核心链路 |
| **教学策略调整** | teach → scaffold-exercises | Router / Strategy 服务 |
| **IPC Handler 开发** | systematic-debugging → verification-before-completion | 入参校验(R-028) + 出参格式 |
| **UI 改造/新界面** | design-an-interface → accessibility-auditor | 必须通过 WCAG AA 检查 |
| **架构重构** | improve-codebase-architecture → request-refactor-plan → zoom-out | 先全局审视再动手 |
| **Bug 排查** | systematic-debugging → triage | 超 15min 记录到 debug-log(R-023) |
| **代码审查** | review → requesting-code-review → grill-with-docs | R-027 四道门禁 |
| **测试编写** | tdd → qa → desktop-app-testing | 单元→集成→Electron专项 |
| **E2E 验证** | playwright-e2e | 全流程冒烟+关键路径 |
| **无障碍检查** | accessibility-auditor | WCAG 2.1 AA + axe-core |
| **Git 操作/回退** | git-guardrails-claude-code | R-006/R-016 合规 |
| **反馈进入工作流** | triage → to-issues → handoff | R-030 Step -1 → Step 0 |
| **变更溯源** | grill-with-docs → zoom-out | R-018 四环追溯 |
| **性能问题** | systematic-debugging → improve-codebase-architecture | 先定位根因再优化 |
| **多文件并行改动** | subagent-driven-development | 大范围重构时使用 |

---

## 四、未覆盖缺口 & 待观察

| 缺口描述 | 优先级 | 说明 | 计划 |
|----------|--------|------|------|
| 前端性能检测 skill | 低 | 当前 Phase V2 收尾，性能非瓶颈 | 需要时安装 `frontend-performance`(qaskills ★84) |
| i18n 国际化 skill | 低 | 项目暂无多语言需求 | 观察中 |
| 原始清单 axiom-database-migration | 不需要 | 面向 iOS/GRDB，与 Node.js/better-sqlite3 栈不匹配 | 不安装 |

---

## 五、变更记录

| 版本 | 日期 | 变更内容 |
|------|------|---------|
| V1.0 | 2026-06-01 | 初版，基于 Task 子代理类型规划（已过时） |
| V2.0 | 2026-06-09 | 重写：基于 `npx skills list` + `@qaskills/cli list` 实际扫描结果；新增 desktop-app-testing + accessibility-auditor；删除过时的子代理类型映射 |
