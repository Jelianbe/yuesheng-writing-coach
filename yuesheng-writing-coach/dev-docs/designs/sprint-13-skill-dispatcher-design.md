# Sprint 13 设计 — Skill Dispatcher（v5 拆分 + 按需加载）

> **Sprint**: 13
> **Stage**: GStack Think / Plan
> **Issue**: #18 (P1) — 教育链路重整
> **前置**: Sprint 12 完成（PR #19 待 merge，v5 已合并）
> **状态**: 待批准
> **作者**: AI 架构师（brainstorming 阶段）
> **依据**: R-018 变更溯源 / R-014 配置外置 / R-025 Prompt 治理 / GStack 7 阶段工作流（提取思想）

---

## 一、设计目标

Sprint 12 把 v4 拆分的 5 个 SKILL 合并回单一 v5.md（30K 字符）。Sprint 13 解决 v5 暴露的 4 个痛点：

1. **v5 太大占用 token**：30K 字符 ≈ 45K tokens，单 prompt 框架就接近 DeepSeek 8K 模型余量上限
2. **修改牵一发动全身**：v5 单一文件改一个 SKILL 块要触碰其他块
3. **模块边界重叠**：IDENTITY（§2.6 防御点 H）与 VALIDATION（V-09）语义重叠
4. **不能按需加载**：5 大块静态全量加载，P0 初次见面也加载 SCENARIO 拒绝话术

**GStack 思想提取**（不 1:1 复制）：
- **按阶段分职责**：每个 SKILL 只做自己职责范围内的事
- **角色边界清晰**：YAML metadata 显式声明依赖与加载条件
- **可插拔**：新增 SKILL 只需加文件 + 改 PromptBuilder 映射表
- **可观测**：每条 SKILL 估算 tokens，便于 phase 组合时计算总占用

---

## 二、4 个关键决策（已确认）

| # | 决策点 | 选项 | 理由 |
|---|--------|------|------|
| 1 | TEACHING 九/十是否拆出 `reference-drawer.md` | **B：拆出** | P0/P1 用不到，浪费 2K token；增加 1 个文件成本可接受 |
| 2 | DP-F/G/I 留在 `scenario-rules.md` 还是合并进 `validation-rules.md` | **A：保持独立** | V-01~V-09 是"输出规则"（每次检查），DP 是"场景拒绝话术"（触发才用），合并让 P0/P1 加载完整拒绝话术，浪费 token |
| 3 | 调度粒度 phase 唯一 / +attitude / +evidence | **B：phase + attitude（10 种组合，attitude 接口预留不实质过滤）** | A 太粗（sensei 档仍加载"加油"鼓励话术）；C 太细（30 种组合测试矩阵爆炸）；B 是 sweet spot。Sprint 13 实质做 phase 维度 5 种，attitude 维度推到 C 做实质过滤 |
| 4 | 方向 C（完整 dispatcher）占位位置 | **D：三处都写** | 决策日志（为什么+何时） + GitHub Issue（做什么+验收） + 设计草案（怎么做） |

---

## 三、架构（3 层）

```
┌─────────────────────────────────────────────────────┐
│  Layer 1: Skill 元数据 (YAML frontmatter, 文件级)    │
│  - id / estimatedTokens / loadWhen.phases/attitudes │
└─────────────────────────────────────────────────────┘
            ↓
┌─────────────────────────────────────────────────────┐
│  Layer 2: Skill 文件 (拆分后的 v5 产物)             │
│  - core-identity.md        必加载, ~3K 字符          │
│  - teaching-strategy.md    必加载, ~8K 字符          │
│  - validation-rules.md     必加载, ~5K 字符          │
│  - feedback-cognition.md   按需, ~3K 字符            │
│  - scenario-rules.md       必加载, ~4K 字符          │
│  - reference-drawer.md     P2/P3/P4 only, ~2K 字符   │
└─────────────────────────────────────────────────────┘
            ↓
┌─────────────────────────────────────────────────────┐
│  Layer 3: PromptBuilder (新增 phase+attitude→skills) │
│  - SkillDispatcher.selectForPhase(phase, attitude)  │
│  - 估算总 token + truncation 仍只对章节内容生效      │
└─────────────────────────────────────────────────────┘
```

