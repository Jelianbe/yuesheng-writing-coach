# GStack 工作流 × Kanban 看板

> **版本**: v1.0
> **创建**: 2026-06-21
> **依据**: GStack (Garry Tan) × GitHub Flow × Kanban
> **适用范围**: 月笙写作教练项目开发

---

## 一、核心原则

```
gstack is a process, not a collection of tools.
```

GStack 的核心是**角色驱动**而非流程驱动。每个阶段有明确的角色、职责、门禁和产物。前一个阶段的产物自动传递给下一个阶段。

### 角色边界

| 角色 | 阶段 | 职责 | 禁止 |
|:-----|:-----|:------|:-----|
| **产品（你）** | Think | 定义需求、决定范围、验收 | 不陷入技术细节 |
| **架构师（AI）** | Plan | 锁定架构、数据流、边界条件 | 不替产品做范围决策 |
| **工程师（AI）** | Build | 实现代码、跑门禁 | 不顺手改无关文件 |
| **审查官（AI）** | Review | 找 bug、查安全、核契约 | 不修 bug（修了就没法客观审查） |
| **QA（AI）** | Test | 链路验证、边界测试 | 不改代码 |
| **发布经理（AI）** | Ship | 测试→版本号→changelog→PR | 不讨论产品方向 |
| **复盘官（AI）** | Reflect | 复盘、知识归档、债务记录 | 不新增任务 |

---

## 二、七阶段工作流

```
Think → Plan → Build → Review → Test → Ship → Reflect
```

### Stage 1: Think — 思考与定义

**角色**: 产品（你）
**门槛**: 一个模糊的需求或问题

| 步骤 | 产出 | 工具 |
|:-----|:-----|:------|
| 1.1 定义痛点 | 一句话问题陈述 | 文档/对话 |
| 1.2 界定用户 | 目标用户画像 | 文档/对话 |
| 1.3 验证需求 | 3 个证据/反证 | 搜索/对话 |
| 1.4 定义成功 | 可验证的 DoD | 任务文档 |
| 1.5 最小范围 | 最小的可交付版本 | 任务文档 |

**门禁**: DoD 包含至少 3 条可验证标准（R-004）
**产物**: Issue / 任务卡片（Backlog 列）

### Stage 2: Plan — 计划与架构

**角色**: 架构师（AI）
**门槛**: 有明确的问题陈述和 DoD

| 步骤 | 产出 | 工具 |
|:-----|:-----|:------|
| 2.1 锁定架构 | 涉及文件清单 | 代码搜索 |
| 2.2 数据流 | 数据流向图 | 文档 |
| 2.3 边界条件 | 错误/空/边界处理方案 | 文档 |
| 2.4 测试计划 | 测试矩阵 | 文档 |

**门禁**:
- 涉及文件清单完整
- 无循环依赖（R-020）
- 安全合规（R-029）
- 变更可溯源（R-018）

**产物**: 计划文档 → 任务卡片移入 In Progress 列

### Stage 3: Build — 实现

**角色**: 工程师（AI）
**门槛**: Plan 审批通过

| 步骤 | 规范 | 门禁 |
|:-----|:-----|:------|
| 3.1 实现 | R-019 代码规范 | 单文件 ≤300 行，单函数 ≤50 行 |
| 3.2 安全 | R-029 安全规范 | 零硬编码密钥 |
| 3.3 范围 | R-010 最小化范围 | 只改必要文件 |
| 3.4 防御 | R-028 防御性编码 | 边界处理、空值保护 |
| 3.5 文档 | R-005 逻辑解释 | 复杂逻辑有注释 |
| 3.6 测试 | R-013 测试覆盖 | 新增功能有对应测试 |

**产物**: 代码变更 → `git commit`

### Stage 4: Review — 审查

**角色**: 审查官（AI）
**门槛**: Build 完成，有可审查的代码变更

**审查维度**（R-027 AI 代码质量门禁）:

| 门禁 | 检查项 | 工具 |
|:-----|:--------|:------|
| 道-1 类型 | tsc --noEmit 零错误 | `npm run typecheck` |
| 道-2 测试 | vitest run 全绿 | `npm run test` |
| 道-3 代码风格 | eslint 零 error | `npm run lint` |
| 道-4 安全 | 密钥零硬编码 | R-029 检查清单 |

