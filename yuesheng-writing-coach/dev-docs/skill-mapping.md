# 月笙写作教练 — Skill 场景映射表

> 参考来源：[CYS 同学 Skill 选择纲要](./external-references/CYS同学总结/2.SKILL纲要.txt)
> 本表与 AGENTS.md 配合使用：**AGENTS.md 管规则（什么能做/不能做），本表管流程（什么场景用什么工具）**。

---

## 一、月笙项目常见任务场景映射

| 核心目的 | 典型触发语句 | 推荐 Skill / Agent | 对应流程要点 |
|----------|--------------|--------------------|--------------|
| **需求讨论与方案设计** | "帮我分析一下这个功能怎么做"、"先别写代码，讨论方案" | `brainstorming` | 禁止直接写代码；先理需求、约束、设计取舍，产出设计方向后再动手 |
| **制定执行计划** | "把这个需求拆成开发任务"、"列一个实现步骤" | `writing-plans` | 拆解为可执行可验证的任务序列，明确依赖关系 |
| **代码审查** | "帮我看一下这段代码"、"审查最近的提交" | `TRAE-code-review` → 通用审查<br>`月笙代码审查` → 月笙专有规则审查 | 独立视角检查安全/性能/规范，不修改代码本身 |
| **安全扫描** | "检查一下 IPC 层有没有漏洞"、"安全审查最近的改动" | `TRAE-security-review` | 重点审查 IPC 通道白名单、输入校验、密钥管理 |
| **规则合规检查** | "检查代码是否符合 R-019"、"做一次门禁检查" | `rule-guardian` | 对照项目规则逐项检查代码合规性 |
| **排查 Bug** | "这个功能报错了"、"帮我找出为什么页面卡顿" | `bug-detective` | 复现→缩小范围→根因定位→修复验证，禁止猜测 |
| **编写测试** | "为这个模块写测试"、"增加测试覆盖率" | `test-automation-expert` | 覆盖正常/边界/异常情况 |
| **测试规划** | "规划这个功能的测试用例" | `月笙测试规划` | 按月笙规范规划诊断解析器/状态机/IPC/Store/UI 测试 |
| **文档验证** | "检查文档是否符合规范" | `月笙文档验证` | 检查文档结构/版本/命名/分类符合 R-017 |
| **React 组件开发** | "实现一个左侧面板组件"、"把 Shell 拆成 React 组件" | `react-frontend-developer` | 配合 V6.2 设计规范，参考 Phase J 组件树 |
| **前端 UI/UX 设计** | "设计一个更好的输入区布局"、"美化右侧面板" | `frontend-design` / `design-spell` | 配合 V6.2 Design Tokens，不引入新颜色变量 |
| **架构评审** | "看看这个模块设计是否合理"、"评审后端架构" | `architecture-review-expert` | 以独立视角评审架构决策、模块边界、依赖关系 |
| **性能优化** | "页面加载太慢了"、"优化 IPC 调用性能" | `performance-optimization-engineer` | 先定位瓶颈再优化，禁止盲目重构 |
| **后端架构设计** | "设计这个模块的 IPC 合约"、"设计数据流" | `backend-architect` | 输出 API 端点定义、数据库 schema、服务边界 |
| **模块化重构** | "把单体重构为模块化"、"拆分这个文件" | `modular-refactoring-architect` | 适用于月笙项目 DDD 重构场景 |
| **API 文档编写** | "为这个接口写文档"、"生成 API 参考" | `api-documentation-engineer` | 包含请求/响应示例、类型定义、调用说明 |
| **差异分析** | "看看这次改了什么"、"对比两个版本" | `understand-diff` | 分析 git diff 输出变更影响范围 |
| **环境配置审查** | "检查配置是否有安全隐患"、"审查部署配置" | `config-security-reviewer` | 重点检查密钥泄露、硬编码、白名单缺失 |
| **TypeScript 类型安全** | "修复这个类型错误"、"强化类型约束" | `typescript-expert` | 配合 strict 模式，优先用精确类型而非 `any` |
| **Python 数据处理** | "写一个数据清洗脚本"、"分析训练数据" | `data-scientist` / `python-expert` | 根据任务选择合适 agent |
| **确认完成并交付** | "我做好了，检查一下"、"这个功能算完成了吗？" | 门禁检查（`typecheck + test + lint + check:circular`）+ `rule-guardian` | 强制自证：提供测试步骤、边界覆盖、无新增问题 |
| **全流程工程实施** | "从计划到交付做完这个功能" | 按阶段组合：`brainstorming` → `writing-plans` → 实施（按场景选 Agent）→ 门禁验证 | 架构优先、溯源优先、严格验收 |

---

## 二、月笙专用 Skill 说明

| Skill 名称 | 何时用 | 核心行为 |
|------------|--------|----------|
| `月笙代码审查` | 提交前、PR 合并前、功能完成后 | 检查 TypeScript 类型安全、Electron IPC 规范、Zustand Store 规范、诊断引擎特殊检查 |
| `月笙文档验证` | 创建/更新文档时 | 验证是否符合 R-017：结构/版本控制/命名规范/分类体系 |
| `月笙测试规划` | 功能开发完成后、重构后 | 覆盖诊断解析器、教学状态机、IPC 处理器、Zustand Store、UI 组件 |
| `rule-guardian` | 项目规则检查、合规性验证 | 检查代码是否符合已有规则，改进规则文档，创建新规则 |
| `bug-detective` | 系统化排错 | 遵循复现→缩小→根因→修复流程，禁止猜测式修改 |
| `config-security-reviewer` | 配置/部署审查 | 检查密钥泄露、硬编码、白名单缺失等安全隐患 |

---

## 三、常见组合模式

| 场景 | 推荐组合 |
|:-----|:---------|
| **大功能开发** | `brainstorming` → `writing-plans` → `react-frontend-developer` / `backend-architect` → `月笙测试规划` → `月笙代码审查` → 门禁 |
| **Bug 修复** | `bug-detective` → 修复 → `test-automation-expert`（补充测试）→ 门禁 |
| **代码重构** | `architecture-review-expert`（前置评审）→ `modular-refactoring-architect` → `月笙测试规划` → `月笙代码审查` → 门禁 |
| **安全加固** | `TRAE-security-review`（发现问题）→ 实施修复 → `config-security-reviewer`（验证）→ 门禁 |
| **文档迭代** | `api-documentation-engineer`（API 文档）→ `月笙文档验证`（合规检查） |

---

## 四、使用注意

1. **AGENTS.md 优先**：任何 Skill 的执行不能突破 AGENTS.md 定义的边界和禁区
2. **按需激活**：不是所有 Skill 同时加载，仅在语义匹配时使用对应 Skill
3. **用户可干预**：用户可主动指定 Skill，AI 不得绕过用户意图自由发挥
4. **可组合**：复杂任务可按组合模式使用多个 Skill 顺序协作
5. **本表会随项目演进更新**：新增 Skill 或新场景时同步补充