---

## 四、模块边界（6 个 SKILL 文件）

| 旧 v5 块 | 新 SKILL 文件 | loadWhen phases | loadWhen attitudes | token 估算 |
|---------|--------------|----------------|-------------------|-----------|
| IDENTITY (§一/二/2.6) | `core-identity.md` | always | all | ~3K |
| TEACHING (§三/四/五/六) | `teaching-strategy.md` | always | all | ~8K |
| TEACHING (§九/十) | `reference-drawer.md` | P2/P3/P4 | all | ~2K |
| VALIDATION (§八) | `validation-rules.md` | always | all | ~5K |
| FEEDBACK (§七) | `feedback-cognition.md` | P2/P3/P4 | all | ~3K |
| SCENARIO (§十一) | `scenario-rules.md` | always | all | ~4K |

**总 token 估算对比**：
- v5 当前：~30K（所有 phase 都全量加载）
- Sprint 13 后：P0/P1 ~12K，P2/P3/P4 ~20K（节省 33%~60%）

**phase 与 attitude 组合矩阵**（10 种）：
- P0_INIT × {doubao, yuesheng, sensei} = 3 种
- P1_WORLD × {doubao, yuesheng, sensei} = 3 种
- P2_PRACTICE_LOOP × {doubao, yuesheng, sensei} = 3 种
- P3_TRAINING × {doubao, yuesheng, sensei} = 3 种
- P4_REVIEW × {doubao, yuesheng, sensei} = 3 种
- 实际：P0/P1 加载 core-identity + teaching-strategy + validation-rules + scenario-rules（4 个）
- P2/P3/P4 加载上面 4 个 + reference-drawer + feedback-cognition（6 个）

**attitude 过滤规则**（YAGNI：先用硬编码，不引入元数据配置）：
- `doubao`：全量加载（鼓励性话术保留）
- `yuesheng`：剔除 sensei 档特有犀利话术（实际不剔除，先全量；attitude 过滤留给 C）
- `sensei`：剔除"鼓励""加油"等字眼（实际先全量；C 时再做精细过滤）

> **简化说明**：Sprint 13 的 attitude 过滤先采用"全量加载"简化实现（决策点 B 的"phase + attitude" 实际表现为 phase 维度的 5 种组合，attitude 维度预留接口但不实质过滤）。完整 attitude 过滤推迟到方向 C。

---

## 五、数据/接口（YAML metadata schema）

**最小化版本**（Sprint 13）：
```yaml
---
id: core-identity
estimatedTokens: 3000
loadWhen:
  phases: [P0_INIT, P1_WORLD, P2_PRACTICE_LOOP, P3_TRAINING, P4_REVIEW]
  attitudes: [doubao, yuesheng, sensei]
---
# SKILL 内容...
```

**完整版本**（方向 C 时再扩展）：
```yaml
---
id: core-identity
version: 1.0
estimatedTokens: 3000
depends: []           # 依赖的其他 SKILL
loadWhen:
  phases: [...]
  attitudes: [...]
  conditions: []      # 运行时条件（如 evidence 质量）
tokenPriority: 10     # 截断时优先级
---
```

**TypeScript 接口**：
```typescript
// prompt-loader/skill-metadata.ts
export type TeachingPhase = 
  | 'P0_INIT' | 'P1_WORLD' | 'P2_PRACTICE_LOOP' | 'P3_TRAINING' | 'P4_REVIEW';

export type AttitudeLevel = 'doubao' | 'yuesheng' | 'sensei';

export interface SkillMetadata {
  id: string;
  estimatedTokens: number;
  loadWhen: {
    phases: TeachingPhase[];
    attitudes: AttitudeLevel[];
  };
}

export interface Skill {
  meta: SkillMetadata;
  content: string;
}
```

