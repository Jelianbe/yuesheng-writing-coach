# 设计 005 — 提示词逆转 v4 + 教育链路重整

> **版本**: v1.0
> **创建**: 2026-06-23
> **作者**: AI 架构师（Think 阶段）
> **状态**: 待审阅
> **依据**: R-018 变更溯源 / R-021 AI 行为边界 / R-005 全流程文档化 / R-010 最小化范围

---

## 一、背景

### 1.1 问题陈述

项目当前**提示词资产散落严重**，存在两套并存体系：

| 位置 | 性质 | 数量 |
|:-----|:-----|:----:|
| `resources/prompts/` | 老根目录 | 12+ 文件 |
| `resources/03-teaching/prompts/` | 领域组织 | 6+ 文件 |
| `resources/01-diagnosis/` | 领域单文件 | 1 |
| `resources/04-validation/evaluation/` | 领域单文件 | 1 |
| `resources/prompts/skills/` | v4 拆分产物 | 5 |
| `resources/03-teaching/prompts/skills/` | v4 拆分副本 | 5 |
| `.trae/.agents/.claude/.qoder/skills/` | IDE 工具技能 | 数十（重复） |

`teaching-agent-prompt-v2.md` 在老位置与新位置是**完全相同的内容**（已验证）。

`yuesheng-prompt-v3.md` V4.0.0 注释明确写明：

> Change: Skill 工程化 — 拆分为 5 个独立 Skill + 动态组装逻辑
> Rollback: `git checkout prompt/v3.9.0 -- resources/prompts/yuesheng-prompt-v3.md`

**V4 拆分是 2026-06-15 的尝试**，带来运行时复杂度（动态加载 5 个 Skill），用户已判断**该方向不适合本项目**，要求"逆转回来做统一调整"。

### 1.2 业务链路现状

`resources/01-diagnosis/02-prescription/03-teaching/04-validation/05-retro/` 五环职责边界未明：
- 谁做什么、不做什么
- 跳词规则（诊断→训练 跳过处方可以吗）
- 拆书适用度分级（新手 vs 已完成作者）
- 表达欲 / 完成度门槛

外部材料 [网文大家庭(169) 群聊截图提取] 提供 4 个可融合洞察：
1. 表达欲 / 倾诉欲是写书源动力 → `01-diagnosis` user-type 判别
2. "写完一本完整小说"是最低门槛 → `04-validation` 阶段判定
3. 拆书适用度分新手 vs 已完成 → `02-prescription` 训练处方
4. 个人XP / 喜好决定方向 → 教学 Agent "教什么"决策

### 1.3 设计哲学

> **单一真源 + 清晰业务边界 + 持续资源归档**

不追求"完美统一"，追求"每次 Sprint 后状态更收敛"。

---

## 二、目标

| 目标 | 衡量标准 |
|------|----------|
| **G1 单一真源** | yuesheng-prompt 仅 1 个有效版本（v5） |
| **G2 散落收敛** | 同名/同义 prompt 文件去重，2 套并轨为 1 套 |
| **G3 业务清晰** | 5 环职责有 ADR 文档 + 边界单测 |
| **G4 资源规范** | 01-05 domain 文件夹命名一致 + 过期文件清理 |
| **G5 外部融合** | 网文群聊 4 个洞察落到 3 处 + 测试 |

---

## 三、3 个 Sprint 范围

### Sprint 11 — 资产普查（**Sprint 0**：盘点不动业务）

**角色**: 工程师（AI）
**阶段**: Plan → Build → Review
**优先级**: P1
**估时**: S

#### 任务清单

| 编号 | 任务 | 产物 |
|:----:|------|------|
| T0-1 | 全项目 prompt/skill/config 资产清单 | `dev-docs/audits/2026-06-23-prompt-asset-inventory.md` |
| T0-2 | 重复文件标记（hash 一致 + 内容一致） | 同上文件内嵌表格 |
| T0-3 | 命名规范 PR 草案（未执行） | `dev-docs/standards/2026-06-23-prompt-naming-spec.md` |
| T0-4 | 决策日志更新 | `decision-log.md` 新条目 |

#### DoD

- [ ] **D0-1**：100% 资产清单（path / size / version / last_modified / hash / 引用关系）
- [ ] **D0-2**：重复文件列表（hash 匹配 + 内容 diff 验证）
- [ ] **D0-3**：命名规范 PR 草案（不执行，仅文档）
- [ ] **D0-4**：决策日志记录"为什么先普查再动手"
- [ ] **D0-5**：门禁 `typecheck && test && lint` 全绿（无代码改动也应全绿）

#### 涉及文件

- `resources/prompts/**`（只读扫描）
- `resources/01-05/**`（只读扫描）
- `.trae/.agents/.claude/.qoder/skills/**`（只读扫描）

