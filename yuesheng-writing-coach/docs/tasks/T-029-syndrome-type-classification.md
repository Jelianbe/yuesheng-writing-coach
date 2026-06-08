# T-029：症候类型分类

> **版本**: V1.0  
> **创建日期**: 2026-06-06  
> **阶段**: Phase 2.5  
> **优先级**: P0  
> **预估**: 0.5d  
> **依赖**: —  
> **设计依据**: education-theory-distillation_V1.0.md §4.1, distillation-three-paths_V2.0.md

---

## 目标

新增 `syndrome-type-map.config.json` 配置文件，将 9 个活跃症候按教育学蒸馏产出的三类分型（expressive_deficit / structural_disorder / motivation_deficit）归类，为 T-031 教育学规则接入提供前置条件。

## 设计

### 症候类型分类（来自教育学蒸馏 §4.1）

| 类型 | 包含症候 | 核心特征 | 推荐教学入口 |
|------|---------|---------|------------|
| expressive_deficit | P003, P010, P002 | 有感受但写不出 | 先案例再模仿 |
| structural_disorder | P005, P006, P004 | 有能力但缺觉察 | 先反思再练习 |
| motivation_deficit | P009, P001 | 缺内在驱动 | 先提问再案例 |

### 配置文件格式

`resources/config/syndrome-type-map.json`:

```json
{
  "version": "1.0",
  "updatedAt": "2026-06-06",
  "types": {
    "expressive_deficit": {
      "name": "展示力不足型",
      "syndromes": ["P003", "P010", "P002"],
      "coreIssue": "用户有感受和构思，但缺乏将其转化为具体文字表达的能力",
      "recommendedEntry": "先案例再模仿",
      "rationale": "Schön 反思性实践 + Bandura 社会学习：用户缺的不是反思能力，而是'好的展示长什么样'的参照系"
    },
    "structural_disorder": {
      "name": "结构/视角失控型",
      "syndromes": ["P005", "P006", "P004"],
      "coreIssue": "用户有一定写作能力但缺乏对结构和视角的自我觉察",
      "recommendedEntry": "先反思再练习",
      "rationale": "Schön 反思性实践：用户往往已有能力但缺乏自我觉察，先引导反思而非给案例"
    },
    "motivation_deficit": {
      "name": "动机/意图缺失型",
      "syndromes": ["P009", "P001"],
      "coreIssue": "用户缺乏对角色动机或世界观的内在驱动理解",
      "recommendedEntry": "先提问激发再案例",
      "rationale": "Kolb 体验学习圈：需要先通过提问激发用户的思考动机，再给案例参考"
    }
  }
}
```

### 使用方式

```typescript
// 在 diagnosis-merger.ts 或 training-recommendation.service.ts 中
function getSyndromeType(syndromeId: string): string | null {
  for (const [type, info] of Object.entries(syndromeTypeMap.types)) {
    if (info.syndromes.includes(syndromeId)) return type;
  }
  return null;
}
```

---

## 涉及文件

| 文件 | 操作 | 说明 |
|------|------|------|
| `resources/config/syndrome-type-map.json` | **新建** | 症候→类型映射配置 |
| `src/main/services/training-recommendation.service.ts` | 修改 | 匹配症候类型，影响 trainingMode |
| `src/shared/types.ts` | 修改 | 可选：新增 SyndromeType 类型 |

---

## DoD

| # | 标准 | 验证方式 |
|---|------|---------|
| S1 | syndrome-type-map.json 存在且格式正确，覆盖所有 9 个活跃症候 | 文件可被 JSON.parse，类型分组无遗漏 |
| S2 | training-recommendation.service.ts 能通过 syndromeId 获取其类型 | 单元测试验证 P003 → expressive_deficit |
| S3 | TypeScript 编译 0 错误 | `npx tsc --noEmit` 通过 |

---

## 变更记录

| 日期 | 版本 | 变更内容 |
|------|------|---------|
| 2026-06-06 | V1.0 | 创建 |
