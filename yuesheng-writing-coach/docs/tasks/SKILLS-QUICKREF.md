# SKILLS-QUICKREF 技能速查表

> **最后更新**: 2026-06-09
> **版本**: V1.0
> **用途**: 统一索引项目所有可用 AI Agent Skills，按类别组织，标注触发场景和关联任务

---

## 总览

| 类别 | 数量 | 说明 |
|------|:----:|------|
| A. 前端 UI / 设计 | 9 | Trae 内置设计技能 |
| B. 工程实践 | 8 | 测试/调试/重构/TDD |
| C. 写作 / 教学（核心） | 5 | 写作链路核心技能 |
| D. 数据库 / 架构 | 2 | SQLite/状态管理/架构 |
| E. Electron / 桌面 | 1 | 桌面应用测试 |
| F. 测试 / QA | 3 | 质量保障流程 |
| G. 工作流 / 元技能 | 9 | brainstorming/skill-creator/find-skills 等 |
| H. **项目专属（新增）** | **3** | **coach-output-validator / yuesheng-dev-practices / prompt-ab-tester** |
| **总计** | **40** | |

---

## H. 项目专属 Skills（2026-06-09 新增）

> 这 3 个 Skill 是基于月笙写作教练项目的实际架构和规则体系**自建**的专用技能。它们不是通用工具，而是将项目特有的约束和最佳实践固化为可被 AI 自动加载的操作指南。

### H1. 教练 AI 质量保障

| Skill 名称 | 文件路径 | 触发场景 | 核心能力 | 关联规则 |
|-----------|---------|---------|---------|---------|
| **coach-output-validator** | `.trae/skills/coach-output-validator/SKILL.md` | 每次 AI 回复生成后；修改 Prompt 时；审查诊断/训练逻辑时 | 8 条合规校验（V-01~V-08）：替写检测/决策句式/编号泄露/语气漂移/段落数/建议数/安全词降档/引用格式 | R-025, R-009, R-030 |
| **prompt-ab-tester** | `.trae/skills/prompt-ab-tester/SKILL.md` | 修改 System Prompt 后；调整态度档位后；新增症候/动作后 | 5 维评估框架：教练定位(30%)+诊断准确(25%)+可操作性(20%)+自然度(15%)+Token效率(10%)；含 Golden Dataset 设计 + 对比报告模板 | blind-test-plan.md, coach-output-validator |

### H2. 开发规范聚合

| Skill 名称 | 文件路径 | 触发场景 | 核心能力 | 关联规则 |
|-----------|---------|---------|---------|---------|
| **yuesheng-dev-practices** | `.trae/skills/yuesheng-dev-practices/SKILL.md` | 编写任何代码前；代码审查时；重构决策时 | 8 条规则精华 → 三阶段检查清单（编码前/中/后）；命令速查表；反模式速查 | R-019, R-028, R-007, R-010, R-029, R-014, R-020 |

### 使用指南：何时调用哪个

| 你想做... | 调用 Skill | 备注 |
|-----------|-----------|------|
| 检查 AI 回复是否违规 | `coach-output-validator` | 自动跑 8 条规则，输出 ValidationResult |
| 验证 Prompt 修改效果 | `prompt-ab-tester` | 准备 5 条测试输入，按 5 维评分对比 |
| 开始写新代码 | `yuesheng-dev-practices` | 先过一遍 Phase 1 检查清单再动手 |
| 审查别人的 PR | `yuesheng-dev-practices` + `coach-output-validator` | 开发规范 + 输出质量双重检查 |
| 建立新的 Golden Dataset | `prompt-ab-tester` T-01~T-05 模板 | 最小可行集 5 条，扩展集 10 条 |

---

## A-G 类别速查（完整列表见 TASK-CHAIN.md §六）

### A. 前端 UI / 设计 (9)

design-spell, frontend-design, figma, imagegen-frontend-web, image-to-code, impeccable, high-end-visual-design, gpt-taste, web-dev

### B. 工程实践 (8)

tdd, qa, systematic-debugging, react-component-generator, design-analyze-refactor, prototype, setup-matt-pocock-skills, tsup-config

### C. 写作 / 教学 (5)

teach, writing-fragments, beats, shape, ubiquitous-language

### D. 数据库 / 架构 (2)

database-administrator, architecture-review-expert

### E. Electron / 桌面 (1)

desktop-app-testing (qaskills)

### F. 测试 / QA (3)

test-automation-expert, playwright-e2e, accessibility-auditor

### G. 工作流 / 元技能 (9)

brainstorming, skill-creator, find-skills, subagent-driven-development, writing-plans, to-prd, full-output-enforcement, TRAE-code-review, TRAE-security-review

---

## 变更记录

| 版本 | 日期 | 变更内容 |
|:----:|------|---------|
| V1.0 | 2026-06-09 | 初始版本：创建 SKILLS-QUICKREF.md；新增 H 类「项目专属 Skills」（3 个自建 Skill）|
