# Sprint 12 Plan — 提示词工程统一（v4 逆转 + 去重）

> **Sprint**: 12
> **Stage**: GStack Plan
> **Issue**: #17 (P0)
> **Design**: 005 — 提示词逆转 + 教育链路重整（§三 Sprint 12）
> **状态**: 待批准
> **依赖**: Sprint 11 资产普查已完成（PR #19 待 merge）
> **作者**: AI 架构师（Plan 阶段）
> **依据**: R-018 变更溯源 / R-006 回退机制 / R-019 代码规范 / R-025 Prompt 治理

---

## 一、Plan 目标

Sprint 12 是设计 005 的 **Sprint N**（v4 逆转 + 去重）。目标：

1. **逆转 v4 拆分**：5 个 SKILL-*.md 合并回单一 yuesheng-prompt-v5.md
2. **去重散落**：双副本结构（老 `resources/prompts/` + 新 `resources/0X-domain/`）收敛为单一真源
3. **代码侧更新**：所有 hardcode `yuesheng-prompt-v3.md` 路径的代码点改为 v5
4. **保留可回退**：v3.9 / v4.0 通过 git tag 保留，旧文件归档不删除

**不涉及**（Sprint 13 范围）：
- 5 环职责边界 ADR-005
- 网文群聊 4 洞察融合
- 01-05 domain 文件夹命名规范落地
- 过期文件清理

---

## 二、现状盘点（来自 Sprint 11 普查）

### 2.1 prompt 文件分布

| 位置 | 文件数 | 状态 |
|:-----|:----:|:-----|
| `resources/prompts/` | 17 | 老根目录，含 v3 + 5 SKILL + 多个子 prompt |
| `resources/prompts/skills/` | 5 | v4 拆分产物（SKILL-IDENTITY/TEACHING/VALIDATION/FEEDBACK/SCENARIO） |
| `resources/03-teaching/prompts/` | 6 | 新 domain 副本（含 yuesheng-prompt-v3 + teaching-agent-v2） |
| `resources/03-teaching/prompts/skills/` | 5 | v4 副本（与老位置内容相同） |

### 2.2 代码侧引用 yuesheng-prompt 的位置（17 处 hardcode）

| 文件 | 行号 | 内容 | 状态 |
|:-----|:----:|:-----|:----:|
| `src/main/domains/03-teaching/prompt/prompt-loader.ts` | 195 | `readPrompt('yuesheng-prompt-v3.md', FALLBACK)` | 核心，需改 |
| `src/main/domains/03-teaching/prompt/dynamic-context.service.ts` | 134 | `readPrompt('yuesheng-prompt-v3.md')` | 核心，需改 |
| `src/main/domains/03-teaching/prompt/__tests__/prompt-placeholder-style.test.ts` | 5, 9 | 扫描路径 + 注释 | 测试，需改 |
| `src/main/domains/03-teaching/prompt/__tests__/prompt-integration.test.ts` | 424, 462 | 注释 | 测试，需改 |
| `src/main/domains/04-validation/training/training-evaluator.service.ts` | 41 | `resources/prompts/training-evaluator-prompt-v1.md` | 子 prompt，不变 |
| `src/main/domains/04-validation/training/behavior-derivation.service.ts` | 39 | `resources/prompts/behavior-derivation-prompt-v1.md` | 子 prompt，不变 |
| `src/main/domains/01-diagnosis/orchestrator/diagnosis-orchestrator.service.ts` | 99 | `resources/prompts/diagnosis-agent-prompt-v1.md` | 子 prompt，不变 |

**注意**：Sprint 12 仅修改 yuesheng-prompt 引用（4 处），子 prompt（diagnosis/training-evaluator/behavior-derivation）保持原位置和引用。

---

## 三、任务拆分（执行顺序）

