# T-022: 技法库 JSON 化与系统接入

> **优先级**: P0 | **状态**: done | **预估**: 2d
> **依赖**: — | **后续**: T-024（训练效果评分）、T-027（症候变种标注）

## 目标

将 docs/teaching/technique-library/ 中的 34 条技法从 Markdown 文档转为系统可用的 JSON 配置文件，消除 diagnosis-agent-prompt-v1.md 中的技法硬编码，打通「诊断 → 技法推荐 → 训练」的完整链路。

## 设计依据

- **设计依据文档**: [design-philosophy_V1.0.md](../design/design-philosophy_V1.0.md) §第四章「Prompt逆向工程」、§第八章「能力图谱」
- **技术规格**: [SPEC_Technique_Invocation_V1.md](../specs/SPEC_Technique_Invocation_V1.md)
- **关联发现**: system-scan-report_V1.0.md §5.2（技法库仅文档存在，未被系统使用）、§12.1（技法蒸馏的正确处理方式）
- **来源任务**: T-021（训练入口完成后，训练方案需要技法库支撑）
- **已有资源**: docs/teaching/technique-library/ 下 5 个技法文档，共 34 条技法（TQ-001~TQ-024 + TC-001~TC-010）

## 前后端分工

| 层 | 改动内容 | 涉及文件 |
|----|---------|---------|
| 数据/配置 | 技法库从 Markdown 转为 technique-library.json | `resources/config/technique-library.json` |
| 后端 | diagnosis-agent-prompt-v1.md 删除硬编码技法列表，改为占位符 | `resources/prompts/diagnosis-agent-prompt-v1.md` |
| 后端 | prompt-builder.ts 在构建 Agent Prompt 时从 JSON 动态注入技法列表 | `src/main/services/prompt-builder.ts` |
| 后端 | training-recommendation.service.ts 在推荐中附加 matchingTechniques | `src/main/services/training-recommendation.service.ts` |
| 前端 | TrainingWorkshop 展示 "参考技法" 区块 | `src/renderer/components/training/TrainingWorkshop.tsx` |

## 涉及文件清单

| # | 文件路径 | 操作 | 说明 |
|---|---------|:----:|------|
| 1 | `resources/config/technique-library.json` | **新增** | 34 条技法完整 JSON，每条含 id/name/source/difficulty/category/applicableSyndromes/description/example |
| 2 | `resources/prompts/diagnosis-agent-prompt-v1.md` | 修改 | 删除 Step 3 的技法硬编码列表，替换为占位符 `{{technique_pool}}` |
| 3 | `src/main/services/prompt-builder.ts` | 修改 | buildAgentPrompt() 中加载 technique-library.json 并注入技法列表 |
| 4 | `src/main/services/training-recommendation.service.ts` | 修改 | generateRecommendations() 中为每个推荐附加 matchingTechniques（按 syndromeId 匹配） |
| 5 | `src/renderer/components/training/TrainingWorkshop.tsx` | 修改 | 训练步骤卡片底部新增 "参考技法" 区块 |
| 6 | `src/renderer/shared/types.ts` | 修改 | 新增 TechniqueInfo 类型，TrainingRecommendation 增加 techniques 字段 |

## 技法 JSON 结构定义

```typescript
interface Technique {
  id: string;                    // TQ-001 ~ TQ-024, TC-001 ~ TC-010
  name: string;                  // 技法名，如 "三词递进开篇"
  source: string;                // 来源小说，如 "诡秘之主"
  difficulty: 'beginner' | 'intermediate' | 'advanced';
  category: string;              // "开篇" | "节奏" | "人物" | "世界观" | "对话"
  applicableSyndromes: string[]; // ["P001"], ["P002", "P009"] 等
  description: string;          // 简述技法是什么
  example: string;              // 原文示例
  exercise: string;             // 可执行的练习引导
}
```

## DoD（完成标准）

- [x] S1. `resources/config/technique-library.json` 包含全部 34 条技法，每条含完整的 id/name/source/difficulty/category/applicableSyndromes/description/example 字段
- [x] S2. `diagnosis-agent-prompt-v1.md` 的 Step 3 技法匹配中不再出现硬编码技法名称列表，改为 `{{technique_pool}}` 运行时注入
- [x] S3. 对 P001 症候的诊断结果，techniquePool 中的技法数据来自 JSON 而非硬编码

## 回退方案

1. `diagnosis-agent-prompt-v1.md` 保留硬编码列表作为运行时注入失败的 fallback
2. JSON 文件语法错误时不影响启动（prompt-builder 捕获异常后回退到硬编码列表）

## 执行记录

### 改动文件（实际完成时填写）

| 文件 | 改动摘要 |
|------|---------|
| `resources/config/technique-library.json` | 新增：34条技法完整JSON（TQ-001~TQ-024 + TC-001~TC-009 + TN-001） |
| `resources/prompts/diagnosis-agent-prompt-v1.md` | Step 2.5/2.6/2.7/第三步 硬编码技法列表替换为 {{technique_pool}} 占位符 |
| `src/main/ipc/chat.handler.ts` | 新增 `injectTechniquePool()` 函数，加载 JSON 并替换占位符（懒加载+缓存） |
| `src/main/services/training-recommendation.service.ts` | 新增 `matchTechniques()` 函数，推荐中附加 techniques 字段（最多3条） |
| `src/renderer/shared/types.ts` | 新增 `TechniqueInfo` 类型，`TrainingRecommendation` 增加 `techniques?` 字段 |
| `src/renderer/components/training/RecommendationsSection.tsx` | 推荐卡片底部新增"参考技法"区块 |

### 验证结果（实际完成时填写）

- [x] TypeScript 编译通过（`npx tsc --noEmit`）
- [x] 测试通过（439 passed, 38 files）

## 下个任务建议

T-024（训练效果评分）或 T-027（症候变种标注），两者均依赖 T-022 提供的技法库。建议先做 T-024 形成「诊断→训练→评分」闭环。
