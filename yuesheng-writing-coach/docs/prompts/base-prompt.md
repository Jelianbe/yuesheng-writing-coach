# Base Prompt — 月笙核心系统 Prompt

> V2-PROMPT-001 文档制品 | 对应代码：`resources/prompts/yuesheng-prompt-v3.md` + `prompt-loader.ts` 三段式组装

## 定义

Base Prompt 是月笙写作教练的核心身份定义 —— 定义"月笙是谁"以及"月笙如何教学"。它不是单一文件，而是由 **prompt-loader.ts** 在运行时三阶段动态组装的结果。

## 物理来源：yuesheng-prompt-v3.md

**文件**：`resources/prompts/yuesheng-prompt-v3.md`（当前 V3.5）

分为三个层次：

| 层次 | 内容 | 装载策略 |
|------|------|---------|
| **L1 身份层**（铁三角） | 倾听优先 · 教练定位 · 找根因 | 始终装载（核心层） |
| **L2 知识层**（教学策略） | 教学铁律 · 三阶段流程 · 态度档位 · 场景索引 · 回复控制 | 始终装载（核心层） |
| **L3 画像层**（动态注入） | `{student_context}` 占位符 | 运行时由 DynamicContextService 注入 |

## 三段式组装模型（prompt-loader.ts）

`prompt-loader.ts` 的 `loadSystemPrompt()` 方法（第 153 行）负责最终组装：

```
┌─────────────────────────────────────────────────────────────┐
│ 第1段：核心层（始终装载）                                      │
│ 来自 DynamicContextService.loadContext()                     │
│  ├── yuesheng-prompt-v3.md 中的 L1+L2 部分（铁三角+教学原则）    │
│  └── L3 占位符 {student_context} → 运行时替换为当前学生状态      │
├─────────────────────────────────────────────────────────────┤
│ 第2段：按需层（参考抽屉）                                      │
│ 来自 DynamicContextService.formatReferenceDrawer()           │
│  ├── 活跃症候的手册片段（syndrome-manual.md 的对应条目）         │
│  └── 关联动作库片段（action-library.md 的对应条目）              │
├─────────────────────────────────────────────────────────────┤
│ 第3段：上下文层（动态注入）                                     │
│  ├── 3a. 诊断增强（buildDiagnosisEnhancement → 见 diagnosis-augment.md）│
│  ├── 3b. 历史诊断摘要（PromptBuilder.updateDiagnosisSummary）  │
│  ├── 3c. 教学进度（PromptBuilder.buildSystemPrompt 当前阶段）   │
│  ├── 3d. Codex 结构化知识（按需注入）                          │
│  └── 3e. 语气修饰（toneModifier，根据 attitude 参数调整）       │
└─────────────────────────────────────────────────────────────┘
```

## 数据流

```
yuesheng-prompt-v3.md (L1+L2)
    │
    ▼
DynamicContextService.loadCorePrompt()
    │  提取铁三角部分（~500 字）
    │  替换 {student_context} 占位符
    ▼
prompt-loader.ts.loadSystemPrompt()
    │  三段式组装
    │  拼接诊断增强、教学进度、语气等
    ▼
chat.handler.ts / teaching.handler.ts
    │  注入给 AI 模型
    ▼
AI 输出（教学对话）
```

## 降级策略

当 `DynamicContextService` 不可用时（prompt-loader 第 186 行），退化为全量 V3 Prompt 加载：

```typescript
let basePrompt = this.readPrompt('yuesheng-prompt-v3.md', FALLBACK);
basePrompt = basePrompt.replace('{student_context}', studentContext || '暂无学生状态数据。');
```

其中 `FALLBACK` 为：`你是一个专业的写作教练月笙，帮助用户提升写作水平。`

## 关键依赖

| 依赖 | 用途 | 位置 |
|------|------|------|
| `yuesheng-prompt-v3.md` | 核心身份文本 | `resources/prompts/` |
| `DynamicContextService` | 核心层注入 + 按需层索引 | `src/main/services/dynamic-context.service.ts` |
| `prompt-loader.ts` | 三段式组装引擎 | `src/main/services/prompt-loader.ts:153` |
| `PromptBuilder` | 上下文层组装（进度+策略） | `src/main/services/prompt-builder.ts` |
| `diagnosis-merger.service.ts` | 诊断增强的原始输入 | `src/main/services/diagnosis-merger.service.ts` |

## 变更记录

| 版本 | 日期 | 变更 | 依据 |
|------|------|------|------|
| V1.0 | 2026-06-09 | 初始文档，记录 V3.5 架构 | V2-PROMPT-001 审查 |
