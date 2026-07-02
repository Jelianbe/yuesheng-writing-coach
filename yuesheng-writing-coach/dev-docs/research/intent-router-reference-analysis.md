# 意图路由架构：开源项目参考分析

> **目的**：为月笙写作教练的意图路由模块设计提供跨项目参考基准。
> **分析对象**：Rasa 3.x/4.x、InkOS、LangGraph、Parlant
> **日期**：2026-06-24

---

## 1. 概述

意图路由（Intent Routing）是对话式 AI 系统的核心架构层，负责将用户输入映射到预定义的意图类别，并路由到对应的处理逻辑。本报告分析四种不同的开源实现范式，为月笙写作教练的意图路由设计提供参考。

| 项目 | 范式 | 语言 | 意图分类方式 | 路由策略 |
|------|------|------|-------------|---------|
| **Rasa** | NLU Pipeline + 对话管理 | Python | ML 分类器（DIET/Transformer） | 意图标签 → 对话策略选择 |
| **InkOS** | 枚举式路由 | TypeScript | 无（LLM 直接输出意图枚举值） | Zod Schema 校验 → switch-case 分发 |
| **LangGraph** | 状态机图路由 | Python | LLM 分类 + 置信度阈值 | Condition Edge → 节点选择 |
| **Parlant** | 指南匹配引擎 | Python | 分类批量 LLM 评估 | 动态条件 → 指南匹配而非路由 |

---

## 2. 各项目详细分析

### 2.1 Rasa：NLU Pipeline + 对话管理

#### 架构模型

Rasa 采用经典的两阶段架构：

```
用户输入 → NLU Pipeline → Intent + Entities → Dialogue Manager → Action
              │                              │
              ├─ Tokenizer                   ├─ Policy Ensemble
              ├─ Featurizer                  │   ├─ TEDPolicy (ML)
              ├─ Intent Classifier            │   ├─ RulePolicy
              └─ Entity Extractor             │   └─ MemoizationPolicy
                                              └─ Action Server
```

**核心特点**：

- **IntentBasedRouter**：根据 NLU 预测的 intent 决定路由目标（NLU-based 或 CALM 系统），支持 `sticky` / `non_sticky` 会话模式
- **LLMBasedRouter**：使用 LLM 判断路由目标，适用于迁移场景
- **Fallback 策略**：未匹配 intent 时根据 NLU trigger 或默认规则路由
- **Slot Filling**：多轮对话中逐步收集必要参数

#### 意图分类方式

- 使用 DIET（Dual Intent and Entity Transformer）或 SklearnIntentClassifier
- 支持多意图标签（intent_tokenization_flag）
- 输出 `intent` + `intent_ranking`（置信度排名列表）
- 可通过 Hugging Face 模型替换默认分类器

#### 路由模式

```yaml
# Rasa IntentBasedRouter 配置
- name: IntentBasedRouter
  nlu_entry:
    sticky: [transfer_money, check_balance]
    non_sticky: [chitchat]
  calm_entry:
    sticky: [book_hotel, cancel_hotel]
```

**关键设计决策**：

| 决策 | 选择 | 理由 |
|------|------|------|
| NLU vs Core 是否分离 | 严格分离 | 独立迭代、分别调优 |
| 路由粒度 | 意图级别 | 细粒度控制，但配置复杂度高 |
| 规则 vs ML | 混合（RulePolicy + TEDPolicy） | 确定性流程用规则，复杂对话用 ML |
| 回退处理 | 多层次（NLU trigger → 默认路由） | 防止静默失败 |

#### 优点与不足

**优点**：
- 开箱即用的完整 NLU 管道
- 成熟的 slot filling 机制
- 支持自定义组件扩展
- 本地部署，数据隐私可控

**不足**：
- 学习曲线陡峭
- 冷启动时间长
- 训练数据需求量大
- 意图数量多时管理复杂

---

### 2.2 InkOS：枚举式 Schema 路由

#### 架构模型

InkOS 采用 TypeScript + Zod Schema 的强类型路由方式：

