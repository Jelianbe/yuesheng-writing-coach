# T-028：技法核心化分类

> **版本**: V1.0  
> **创建日期**: 2026-06-06  
> **阶段**: Phase 2.5  
> **优先级**: P0  
> **预估**: 1.5d  
> **依赖**: T-026（三管蒸馏产出）  
> **设计依据**: distillation-three-paths_V2.0.md

---

## 目标

将 technique-library.json 中目前扁平的 89 条技法重组为"核心模式 + 难度变种"的树形结构，使系统能按核心模式推荐技法，按用户水平选择变种。

## 设计

### 当前问题

```
technique-library.json 现有结构（扁平）：
  [
    { id: "TQ-025", name: "感官替代法", difficulty: "intermediate", applicableSyndromes: ["P003"] },
    { id: "TQ-027", name: "微动作泄露法", difficulty: "beginner", applicableSyndromes: ["P003"] },
    ...
  ]

问题：TQ-025 和 TQ-027 本质上是"展示而非告知"核心模式的两个变种，
但系统无法知道它们属于同一模式，只能按适用症候匹配。
```

### 目标结构

新增 `coreId`, `coreName`, `difficultyOrder` 字段，不破坏现有字段的兼容性：

```json
{
  "id": "TQ-025",
  "name": "感官替代法",
  "coreId": "show-dont-tell",
  "coreName": "展示而非告知",
  "difficulty": "intermediate",
  "difficultyOrder": 2,
  "category": "情绪",
  "applicableSyndromes": ["P003"],
  "source": "道诡异仙",
  ...
}
```

### 核心模式定义（预研结果，任务执行中确认）

| coreId | coreName | 包含技法数 | 难度分布 |
|--------|---------|:---------:|---------|
| show-dont-tell | 展示而非告知 | ~8 | beginner 2 / intermediate 3 / advanced 3 |
| suspense-engine | 悬念驱动 | ~6 | beginner 3 / intermediate 3 / advanced 0 |
| pov-control | 视角控制 | ~5 | beginner 2 / intermediate 2 / advanced 1 |
| structure-innovation | 结构创新 | ~7 | beginner 1 / intermediate 4 / advanced 2 |
| worldbuilding-embed | 设定融入 | ~9 | beginner 4 / intermediate 4 / advanced 1 |
| character-depth | 角色立体化 | ~10 | beginner 4 / intermediate 4 / advanced 2 |
| dialogue-depth | 对话层次 | ~12 | beginner 3 / intermediate 7 / advanced 2 |
| rhythm-control | 节奏呼吸 | ~16 | beginner 8 / intermediate 6 / advanced 2 |
| opening-hook | 开篇钩子 | ~12 | beginner 10 / intermediate 2 / advanced 0 |
| negative-example | 反面教材 | ~1 | — (TN 编号) |
| trad-adapted | 传统技法适配 | ~3 | (TC 编号，但部分 TC 已归入以上模式) |

### 使用方式

```typescript
// 按 coreId 推荐
function recommendTechniques(syndromeId: string, userLevel: string): TechniqueCore[] {
  const matchedBySyndrome = techniques.filter(t => t.applicableSyndromes.includes(syndromeId));
  const byCore = groupBy(matchedBySyndrome, 'coreId');
  // 对每个 coreId，选择最匹配 userLevel 的 variant
  return Object.entries(byCore).map(([coreId, variants]) => ({
    coreId,
    coreName: variants[0].coreName,
    recommendVariant: variants.find(v => v.difficulty === userLevelToDifficulty(userLevel))
                        ?? variants.sort(by('difficultyOrder'))[0],
    allVariants: variants,
  }));
}
```

---

## 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `resources/config/technique-library.json` | 修改 | 每条技法追加 coreId / coreName / difficultyOrder |
| `src/shared/types.ts` | 修改 | TechniqueInfo 追加 coreId / coreName / difficultyOrder |
| `src/main/services/training-recommendation.service.ts` | 修改 | matchTechniques() 改用核心模式推荐 |
| `docs/teaching/technique-library/index_V1.md` | 修改 | V6.0，增加"核心模式 → 变种"层次结构 |

---

## DoD

| # | 标准 | 验证方式 |
|---|------|---------|
| S1 | technique-library.json 中每条技法有正确的 coreId 和 coreName | 检查每个 coreId 包含 ≥2 条技法，总分到 ≥8 个 coreId |
| S2 | training-recommendation.service.ts 按核心模式推荐技法，按用户水平选择变种 | matchTechniques() 返回结果中包含 coreId，不同 userLevel 返回不同 difficulty 的变种 |
| S3 | TypeScript 编译 0 错误 | `npx tsc --noEmit` 通过 |

---

## 变更记录

| 日期 | 版本 | 变更内容 |
|------|------|---------|
| 2026-06-06 | V1.0 | 创建 |
