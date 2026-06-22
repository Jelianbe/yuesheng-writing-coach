# ADR-003: AI 读写总览（Reading & Writing Pipeline）

> 状态: **提议 (Proposed)** · 2026-06-22
> 决策者: 月笙
> 关联: [ADR-001](001-stream-pipeline.md) · [ADR-002](002-workspace-registry.md)
> 前置: Sprint 9 全面审计（32 项）+ R-030 反馈处理工作流

## 背景 (Context)

月笙写作教练的核心教学链路是 **"用户作品 → 发现问题 → 解释原因 → 制定训练 → 执行训练 → 验证进步 → 形成能力"**。AI 在其中承担两件事：

- **读 (Reading)**：从用户作品中抽取证据、识别症候、定位根因
- **写 (Writing)**：把训练稿、修改建议、评估反馈写回用户作品或对话

Sprint 9 审计发现"读"和"写"这两条链路**没有全局设计文档**，导致：

1. 关键证据无法溯源（keyPassage 缺少 offset / fragment_id）
2. 占位符风格混乱（`{{}}` 与 `{}` 混用）
3. 长文直接传入 prompt，无截断/分段
4. 写回协议（X-02）实现存在但无正式 ADR
5. 新人 onboarding 困难（25 个 store + 3 个 prompt 缺导航）

**本 ADR 目标**：为后续所有 AI 读写改动（B/C/D/E）提供统一基线，**不在本 ADR 实施**。实施拆为后续 Sprint 卡片。

## 现状 (Current State)

### 1. 真实服务与 Store 骨架

`src/renderer/services/` 实际只有 **9 个文件**（不是 100+）：

| 文件 | 职责 |
|:-----|:-----|
| [ipc-client.ts](../../../yuesheng-writing-coach/src/renderer/services/ipc-client.ts) | 类型化 IPC 客户端（统一入口） |
| [diagnosis.service.ts](../../../yuesheng-writing-coach/src/renderer/services/diagnosis.service.ts) | 诊断服务封装 |
| [training.service.ts](../../../yuesheng-writing-coach/src/renderer/services/training.service.ts) | 训练评估封装 |
| [teaching-state.service.ts](../../../yuesheng-writing-coach/src/renderer/services/teaching-state.service.ts) | 教学状态机 |
| [student-context.service.ts](../../../yuesheng-writing-coach/src/renderer/services/student-context.service.ts) | 学生上下文（PromptBuilder 雏形） |
| [session.service.ts](../../../yuesheng-writing-coach/src/renderer/services/session.service.ts) | 会话管理 |
| [chat.service.ts](../../../yuesheng-writing-coach/src/renderer/services/chat.service.ts) | 对话流（流式输出） |
| [app-controller.ts](../../../yuesheng-writing-coach/src/renderer/services/app-controller.ts) | IPC 编排 + 状态桥接 |
| [useAppController.ts](../../../yuesheng-writing-coach/src/renderer/services/useAppController.ts) | 控制器 hook |

> **重要**：项目记忆曾提到"PromptBuilder 必须集成"，实际 `prompt-builder.ts` **不存在**。
> 当前能力**散落在** [prompt-loader.ts](../../../yuesheng-writing-coach/src/main/domains/03-teaching/prompt/prompt-loader.ts)（主进程）、[student-context.service.ts](../../../yuesheng-writing-coach/src/renderer/services/student-context.service.ts)（渲染进程）、[app-controller.ts](../../../yuesheng-writing-coach/src/renderer/services/app-controller.ts)（编排）。

### 2. 读链路 (Reading Pipeline)

```
用户作品 (manuscript / chapter)
  ↓ chapter.store.loadContent(id) + contentCache
  ↓ IPC: CHAPTER_GET
章节内容 (纯文本)
  ↓ 调用方决定切片范围 (chapter / paragraph / window)
切片文本 → AI 消费链
  ↓ 4 个 context-builder
诊断 / 训练 / 教学 / 评估 Prompt
  ↓ 占位符注入
LLM 推理
  ↓ 输出 JSON (含 keyPassage / errorCard / recommendation)
诊断 / 训练结果 → store 持久化
  ↓ evidence 字段
UI 展示
```

**关键数据源**：
- [chapter.store.ts](../../../yuesheng-writing-coach/src/renderer/stores/chapter.store.ts) — 章节列表 + 缓存
- [manuscript.store.ts](../../../yuesheng-writing-coach/src/renderer/stores/manuscript.store.ts) — 作品元数据