```
用户输入（NL 文本） → LLM 意图识别 → Zod Schema 校验 → 路由分发 → Handler
                                              │
                                    ┌─────────┼─────────┐
                                    ↓         ↓         ↓
                               DraftLifecycle  BookSelection  ContentOps
                                   Handler      Handler      Handler
```

#### 源码分析

**intents.ts** — 枚举式意图定义（已读取完整文件）：

```typescript
// 22 个枚举意图，Zod 校验
export const InteractionIntentTypeSchema = z.enum([
  "develop_book", "show_book_draft", "create_book", "discard_book_draft",
  "list_books", "select_book", "continue_book", "write_next",
  "pause_book", "resume_book", "revise_chapter", "rewrite_chapter",
  "patch_chapter_text", "replace_chapter_text", "edit_truth",
  "rename_entity", "update_focus", "update_author_intent",
  "chat", "explain_status", "explain_failure", "export_book",
]);
```

**request-router.ts** — 极简路由校验：

```typescript
// 仅做 Schema 校验，路由逻辑在 runtime.ts 中
export function routeInteractionRequest(input: InteractionRequest): InteractionRequest {
  return InteractionRequestSchema.parse(input);
}
```

**runtime.ts** — 实际的意图分发（1153 行），核心模式：

```typescript
// 分层处理 + switch-case 分发
export async function runInteractionRequest(params) {
  // 1. Schema 校验（通过 routeInteractionRequest）
  // 2. 草案生命周期处理
  const draftResult = await handleDraftLifecycleRequest({ session, request, tools, helpers });
  if (draftResult) return draftResult;
  // 3. 作品选择处理
  const bookResult = await handleBookSelectionRequest({ session, request, tools, helpers });
  if (bookResult) return bookResult;
  // 4. 主路由分发（switch-case）
  switch (request.intent) {
    case "write_next":
    case "continue_book": { /* ... */ }
    case "revise_chapter":
    case "rewrite_chapter": { /* ... */ }
    // ... 每个 intent 对应一个 case
    case "chat": { /* ... */ }
    default: throw new Error(`未实现意图「${request.intent}」`);
  }
}
```

**关键设计决策**：

| 决策 | 选择 | 理由 |
|------|------|------|
| 意图枚举方式 | Zod Schema 枚举 | 编译期校验 + 运行时 parse |
| 路由实现 | 分层 switch-case | 简单、可预测、类型安全 |
| 参数传递 | 结构化 Request Schema | 所有 intent 共享同一接口定义 |
| 回退处理 | 显式 throw Error | 快速失败，不静默降级 |
| 自动化模式 | auto/semi/manual 三级 | 根据模式决定是否需要人工审批 |

#### 优点与不足

**优点**：
- 类型安全（Zod 校验保证运行时与编译期一致）
- 路由逻辑简洁透明（switch-case 一目了然）
- 分层处理隔离关注点（草案/选择/内容操作）
- 意图数量有限（22 个），枚举可控

**不足**：
- 无 ML 意图分类（依赖 LLM 精确输出枚举值）
- switch-case 模式下代码冗长（每个 case 数十行）
- 无置信度回退机制（分类错误即错误）
- 扩展新意图需改动多处（Schema + case + handler）

---

### 2.3 LangGraph：状态机图路由

#### 架构模型

LangGraph 采用有向图状态机架构：

```
                    ┌──────────────────┐
                    │    StateGraph     │
                    │  (TypedDict)      │
                    │  messages: []     │
                    │  intent: str      │
                    │  tool_outputs: [] │
                    └────────┬─────────┘
                             │
                    ┌────────▼─────────┐
                    │   Classifier      │
                    │   (LLM/ML)        │
                    └────────┬─────────┘
                             │
              ┌──────────────┼──────────────┐
              │ 置信度≥阈值    │ 置信度<阈值   │
              ▼               ▼              ▼
        ┌──────────┐   ┌──────────┐   ┌──────────┐
        │  Intent A │   │  Intent B │   │ Clarify  │
        │  Handler  │   │  Handler  │   │  Node    │
        └──────────┘   └──────────┘   └──────────┘
```

#### 核心机制

**State Schema** — 类型化的共享状态：