#### 回退路径

无副作用，git revert commit 即可。

#### 风险

| 风险 | 等级 | 缓解 |
|------|:----:|------|
| 扫描脚本误报 | 低 | diff 二次确认 + 人工 spot check |

---

### Sprint 12 — 提示词工程统一（**Sprint N**：v4 逆转 + 去重）

**角色**: 工程师（AI）
**阶段**: Plan → Build → Review → Test
**优先级**: P0
**估时**: L

#### 任务清单

| 编号 | 任务 | 产物 |
|:----:|------|------|
| T12-1 | 5 个 SKILL-*.md 合并 → `resources/prompts/yuesheng-prompt-v5.md` | 新建 v5.md |
| T12-2 | 5 个 SKILL-*.md 归档到 `resources/archive/prompts/skills-v4/` | 移动 + git mv |
| T12-3 | `yuesheng-prompt-v3.md` 归档到 `resources/archive/prompts/yuesheng-prompt-v3.md` | 移动 + git mv |
| T12-4 | 老位置 `resources/prompts/teaching-agent-prompt-v2.md` 等去重 | 取新位置为真源 |
| T12-5 | 子 prompt 引用关系梳理（diagnosis / training-evaluator / onboarding-analysis / behavior-derivation） | 文档化引用图 |
| T12-6 | 引用 v5 的代码点更新（chat-orchestrator / chat-tools 等） | 代码变更 |
| T12-7 | v5 placeholder 回归测试 | 自动化测试 |
| T12-8 | v5 truncation 集成测试 | 自动化测试 |

#### DoD

- [ ] **D12-1**：`yuesheng-prompt-v5.md` 存在，含原 5 个 SKILL 全部内容（IDENTITY/TEACHING/VALIDATION/FEEDBACK/SCENARIO）
- [ ] **D12-2**：5 个 SKILL-*.md 归档到 `archive/prompts/skills-v4/`，原位置不再存在
- [ ] **D12-3**：`prompt-placeholder-style.test.ts` 通过（双花 `{{xxx}}`）
- [ ] **D12-4**：`truncation.test.ts` 通过
- [ ] **D12-5**：`chat-orchestrator.service.ts` 引用 v5 路径生效（集成测试）
- [ ] **D12-6**：老位置 prompt 重复文件已清理（保留新位置为唯一真源）
- [ ] **D12-7**：v3.9 / v4.0 仍可从 git 历史回滚（tag 或分支保留）
- [ ] **D12-8**：R-025 治理：v5 commit 包含版本号 + 变更说明
- [ ] **D12-9**：门禁 `typecheck && test && lint` 全绿

#### 涉及文件

**新增**：
- `resources/prompts/yuesheng-prompt-v5.md`

**移动**：
- `resources/prompts/skills/SKILL-*.md` → `resources/archive/prompts/skills-v4/`
- `resources/03-teaching/prompts/skills/SKILL-*.md` → `resources/archive/prompts/skills-v4/`
- `resources/prompts/yuesheng-prompt-v3.md` → `resources/archive/prompts/`
- `resources/prompts/teaching-agent-prompt-v2.md` → `resources/archive/prompts/`（取新位置为真源）
- `resources/03-teaching/prompts/teaching-agent-prompt-v2.md` 保留

**代码侧**：
- `src/main/domains/03-teaching/chat/chat-orchestrator.service.ts`
- `src/main/domains/03-teaching/chat/chat-tools.ts`
- 其他引用 yuesheng-prompt-v3 路径的位置

**测试**：
- `src/main/domains/03-teaching/prompt/__tests__/prompt-placeholder-style.test.ts`（已存在，需更新）
- `src/main/domains/03-teaching/prompt/__tests__/truncation.test.ts`（已存在）
- 新增：`src/main/domains/03-teaching/prompt/__tests__/v5-integration.test.ts`

#### 回退路径

```bash
# 1. 回滚 Sprint 12 全部 commit
git revert <sprint-12-merge-commit>

# 2. 或从历史恢复
git checkout v3.9.0 -- resources/prompts/yuesheng-prompt-v3.md
```

#### 风险

| 风险 | 等级 | 缓解 |
|------|:----:|------|
| 提示词合并后效果变差 | 中 | 保留 v3/v4 双存档，v5 不删 v3/v4 文件 |
| 代码侧引用路径遗漏 | 中 | T12-5 引用图先于 T12-6 代码改动 |
| 占位符 / 截断回归 | 低 | D12-3/D12-4 强制门禁 |

---

### Sprint 13 — 教育链路重整（**Sprint N+1**：业务 + 资源）

**角色**: 架构师（AI）→ 工程师（AI）
**阶段**: Think → Plan → Build → Review → Test
**优先级**: P1
**估时**: XL

#### 任务清单