### T12-1 5 个 SKILL 合并 → yuesheng-prompt-v5.md
- **产物**: `resources/prompts/yuesheng-prompt-v5.md`（新增）
- **输入**:
  - `resources/prompts/skills/SKILL-IDENTITY.md`（3358 B）
  - `resources/prompts/skills/SKILL-TEACHING.md`（9399 B）
  - `resources/prompts/skills/SKILL-VALIDATION.md`（3676 B）
  - `resources/prompts/skills/SKILL-FEEDBACK.md`（2370 B）
  - `resources/prompts/skills/SKILL-SCENARIO.md`（2750 B）
- **结构**:
  ```
  # 月笙写作教练 v5 (合并版)
  > 版本: v5.0
  > 创建: 2026-06-23
  > 来源: SKILL-IDENTITY/TEACHING/VALIDATION/FEEDBACK/SCENARIO (v4 拆分产物合并)
  > 回退: git checkout v3.9.0 -- resources/prompts/yuesheng-prompt-v3.md

  ## 1. IDENTITY（来自 SKILL-IDENTITY）
  [内容]

  ## 2. TEACHING（来自 SKILL-TEACHING）
  [内容]

  ## 3. VALIDATION（来自 SKILL-VALIDATION）
  [内容]

  ## 4. FEEDBACK（来自 SKILL-FEEDBACK）
  [内容]

  ## 5. SCENARIO（来自 SKILL-SCENARIO）
  [内容]
  ```
- **占位符**: 验证所有占位符符合 `{{xxx}}` 双花规范（D12-3 强制）
- **行数**: 估算 ~22 KB（5 文件合并）
- **风险**: 合并时丢失章节标题层级 → 保留原 Markdown 结构

### T12-2 5 个 SKILL 归档到 archive/prompts/skills-v4/
- **操作**: `git mv resources/prompts/skills/SKILL-*.md resources/archive/prompts/skills-v4/`
- **数量**: 5
- **可恢复**: git 历史 + archive 目录双重保留
- **副作用**: 无代码侧引用（5 SKILL 文件无代码引用，已在 T12-5 引用图中确认）

### T12-3 yuesheng-prompt-v3.md 归档
- **操作**: `git mv resources/prompts/yuesheng-prompt-v3.md resources/archive/prompts/`
- **可恢复**: `git tag v3.9.0` + archive 目录
- **副作用**: 需在 v3.9 tag 处打 tag（如果还没有）
- **风险**: D-027 已记录合并前必须 review v3 内容，不能直接删除

### T12-4 老位置去重
- **目标**: `resources/prompts/teaching-agent-prompt-v2.md` 与 `resources/03-teaching/prompts/teaching-agent-prompt-v2.md` 内容一致（已验证）
- **操作**: `git mv resources/prompts/teaching-agent-prompt-v2.md resources/archive/prompts/`
- **保留**: `resources/03-teaching/prompts/teaching-agent-prompt-v2.md`（新位置为真源）
- **例外**:
  - `assistant-prompt.md` / `core-principles.md` / `teacher-prompt.md` / `clown-prompt.md` 双副本在 Issue #17 范围之外，Sprint 13 处理
  - `teaching-agent-prompt-v2草案.md` 草案状态保留（不归档）
  - `DIAGNOSIS-UPGRADE-CHANGELOG.md` 文档，不归档

### T12-5 子 prompt 引用关系梳理
- **产物**: 引用图文档（`dev-docs/audits/2026-06-23-prompt-reference-graph.md`）
- **覆盖范围**:
  - diagnosis-agent-prompt-v1.md（01-diagnosis）
  - training-evaluator-prompt-v1.md（04-validation）
  - onboarding-analysis-prompt.md（01-diagnosis 入口）
  - behavior-derivation-prompt-v1.md（04-validation）
  - teacher-prompt.md / assistant-prompt.md / core-principles.md / clown-prompt.md（教学辅助）
- **格式**: 表格（file | imports | imported_by | domain | status）
- **依据**: 防止 T12-6 改路径时遗漏