```python
class AgentState(TypedDict):
    messages: Annotated[list[BaseMessage], add_messages]
    intent: str  # 覆盖写入
    tool_outputs: Annotated[list[dict], lambda l, r: l + r]
    confidence: float
```

**Conditional Edges** — 动态路由：

```python
def route_intent(state: AgentState) -> str:
    if state.confidence >= 0.85:
        return state.intent  # 返回节点名
    elif state.confidence >= 0.5:
        return "clarify"
    else:
        return "fallback"
```

**典型的三层动态路由方案**（来自生产实践）：

| 组件 | 功能 | 实现方式 |
|------|------|---------|
| 意图分类模块 | 分析用户意图及其概率分布 | LLM / 微调分类器 |
| 置信度阈值校准 | 判断分类结果是否可靠 | 动态阈值（业务场景敏感） |
| 回退链路模块 | 降级处理、多轮澄清、转人工 | clarify / fallback 节点 |

**生产级路由方案对比**（来自 LangGraph 实践文章数据）：

| 路由方案 | 实现成本 | 路由准确率 | 容错能力 | 生产可用性 |
|----------|---------|-----------|---------|-----------|
| 静态规则（if/else/正则） | 低 | 低 | 极差 | 不推荐 |
| 无置信度 LLM 路由 | 中 | 中（边界场景低） | 差 | 仅限非核心 |
| 置信度+回退动态路由 | 中高 | 高（边界有兜底） | 极高 | 生产首选 |

#### 优点与不足

**优点**：
- 状态机模型天然适配多轮对话
- 确定性路由（Condition Edge 是纯函数，可测试）
- 支持并行执行（fan-out/join）
- 可组合（Subgraph 可嵌套）
- 持久化/重放/调试能力强

**不足**：
- 学习曲线陡
- 路由模式在多意图混合场景存在局限性（Parlant 观点）
- 图结构复杂时难以调试
- 对简单场景过度工程化

---

### 2.4 Parlant：指南匹配引擎（反路由模式）

#### 架构模型

Parlant 刻意不采用"路由"模式，改用**动态指南匹配（Dynamic Guideline Matching）**：

```
用户输入
     │
     ▼
┌─────────────────────────────────────┐
│          Guideline Matching Engine   │
│                                      │
│  1. Journey Prediction               │
│  2. Guideline Pruning (10-30%)       │
│  3. Category Batching                │
│  4. Parallel LLM Evaluation          │
│  5. Relationship Resolution          │
│  6. Apply Matched Guidelines         │
└──────────────────┬──────────────────┘
                   │
                   ▼
           LLM + Guidelines → Response
```

#### 与路由模式的本质区别

| 维度 | 路由模式（Rasa/LangGraph/InkOS） | 指南模式（Parlant） |
|------|----------------------------------|-------------------|
| 用户路径 | 强制走预设路径 | 自然流动，动态适配 |
| 意图数量 | 有限（20-50 个意图） | 理论上无限（指南数） |
| 混合话题 | 难以处理 | 天然支持 |
| 上下文丢失 | 路由硬切换时易丢失 | 持续评估，无缝衔接 |
| 扩展性 | 新增意图需改路由逻辑 | 新增指南无需改代码 |

**Parlant 对路由模式的批评**（来自官方博客）：

> "Router-based architectures **inherently fail** for natural, free-form conversation — not due to implementation details you can fix, but due to fundamental architectural constraints."

**指南匹配管道**（详情见官方文档）：

```
ALGORITHM: Guideline Matching Pipeline

1. PREDICT relevant journeys
2. PRUNE guidelines (排除不相关旅程的指南)
3. CATEGORIZE each candidate
   - Observational / Previously applied / Customer-dependent / etc.
4. CREATE batches (按类别分组)
5. EVALUATE batches in parallel (LLM 评估)
6. RESOLVE relationships (entailment/suppression/priority)
7. RETURN matched_guidelines
```

#### 指南分类与评估

| 类别 | 评估方式 | 示例 |
|------|---------|------|
| Observational | 快速模式匹配 | "客户提到竞争对手" |
| Previously Applied | 检查已应用状态 | "已经解释过退货政策" |
| Customer-dependent | 需客户信息 | "客户是 VIP 会员" |
| Journey-scoped | 旅程上下文 | "用户完成第二步流程" |