**关键问题**：

| ID | 问题 | 位置 | 影响 |
|:---|:-----|:-----|:-----|
| R-01 | keyPassage 无 offset / chapterId / fragment_id | [types-diagnosis.ts](../../../yuesheng-writing-coach/src/shared/types-diagnosis.ts) | 用户看不到 AI 引用的是哪段 |
| R-02 | 长章节直接传入 prompt，无 chunking/截断 | prompt-loader.ts | 超出 token 限制的章节会丢信息 |
| R-03 | 占位符风格不统一（`{{}}` vs `{}`） | 3 个 prompt 文件 | 维护混乱，注入器分支处理 |

### 3. 写链路 (Writing Pipeline)

#### 路径 A：诊断修改回写（评估反馈，不写回章节）

```
[ChatView 诊断卡片"改写"]
  → useDiagnosisFlow.submitRewrite(text)    [useDiagnosisFlow.ts:84]
    → IPC: diagnosis:submitRewrite
    → 后端: 评分 + 反馈 (RewriteEvaluation)
  → 显示评估卡片（不写回章节正文）
```

#### 路径 B：X-02 训练稿写回编辑器（**核心写回路径**）

```
[TrainingWorkshop 按钮"发送到编辑器"]
  → training.store.sendToEditor()              [training.store.ts:120]
    → chapter.store.pendingRewrite = draft     [跨 store setState]
[ManuscriptPanel 横幅]
  → 用户点"应用"（**先确认后写**）
    → chapter.store.applyRewrite()             [chapter.store.ts:210]
      → IPC: chapter:updateContent             [持久化]
      → contentCache 失效
      → pendingRewrite = null
```

**✅ 设计原则**：3 段式（暂存 → 确认 → 落库），避免静默覆盖。

**关键问题**：

| ID | 问题 | 影响 |
|:---|:-----|:-----|
| W-01 | `pendingRewrite → applyRewrite` 无事务保护 | 跨 store 状态切换，IPC 失败时可能留下半态 |
| W-02 | 无 ADR 正式记录 X-02 协议 | 新人不知道为什么要 3 段式 |

### 4. 占位符现状