### T12-6 代码侧引用 v5 路径更新
- **修改文件**: 4 处 hardcode `yuesheng-prompt-v3.md`
  - `src/main/domains/03-teaching/prompt/prompt-loader.ts:195`
  - `src/main/domains/03-teaching/prompt/dynamic-context.service.ts:134`
  - `src/main/domains/03-teaching/prompt/__tests__/prompt-placeholder-style.test.ts`（注释 + 路径）
  - `src/main/domains/03-teaching/prompt/__tests__/prompt-integration.test.ts`（注释）
- **改动**: `yuesheng-prompt-v3.md` → `yuesheng-prompt-v5.md`
- **范围**: 仅文件名替换，路径前缀 `resources/prompts/` 保持
- **风险**: 漏改 → T12-5 引用图先于 T12-6，强制门禁 grep 验证

### T12-7 v5 placeholder 回归测试
- **产物**: 增强现有 `src/main/domains/03-teaching/prompt/__tests__/prompt-placeholder-style.test.ts`
- **测试范围**:
  - v5 文件中所有占位符 `{{xxx}}` 都有对应 schema 字段
  - 旧 `{{xxx}}` 单花不出现（已由 D12-3 强制）
  - 与 v3.9 占位符集对比：新增/废弃占位符清单
- **行数**: 测试 +20 行
- **门禁**: `npm run test` 通过

### T12-8 v5 truncation 集成测试
- **产物**: 新增 `src/main/domains/03-teaching/prompt/__tests__/v5-integration.test.ts`
- **测试场景**:
  - v5 文件 + 章节内容（> 4000 chars）→ truncation 工具正确截断
  - v5 占位符替换 + 截断顺序：截断在占位符替换前（D-027 决策）
  - readPrompt 失败时降级到 FALLBACK（不动行为，仅验证路径）
- **行数**: 测试 +60 行
- **门禁**: `npm run test` 通过

---

## 四、DoD 验证矩阵

| DoD | 验证方式 | 对应任务 | 状态 |
|:----|:---------|:---------|:----:|
| **D12-1** v5.md 存在，含 5 SKILL 全部内容 | git show HEAD:resources/prompts/yuesheng-prompt-v5.md | T12-1 | ⏳ |
| **D12-2** 5 SKILL 归档，原位置不再存在 | `ls resources/prompts/skills/` 为空 | T12-2 | ⏳ |
| **D12-3** prompt-placeholder-style.test.ts 通过 | `npm run test` | T12-7 | ⏳ |
| **D12-4** truncation.test.ts 通过 | `npm run test` | T12-8 | ⏳ |
| **D12-5** chat-orchestrator 引用 v5 路径生效 | 集成测试 + grep 验证 | T12-6, T12-8 | ⏳ |
| **D12-6** 老位置 prompt 重复文件已清理 | `ls resources/prompts/` 无重复 | T12-4 | ⏳ |
| **D12-7** v3.9/v4.0 从 git 历史可回滚 | `git tag -l "v3.*" "v4.*"` 显示存在 | T12-3 | ⏳ |
| **D12-8** v5 commit 含版本号 + 变更说明 | R-025 治理：commit message 含 v5 + scope(prompt) | T12-1 | ⏳ |
| **D12-9** 门禁 typecheck && test && lint 全绿 | CI / 本地 | 全部 | ⏳ |

---

## 五、涉及文件清单

### 5.1 新增（1 个）
- `resources/prompts/yuesheng-prompt-v5.md`（~22 KB）

### 5.2 移动（git mv，6 个）
- `resources/prompts/skills/SKILL-IDENTITY.md` → `resources/archive/prompts/skills-v4/`
- `resources/prompts/skills/SKILL-TEACHING.md` → `resources/archive/prompts/skills-v4/`
- `resources/prompts/skills/SKILL-VALIDATION.md` → `resources/archive/prompts/skills-v4/`
- `resources/prompts/skills/SKILL-FEEDBACK.md` → `resources/archive/prompts/skills-v4/`
- `resources/prompts/skills/SKILL-SCENARIO.md` → `resources/archive/prompts/skills-v4/`
- `resources/prompts/yuesheng-prompt-v3.md` → `resources/archive/prompts/`
- `resources/prompts/teaching-agent-prompt-v2.md` → `resources/archive/prompts/`

