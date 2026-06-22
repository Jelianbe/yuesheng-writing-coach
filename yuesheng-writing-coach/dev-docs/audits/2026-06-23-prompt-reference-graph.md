# Prompt 引用关系图（Sprint 12 T12-5）

> **生成日期**: 2026-06-23
> **Sprint**: 12 (T12-5)
> **范围**: Sprint 12 涉及的 prompt 文件 + 代码侧引用
> **目的**: 防止 T12-6 代码改动遗漏，确保所有引用路径正确更新

---

## 一、单一真源（Active）

| 路径 | 大小 | 行数 | 状态 | 备注 |
|:-----|:----:|:----:|:----:|:-----|
| `resources/prompts/yuesheng-prompt-v5.md` | 21969 B | 514 | **ACTIVE** | Sprint 12 合并 5 SKILL 产物（v3.9 + v4 逆转） |

> ⚠️ v5.md 514 行超过 R-019 硬上限 300 行（DEBT-2026-06-23-05），内容完整性优先。

---

## 二、归档文件（Archive，可恢复）

| 原路径 | 归档路径 | 最后 commit | Tag |
|:-------|:---------|:-----------:|:---:|
| `resources/prompts/yuesheng-prompt-v3.md` | `resources/archive/prompts/yuesheng-prompt-v3.md` | `ac60ded` | `v3.9.0` |
| `resources/prompts/skills/SKILL-IDENTITY.md` | `resources/archive/prompts/skills-v4/SKILL-IDENTITY.md` | `9795ff1` | — |
| `resources/prompts/skills/SKILL-TEACHING.md` | `resources/archive/prompts/skills-v4/SKILL-TEACHING.md` | `9795ff1` | — |
| `resources/prompts/skills/SKILL-VALIDATION.md` | `resources/archive/prompts/skills-v4/SKILL-VALIDATION.md` | `9795ff1` | — |
| `resources/prompts/skills/SKILL-FEEDBACK.md` | `resources/archive/prompts/skills-v4/SKILL-FEEDBACK.md` | `9795ff1` | — |
| `resources/prompts/skills/SKILL-SCENARIO.md` | `resources/archive/prompts/skills-v4/SKILL-SCENARIO.md` | `9795ff1` | — |
| `resources/prompts/teaching-agent-prompt-v2.md` (老位置) | `resources/archive/prompts/teaching-agent-prompt-v2.md` | `ac60ded` | — |

**回退命令**（R-006）:
```bash
git checkout v3.9.0 -- resources/prompts/yuesheng-prompt-v3.md
git checkout 9795ff1 -- resources/prompts/skills/
```

---

## 三、子 prompt（不变位置，Sprint 12 不动）

| 路径 | 大小 | Domain | 代码侧引用 |
|:-----|:----:|:------|:----------|
| `resources/01-diagnosis/diagnosis-agent-prompt-v1.md` | — | 01-diagnosis | diagnosis-orchestrator.service.ts:99 |
| `resources/02-prescription/ability-nodes/ability-node-prototypes.json` | — | 02-prescription | ability-atlas.loader.ts:33 |
| `resources/01-diagnosis/syndromes/syndrome-action-map.json` | — | 01-diagnosis | ability-atlas.loader.ts:34 |
| `resources/02-prescription/learning-paths/development-path.json` | — | 02-prescription | development-path.service.ts:57 |
| `resources/prompts/diagnosis-agent-prompt-v1.md` | 13115 B | 01-diagnosis | diagnosis-orchestrator.service.ts:99 |
| `resources/prompts/training-evaluator-prompt-v1.md` | 1721 B | 04-validation | training-evaluator.service.ts:41 |
| `resources/prompts/behavior-derivation-prompt-v1.md` | 1013 B | 04-validation | behavior-derivation.service.ts:39 |
| `resources/prompts/onboarding-analysis-prompt.md` | 604 B | 01-diagnosis | (无代码侧引用) |
| `resources/03-teaching/prompts/teaching-agent-prompt-v2.md` | 13586 B | 03-teaching | (无代码侧引用) |
| `resources/03-teaching/prompts/assistant-prompt.md` | 2755 B | 03-teaching | (无代码侧引用) |
| `resources/03-teaching/prompts/core-principles.md` | 5230 B | 03-teaching | (无代码侧引用) |
| `resources/03-teaching/prompts/teacher-prompt.md` | 4753 B | 03-teaching | (无代码侧引用) |
| `resources/03-teaching/prompts/clown-prompt.md` | 1681 B | 03-teaching | (无代码侧引用) |
| `resources/03-teaching/prompts/yuesheng-prompt-v3.md` | 4020 B | 03-teaching (副本) | (无代码侧引用) |
| `resources/03-teaching/prompts/skills/SKILL-*.md` (5 个) | 2425-9622 B | 03-teaching (副本) | (无代码侧引用) |