| 风格 | 占位符 | 在哪 | 注入器位置 |
|:-----|:-------|:-----|:-----------|
| `{{xxx}}` 双花 | `{{technique_pool}}` | [diagnosis-agent-prompt-v1.md](../../../yuesheng-writing-coach/resources/prompts/diagnosis-agent-prompt-v1.md) | [technique-pool.service.ts:87](../../../yuesheng-writing-coach/src/main/domains/02-prescription/technique-pool.service.ts#L87) |
| `{xxx}` 单花 | `{originalQuote}` `{userDraft}` `{constraint}` `{challengeDescription}` | [training-evaluator-prompt-v1.md](../../../yuesheng-writing-coach/resources/prompts/training-evaluator-prompt-v1.md) | [training-evaluator.service.ts:74](../../../yuesheng-writing-coach/src/main/domains/04-validation/training/training-evaluator.service.ts#L74) |
| `{xxx}` 单花 | `{student_context}` | [yuesheng-prompt-v3.md](../../../yuesheng-writing-coach/resources/prompts/yuesheng-prompt-v3.md) | [prompt-loader.ts:193](../../../yuesheng-writing-coach/src/main/domains/03-teaching/prompt/prompt-loader.ts#L193) |

**风格不统一导致**：
- 注入器代码分支处理（[string-replace] vs [string-replace]）
- 维护时容易混淆
- 未来做统一的 Linter / Validator 困难

## 决策驱动 (Decision Drivers)

- **核心价值 (R-005)**：用户能看到 AI 引用的原文段（不替写、找根因）
- **类型安全 (R-019)**：所有改动 typecheck 零错误
- **最小变更 (R-021)**：本 ADR 只立基线，**不实施**任何代码改动
- **可测试 (R-013)**：新逻辑可单测
- **Prompt 治理 (R-025, R-026)**：占位符规范、模板结构统一
- **可回滚 (R-006)**：后续 Sprint 卡片各自独立 commit

## 候选方案 (Considered Options)

### 占位符风格统一

#### 选项 A：统一为 `{{xxx}}` 双花（**推荐**）

**理由**：
- 与 Mustache / Handlebars / Vue / Angular 等主流模板系统一致
- 与 Markdown 兼容性更好（单花在 markdown 中常被解释为变量）
- 诊断 prompt 已使用 `{{}}`，迁移成本低（2 个文件）
- 未来加 Linter 规则更自然

#### 选项 B：统一为 `{xxx}` 单花

**理由**：
- 字数更少
- 主 prompt 和评估 prompt 已使用

**不采用**：与诊断 prompt 不一致，迁移成本高。

#### 选项 C：保持现状

**不采用**：风格混乱是技术债。

### 长度限制策略

#### 选项 A：先 hard-cap + warn，**不做 chunking**（**推荐 Sprint 10**）

**做法**：
- 在 [prompt-loader.ts](../../../yuesheng-writing-coach/src/main/domains/03-teaching/prompt/prompt-loader.ts) 加长度检查
- 超过 `MAX_CHARS`（如 8000）→ 截断 + 注入告警块 `[已截断，原文 XXX 字]`
- 后续 Sprint 评估是否需要 chunking

**理由**：
- 当前章节平均长度可能未到爆 token 规模
- chunking 改动涉及 RAG-like 检索，过早优化风险
- 截断 + 告警是最小可回滚方案

#### 选项 B：实现滑动窗口 chunking

**不采用**：过早优化。需先观察实际章节长度分布。

### 证据溯源 schema

#### 选项 A：扩展 keyPassage 加 `chapterId` + `startOffset` + `endOffset`（**推荐 Sprint 10**）

**理由**：
- offset 是文本位置最直接的可计算证据
- 不依赖额外 LLM 输出 fragment_id
- 验证逻辑简单（offset 在 `[0, content.length)` 范围内）
- UI 可用 `<mark>` 高亮原文对应位置

#### 选项 B：只加 `fragmentId`（后端生成）

**不采用**：增加后端复杂度，且对溯源目标价值有限。

## 决策 (Decision)

**本 ADR 接受 3 个总览决策**（仅文档化，不实施代码改动）：

1. **占位符统一为 `{{xxx}}` 双花**（后续 Sprint 实施）
2. **长度限制先 hard-cap + warn，不做 chunking**（后续 Sprint 实施）
3. **keyPassage 扩展为 `{text, chapterId, startOffset, endOffset, syndromeRef}`**（后续 Sprint 实施）

**本 ADR 拒绝的内容**：
- 不创建新的 `PromptBuilder.ts`（项目记忆曾提及，但当前能力已散落在 3 个 service 中，抽取为统一类的 ROI 不高）
- 不做 chunking（RAG 改造）
- 不动 IPC 通道（写回路径已稳定）

## 实施细节 (Implementation Plan)

### 本 ADR 不实施任何代码改动

**仅作为后续 Sprint 卡片的基线**。后续卡片清单：

### Sprint 10 推荐卡片

#### B. 证据溯源增强（**最高优先级**）

| 子任务 | 改动文件 | 风险 |
|:-------|:---------|:-----|
| B-1: 扩展 [types-diagnosis.ts](../../../yuesheng-writing-coach/src/shared/types-diagnosis.ts) | `KeyPassage` 加 `chapterId` / `startOffset` / `endOffset` | 低 |
| B-2: 改 [diagnosis-agent-prompt-v1.md](../../../yuesheng-writing-coach/resources/prompts/diagnosis-agent-prompt-v1.md) | 要求 LLM 输出 offset | 中（LLM 准确度） |
| B-3: 解析器加 offset 验证 | [diagnosis-result-processor.ts](../../../yuesheng-writing-coach/src/renderer/services/)（如不存在则新建 `diagnosis-parser.ts`） | 低 |
| B-4: ChatView 诊断卡片点击跳转原文 | [ChatView](../../../yuesheng-writing-coach/src/renderer/components/chat/ChatView/) | 中 |
| B-5: 单测（offset 解析 + 验证） | `__tests__/` | 低 |

#### E. X-02 写回 ADR

- 单独建 ADR-004 正式记录 X-02 协议
- 复用本 ADR 的"写链路"部分

#### C. 占位符统一

- 改 [training-evaluator-prompt-v1.md](../../../yuesheng-writing-coach/resources/prompts/training-evaluator-prompt-v1.md) `{xxx}` → `{{xxx}}`
- 改 [yuesheng-prompt-v3.md](../../../yuesheng-writing-coach/resources/prompts/yuesheng-prompt-v3.md) `{xxx}` → `{{xxx}}`
- 改对应 service 注入器
- 加 Linter 规则禁止单花

#### D. 长度限制

- 在 [prompt-loader.ts](../../../yuesheng-writing-coach/src/main/domains/03-teaching/prompt/prompt-loader.ts) 加 `MAX_CHARS` 检查
- 截断时注入 `[已截断，原文 XXX 字，当前显示 YYY 字]`
- 监控实际章节长度（埋点）

## 风险与回退 (Risks & Rollback)

| 风险 | 等级 | 缓解 |
|:-----|:----:|:-----|
| 本 ADR 决策与未来实际需求冲突 | 低 | 本 ADR 不实施代码，回退 = 改文档 |
| B 阶段 LLM 输出 offset 不准确 | 中 | 解析器加容错（offset 无效则降级为只显示 text） |
| 偏移量受 Unicode 字符影响 | 中 | 使用 `Array.from(content)` 后的字符 offset，**不**用 `content.length` 字节数 |
| 占位符统一破坏现有 prompt | 中 | 双花与单花共存时先做 linter 告警，不强制 |

## 测试策略 (Testing)

本 ADR 自身**不需要测试**（纯文档）。

后续 Sprint 卡片各自的测试策略在对应卡片中定义。

## ADR 状态

- [x] 提议 (Proposed)
- [ ] 接受 (Accepted)
- [ ] 实施 (Implemented)
- [ ] 废弃 (Deprecated)

## 附录 A：AI 读写全图

```
┌─────────────────────────────────────────────────────────────┐
│                  用户作品 (Manuscript / Chapter)             │
└─────────────────────────────────────────────────────────────┘
                            │ 读
                            ▼
            chapter.store.loadContent(id) + contentCache
                            │ 纯文本
                            ▼
                  调用方决定切片范围
                  (chapter / paragraph / window)
                            │
                ┌───────────┴───────────┐
                ▼                       ▼
        诊断上下文构造器          训练上下文构造器
        (diagnosis-context)      (training-context)
                │                       │
                ▼                       ▼
   diagnosis-agent-prompt       training-evaluator-prompt
   {{user_text}}                {{originalQuote}} {{userDraft}}
   {{technique_pool}}           {{constraint}}
                │                       │
                └───────────┬───────────┘
                            ▼
                       AI LLM 推理
                            │
            ┌───────────────┼───────────────┐
            ▼               ▼               ▼
       诊断 JSON        训练评估        对话回复
       (keyPassage)     (errorCard)    (流式文本)
            │               │               │
            ▼               ▼               ▼
       diag.store      training.store   chat.store
            │               │
            │               │ 写
            │               ▼
            │      X-02 训练稿写回编辑器
            │      ┌────────────────────┐
            │      │ sendToEditor       │
            │      │  ↓ pendingRewrite  │
            │      │  ↓  用户确认        │
            │      │  ↓ applyRewrite    │
            │      │  ↓ IPC updateContent│
            │      └────────────────────┘
            │
            ▼
       ChatView 诊断卡片
       (点击 → 跳转原文)
```

## 附录 B：占位符规范（推荐）

### 语法

- 必须使用双花 `{{xxx}}`
- 占位符命名：小写 + 下划线（如 `{{user_draft}}`）
- 嵌套禁止：`{{outer_{{inner}}}}` 不允许
- 转义：使用 `{{{` 表示字面 `{{`（如需要）

### 数据源标签

| 标签 | 含义 | 示例 |
|:-----|:-----|:-----|
| `{{user_*}}` | 用户作品相关 | `{{user_text}}`, `{{user_draft}}` |
| `{{chapter_*}}` | 章节元数据 | `{{chapter_id}}`, `{{chapter_title}}` |
| `{{diagnosis_*}}` | 诊断结果 | `{{diagnosis_summary}}` |
| `{{training_*}}` | 训练配置 | `{{training_constraint}}` |
| `{{student_*}}` | 学生状态 | `{{student_context}}`, `{{mastery_suffix}}` |
| `{{system_*}}` | 系统配置 | `{{system_attitude_level}}` |

### 注入器接口（参考实现）

```ts
// src/renderer/services/prompt-injector.ts (推荐新增)
export function injectPlaceholders(
  template: string,
  context: Record<string, string | number | boolean>
): string {
  return template.replace(/\{\{(\w+)\}\}/g, (match, key) => {
    if (!(key in context)) {
      console.warn(`[PromptInjector] Missing placeholder: ${key}`);
      return `[MISSING:${key}]`;  // 显式占位，避免静默丢内容
    }
    return String(context[key]);
  });
}
```
