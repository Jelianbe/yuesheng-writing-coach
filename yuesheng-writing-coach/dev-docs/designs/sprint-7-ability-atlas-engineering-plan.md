# Sprint 7 — 能力图谱工程化接入

> Issue #14 的实施计划

## 定位

将 `resources/` 下已有但代码层未消费的 3 个核心结构化数据文件通过 TypeScript Loader 接入主进程，打通症候→能力→教学策略的链路，消除诊断引擎和教学引擎中的静态硬编码映射。

## 现状

| 文件 | 数据 | 代码层消费状态 |
|:-----|:-----|:--------------|
| `resources/knowledge-graph/ability-atlas.json` | 8 能力节点 + 10 症候 + 20 训练任务 + 依赖拓扑 | ❌ 未消费 |
| `resources/01-diagnosis/syndromes/syndrome-action-map.json` | 症候→触发模板/教练问题 | ❌ 未消费（标注供 TeachingStrategyRouter 使用） |
| `resources/02-prescription/ability-nodes/ability-node-prototypes.json` | 5 个教学原子节点 | ❌ 未消费 |
| `resources/01-diagnosis/syndromes/syndrome-classical-map.json` | 症候→经典原则 | ❌ 未消费 |
| `resources/config/challenge-templates.json` | 31 个训练模板 | ✅ 已载入 training-recommendation.service.ts |
| `resources/config/technique-library.json` | 技法库 | ✅ 已载入 training-recommendation.service.ts |

### 链路断裂示意图

```
诊断 Agent V2 (prompt 已写 abilityNode 格式)
    ↓
诊断解析器 (DiagnosisParser)
    ↓     需要从 ability-atlas.json 获取症候→能力映射
症候动作映射 (syndrome-action-map.json)
    ↓     需要载入 TeachingStrategyRouter
教学策略路由 (TeachingStrategyRouter Layer 1/2/3)
    ↓
训练推荐 (TrainingRecommendationService)
        只需要从 ability-atlas.json 补充能力节点元数据
```

## 实施范围

### 1. 能力图谱 Loader（新增）

**路径**：`src/main/domains/02-prescription/ability-atlas/ability-atlas.loader.ts`

**职责**：读取 `ability-atlas.json` + `ability-node-prototypes.json`，提供类型化查询接口。

```typescript
// 公开查询方法
interface AbilityAtlasLoader {
  /** 按症候 ID 查询相关能力节点 */
  getAbilitiesBySyndrome(syndromeId: string): AbilityNode[];
  /** 按能力节点 ID 查询训练任务 */
  getTrainingTasksByAbility(abilityId: string): TrainingTask[];
  /** 按能力节点 ID 查询前置依赖 */
  getPrerequisites(abilityId: string): string[];
  /** 按症候 ID 查询症候详情 */
  getSyndrome(syndromeId: string): Syndrome | undefined;
  /** 获取能力依赖拓扑（有向图） */
  getDependencyGraph(): Map<string, string[]>;
  /** 获取能力节点 ID → 教学节点的映射（ABL-XXX → AB-XXX） */
  getAbilityNodeMapping(): Map<string, string>;
  /** 重新加载（JSON 文件变动时调用） */
  reload(): void;
}
```

**内部结构**：
- 惰性加载：首次使用时读取 JSON，加载后缓存
- 热更新：通过 `fs.watchFile` 监听 JSON 变动
- 类型安全：所有返回数据通过 TypeScript 接口约束
- 文件路径通过 `app.getAppPath()` 或相对路径解析

**不引入**：
- 数据库层（当前 JSON 足够，不需要 SQLite）
- 循环依赖（Loader 独立，不依赖其他服务模块）

### 2. 症候动作映射接入（修改）

**文件**：`src/main/domains/02-prescription/strategy/router.ts`

**变更**：
- 在 `router.ts` 的配置加载中新增 `syndrome-action-map.json` 的导入
- 在 Layer 1（聚焦症候选择 `selectFocusSyndrome`）后，用 action-map 的 `triggerTemplate` 和 `coachingQuestion` 填充教学策略
- 扩展 `RouterOutput` 类型（在 `router.types.ts` 中），增加 `triggerTemplate` / `coachingQuestion` 字段

```
当前：RouterOutput = { focusSyndrome, teachingMode, ... }
新增：RouterOutput = { focusSyndrome, teachingMode, triggerTemplate, coachingQuestion, ... }
```

**注意事项**：
- syndrome-action-map.json 中部分症候的 `discoverable` 为 `false`（P004/P006/P007），应作为教学策略的提示，而非硬性过滤
- 保持向后兼容：现有测试不破坏

### 3. 训练推荐链路增强（修改）

**文件**：`src/main/domains/04-validation/training/training-recommendation.service.ts`