**审查官禁止**: 修 bug — 只报告，不修改
**产物**: Review Report → 任务卡片移入 QA 列 / 退回 In Progress

### Stage 5: Test — 验证

**角色**: QA（AI）
**门槛**: Review 通过，代码可测试

| 类型 | 内容 | 方法 |
|:-----|:------|:------|
| 链路验证 | 核心业务流程跑通 | 手动验证 + IPC 测试 |
| 边界测试 | 空/异常/边界输入 | 测试用例 |
| 回退验证 | R-006 回退路径可用 | 文档验证 |

**产物**: QA Report → 任务卡片移入 Done 列 / 退回 In Progress

### Stage 6: Ship — 发布

**角色**: 发布经理（AI）
**门槛**: ALL GREEN

| 步骤 | 内容 | 规范 |
|:-----|:------|:------|
| 6.1 分支同步 | rebase main | 无冲突 |
| 6.2 版本号 | semver 规范 | package.json 更新 |
| 6.3 Changelog | 变更摘要 | R-016 格式 |
| 6.4 PR 创建 | 描述 + review 链接 | GitHub |
| 6.5 合并 | squash merge | 保持历史干净 |

**产物**: Merge commit → 任务卡片移入 Ship 列

### Stage 7: Reflect — 复盘

**角色**: 复盘官（AI）
**门槛**: Ship 完成后

| 步骤 | 内容 | 输出 |
|:-----|:------|:------|
| 7.1 复盘 | 哪些做得好、哪些可改进 | 复盘记录 |
| 7.2 债务记录 | 新发现的债务写入 RWR-MASTER-CHAIN.md | 债务条目 |
| 7.3 知识归档 | 有用信息写入 dev-docs | 文档更新 |
| 7.4 决策记录 | 关键决策写入 decision-log.md | 决策日志 |

**产物**: 复盘记录 → 任务卡片移入 Closed 列

---

## 三、Kanban 看板设计

### 列定义

| 列 | 对应 GStack 阶段 | WIP 限制 | 说明 |
|:---|:-----------------|:---------:|:-----|
| **Backlog** | Think | 无 | 想法池，待细化 |
| **To Do** | Plan | 5 | 已定义，待进入 Sprint |
| **In Progress** | Build | 3 | 正在实现 |
| **Review** | Review | 3 | 等待审查 |
| **QA** | Test | 2 | 等待验证 |
| **Ship** | Ship | 1 | 准备发布 |
| **Done** | 已完成 | — | 当期完成 |
| **Closed** | Reflect | — | 已复盘关闭 |

### 卡片模板

```markdown
## 任务卡片

### 元信息
- **ID**: SPRINT-XXX
- **标题**: [类型] 简短描述
- **阶段**: GStack 阶段名
- **优先级**: P0/P1/P2/P3
- **预估**: S/M/L/XL

### 内容
**问题陈述**:
一句话描述要解决的问题。

**DoD**（完成定义）:
- [ ] 条件 1
- [ ] 条件 2
- [ ] 条件 3

**涉及文件**:
- path/to/file1.ts
- path/to/file2.ts

**回退路径**:
如果失败，如何回退。

### 状态追踪
- [ ] Think ✅ — 问题定义完成
- [ ] Plan ✅ — 架构/方案已确认
- [ ] Build ✅ — 代码实现 + 门禁通过
- [ ] Review ✅ — 审查通过，零 P0/P1 问题
- [ ] Test ✅ — 验证通过
- [ ] Ship ✅ — 已合并
- [ ] Reflect ✅ — 已复盘
```

### 标签体系

| 标签 | 含义 |
|:----|:------|
| `bug` | 缺陷修复 |
| `feature` | 新功能 |
| `refactor` | 重构 |
| `security` | 安全修复 |
| `debt` | 技术债务 |
| `documentation` | 文档 |
| `p0` / `p1` / `p2` | 优先级 |
| `sprint-N` | Sprint 归属 |

---

## 四、Sprint 规划

### Sprint 节奏

| 属性 | 值 |
|:-----|:-----|
| 周期 | 滚动式（不固定周数） |
| 规划方式 | 当前 Phase 指针 + 用户优先级 |
| 容量 | ≤3 个 In Progress 卡片 |
| 复盘 | 每 Phase 结束后 |

### Sprint 0（初始化）