### 5.3 代码侧修改（4 个）
- `src/main/domains/03-teaching/prompt/prompt-loader.ts`
- `src/main/domains/03-teaching/prompt/dynamic-context.service.ts`
- `src/main/domains/03-teaching/prompt/__tests__/prompt-placeholder-style.test.ts`
- `src/main/domains/03-teaching/prompt/__tests__/prompt-integration.test.ts`

### 5.4 测试新增（1 个）
- `src/main/domains/03-teaching/prompt/__tests__/v5-integration.test.ts`

### 5.5 文档新增（1 个）
- `dev-docs/audits/2026-06-23-prompt-reference-graph.md`（T12-5）

---

## 六、风险评估

| 风险 | 等级 | 缓解措施 | 关联任务 |
|:-----|:----:|:---------|:--------:|
| v5 合并后效果变差 | 中 | v3/v4 archive 保留 + git tag 可回滚 | T12-1, T12-3 |
| 代码侧 hardcode 路径漏改 | 中 | T12-5 引用图先于 T12-6 + grep 验证 | T12-5, T12-6 |
| 占位符 `{{xxx}}` 回归 | 低 | T12-7 强制测试门禁 | T12-7 |
| truncation 与 v5 不兼容 | 低 | T12-8 集成测试 + D-027 决策（截断在替换前） | T12-8 |
| archive 目录不存在 | 低 | T12-2 前 `mkdir -p resources/archive/prompts/skills-v4/` | T12-2 |
| v3.md 文件被破坏（编码灾难） | 中 | 用 node.js 写文件（避免 PowerShell 5.1 UTF-8 mojibake） | 全部 |

---

## 七、回退机制（R-006）

### 7.1 单 commit 回滚
```bash
# Sprint 12 全部 commit 一个 PR，merge 后回滚：
git revert -m 1 <sprint-12-merge-commit>
```

### 7.2 文件级回退
```bash
# v5 不满意 → 恢复 v3.9
git checkout v3.9.0 -- resources/prompts/yuesheng-prompt-v3.md
# 恢复 v4 SKILL 拆分
git checkout v4.0.0 -- resources/prompts/skills/
```

### 7.3 Git tag 保留
```bash
# Sprint 12 merge commit 前打 tag
git tag -a sprint-12-pre-merge HEAD
# 任意时刻回到 Sprint 12 起点
git checkout sprint-12-pre-merge
```

---

## 八、决策依据

### 8.1 上游决策
- **D-027**（2026-06-23）：Sprint 12 启动必须基于 Sprint 11 资产普查事实基线
- **设计 005 §三 Sprint 12**：任务清单 + DoD + 涉及文件 + 风险（直接来源）
- **ADR-003 + ADR-004**（2026-06-22）：AI 读写管道（v5 仍需走 truncation + 写回协议）

### 8.2 范围排除
- **不在 Sprint 12 范围**：
  - 5 SKILL 之外的子 prompt（diagnosis/training-evaluator/behavior-derivation）位置不动
  - assistant-prompt / core-principles / teacher-prompt / clown-prompt 双副本收敛（Sprint 13）
  - 01-05 domain 文件夹命名规范落地（Sprint 13）
  - 5 环职责边界 ADR（Sprint 13）

### 8.3 关联 Issue
- **依赖**: #16 (Sprint 11 资产普查，已完成待 merge)
- **本 Sprint**: #17 (Sprint 12 提示词工程统一 P0)
- **下游**: #18 (Sprint 13 教育链路重整 P1) — Sprint 12 完成后启动

---

## 九、Plan 批准门

- [ ] 用户 review 本 Plan 文档
- [ ] 用户在 Issue #17 评论 "approved"
- [ ] 用户授权开始 Build 阶段

**进入 Build 阶段的最小动作**：
1. 合并 PR #19（Sprint 11 资产普查）
2. 用户在 GitHub Issue #17 评论 approved
3. AI 收到 "approved" 信号后启动 T12-1

---

**Plan 草案完成**。请审阅。