| 编号 | 任务 | 产物 |
|:----:|------|------|
| T13-1 | ADR-005 教育链路职责文档 | `dev-docs/designs/adr/005-teaching-chain-responsibility.md` |
| T13-2 | 5 环职责边界重梳 | ADR + 边界单测 |
| T13-3 | 跳词规则定义（诊断→训练 跳过处方的条件） | ADR + 单测 |
| T13-4 | 拆书适用度分级（新手/进阶/老手） | `02-prescription/techniques/technique-selection-matrix.json` 更新 |
| T13-5 | 表达欲/完成度门槛 | `01-diagnosis` user-type-matrix 更新 |
| T13-6 | 网文群聊洞察 1：表达欲分层 → 01-diagnosis | 代码 + 配置 + 测试 |
| T13-7 | 网文群聊洞察 2：完成度门槛 → 04-validation | 代码 + 配置 + 测试 |
| T13-8 | 网文群聊洞察 3：拆书分级 → 02-prescription | 代码 + 配置 + 测试 |
| T13-9 | 网文群聊洞察 4：个人XP 决策 → 教学 Agent | 代码 + 测试 |
| T13-10 | 01-05 资产命名规范落地 | 命名空间收敛 |
| T13-11 | 过期文件清理（v1、草案、bak） | git rm |

#### DoD

- [ ] **D13-1**：ADR-005 已落盘，含 5 环职责矩阵 + 跳词规则 + 拆书分级
- [ ] **D13-2**：5 环边界单测覆盖（每个边界条件至少 1 个测试）
- [ ] **D13-3**：网文群聊 4 个洞察在 3 处融合（user-type / validation / teaching），每处有测试
- [ ] **D13-4**：01-05 文件夹命名一致（lowercase + hyphen + 无缩写歧义）
- [ ] **D13-5**：过期文件清理（v1、草案、bak），git 历史保留
- [ ] **D13-6**：决策日志记录"为什么这样分 5 环"
- [ ] **D13-7**：门禁 `typecheck && test && lint` 全绿

#### 涉及文件

**新增**：
- `dev-docs/designs/adr/005-teaching-chain-responsibility.md`
- `src/main/domains/01-diagnosis/__tests__/responsibility-boundary.test.ts`
- `src/main/domains/02-prescription/__tests__/technique-tier.test.ts`
- `src/main/domains/04-validation/__tests__/completion-threshold.test.ts`
- `src/main/domains/03-teaching/__tests__/personal-xp-decision.test.ts`

**更新**：
- `resources/01-diagnosis/config/user-type-matrix.json`
- `resources/04-validation/mastery/challenge-templates.json`
- `resources/02-prescription/techniques/technique-selection-matrix.json`
- `src/main/domains/01-05/**/*.ts`（业务边界代码）

**清理**：
- `resources/01-05/` 下 v1、草案、bak 文件

#### 回退路径

```bash
# 1. 回滚 Sprint 13 全部 commit
git revert <sprint-13-merge-commit>

# 2. ADR 文档可独立保留（不依赖代码）
```

#### 风险

| 风险 | 等级 | 缓解 |
|------|:----:|------|
| 5 环边界重梳影响范围广 | 中 | Sprint 11 先普查，T13-2 边界单测先于 T13-6/7/8/9 业务代码 |
| 网文群聊洞察误用 | 中 | 群聊洞察只作输入不直接生成规则；T13-6/7/8/9 每处需用户复审 |
| 命名规范变动大 | 低 | Sprint 11 T0-3 先 PR 草案评审 |
| 教学 Agent 个人XP 决策边界模糊 | 中 | T13-9 单测覆盖"对什么样的人不教" |

---

## 四、整体数据流

```
[用户输入]
   ↓
[01-diagnosis]  ←  user-type-matrix（表达欲分层）
   ↓ diagnosis result
[02-prescription]  ←  technique-selection-matrix（拆书分级）
   ↓ training plan
[03-teaching]  ←  yuesheng-prompt-v5（个人XP 决策）
   ↓ training delivery
[04-validation]  ←  challenge-templates（完成度门槛）
   ↓ evaluation result
[05-retro]  ←  case library
   ↓
[持久化] SQLite
```

**5 环职责边界**（待 ADR-005 详化）：

| 环 | 做什么 | 不做什么 |
|:--:|--------|----------|
| 01 诊断 | 找根因 | 不出训练方案 |
| 02 处方 | 给训练 | 不教具体写法 |
| 03 教学 | 教具体 | 不评分 |
| 04 验证 | 评分 | 不教新内容 |
| 05 复盘 | 归档案例 | 不参与主链路 |

**跳词规则**（待 ADR-005 详化）：
- 诊断 → 训练 跳过处方：仅当 diagnostic severity < 3（轻微症状）
- 教学 → 验证 跳过处方：不允许（必须经处方）
- 其他：按 Sprint 13 重梳结果