**目的**: 建立工作流基础设施

| 卡片 | 内容 | 优先级 | 状态 |
|:-----|:------|:------:|:----:|
| S0-1 | GStack 工作流文档创建 | P0 | ✅ |
| S0-2 | Kanban 看板创建 | P0 | ✅ |
| S0-3 | 首个 Sprint 任务卡片创建 | P0 | ✅ |

### Sprint 1（当前 Phase BL 基线修复 → Phase G 交互填充）

**目的**: 清除门禁阻塞，建立干净基线，进入交互填充

**From RWR-MASTER-CHAIN.md**: Phases BL → G

| 任务 | 类型 | 优先级 | GStack 阶段 |
|:-----|:-----|:------:|:-----------|
| BL-01 修复 tsc 类型错误 | fix | P0 | Plan→Build→Review |
| BL-02 修复空接口类型 | refactor | P0 | Plan→Build→Review |
| BL-03 修复测试环境 | fix | P0 | Build→Test |
| BL-04 超限文件评估 | debt | P1 | Review→Reflect |
| BL-05 硬编码颜色修复 | refactor | P1 | Plan→Build→Review |
| G-01 会话点击联动 | feature | P1 | Think→Plan→Build→Review→Test |
| G-02 训练历史选中 | feature | P1 | Think→Plan→Build→Review→Test |
| G-03 项目章节联动 | feature | P1 | Think→Plan→Build→Review→Test |
| G-04 技法目录子标签展开 | feature | P1 | Think→Plan→Build→Review→Test |
| G-05 右侧工具切换联动 | feature | P1 | Think→Plan→Build→Review→Test |

---

## 五、日常操作流程

### 启动新任务

```
1. 产品（你）在 Backlog 创建 Issue（Think）
2. 产品将 Issue 拖入 To Do + 分配 Sprint 标签
3. 架构师（AI）读取 Issue，确认 Plan（Plan）
4. 你批准 Plan → 卡片移入 In Progress
5. 工程师（AI）实现 + 门禁（Build）
6. 审查官（AI）审查（Review）
7. QA（AI）验证（Test）
8. 发布经理（AI）合并 + 部署（Ship）
9. 复盘官（AI）复盘 → Close（Reflect）
```

### 出错时的处理

| 问题 | 处理 |
|:-----|:------|
| Review 发现 P0 问题 | 卡片退回 In Progress，修复后重新 Review |
| Test 发现失败 | 卡片退回 In Progress，修复后重新经 Review→Test |
| 需求变更 | 暂停当前卡片，新建 Issue，走 Think→Plan 流程 |
| 你喊"停止" | 立即停下，切换咨询模式（R-009） |

---

## 六、与现有体系的关系

| 现有文档 | 与 GStack 的关系 |
|:---------|:----------------|
| RWR-MASTER-CHAIN.md | **任务来源** — Sprint 卡片从此文档提取 |
| .specify/* | **设计依据** — Plan 阶段必须参考 |
| AGENTS.md | **规则入口** — GStack 路由规则在此定义 |
| `.trae/rules/*` | **门禁标准** — Review/Test 阶段以此检查 |
| dev-docs/designs/* | **架构参考** — Plan 阶段必须阅读 |
| .github/workflows/ci.yml | **自动门禁** — Ship 阶段前必须通过 |

### GStack 阶段 ↔ 现有 Phase 对照

| GStack 阶段 | 对应 Phase | 产出 |
|:------------|:-----------|:------|
| Think | — | Issue / 任务卡片 |
| Plan | Phase 开始前 | 方案确认 |
| Build | BL / G / H / I / J / K | 代码变更 |
| Review | Phase 门禁 | Review Report |
| Test | Phase 验收 | QA Report |
| Ship | PR 合并 | 合并提交 |
| Reflect | Phase 结束后 | 复盘 + 债务记录 |

---

## 七、检查清单

### 每天开始

```
□ 检查 Kanban 看板：当前 In Progress 卡片状态
□ 有无阻塞卡片？需要你决策？
□ 今天的目标卡片是哪个？
```

### 每次提交前

```
□ typecheck 零错误？
□ test 全绿？
□ lint 零 error？
□ 密钥零硬编码？（R-029）
□ 只改了必要文件？（R-010）
□ 回退路径清楚？（R-006）
```