---

## 四、代码侧引用映射（v3 → v5 必须改）

| 代码文件 | 行 | 引用前 | 引用后 | 状态 |
|:---------|:--:|:-------|:-------|:----:|
| `src/main/domains/03-teaching/prompt/prompt-loader.ts` | 195 | `readPrompt('yuesheng-prompt-v3.md', FALLBACK)` | `readPrompt('yuesheng-prompt-v5.md', FALLBACK)` | ⏳ T12-6 |
| `src/main/domains/03-teaching/prompt/dynamic-context.service.ts` | 134 | `readPrompt('yuesheng-prompt-v3.md')` | `readPrompt('yuesheng-prompt-v5.md')` | ⏳ T12-6 |
| `src/main/domains/03-teaching/prompt/__tests__/prompt-placeholder-style.test.ts` | 5, 9 | 注释 + 路径 | 注释更新 | ⏳ T12-6 |
| `src/main/domains/03-teaching/prompt/__tests__/prompt-integration.test.ts` | 424, 462 | 注释 | 注释更新 | ⏳ T12-6 |

---

## 五、代码侧引用映射（不变，仅记录）

| 代码文件 | 行 | 引用 | 备注 |
|:---------|:--:|:-----|:-----|
| `src/main/domains/04-validation/training/training-evaluator.service.ts` | 41 | `resources/prompts/training-evaluator-prompt-v1.md` | 子 prompt，不变 |
| `src/main/domains/04-validation/training/behavior-derivation.service.ts` | 39 | `resources/prompts/behavior-derivation-prompt-v1.md` | 子 prompt，不变 |
| `src/main/domains/01-diagnosis/orchestrator/diagnosis-orchestrator.service.ts` | 99 | `resources/prompts/diagnosis-agent-prompt-v1.md` | 子 prompt，不变 |
| `src/main/domains/02-prescription/development-path/development-path.service.ts` | 57 | `resources/02-prescription/learning-paths/development-path.json` | config，不变 |
| `src/main/domains/02-prescription/ability-atlas/ability-atlas.loader.ts` | 33 | `resources/02-prescription/ability-nodes/ability-node-prototypes.json` | config，不变 |
| `src/main/domains/02-prescription/ability-atlas/ability-atlas.loader.ts` | 34 | `resources/01-diagnosis/syndromes/syndrome-action-map.json` | config，不变 |

---

## 六、Sprint 12 涉及 vs 不涉及

### 6.1 涉及（Sprint 12 改动）
- ✅ `yuesheng-prompt-v5.md` 新建
- ✅ 5 SKILL + yuesheng-prompt-v3.md + teaching-agent-prompt-v2.md (老位置) 归档
- ✅ 4 处代码侧 hardcode 更新

### 6.2 不涉及（保留原状）
- ❌ `03-teaching/prompts/skills/SKILL-*.md` (5 副本) — DEBT-2026-06-23-06，Sprint 13 处理
- ❌ `03-teaching/prompts/yuesheng-prompt-v3.md` (副本) — 已被 v5.md 取代，但文件未删
- ❌ `assistant-prompt.md` / `core-principles.md` / `teacher-prompt.md` / `clown-prompt.md` 双副本 — Sprint 13 处理
- ❌ 子 prompt 路径（diagnosis/training-evaluator/behavior-derivation）— 不动

---

## 七、引用验证门禁（T12-6 完成后执行）

```bash
# 1. 验证没有残留 v3 引用
grep -rn "yuesheng-prompt-v3" src/ 2>&1 | grep -v "v3.9.0\|v3 history"

# 2. 验证 v5 引用生效
grep -rn "yuesheng-prompt-v5" src/

# 3. 验证子 prompt 不受影响
grep -rn "training-evaluator-prompt-v1\|behavior-derivation-prompt-v1\|diagnosis-agent-prompt-v1" src/ | grep -v ".test.ts"
```

通过条件：1 输出为空 + 2 输出非空 + 3 输出与 Sprint 11 普查一致。

---

**引用图完成**。请审阅。T12-6 启动前最后一道检查。
