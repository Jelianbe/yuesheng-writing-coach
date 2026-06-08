# Diagnosis Augment — 诊断增强注入

> V2-PROMPT-001 文档制品 | 对应代码：`prompt-loader.ts` `buildDiagnosisEnhancement()` + `diagnosis-agent-prompt-v1.md`

## 定义

Diagnosis Augment（诊断增强）是三段式组装模型中**上下文层的第 3a 段**。它将 Diagnosis Agent 产出的结构化 JSON 分析结果翻译为教学指引文本，注入到 System Prompt 中，让 AI 模型在回复时聚焦根因治疗。

## 数据流

```
用户文本（小说章节）
    │
    ▼
diagnosis-agent-prompt-v1.md（诊断 Agent）
    │  输出：结构化 JSON
    │  { rootCause, intentPhase, syndromeRef, keyPassages, techniquePool, confidence }
    ▼
diagnosis-merger.service.ts（诊断合并服务）
    │  合并多轮诊断结果
    │  校验 syndromeRef 合法性
    │  过滤内部编号（V2-PROMPT-001 Layer 1 铁律）
    ▼
prompt-loader.ts.buildDiagnosisEnhancement()
    │  将 JSON → 格式化文本块
    ▼
prompt-loader.ts.loadSystemPrompt() 第 3a 段
    │  注入 System Prompt
    ▼
AI 模型（教学对话）
```

## Diagnosis Agent（诊断 Agent）

**文件**：`resources/prompts/diagnosis-agent-prompt-v1.md`（V1.2）

一个独立的 Agent，不跟用户对话，只输出结构化 JSON。核心职责：

1. **内容类型判断**：判断输入是 narrative（叙事文本）还是 non-narrative（非叙事文本）
2. **症候检测**：检测 P001~P006、H001/H002、E001、I001~I006 等症候
3. **V3.3 诊断维度扩展**：动词风格 · 角色行为 · 设定执行
4. **技法匹配**：从 `technique-library.json` 中匹配合适的技法
5. **输出 JSON**：包含 rootCause、intentPhase、syndromeRef、techniquePool、keyPassages

## 诊断增强构建（buildDiagnosisEnhancement）

**位置**：`src/main/services/prompt-loader.ts:255-301`

将 `DiagnosisAnalysis` 对象翻译为以下格式的文本块：

```markdown
---
## 当前诊断结果（本轮触发）

**根因分析**：{rootCause}
**意图阶段**：{intentPhase}
**识别到的症候**：
- {syndromeName}（{severity}）
**关键段落**：
- {原文片段} → {问题描述}
**建议技法**（按需调用）：
- {技法名}（来源：{作品}，难度：{难度}）
---
请基于以上诊断结果，在回复中聚焦根因治疗，使用场景快速索引中的对应规则。
```

### 构建规则

| 字段 | 来源 | 处理逻辑 |
|------|------|---------|
| `rootCause` | DiagnosisAnalysis.rootCause | 不超过 20 字的根因摘要 |
| `intentPhase` | DiagnosisAnalysis.intentPhase | 0/1/2 三阶段意图标识 |
| `syndromeRef` | DiagnosisAnalysis.syndromeRef | 翻译为症候名称 + 严重度，经由 SYNDROME_NAMES + SYNDROME_META |
| `keyPassages` | DiagnosisAnalysis.keyPassages | 最多显示 3 条，每条标注原文和问题 |
| `techniquePool` | DiagnosisAnalysis.techniquePool | 显示技法名、来源作品和难度等级 |

## 关键依赖

| 依赖 | 用途 | 位置 |
|------|------|------|
| `diagnosis-agent-prompt-v1.md` | 诊断 Agent 行为定义 | `resources/prompts/` |
| `diagnosis-merger.service.ts` | 合并多轮诊断、过滤内部编号 | `src/main/services/` |
| `prompt-loader.ts:buildDiagnosisEnhancement()` | JSON→文本转换 | `src/main/services/prompt-loader.ts:255` |
| `prompt-loader.ts:loadSystemPrompt()` | 注入到 System Prompt 第 3a 段 | `src/main/services/prompt-loader.ts:193` |
| `technique-library.json` | 技法池数据源 | `resources/config/` |

## 变更记录

| 版本 | 日期 | 变更 | 依据 |
|------|------|------|------|
| V1.0 | 2026-06-09 | 初始文档，记录 V1.2 诊断增强架构 | V2-PROMPT-001 审查 |