**调度器**：
```typescript
// prompt-loader/skill-dispatcher.ts
export class SkillDispatcher {
  private skills = new Map<string, Skill>();

  loadAll(skillsRoot: string): void {
    // 扫描 skillsRoot 下所有 .md 文件，解析 YAML frontmatter
  }

  selectForPhase(phase: TeachingPhase, attitude: AttitudeLevel): Skill[] {
    return [...this.skills.values()].filter(s =>
      s.meta.loadWhen.phases.includes(phase) &&
      s.meta.loadWhen.attitudes.includes(attitude)
    );
  }

  estimateTokens(phase: TeachingPhase, attitude: AttitudeLevel): number {
    return this.selectForPhase(phase, attitude)
      .reduce((sum, s) => sum + s.meta.estimatedTokens, 0);
  }

  composePrompt(phase: TeachingPhase, attitude: AttitudeLevel): string {
    return this.selectForPhase(phase, attitude)
      .map(s => s.content)
      .join('\n\n---\n\n');
  }
}
```

**PromptBuilder 改造**：
```typescript
// prompt-loader/prompt-builder.ts（改造）
class PromptBuilder {
  constructor(
    private dispatcher: SkillDispatcher,
    // 保留旧依赖以兼容 v3 降级路径
  ) {}

  buildSystemPrompt(state: TeachingState, attitude: AttitudeLevel): string {
    // 新路径：按 phase+attitude 选 SKILL
    const skills = this.dispatcher.selectForPhase(state.currentPhase, attitude);
    const composed = this.dispatcher.composePrompt(state.currentPhase, attitude);
    return composed;
    // 旧路径（降级）：无 dispatcher 时回退到 v5 全量
  }
}
```

---

## 六、测试策略

**新增测试**：
- `__tests__/skill-metadata.test.ts`：YAML frontmatter 解析 + 校验
- `__tests__/skill-dispatcher.test.ts`：phase+attitude 组合矩阵（10 种）+ token 估算
- `__tests__/skill-composer.test.ts`：组合顺序 + 边界（空 phase / 未知 attitude）

**改造测试**：
- `__tests__/v5-structure.test.ts` → `__tests__/skill-structure.test.ts`：按 SKILL 文件独立校验（每个文件含必需防御点）

**保留测试**：
- `__tests__/prompt-integration.test.ts`：保留 3 处"月笙写作教练 v5"断言改为"月笙"通用断言
- `__tests__/truncation.test.ts`：不变（truncation 与 SKILL 拆分正交）
- `__tests__/prompt-placeholder-style.test.ts`：不变

**E2E**：Sprint 13 不写（保留给 Sprint 14+ 升级 C 时再做）

---

## 七、范围与不做的事

**Sprint 13 做**：
- 拆分 v5.md 为 6 个 SKILL 文件 + YAML metadata
- 新增 `SkillDispatcher` 类（`prompt-loader/skill-dispatcher.ts`）
- 改 `PromptBuilder` 支持 phase+attitude→skills
- 6 个 SKILL 文件 + dispatcher 单元测试
- 清理 03-teaching/ 双副本（D-DEBT-2026-06-23-05）
- 新增 v5.0.0 tag（拆分前快照）

**Sprint 13 不做**（保留给方向 C）：
- ❌ 完整 YAML metadata schema（depends / tokenPriority / version）
- ❌ 跨 SKILL 依赖图自动校验
- ❌ 运行时根据 user 行为（evidence 质量 / 触发关键词）切换 SKILL
- ❌ 动态 load 缓存 + LRU
- ❌ SKILL 热更新
- ❌ attitude 维度的实质过滤（先全量加载）
- ❌ E2E 测试

**C 占位（三处都写）**：
1. `docs/decision-log.md` D-030：记录"为什么保留 C 升级路径" + "何时启动"
2. `gh issue create`：建 Sprint 14+ Skill Dispatcher 升级 backlog
3. `dev-docs/designs/sprint-14-dispatcher-upgrade.md`：方向 C 草案（架构 + 任务 + DoD 草稿）

---

## 八、回退机制

**3 个回退锚点**：
1. **v3.9.0 tag**（已有）：回到 v3 单一 prompt
2. **v5.0.0 tag**（新增）：Sprint 13 拆分前的 v5 单一 prompt 快照
3. **git reflog**：任意 commit 恢复