#### 优点与不足

**优点**：
- 天然支持自由形式对话
- 可扩展性好（新增指南不影响现有逻辑）
- 决策可解释（给出匹配理由和评分）
- 避免"硬切换"导致的上下文丢失

**不足**：
- 实现复杂度极高（Parlant 团队花了 1 年多）
- 延迟/成本较高（多次 LLM 调用）
- 不适用于确定性路由场景
- 项目较新，社区生态不成熟
- 与"写作教练"的有限意图集合可能不匹配

---

## 3. 对比分析

### 3.1 关键架构决策对比表

| 决策维度 | Rasa | InkOS | LangGraph | Parlant |
|----------|------|-------|-----------|---------|
| **意图分类方式** | ML 模型训练 | LLM 直接输出枚举值 | LLM + 置信度阈值 | 分类批量 LLM 评估 |
| **路由策略** | Intent → Policy → Action | Schema 校验 → switch-case | Condition Edge → Node | 无路由，动态匹配 |
| **状态管理** | Tracker（对话历史+槽位） | Session（ExecutionState） | StateGraph（TypedDict） | Journey State |
| **错误处理** | Fallback Intent + Human Handoff | throw Error + catch | Clarify/Retry/Fallback Node | 自动降级匹配 |
| **配置方式** | YAML 配置文件 | TypeScript 代码 | Python 代码 | Python API |
| **扩展新意图** | 加训练数据 + 加 Story | 加枚举值 + 加 case | 加 Node + Edge | 加 Guideline |
| **调试能力** | Rasa SDK 追踪 | 控制台日志 | LangSmith 追踪 | 决策可解释性 |
| **学习成本** | 高 | 低 | 高 | 中高 |
| **适用场景** | 复杂任务型对话 | 有限意图的确定性路由 | 复杂多步 Agent | 自由形式客户对话 |

### 3.2 意图识别准确率参考

| 项目 | 准确率数据 | 说明 |
|------|-----------|------|
| Rasa（DIET + BERT） | 92.1% | 医疗/客服领域（2026 IRE 论文） |
| Rasa vs Dialogflow | 92% vs 85% | 开放域任务 |
| LangGraph 置信度+回退 | 路由错误率 21%→2.3% | 生产环境优化后 |
| Parlant 指南匹配 | 未公开基准 | 项目较新 |

### 3.3 回退/错误处理模式对比

| 模式 | Rasa | InkOS | LangGraph | Parlant |
|------|------|-------|-----------|---------|
| 低置信度回退 | NLU trigger 检查 | 无（外部处理） | Clarify Node | 自动降低评分 |
| 未匹配处理 | 默认路由规则 | throw Error | Fallback Node | 匹配最接近的指南 |
| 多轮澄清 | Slot Filling | 无 | 循环 Clarify | 动态上下文感知 |
| 转人工 | Human Handoff | 无（设计为 CLI） | Human-in-the-loop | 通过 Guideline 配置 |
| 重试机制 | Policy 自动 | 无 | Tool retry 节点 | 不适用 |

---

## 4. 对月笙写作教练的启示

### 4.1 月笙的意图集特征

基于月笙写作教练的业务场景，意图集有以下特征：

- **意图数量有限**：预计 15-30 个核心意图（类似 InkOS 的 22 个）
- **意图相对稳定**：不会频繁新增意图类别
- **多轮上下文依赖**：如诊断对话需要 3-5 轮交互
- **确定性要求高**：写作诊断需要精确路由，不能模棱两可
- **用户自由度受限**：用户在预设功能框架内操作

### 4.2 推荐方案

综合各项目优缺点，建议月笙采用 **InkOS 风格 + LangGraph 状态机** 的混合方案：

#### 核心架构

```
用户输入 → LLM 意图分类 → Zod Schema 校验 → State Machine 路由 → Handler
                              │
                     ┌────────┴────────┐
                     │ 置信度 ≥ 阈值    │ 置信度 < 阈值
                     ▼                 ▼
               Intent Handler      Clarification Loop
```

#### 具体建议

