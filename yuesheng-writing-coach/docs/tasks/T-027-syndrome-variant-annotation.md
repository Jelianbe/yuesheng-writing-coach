# T-027: 症候变种标注能力

> **优先级**: P2 | **状态**: ready | **预估**: 1.5d  
> **依赖**: T-022（技法库JSON化完成后再做变种标注更顺畅） | **后续**: 诊断精度迭代（需单独任务）

## 目标

在不破坏现有 P001~P010 症候 ID 体系的前提下，为核心症候增加变种（variant）标注能力。当前症候定义过于扁平——"P001 世界观膨胀"只是一个标签，无法区分"开篇大量设定说明"、"对话中塞入世界观"、"描写场景时突然插入设定解释"等不同表现形式。通过轻量变种标注，让 AI 输出更精确的诊断，让训练更有针对性。

## 设计依据

- **设计依据文档**: [design-philosophy_V1.0.md](../design/design-philosophy_V1.0.md) §第五章「教学诊断体系」
- **关联发现**: system-scan-report_V1.0.md §11.1（症候定义过于扁平，无法区分不同变种）
- **对比方案**: 报告中建议的"核心问题+变种"重构（RC-001~RC-004）经评估暂不执行。本任务为其轻量替代方案
- **不重构的理由**: 当前扁平模型工作正常，完整 RC 重构需要修改 diagnosis-agent-prompt、diagnosis-parser、teaching-state-machine、challenge-templates 全部环节，风险高收益不确定。变种标注是增量改造

## 前后端分工

| 层 | 改动内容 | 涉及文件 |
|----|---------|---------|
| 后端 | Syndrome 类型扩展 variant 字段 | `src/shared/types.ts` |
| 后端 | AI Prompt 中为 3 个核心症候增加变种触发条件 | `resources/prompts/diagnosis-agent-prompt-v1.md` |
| 后端 | diagnosis-parser 解析 variant 字段 | `src/main/services/diagnosis-parser.ts` |
| 数据 | challenge-templates 增加 variant 关联 | `resources/config/challenge-templates.json` |
| 前端 | DiagnosisCard 展示变种标签 | `src/renderer/components/diagnosis/DiagnosisCard.tsx` |
| 前端 | 翻译层增加 variant 的正向表述 | `src/shared/diagnosis-translations.ts` |

## 涉及文件清单

| # | 文件路径 | 操作 | 说明 |
|---|---------|:----:|------|
| 1 | `src/shared/types.ts` | 修改 | Syndrome 接口新增 `variant?: string` |
| 2 | `resources/prompts/diagnosis-agent-prompt-v1.md` | 修改 | P001/P002/P004 各增加 2-3 个变种触发条件，要求 AI 在 syndromeRef 中标注变种（如 "P001::setting_overload"） |
| 3 | `src/main/services/diagnosis-parser.ts` | 修改 | 解析 `syndromeRef` 中的 `::` 分隔符，提取 variant |
| 4 | `resources/config/challenge-templates.json` | 修改 | 选择性增加 variant 层级的微练变体（如 P001 增加 "对话中塞入世界观" 变体的微练描述） |
| 5 | `src/renderer/components/diagnosis/DiagnosisCard.tsx` | 修改 | 症候名称旁展示变种标签，如 "世界观膨胀 · 设定说明型" |
| 6 | `src/shared/diagnosis-translations.ts` | 修改 | 增加 variant 的正向表述翻译 |

## Prompt 修改示例

### P001 世界观膨胀 — 变种定义

在 diagnosis-agent-prompt-v1.md 中将 P001 的触发条件拆分为：

```
P001 世界观膨胀
  variant :: setting_overload（设定超载）：
    开篇 200 字内直接铺陈世界观设定，如种族、地理、历史
    → 原文示例："在这片大陆上，有五个王国..."
  
  variant :: info_in_dialogue（对话塞设定）：
    角色对话中刻意向读者解释世界观信息
    → 原文示例："你知道我们精灵族从来不..."
  
  variant :: setting_interrupt（设定打断）：
    在叙事进行中突然插入设定说明
    → 原文示例："他推开门的瞬间...（矮人族擅长锻造，他们的武器...）"
```

AI 在 syndromeRef 中输出 `"P001::setting_overload"` 而非 `"P001"`。

## 变种标注范围

| 症候 | 变种数量 | 变种说明 |
|------|:--------:|---------|
| P001 世界观膨胀 | 3 | setting_overload / info_in_dialogue / setting_interrupt |
| P002 角色工具人化 | 2 | info_delivery / plot_device |
| P004 信息硬塞 | 2 | exposition_dump / dialogue_explain |
| P003/P005/P006 | 暂不增加 | 维度本身已较具体 |

## DoD（完成标准）

- [ ] S1. 至少 3 个核心症候（P001/P002/P004）拥有 2+ 变种定义，并在 diagnosis-agent-prompt-v1.md 中写入触发条件
- [ ] S2. AI 诊断输出中包含 variant 字段（通过 `P001::setting_overload` 格式传递），diagnosis-parser 正确解析
- [ ] S3. 前端 DiagnosisCard 展示变种标签（如 "世界观膨胀 · 设定说明型"）

## 回退方案

1. Prompt 回退：恢复 diagnosis-agent-prompt-v1.md 的旧症候定义
2. variant 字段向后兼容：parser 遇到无 variant 的旧格式 `"P001"` 时正常解析，不报错
3. 前端降级：variant 为空时不展示标签

## 执行记录

### 改动文件

| 文件 | 改动摘要 |
|------|---------|
| src/renderer/shared/types.ts | SyndromeResult 新增 `variant?: string` |
| src/main/services/diagnosis-parser.ts | `validateSyndromes` 解析 `::` 分隔符提取 variant |
| resources/prompts/diagnosis-agent-prompt-v1.md | P001/P002/P004 变种定义 + 标注格式说明 |
| src/shared/diagnosis-translations.ts | 新增 `VARIANT_TRANSLATIONS` + `getVariantLabel()` |
| src/renderer/components/diagnosis/DiagnosisCard.tsx | 折叠/展开视图均展示变种标签 |

### 验证结果

- [x] TypeScript 编译通过（`npx tsc --noEmit` — 0 错误）
- [x] 测试通过（`npx vitest run` — 455/455, 39 文件）

## 下个任务建议

结合 T-024 的评分数据和 T-027 的变种标注，建立诊断精度追踪。建议下一阶段关注 "同一症候不同变种的训练效果差异分析"。