**变更**：
- 在现有 `challengeTemplates` 映射基础上，从能力图谱 Loader 获取 `training_tasks` 元数据
- 推荐结果 `TrainingRecommendation` 类型增加字段：
  - `abilityNodeIds: string[]` — 相关能力节点
  - `difficulty: number` — 难度级别
  - `prerequisites: string[]` — 前置能力
- 当 `abilityNodeIds` 有数据时，推荐优先级按依赖拓扑排序（先基础能力再进阶能力）

### 4. 诊断输出扩展（修改）

**文件**：`src/main/domains/01-diagnosis/diagnosis-parser.ts`

**变更**：
- 诊断解析完成后，从能力图谱 Loader 查询每个症候对应的能力节点
- 在诊断输出（`DiagnosisEntry` 或诊断结果类型）中填充 `abilityNode` 字段
- 格式：`{ id: "ABL-001", name: "结构控制", focus: "信息密度控制、节奏管理、章节结构" }`

**注意**：
- Diagnosis Agent V2 prompt 已写入 `abilityNode` 格式（teaching-agent-prompt-v2.md 第 26-30 行消费此字段）
- 但代码层从未实际填充此数据，导致 Teaching Agent 收到的 diagnosis 结果中 `abilityNode` 为 undefined
- 本次仅填充能力图谱数据，不修改 Diagnosis Agent prompt 本身

## 不涉及

| 项目 | 理由 |
|:-----|:------|
| 训练任务内容重构 | Sprint 8（训练体系） |
| 七阶段发展路径工程化 | Sprint 8+ |
| 蒸馏素材工程化 | 后续 Sprint |
| UI 改动 | 纯后端工程化 |
| Diagnosis Agent prompt 修改 | 只补代码层，不改 prompt |
| 能力节点原型 AB-001~005 的产出 | 数据已有，Loader 只需读取 |

## 文件变更清单

| 文件 | 改动量 | 操作 | 说明 |
|:-----|:------:|:----:|:------|
| `src/main/domains/02-prescription/ability-atlas/ability-atlas.loader.ts` | ~120 行 | 新增 | 能力图谱 Loader |
| `src/main/domains/02-prescription/ability-atlas/ability-atlas.types.ts` | ~40 行 | 新增 | Loader 内部类型 |
| `src/main/domains/02-prescription/strategy/router.ts` | ~20 行 | 修改 | 加载 action-map，扩展 RouterOutput |
| `src/main/domains/02-prescription/strategy/router.types.ts` | ~10 行 | 修改 | 增加 triggerTemplate/coachingQuestion |
| `src/main/domains/04-validation/training/training-recommendation.service.ts` | ~30 行 | 修改 | 补充能力节点元数据 |
| `src/main/domains/01-diagnosis/diagnosis-parser.ts` | ~15 行 | 修改 | 填充 abilityNode 字段 |
| `src/main/domains/02-prescription/ability-atlas/__tests__/ability-atlas.loader.test.ts` | ~80 行 | 新增 | Loader 单元测试 |
| **合计** | **~315 行** | | |

## 依赖关系

```
ability-atlas.loader.ts (新增)
    ↑ 读取
ability-atlas.json + ability-node-prototypes.json

    ↓ 注入
router.ts ──────────────────── diagnosis-parser.ts
    ↓ (syndrome-action-map)       ↓ (abilityNode 字段)
Layer 1/2/3 decision             DiagnosisEntry
    ↓
training-recommendation.service.ts (能力节点元数据补充)
```

## 风险评估

| 风险 | 概率 | 影响 | 应对 |
|:-----|:----:|:----:|:------|
| JSON 路径在打包后失效 | 中 | 高 | 使用 `app.getAppPath()` 而非相对路径，添加路径存在检查 |
| ABL-XXX / AB-XXX 两套 ID 体系混淆 | 高 | 中 | Loader 中通过 `getAbilityNodeMapping()` 显式映射 |
| 现有测试因 RouterOutput 扩展而破坏 | 低 | 中 | 扩展字段为可选，不破坏现有断言 |
| 热更新导致竞态 | 低 | 低 | 惰性加载 + 重新加载前清空缓存 |

## DoD

- [ ] 能力图谱 Loader 通过单元测试（按症候查询、按能力查询、依赖拓扑、节点映射）
- [ ] TeachingStrategyRouter 的 RouterOutput 包含 triggerTemplate/coachingQuestion
- [ ] TrainingRecommendationService 推荐结果包含能力节点元数据（abilityNodeIds, difficulty, prerequisites）
- [ ] DiagnosisParser 输出的诊断结果包含 abilityNode 字段
- [ ] Typecheck 0 errors
- [ ] 既有测试全绿（`npm run test --run`）
- [ ] Lint 0 errors（`npm run lint`）