| 决策项 | 推荐 | 理由 |
|--------|------|------|
| **意图定义** | Zod 枚举（参考 InkOS） | 类型安全，编译期检查 |
| **意图分类** | LLM + 置信度阈值 | 无需训练数据，边界情况有兜底 |
| **路由实现** | State Machine + switch-case | 可测试的确定性路由，兼顾多轮状态 |
| **参数校验** | Zod Schema（参考 InkOS） | 与现有 TypeScript 技术栈一致 |
| **回退处理** | 三级回退（参考 LangGraph） | Clarify → Retry → 转人工/兜底 |
| **状态管理** | Zustand（已使用）+ 路由状态 | 与现有状态管理一致 |
| **自动化模式** | InkOS 的 auto/semi/manual | 满足不同用户偏好 |
| **多轮上下文** | 对话历史 + Slot Filling | 诊断场景需要逐步收集信息 |

#### 不推荐采用 Parlant 的原因

1. 月笙的意图集是有限且稳定的，不需要无限扩展的指南系统
2. Parlant 的实现复杂度高，不适合小型项目
3. 写作教练需要确定性路由（如"诊断"必须走到诊断流程），而非"自由匹配"
4. Parlant 的多次 LLM 调用带来延迟和成本问题

### 4.3 关键设计原则

```
1. 意图定义为枚举（先验已知类别），而非动态发现
2. 路由前必须通过 Schema 校验（fail-fast）
3. 每个 Handler 独立测试（单元测试覆盖所有意图）
4. 回退链路必须覆盖所有非法输入
5. 路由日志完整记录（intent + confidence + 路由路径）
6. 运行时意图验证（防止 LLM 输出非法枚举值）
```

### 4.4 与现有架构的集成点

| 现有模块 | 路由集成方式 |
|----------|-------------|
| 诊断引擎 | Intent: `diagnose_essay`, `analyze_problem`, `suggest_improvement` |
| 教学状态机 | 路由到对应状态节点，状态转换由状态机管理 |
| IPC Handlers | `session:intent-classify` 通道，返回意图+置信度 |
| Zustand Store | 存储当前 intent、对话历史、路由状态 |
| Prompt 模板 | 四段式 Prompt 中约束 LLM 输出合法意图枚举值 |

---

## 5. 关键结论

1. **InkOS 的枚举式 Schema 路由最适合月笙的当前阶段**——意图有限、类型安全、实现简单
2. **LangGraph 的状态机和置信度回退机制值得借鉴**——用于未来多轮对话和边界情况处理
3. **Rasa 的 NLU Pipeline 过于重量级**——月笙不需要独立的 ML 训练流程
4. **Parlant 的模式不适合写作教练**——虽然创新，但复杂度远超需求
5. **混合方案是最佳路径**——以 InkOS 框架为主体，吸收 LangGraph 的状态管理和回退策略

### 风险提示

- **LLM 意图分类的可靠性**：LLM 可能输出非法枚举值，必须做 Schema 校验
- **置信度阈值校准**：需要真实用户数据来确定最佳阈值
- **多意图处理**：用户可能在一条消息中表达多重意图（如"帮我看看这段文字，然后改一下"），需要考虑意图分解策略
- **冷启动问题**：新用户无历史对话时，路由的上下文不足

---

## 6. 参考资料

- Rasa IntentBasedRouter 文档: [Rasa Coexistence Routers](https://rasa.com/docs/reference/config/components/coexistence-routers/)
- InkOS 源码: [github.com/Narcooo/inkos](https://github.com/Narcooo/inkos)
- LangGraph State Machine Architecture: [CallSphere Blog](https://www.callsphere.ai/blog/langgraph-state-machine-architecture-deep-dive-2026)
- LangGraph 动态路由实践: [CSDN 专栏](https://blog.csdn.net/2502_91534727/article/details/161291707)
- Parlant vs LangGraph: [Parlant Blog](https://www.parlant.io/blog/parlant-vs-langgraph/)
- Parlant Guideline Matching Engine: [Parlant Docs](https://www.parlant.io/docs/engine-internals/guideline-matching/)
- 混合 AI 动态路由论文: [arXiv:2506.02097](https://arxiv.org/html/2506.02097v1/)