---

## 五、测试策略

| Sprint | 测试类型 | 范围 |
|:------:|----------|------|
| 11 | 无（只读） | — |
| 12 | 单元 + 集成 | v5 placeholder / truncation / chat-orchestrator 集成 |
| 13 | 单元 + 边界 + 端到端 | 5 环边界 / 网文洞察融合 / 01-05 命名一致性 |

---

## 六、整体时间盒（不承诺时间，按 S/M/L/XL 估容量）

| Sprint | 容量 | 备注 |
|:------:|:----:|------|
| 11 | S | 半天内可完成 |
| 12 | L | 涉及代码侧 + 文档 + 多次门禁 |
| 13 | XL | 涉及 5 环业务 + 资源 + 群聊洞察 4 处 |

---

## 七、整体回退路径

- **Sprint 11**：`git revert <commit>`（无副作用）
- **Sprint 12**：`git revert <merge>` 或 `git checkout v3.9.0 -- resources/prompts/yuesheng-prompt-v3.md`
- **Sprint 13**：`git revert <merge>`；ADR-005 独立保留

---

## 八、风险登记（全局）

| ID | 风险 | 等级 | 缓解 |
|:--:|------|:----:|------|
| R1 | 提示词合并后效果变差 | 中 | 保留 v3/v4 双存档，v5 不删 v3/v4 文件 |
| R2 | 5 环边界重梳影响范围广 | 中 | Sprint 11 先普查，T13-2 边界单测先于业务代码 |
| R3 | 命名规范变动大 | 低 | Sprint 11 T0-3 先 PR 草案评审 |
| R4 | 网文群聊洞察误用 | 中 | 群聊洞察只作输入不直接生成规则；每处需用户复审 |
| R5 | 代码侧引用路径遗漏 | 中 | T12-5 引用图先于 T12-6 代码改动 |
| R6 | 教学 Agent 个人XP 决策边界模糊 | 中 | T13-9 单测覆盖"对什么样的人不教" |
| R7 | Sprint 0 扫描脚本误报 | 低 | diff 二次确认 + 人工 spot check |

---

## 九、决策日志条目（待 Sprint 11 写入）

```markdown
## 2026-06-23 — 提示词逆转 v4 + 教育链路重整

### 决策
将 yuesheng-prompt v4.0.0 的 5-Skill 拆分架构逆转回 v3.9 风格的单一 Prompt
（v5 命名），同时重梳教育链路 5 环职责。

### 原因
1. v4 拆分带来运行时复杂度（动态加载），与项目"小而美"目标不符
2. 资产散落严重，影响维护效率
3. 5 环职责边界未明，外部材料（网文群聊）提供新洞察

### 范围
3 个 Sprint：11（普查）/ 12（合并）/ 13（链路）

### 影响
- 提示词资产从 ~12 个文件收敛到 ~5 个核心 + archive
- 业务链路职责首次有 ADR 文档化
- 网文群聊 4 洞察落到 3 处

### 风险
见文档 §八 风险登记

### 验证
每个 Sprint 独立门禁 + Sprint 13 端到端测试

### 回退
每个 Sprint 独立 git revert，文档 ADR 独立保留
```

---

## 十、检查清单（声称完成前必须跑）

```
□ typecheck 零错误？（Sprint 11/12/13）
□ test 全绿？（Sprint 12/13）
□ lint 零 error？（Sprint 12/13）
□ 密钥零硬编码？（R-029）
□ 只改了必要文件？（R-010）
□ 命名一致 + 无重复？（Sprint 13）
□ ADR-005 落盘？（Sprint 13）
□ 网文洞察 4 处全部落地？（Sprint 13）
□ 决策日志更新？（Sprint 11/12/13）
```

---

## 附录 A：参考资料

- [ADR-003: AI 读写管道](file:///d:/ai-teacher/yuesheng-writing-coach/dev-docs/designs/adr/003-ai-readwrite-pipeline.md)
- [ADR-004: X-02 写回协议](file:///d:/ai-teacher/yuesheng-writing-coach/dev-docs/designs/adr/004-x02-writeback.md)
- [GStack 工作流 v1.0](file:///d:/ai-teacher/yuesheng-writing-coach/dev-docs/workflows/gstack-workflow.md)
- [外部材料：网文大家庭(169) 群聊截图提取](file:///C:/Users/月笙如歌/Documents/xwechat_files/wxid_qwnwolo1n0zt22_3953/msg/file/2026-06/网文大家庭聊天记录提取.md)

## 附录 B：变更历史

| 版本 | 日期 | 变更 |
|:----:|:----:|------|
| v1.0 | 2026-06-23 | 初版（设计草案 v0.1 经用户批准后落盘） |
