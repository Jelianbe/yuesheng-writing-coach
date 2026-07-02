# 意图路由市场调研：AI 写作助手的意图分类与路由架构

> 调研日期：2026-06-24
> 目标：研究 Grammarly 和 Writer.com 等头部产品的意图路由架构，提炼可应用于月笙写作教练项目的模式。

---

## 目录

1. [执行摘要](#1-执行摘要)
2. [Grammarly 意图路由分析](#2-grammarly-意图路由分析)
3. [Writer.com 意图路由分析](#3-writercom-意图路由分析)
4. [行业通用意图路由模式](#4-行业通用意图路由模式)
5. [对比总结](#5-对比总结)
6. [对月笙写作教练的启示](#6-对月笙写作教练的启示)
7. [参考资料](#7-参考资料)

---

## 1. 执行摘要

本报告调研了 Grammarly 和 Writer.com 在 AI 写作助手中处理意图分类和路由的架构设计，并结合行业通用的语义路由模式进行综合分析。

**核心发现：**

| 维度 | Grammarly | Writer.com | 行业趋势 |
|------|-----------|------------|----------|
| 路由策略 | 多级流水线 + 显式"Goals"设置 | 三层架构（Guardrails -> Knowledge Graph -> Agent） | 混合路由（Embedding + LLM） |
| 意图分类粒度 | 细粒度（Intent/Audience/Formality/Domain） | 粗粒度（Agent Playbook 级别） | 任务级路由逐渐取代模型级路由 |
| 模糊请求处理 | Goals 显式设定 + 默认安全行为 | Guardrails 层过滤 + 回退到通用 Agent | 置信度阈值 + 人工确认机制 |
| 个性化机制 | 用户设置 + 学习用户偏好 | 知识图谱 + Brand Voice 配置 | 上下文记忆 + 外部知识注入 |

---

## 2. Grammarly 意图路由分析

### 2.1 整体架构

Grammarly 的核心架构是一个**多级 AI 流水线**，并非单一模型处理所有任务。根据公开的系统设计资料和工程博客，其流程如下：

```
用户输入
  |
  v
[预处理] --> Tokenization, 清洗, 标准化
  |
  v
[多级分析]
  +-- 词汇分析 (Lexical Analysis): 识别词性、词根、词形
  +-- 句法分析 (Syntactic Parsing): 句法树、主谓宾结构
  +-- 语义分析 (Semantic Analysis): 意图、语气、上下文
  |
  v
[分层推理引擎] (Tiered ML Inference)
  +-- 轻量模型: 实时语法/拼写检查（毫秒级）
  +-- 重量模型: 异步处理 Tone/Clarity/Generative Rewrite（亚秒级）
  |
  v
[建议生成] --> 展示给用户
```

**关键特征：** Grammarly 使用分层 ML 推理（Tiered ML Inference）来平衡速度和深度——轻量模型处理即时语法检查，重量模型异步运行用于语气、清晰度和生成式改写。

### 2.2 意图检测机制

Grammarly 的意图检测体现在多个层面：

#### 2.2.1 Dialogue Act 识别（学术研究基础）

Grammarly 研究团队在 NAACL 2019 发表了对话行为（Dialogue Act）识别的工作。他们构建了基于深度学习的序列标注模型，使用自注意力（Self-Attention）和层级深度学习模型来标注对话中每条话语的对话行为。

对话行为的分类包括：
- Greeting / Greeting-Question / Greeting-Answer
- Question / Yes-No-Question
- Statement / Statement-non-opinion
- Backchannel / Backchannel-question
- Request / Opinion

**架构启示：** 对话行为识别是 NLU 系统的基础层，下游组件建立在此之上。Grammarly 将其视为**基础层任务**，而非终点。

#### 2.2.2 Tone and Intent Detection

Grammarly 使用 NLP 模型评估语气，识别情绪和社交意图。分析维度包括：
- 句子结构（Sentence Structure）
- 词汇选择（Word Choice）
- 标点使用习惯（Punctuation Usage）

示例：
- 输入："I need the report now!" -> 语气标记为"aggressive"
- 建议："Could you please send me the report as soon as possible?"

#### 2.2.3 Goals 系统（显式意图配置）

Grammarly Premium 提供 **Goals** 功能，用户可显式设置以下维度：

| 维度 | 选项 | 作用 |
|------|------|------|
| **Intent** | Inform / Describe / Convince / Tell a Story | 决定分析的重点 |
| **Audience** | General / Knowledgeable / Expert | 调整词汇复杂度和假设前提 |
| **Formality** | Informal / Neutral / Formal | 控制正式程度 |
| **Domain** | Academic / Business / General / Email / Creative / Casual | 切换领域特定规则 |

**核心价值：** 这四维目标设置将意图分类从"隐式推断"转为"显式声明"，大幅降低模糊请求的处理难度。每个维度组合会切换 Grammarly 的分析透镜，影响后续所有建议的生成。

### 2.3 模糊请求处理

Grammarly 处理模糊请求的策略：

1. **默认安全行为**：当意图不明确时，Grammarly 回退到基础语法检查，不做激进的重写建议。
2. **Goals 显式引导**：用户可预设目标，减少歧义。
3. **渐进式交互**：GrammarlyGO 在生成内容时通过对话式交互澄清需求，而非一次猜测用户意图。
4. **低承诺设计**：Grammarly 的 Tone 检测是"告知"而非"强制"——它告诉用户检测到的语气，建议修改但不自动修改。

### 2.4 GrammarlyGO 的意图路由

GrammarlyGO（现已更名为 Generative AI Assistant）是 Grammarly 的内容生成引擎。其流程如下：

```
用户 Prompt
  |
  v
[意图理解] --> 通过 Prompt 中的指令推断用户想做什么
  |
  v
[内容生成] --> Palmyra / 其他 LLM
  |
  v
[后处理] --> 语气调整 + 格式修正
  |
  v
[用户确认] --> 可重生成、细化 Prompt、调整语气
```

**关键观察：** GrammarlyGO 的意图路由主要通过 Prompt Engineering 实现，而非专门的分类模型。它依赖用户提供的自然语言指令来推断意图，并通过对话式交互进行修正。

根据 UX 研究数据，GrammarlyGO 存在**60% 用户首次使用后 7 天内不再返回**的问题，其中一个主要原因是用户"对 AI 助手与传统 Grammarly 修正之间的区别感到困惑"。这表明意图路由的透明度和可发现性是关键挑战。

### 2.5 Authorship 功能

2025 年推出的 Grammarly Authorship 功能关注内容溯源，能标记文本中哪些部分由 AI 生成、哪些为人工撰写。虽然这不是意图路由功能，但它体现了 Grammarly 对"内容来源"的细粒度追踪，这在意图路由系统中可以作为用户上下文的一部分。

---

## 3. Writer.com 意图路由分析

### 3.1 整体架构

Writer.com 采用**三层模块化架构**，专为企业级安全和品牌一致性设计：

```
用户 / API 请求
  |
  v
[Guardrails 层] --> PII 检测、品牌合规、安全过滤
  |
  v
[Knowledge Graph 层] --> 图式 RAG，从企业文档检索上下文
  |
  v
[Prompt Construction] --> 构建完整 Prompt（含上下文 + 品牌规则）
  |
  v
[Palmyra LLM] --> 推理与生成
  |
  v
[Output Guardrails] --> 输出合规检查
  |
  v
最终响应
```

### 3.2 路由机制

#### 3.2.1 Agent 架构

Writer 的 Agent 架构由三个互锁层组成：

1. **Palmyra LLM 家族**：专有模型系列，包括 Palmyra-X-V4（复杂推理）、Palmyra-Med（医疗）、Palmyra-Fin（金融）、Palmyra-Creative（创意写作）
2. **Knowledge Graph**：基于图的 RAG 系统，连接企业数据到模型
3. **Agent Orchestration**：无代码 Playbook 构建器 + 代码优先的 Writer Framework

#### 3.2.2 Multi-Agent 路由模式

Writer 通过 Strands Agents SDK 支持多种 Agent 协作模式：

| 模式 | 描述 | 路由特点 |
|------|------|----------|
| **Handoffs** | Agent 可将控制权交给其他 Agent 或人类 | 基于任务范围的路由，保留完整上下文 |
| **Swarms** | 多 Agent 自主协调 | 共享上下文和工作内存，分布式决策 |
| **Graphs** | 定义显式的逐步 Agent 工作流 | 条件路由和决策点，确定性高 |
| **Agents-as-Tools** | 专业化 Agent 作为工具供其他 Agent 调用 | 函数式路由，Agent 间松耦合 |

#### 3.2.3 Guardrails 作为第一层路由

Writer 的 Guardrails 层充当了**第一意图过滤器**：

- **输入 Guardrails**：检测 PII、敏感内容、品牌违规
  - 如果检测到 PII -> 自动脱敏或拦截
  - 如果检测到不安全内容 -> 阻止进一步处理
  - 如果通过检查 -> 传递到 Retrieval 层
- **输出 Guardrails**：检查生成内容是否合规
  - 品牌语气检查
  - 法律合规性检查
  - 包含性语言检查

**关键模式：** Guardrails 既是安全层也是路由层——不符合策略的请求在入口处被拦截或重定向，而不是传递到 LLM。

### 3.3 意图路由的实现方式

Writer 的意图路由主要通过 **Playbook** 实现：

```
用户请求
  |
  v
[Playbook 匹配] --> 基于请求内容匹配预定义 Playbook
  |
  v
[Playbook 执行] --> 按 Playbook 定义的工作流执行
  |    - 调用的工具
  |    - 使用的知识源
  |    - 遵循的品牌规则
  v
[Agent 执行] --> Palmyra LLM 推理 + 工具调用
```

Playbook 是无代码/低代码定义的多步骤工作流，相当于将领域知识编码为可执行的意图路由规则。

### 3.4 模型选择路由

Writer 支持在 Agent 构建时选择底层模型：

- **统一治理**：通过 AI Studio 的 Models 页面管理所有模型
- **外部模型支持**：支持 AWS Bedrock、Azure OpenAI、NVIDIA NIM 等
- **路由策略**：管理员可控制哪些团队可用哪些模型

在 Super Agent（Action Agent）层面，Writer 使用 **Palmyra X5**（2025 年 4 月发布），其 100 万 token 上下文窗口和混合注意力机制使其能够在一个 Agent 调用中处理大量上下文。

### 3.5 对企业级意图路由的启示

Writer 的设计哲学对意图路由有重要启示：

1. **安全先行**：Guardrails 层在意图路由前执行安全过滤
2. **知识为基础**：Knowledge Graph 提供上下文，使路由更精准
3. **可配置性**：Playbook 允许非技术人员定义路由逻辑
4. **透明治理**：所有路由决策可审计、可解释
5. **模型灵活性**：不同任务可路由到不同模型

---

## 4. 行业通用意图路由模式

### 4.1 三种主流路由策略

#### 4.1.1 基于 Embedding 的语义路由

**原理**：将用户请求和预定义的意图分类都转换为高维向量，通过相似度计算匹配。

```
用户请求
  |
  v
[Embedding 模型] --> 生成向量表示
  |
  v
[相似度搜索] --> 与预定义意图向量的余弦相似度
  |
  v
[置信度评估] --> 若 > 阈值则自动路由，否则回退
```

**优点**：速度快，支持大规模意图分类，容易扩展新意图
**缺点**：依赖示例数据质量，对细微语义差异不敏感
**适用场景**：意图数量较多且定义明确的场景
**代表实现**：Aurelio Labs Semantic Router, LangChain 函数路由

#### 4.1.2 基于 LLM 的意图分类

**原理**：使用 LLM 通过 Prompt Engineering 对用户请求进行分类。

```
用户请求
  |
  v
[Prompt 模板] --> "请将以下用户请求分类到以下类别之一：..."
  |
  v
[LLM 推理] --> 输出意图类别（JSON format）
  |
  v
[结构化解析] --> 提取意图和参数
```

**优点**：语义理解能力强，能处理零样本/少样本场景，可以同时完成意图分类和实体提取
**缺点**：延迟较高，成本较高，输出不总是结构化
**适用场景**：意图边界模糊、需要深度理解的复杂请求
**代表实现**：mcp-agent 的 LLMIntentClassifier

#### 4.1.3 混合路由（推荐模式）

**原理**：结合 Embedding 和 LLM 的优点，形成两阶段或三阶段路由。

```
用户请求
  |
  v
[阶段1：Embedding 快速分类]
  +-- 高置信度 ( > 0.9 ) --> 直接路由
  +-- 中置信度 ( 0.6 - 0.9 ) --> 阶段2
  +-- 低置信度 ( < 0.6 ) --> 阶段2
  |
  v
[阶段2：LLM 深度分析]
  +-- 确认意图 --> 路由
  +-- 无法确定 --> 回退到通用模式 / 请求用户澄清
```

**优点**：速度和深度平衡，资源利用率高，鲁棒性好
**缺点**：架构复杂度高，需维护两套模型
**适用场景**：生产级 AI 写作助手

### 4.2 学术界的 Semantic Routing

Prof. Dr. Andreas Haja 提出的 **Semantic Routing** 框架（PROMOS 项目）提供了理论支持：

- **核心思想**：使用轻量级 LLM 进行语义分析，将用户输入与声明式路由表中的预定义路径匹配
- **置信度阈值**：高置信度意图自动路由，模糊输入保持自然对话流
- **事件驱动**：通过事件驱动的 Prompt 注入，避免上下文稀释
- **路由表**：声明式定义意图 -> Prompt 的映射关系

示例路由表：
```
"我想写日记"  ->  Route: DIARY_MODE  -> 启用日记 Prompt 序列
"记得 Sophie 负责服务器"  ->  Route: MEMORY_STORE  -> 存储到记忆系统
"那真有趣"  ->  No Route  -> 保持自由对话
```

### 4.3 IETF 的语义路由架构草案

2025 年 IETF 提出的草案定义了 AI Agent 通信的语义路由架构，由四层组成：

1. **Application Plane**：发出 Intent Vectors 的 AI Agent
2. **Control Plane**：语义路由策略引擎
3. **Data Plane**：内容传输执行
4. **Feedback Plane**：反馈收集和路由优化

这为 Agent 间路由提供了标准化参考。

### 4.4 MuleSoft 定义的五大架构模式

MuleSoft 在 2025 年定义了 AI Agent 时代的五大架构模式，其中第一个就是**意图路由**：

1. **Understand: Intent Routing** - 从逻辑树到语义解析
2. **Plan: Cognitive Orchestration** - 从预定义流程到实时推理
3. **Execute: Tool-Calling Agents** - 工具调用代理
4. **Learn: Continuous Feedback** - 持续反馈学习
5. **Govern: Policy Enforcement** - 策略执行

**核心观点**："目标不再是路由流量，而是帮助 Agent 路由意图——带着清晰、信任和目的。"

### 4.5 意图分类的多级粒度

行业内常见的意图分类粒度：

| 粒度级别 | 描述 | 示例 | 适用场景 |
|----------|------|------|----------|
| L1: 领域 | 识别写作领域 | 学术/商务/创意/日常 | 初始路由过滤 |
| L2: 动作 | 识别用户想做什么 | 校对/改写/生成/查错 | 功能路由 |
| L3: 参数 | 识别具体参数 | 语气/受众/长度 | 微调路由行为 |

---

## 5. 对比总结

### 5.1 Grammarly vs Writer.com

| 对比维度 | Grammarly | Writer.com |
|----------|-----------|------------|
| **核心定位** | 个人写作助手 | 企业 AI Agent 平台 |
| **意图分类方式** | 隐式（NLP 分析）+ 显式（Goals 设置） | 显式（Playbook + Guardrails） |
| **路由层级** | 多级流水线（轻量->重量模型） | 三层架构（Guardrails -> KG -> Agent） |
| **模糊处理** | Goals 预设 + 渐进式交互 | Guardrails 过滤 + 降级到通用 Agent |
| **个性化** | 用户偏好学习 + 文档级设置 | 企业知识图谱 + Brand Voice |
| **生成式 AI 入口** | GrammarlyGO（Prompt 驱动） | Palmyra Agent + Action Agent |
| **架构开放性** | 封闭（自研模型） | 开放（支持外部模型） |

### 5.2 关键差异

1. **路由的确定性**：Writer 的 Playbook 提供了确定性的路由逻辑，Grammarly 更多依赖概率性模型推断。
2. **用户的控制权**：Grammarly 通过 Goals 给予用户显式的意图控制，Writer 通过 Playbook 让管理员/构建者控制。
3. **安全与路由的耦合**：Writer 将安全 Guardrails 作为路由的一部分（前置过滤），Grammarly 的安全检查与路由相对独立。
4. **意图分类的位置**：Grammarly 的意图分类发生在分析阶段，影响后续所有处理；Writer 的意图分类发生在 Playbook 匹配阶段。

---

## 6. 对月笙写作教练的启示

### 6.1 核心建议

#### 6.1.1 采用混合路由架构

建议月笙写作教练采用三阶段混合路由：

```
用户输入
  |
  v
[阶段1：输入 Guardrails] --> R-029 安全过滤，R-009 用户主权检查
  |
  v
[阶段2：意图检测] 
  +-- Embedding 快速匹配 --> 高置信度直接路由
  +-- LLM 深度分析 --> 低置信度使用 LLM 判断
  |
  v
[阶段3：动作路由]
  +-- 诊断意图 --> 诊断引擎（当前核心能力）
  +-- 教学意图 --> 教学状态机
  +-- 改写意图 --> 改写模块
  +-- 写作意图 --> 生成模块
  +-- 模糊意图 --> 请求用户澄清 / 默认诊断
```

#### 6.1.2 设计四维意图配置（借鉴 Grammarly Goals）

为月笙写作教练设计用户可配置的写作目标：

| 维度 | 选项 | 实现方式 |
|------|------|----------|
| **意图 (Intent)** | 诊断 / 教学 / 改写 / 生成 | 路由到不同处理模块 |
| **受众 (Audience)** | 学生 / 专业人士 / 一般写作 | 调整反馈的深度和术语 |
| **风格 (Style)** | 鼓励 / 分析 / 直评 | 调整反馈的语气和结构 |
| **领域 (Domain)** | 学术 / 创意 / 商务 / 通用 | 切换领域特定规则 |

#### 6.1.3 实现置信度路由和安全回退

```
if confidence > 0.9:
    # 自动路由到最佳匹配模块
elif confidence > 0.5:
    # 路由 + 提示"我理解您想...对吗？"
else:
    # 回退到默认诊断模式
    # 使用模糊提示："我无法完全确定您的需求。我将进行基础诊断..."
```

#### 6.1.4 以诊断引擎为默认行为

参照 Grammarly 默认回退到语法检查的做法，月笙写作教练的默认行为应为**诊断**：
- 当意图不明确时，执行基础写作诊断
- 诊断结果可作为上下文传递给后续意图澄清对话
- 避免"空转"或"猜测"导致的错误路由

### 6.2 技术实现参考

#### 6.2.1 Intent Classifier 接口设计

```typescript
// 参考 mcp-agent 和 Semantic Routing 的设计
interface IntentClassifier {
  classify(input: WritingInput): Promise<IntentResult>;
}

interface IntentResult {
  intent: WritingIntent;
  confidence: number;
  parameters: IntentParameters;
  fallback: boolean;
}

type WritingIntent =
  | 'diagnose'      // 写作诊断
  | 'teach'         // 教学过程
  | 'rewrite'       // 改写润色
  | 'generate'      // 内容生成
  | 'analyze'       // 深度分析
  | 'clarify';      // 需要澄清

interface IntentParameters {
  tone?: 'gentle' | 'neutral' | 'direct';
  depth?: 'surface' | 'deep' | 'comprehensive';
  focus?: 'grammar' | 'structure' | 'logic' | 'style' | 'all';
}
```

#### 6.2.2 路由表设计（参考 PROMOS Semantic Routing）

```typescript
const routeTable: RouteEntry[] = [
  {
    intent: 'diagnose',
    patterns: [
      '帮我看看这段',
      '检查一下',
      '有什么问题',
      '改改这个',
      /(哪里|怎么|为什么)\s*(不好|不对|有问题)/,
    ],
    confidence: 0.8,
    action: 'diagnostic:analyze',
  },
  {
    intent: 'teach',
    patterns: [
      '教我怎么',
      '什么叫做',
      '什么是',
      '给我讲讲',
      /^什么是|^什么叫/,
    ],
    confidence: 0.7,
    action: 'teaching:explain',
  },
  {
    intent: 'rewrite',
    patterns: [
      '帮我改一下',
      '改成更好的',
      '润色',
      '优化一下',
      '换个说法',
    ],
    confidence: 0.75,
    action: 'rewrite:suggest',
  },
  // ... 更多路由条目
];
```

#### 6.2.3 联动现有模块

月笙写作教练已有的核心模块应与意图路由无缝对接：

| 意图 | 路由目标 | 现有模块 |
|------|----------|----------|
| 诊断 (Diagnose) | 诊断引擎 | `src/main/diagnostic-engine/` |
| 教学 (Teach) | 教学状态机 | `src/main/teaching-state-machine/` |
| 改写 (Rewrite) | 改写模块 | IPC Handler: `rewrite:*` |
| 生成 (Generate) | 生成模块 | 通过 IPC 调用 LLM |
| 分析 (Analyze) | 深度分析 | 诊断引擎 + 教学状态机协作 |

#### 6.2.4 与其他规则的协作

- **R-009 用户主权**：用户说"停止"时，意图路由应立即中断当前流程
- **R-021 AI 行为边界**：意图路由不替用户做决定，模糊意图时请求澄清
- **R-029 安全与隐私**：路由前的输入 Guardrails 执行 PII 脱敏
- **R-019 代码规范**：路由逻辑应遵循单函数 <= 50 行，必要时拆分为子分类器

### 6.3 分阶段实施建议

| 阶段 | 内容 | 优先级 |
|------|------|--------|
| **Phase 1** | Embedding-based 快速分类器 + 默认回退到诊断 | P0 |
| **Phase 2** | 添加 LLM 辅助的模糊意图处理 | P1 |
| **Phase 3** | 用户可配置的意图设置（类似 Grammarly Goals） | P2 |
| **Phase 4** | 基于用户历史的自适应路由优化 | P3 |

---

## 7. 参考资料

### Grammarly
- [Under the Hood at Grammarly: Understanding Conversational Sequences with AI](https://www.grammarly.com/blog/engineering/understanding-conversational-sequences-with-ai/) - Grammarly Engineering Blog
- [Grammarly System Design Interview Guide](https://www.educative.io/blog/grammarly-system-design-interview) - Educative.io
- [How to Use Grammarly the Right Way: Goals Feature](https://www.aiafter40.com/use-grammarly-goals-bloggers-influencers-professionals/) - AI After 40
- [What Are Grammarly's AI Features](https://autogpt.net/what-are-grammarlys-ai-features/) - AutoGPT
- [Improving GrammarlyGO Retention](https://www.jakecochran.com/grammarlygo) - UX Case Study

### Writer.com
- [WRITER Integrates with Strands Agents SDK](https://writer.com/engineering/strands-writer/) - Writer Engineering
- [Introducing Palmyra X5](https://writer.com/engineering/long-context-palmyra-x5/) - Writer Engineering
- [WRITER Launches Autonomous Super Agent](https://writer.com/blog/writer-action-agent-press-release/) - Writer Blog
- [Writer Review 2026](https://amrytt.com/writer-review/) - Amrytt
- [Writer Guide 2026](https://www.aitoolsdevpro.com/ai-tools/writer-guide/) - AIToolsDevPro
- [Add External Models](https://dev.writer.com/home/external-models) - Writer Developer Docs
- [WRITER and AWS Team Up](https://writer.com/blog/writer-supervise-press-release/) - Writer Blog

### 行业研究
- [Semantic Routing: Intent-Based Navigation for LLMs](https://fearlessengineers.de/publications/2025-haja-promos-semantic-routing-llm-v1-1.pdf) - Prof. Dr. Andreas Haja
- [Toward Super Agent System with Hybrid AI Routers](https://arxiv.org/html/2504.10519v1) - arXiv
- [Architectural Patterns for the Agentic Era](https://blogs.mulesoft.com/automation/architectural-patterns-for-the-agentic-era/) - MuleSoft
- [Semantic Routing Architecture for AI Agents Communication](https://datatracker.ietf.org/doc/html/draft-li-semantic-routing-architecture-00) - IETF Draft
- [Text Classification Using LLMs](https://avichala.com/blog/text-classification-using-llms) - Avichala
- [Intent Classification](https://www.avahitech.com/glossary/intent-classification) - AvaHiTech
- [Intent Recognition and Classification](https://www.artificial-intelligence-wiki.com/conversational-ai/dialogue-management-and-context/intent-recognition-and-classification/) - AI Wiki
- [mcp-agent Intent Classifier](https://blog.csdn.net/gitblog_01176/article/details/151306967) - CSDN
- [Building Multi-Stage LLM Pipelines](https://www.pmdgtech.com/blog/llm-pipelines/building-smarter-ai-systems-multi-stage-llm-pipelines-explained-2026-complete-guide/) - PMDG Tech

---

> **文档维护说明**：本文档属于 R-017 类别的研究文档。建议每季度回顾一次，跟踪 Grammarly 和 Writer 的架构演进，并更新行业模式部分。
