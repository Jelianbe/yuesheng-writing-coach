# 会话5提示词：症候类型分类

## 项目背景

月笙写作教练的 AI 诊断系统定义了 9 个写作症候（P001~P010，P008 已合并）。教育学习蒸馏产出将症候分为三个类型——expressive_deficit（展示力不足型）、structural_disorder（结构/视角失控型）、motivation_deficit（动机/意图缺失型）——不同类型的症候需要不同的教学入口。

目前这个分类仅存在于教育学蒸馏文档中，系统代码不知道这些分类。T-031（教育学规则接入）依赖此分类作为规则条件，因此需要先建立这个配置。

## 任务

创建 `syndrome-type-map.json` 配置文件，让系统能够根据症候 ID 查询其所属类型。

## 必须读取的文件

**参考文件：**
1. `resources/config/syndrome-type-map.json` — **待新建**，目标文件
2. `resources/config/education-theory-fragments.json` — 教育规则配置（参考规则 R-004/R-005/R-006 的类型定义）
3. `docs/research/education-theory-distillation_V1.0.md` — §4.1 症候类型分类的定义
4. `src/renderer/shared/types.ts` — TechniqueInfo 接口所在（新增 SyndromeType 类型）
5. `src/main/services/training-recommendation.service.ts` — 需新增 getSyndromeType() 函数

## 症候类型分类（来自教育学蒸馏）

| 类型 | 包含症候 | 核心特征 | 推荐教学入口 |
|------|---------|---------|------------|
| expressive_deficit | P003, P010, P002 | 有感受但写不出 | 先案例再模仿 |
| structural_disorder | P005, P006, P004 | 有能力但缺觉察 | 先反思再练习 |
| motivation_deficit | P009, P001 | 缺内在驱动 | 先提问再案例 |

注意：P007（阅读结构单一）未被教育学蒸馏明确分类。它属于"有能力但缺觉察"（用户能写但结构单一），归入 **structural_disorder**。

## 执行步骤

### Step 1：创建 syndrome-type-map.json

在 `resources/config/syndrome-type-map.json` 创建配置文件：

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
      "syndromes": ["P005", "P006", "P004", "P007"],
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

注意 P007 归入 structural_disorder（在原始教育学蒸馏中未明确分类，根据综合征候特征判断）。

### Step 2：更新 types.ts

在 `src/renderer/shared/types.ts` 中新增 `SyndromeType` 类型。可以追加在 `TechniqueInfo` 接口之后：

```typescript
/** 症候类型分类（V6.0新增，用于教育学规则匹配） */
export type SyndromeType = 'expressive_deficit' | 'structural_disorder' | 'motivation_deficit';
```

### Step 3：更新 training-recommendation.service.ts

在 `src/main/services/training-recommendation.service.ts` 中：

1. 在文件顶部导入 `syndrome-type-map.json`，使用 `require` 或 `fs.readFileSync`（参考项目中其他配置文件的加载方式）

2. 新增 `getSyndromeType()` 函数：

```typescript
/** 获取症候所属类型（用于教育学规则匹配） */
function getSyndromeType(syndromeId: string): string | null {
  const typeMap = require('../../resources/config/syndrome-type-map.json') as any;
  for (const [type, info] of Object.entries(typeMap.types)) {
    if ((info as any).syndromes.includes(syndromeId)) return type;
  }
  return null;
}
```

3. 在现有的 `matchTechniques()` 函数中，返回结果时携带类型信息：

```typescript
// 在 matchTechniques() 的返回对象中追加
syndromeType: getSyndromeType(syndromeId),
```

## 休止符条件

| 条件 | 说明 |
|:----:|------|
| ✅ syndrome-type-map.json 已创建 | 覆盖全部 9 个活跃症候（P001~P010，P008 已合并）|
| ✅ types.ts 已新增 SyndromeType 类型 | |
| ✅ training-recommendation.service.ts 已新增 getSyndromeType() | 函数可按症候 ID 查询类型 |
| ✅ npx tsc --noEmit 通过 | |

## 输出物

在**工作区**直接修改文件物理内容：

| 文件 | 操作 |
|------|------|
| `resources/config/syndrome-type-map.json` | **新建** |
| `src/renderer/shared/types.ts` | 修改（追加 SyndromeType 类型）|
| `src/main/services/training-recommendation.service.ts` | 修改（追加 getSyndromeType + 调用）|

改完运行 `npx tsc --noEmit` 确认编译通过，然后返回确认。

## 重要

- syndrome-type-map.json 不要引用 education-theory-fragments.json，两者是独立配置
- getSyndromeType() 用懒加载方式加载 JSON（第一次调用时读取），参考项目中已有的配置加载模式
- P007 归类到 structural_disorder，在注释中注明"教育学蒸馏未明确分类，根据症候特征判断" 