**回退命令**：
```bash
# 回到 v5 单一 prompt
git checkout v5.0.0 -- resources/prompts/

# 回到 v3
git checkout v3.9.0 -- resources/prompts/yuesheng-prompt-v3.md

# 完全回退到 Sprint 13 起点
git reset --hard <sprint-12-final-commit>
```

**回退成本**：低（仅 prompt 文件 + 一个新 dispatcher 类 + PromptBuilder 改造，代码改动 ≤ 200 行）

---

## 九、风险评估

| 风险 | 等级 | 缓解 |
|------|------|------|
| YAML frontmatter 解析出错导致 SKILL 不加载 | 中 | 启动时校验全部 SKILL metadata，缺字段立即 fail-fast |
| 拆分时丢失 v5 中的某个防御点 | 中 | skill-structure.test.ts 按 SKILL 块独立校验必需防御点（V-01/V-09/DP-F/DP-G/DP-I） |
| PromptBuilder 改造破坏现有 v3 降级路径 | 低 | 保留 v5 fallback，dispatcher 不可用时自动回退 v5 全量 |
| 调度粒度 phase+attitude 实际效果不佳 | 低 | 5 种 phase 组合已能解决 70% 痛点；attitude 维度预留接口但不实质过滤 |
| 6 个 SKILL 文件边界划分有歧义 | 中 | v5 原文作为唯一真源逐块剪切，不重组语义；review 时逐段对照 v5 |
| 升级 C 时改动量大 | 低 | 6 个 SKILL 文件 + dispatcher 接口已稳定；C 主要加 metadata 字段和运行时条件 |

---

## 十、DoD（4 条可验证）

1. **拆分完整性**：6 个 SKILL 文件的合并内容 = v5.md 原文（diff = 0，按行/段对照）
2. **调度正确性**：10 种 phase+attitude 组合全部命中预期 SKILL 集合（dispatcher.test.ts 全绿）
3. **门禁全绿**：typecheck 0 / test 全绿 / lint 0 errors
4. **回退路径**：v5.0.0 tag 存在且 `git checkout v5.0.0 -- resources/prompts/` 可恢复拆分前状态

---

## 十一、任务列表（草案）

| 编号 | 任务 | 预估 |
|------|------|------|
| T13-1 | 创建 v5.0.0 tag + 备份 v5.md 内容 | 5 min |
| T13-2 | 拆分 v5.md 为 6 个 SKILL 文件 + YAML frontmatter | 30 min |
| T13-3 | 写 SkillMetadata + Skill TypeScript 接口 | 10 min |
| T13-4 | 实现 SkillDispatcher（loadAll / selectForPhase / composePrompt） | 30 min |
| T13-5 | 改 PromptBuilder 集成 SkillDispatcher + 保留 v5 fallback | 20 min |
| T13-6 | 写 skill-metadata.test.ts + skill-dispatcher.test.ts | 30 min |
| T13-7 | 改 v5-structure.test.ts → skill-structure.test.ts | 20 min |
| T13-8 | 清理 03-teaching/prompts/ 双副本 | 10 min |
| T13-9 | 跑全门禁（typecheck / test / lint） | 5 min |
| T13-10 | commit（按 R-016 拆 5-6 commit）+ push + 建 PR | 15 min |
| T13-11 | 写 D-030 决策日志 + 建 Issue + 写 C 草案 | 20 min |
| T13-12 | Reflect：复盘 + 债务记录 | 15 min |

**总预估**：约 3.5 小时

---

## 十二、依据与真源

- **设计 005**：2026-06-23-prompt-unify-and-teaching-chain.md §三 Sprint 12 + §四 Sprint 13
- **Issue #18**：Sprint 13 教育链路重整 (P1)
- **D-027 / D-028 / D-029**：决策日志
- **R-014**：诊断引擎信号权重、动作优先级、阈值常量外置（YAML metadata 设计参考）
- **R-018**：变更溯源（本设计文档 + 决策日志 + Issue + 草案 4 处记录 C 升级路径）
- **R-025**：Prompt 治理（v5 单一真源 + tag 锚点 + 拆分可回退）
- **GStack 工作流**：提取"按阶段分职责 + 角色边界 + 可插拔"思想，不 1:1 复制
