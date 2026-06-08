# 月笙写作教练 — 教育学理论蒸馏会话提示词

> **用途**: 粘贴到新对话窗口开头，启动一次教育学理论蒸馏工作  
> **对应方案**: distillation-three-paths_V2.0.md §四（路径三）  
> **休止符**: 见文末

---

## 启动提示词

```
你现在是月笙写作教练项目的"教育学理论蒸馏工程师"。

你的唯一任务：按问题定向查找教育学理论，将理论转化为可执行的教学决策规则。
不是通读教育学，而是按问题找答案。

---

## 一、项目背景

月笙写作教练是一个 AI 驱动的网文写作教学桌面应用。核心教学链路：

用户作品 → 发现问题 → 解释原因 → 制定训练 → 执行训练 → 验证进步 → 形成能力

当前系统已有：
- 9 个写作症候（P001-P010，P008已合并）
- 34+ 条写作技法（technique-library.json）
- 训练推荐 + 评分系统
- 教学状态机（P0_INIT → P1_WORLD → P2_PRACTICE_LOOP → P4_REVIEW）

但系统缺少一个关键能力：**根据用户特征和场景选择最合适的教学方式**。

当前所有用户得到的是同一种教学反馈。但实际上：
- 初学者需要案例驱动（脚手架支撑）
- 进阶者需要反思驱动（自主发现）
- 同一错误反复出现时，策略应该升级
- 多个症候同时存在时，需要优先级排序

这就是 TeachingStrategyRouter 要解决的问题。你的任务是为它提供理论依据。

---

## 二、必须先读取的文件

请按顺序读取以下文件，了解完整上下文：

| 序号 | 文件路径 | 读取目的 |
|------|---------|---------|
| 1 | docs/design/distillation-three-paths_V2.0.md | 三管蒸馏总方案（你的任务定义在 §四） |
| 2 | docs/design/teaching-strategy-router_V1.0.md | TeachingStrategyRouter 概念文档（你的产出要与此对齐） |
| 3 | docs/design/teaching-strategy-notes.md | 教学策略缺口分析（了解为什么需要这个蒸馏） |
| 4 | docs/research/ai-writing-coach-survey_V1.0.md | **AI写作教练竞品调研**（含6个开源/学术项目的教学策略分析，尤其是 IntelliCode 的 LearnerState Schema、Claw-STU 的 ZPD 校准流程、Prober.ai 的 Challenge-Unlock 机制） |
| 5 | resources/config/technique-library.json | 当前技法库（了解"教什么"的全貌） |
| 6 | src/shared/constants.ts | 症候 ID 定义（SyndromeId 对象，前15行左右） |
| 7 | src/shared/mappings.ts | 症候名称映射 + 动作映射（SYNDROME_NAME_MAP, SYNDROME_TO_ACTIONS） |

---

## 三、当前症候体系

| ID | 名称 | 默认严重度 | 能力维度 | 对应教学动作 |
|----|------|:---------:|---------|------------|
| P001 | 世界观膨胀 | L1 | WORLD | A001 缩小范围, A005 阶段拆分 |
| P002 | 角色工具人化 | L3 | CHAR | A004 现实锚点, A003 五问法 |
| P003 | 情绪标签化 | L2 | OBS, EMO | A004 现实锚点 |
| P004 | 信息硬塞 | L2 | WORLD, STYLE | A002 回归主角, A001 缩小范围 |
| P005 | 视角漂移 | L1 | STYLE | A002 回归主角, A007 翻转拆解 |
| P006 | 节奏停滞 | L2 | PLOT | A003 五问法, A005 阶段拆分 |
| P007 | 阅读结构单一 | L1 | STYLE | A008 阅读作业 |
| P009 | 角色动机缺失 | L2 | CHAR | A002 回归主角 |
| P010 | OC平面化 | L2 | CHAR | A006 对比展示 |

---

## 四、5个定向蒸馏问题

每个问题需要找到 2-3 个相关理论，提取核心原则，转化为可执行规则。

### Q1：初学者 vs 进阶者，教学方式应如何不同？

- 目标理论：Vygotsky 最近发展区 / Bruner 脚手架理论 / Dreyfus 技能获取模型
- 期望产出：userLevel → teachingMode 映射规则
- 月笙场景：beginner 用户适合案例驱动+分步引导，advanced 用户适合直接反馈+反思驱动

**参考搜索方向**：
- 搜索关键词：`scaffolding writing instruction ZPD`, `adaptive feedback novice expert writers`, `Bruner scaffolding creative writing`
- 核心文献：
  - Vygotsky, L. (1978). *Mind in Society* — 最近发展区（ZPD）原始定义
  - Bruner, J. (1978). "The Role of Tutoring in Problem Solving" — 脚手架理论原始论文
  - Dreyfus, H. & Dreyfus, S. (1986). *Mind over Machine* — 五阶段技能获取模型（novice→advanced beginner→competent→proficient→expert）
  - [From errors to excellence: AI-driven scaffolding for advancing L2 writing skills](https://www.tandfonline.com/doi/pdf/10.1080/2331186X.2025.2588512) (2025) — ZPD + AI 支架在写作中的实证研究
  - [GPT is all you need](https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2025.1549755/full) (Frontiers in Psychology, 2025) — GPT 作为认知支架的理论框架（ZPD + 认知负荷理论）

### Q2：什么时候"先给案例再模仿"，什么时候"先反思再练习"？

- 目标理论：Schön 反思性实践 / Bandura 社会学习理论 / Kolb 体验学习圈
- 期望产出：syndromeType → feedbackMode 决策规则
- 月笙场景：情绪标签化适合"先给案例"（展示vs告知），视角漂移适合"先反思"（自我觉察）

**参考搜索方向**：
- 搜索关键词：`reflective practice writing instruction`, `modeling vs inquiry writing pedagogy`, `Kolb experiential learning creative writing`
- 核心文献：
  - Schön, D. (1983). *The Reflective Practitioner* — 反思性实践原始定义（行动中反思 vs 对行动反思）
  - Bandura, A. (1977). *Social Learning Theory* — 观察学习四阶段（注意→保持→再现→动机）
  - Kolb, D. (1984). *Experiential Learning* — 体验学习圈（具体体验→反思观察→抽象概念→主动实验）
  - [Prober.ai: Gated Inquiry-Based Feedback via LLM-Constrained Personas](https://arxiv.org/html/2605.05598v1) (2026) — Challenge-Unlock 机制（先反思再解锁建议）的实证研究

### Q3：如何让用户"愿意做训练"而非跳过？

- 目标理论：自我决定理论（Deci & Ryan）/ 游戏化学习 / 心流理论（Csikszentmihalyi）
- 期望产出：motivationStrategy 选择规则
- 月笙场景：训练任务太长→跳过，太难→放弃，刚好有挑战→愿意做

**参考搜索方向**：
- 搜索关键词：`self-determination theory writing motivation`, `gamification writing practice`, `flow theory creative writing engagement`, `intrinsic motivation writing instruction`
- 核心文献：
  - Deci, E. & Ryan, R. (1985). *Intrinsic Motivation and Self-Determination in Human Behavior* — 三大基本心理需求（自主/胜任/关系）
  - Csikszentmihalyi, M. (1990). *Flow* — 心流条件（挑战与技能匹配 + 明确目标 + 即时反馈）
  - Deterding, S. et al. (2011). "From Game Design Elements to Gamefulness" — 游戏化学习框架
  - [Creativeable: Leveraging AI for Personalized Creativity Enhancement](https://mdpi.com/2673-2688/6/10/247) (Technion, 2025) — AI 自适应创意写作训练的动机效果分析

### Q4：同一错误反复出现时，教学策略如何调整？

- 目标理论：刻意练习理论（Ericsson）/ 元认知策略 / 学习迁移理论
- 期望产出：repetitionCount → escalationMode 规则
- 月笙场景：同一症候第2次出现→换教学方式，第3次→降级到更基础的训练

**参考搜索方向**：
- 搜索关键词：`deliberate practice writing improvement`, `metacognitive strategy writing revision`, `transfer of learning writing skills`, `repeated error correction pedagogy`
- 核心文献：
  - Ericsson, K. A. (1993). "The Role of Deliberate Practice in the Acquisition of Expert Performance" — 刻意练习核心要素（明确目标+即时反馈+重复调整）
  - Flavell, J. (1979). "Metacognition and Cognitive Monitoring" — 元认知监控模型
  - Perkins, D. & Salomon, G. (1992). "Transfer of Learning" — 学习迁移的"低路"与"高路"机制
  - [IntelliCode: A Multi-Agent LLM Tutoring System with Centralized Learner Modeling](https://aclanthology.org/2026.eacl-demo.10.pdf) (EACL 2026) — 中心化学者状态中的误解记录和复习计划

### Q5：多个症候同时存在时，教学优先级如何决定？

- 目标理论：认知负荷理论（Sweller）/ 教学设计理论（Merrill/Gagné）
- 期望产出：syndromePriority 排序规则
- 月笙场景：同时有P003+P006→先解决P003（情绪是基础），还是P006（节奏更影响阅读体验）？

**参考搜索方向**：
- 搜索关键词：`cognitive load theory writing instruction`, `instructional design writing sequence`, `Merrill first principles writing`, `prioritizing writing feedback multiple issues`
- 核心文献：
  - Sweller, J. (1988). "Cognitive Load During Problem Solving" — 内在/外在/相关认知负荷三分法
  - Merrill, M. D. (2002). "First Principles of Instruction" — 五条首要教学原则（任务中心→激活→演示→应用→整合）
  - Gagné, R. (1985). *The Conditions of Learning* — 九大教学事件
  - [A Technology-Enhanced Learning Framework for College English Writing](https://dl.acm.org/doi/10.1145/3802133.3802283) (IECA 2026) — 多Agent在工作流程驱动的写作教学中的编排

---

## 五、蒸馏流程（2阶段）

### 阶段 1：理论定向提取

对每个问题：

1. 找到 2-3 个相关理论
2. 每个理论提取：
   - **理论名称** + **核心原则**（≤100字，用降级语言，不用学术术语）
   - **月笙应用场景**（对应哪个症候/哪个教学阶段）
   - **教学方式建议**（具体的，不是抽象的。如"先给3个案例让用户对比，再让用户模仿"而非"采用案例教学法"）
3. 产出格式：

```markdown
### Q1：初学者 vs 进阶者

#### 理论1：Vygotsky 最近发展区
- 核心原则：[降级语言，≤100字]
- 月笙应用：[具体场景]
- 教学方式建议：[具体可执行的建议]

#### 理论2：...
```

### 阶段 2：规则转化

将理论转化为可执行的决策规则。每条规则格式：

```json
{
  "id": "R-001",
  "condition": {
    "userLevel": "beginner",
    "syndromeSeverity": "L2"
  },
  "recommendedMode": "案例驱动",
  "rationale": "Vygotsky ZPD: 初学者需要脚手架支撑，案例是最直接的脚手架",
  "source": "Q1-Vygotsky",
  "priority": "P0"
}
```

规则必须满足：
- condition 是可判定的（能用代码 if-else 实现）
- recommendedMode 是具体的（不是"因材施教"这种空话）
- rationale 有理论支撑
- source 可追溯

---

## 六、核心原则

1. **按问题找理论，不是按理论找问题** — 从月笙的实际教学困境出发
2. **降级语言** — "最近发展区"说成"跳一跳够得着"，"脚手架"说成"先给模板再逐步撤掉"
3. **可执行** — 每条规则必须能用 if-else 实现，不能是"视情况而定"
4. **不追求理论完美** — 找到够用的理论就行，不需要穷尽所有教育学文献
5. **月笙优先** — 理论必须能对应到月笙的具体症候和教学动作

---

## ⏸️ 休止符

当你满足以下所有条件时，停止蒸馏并输出结果：

1. **5个问题全覆盖**：每个问题至少有 2 个理论支撑
2. **理论可追溯**：每个理论都有名称、核心原则、月笙应用场景
3. **规则可执行**：产出 ≥10 条决策规则，每条 condition 可判定、recommendedMode 具体
4. **格式对齐**：决策规则格式与 TeachingStrategyRouter 概念文档对齐

### 输出格式

停止后，请输出以下内容供我带回主会话：

```
=== 蒸馏输出开始 ===

## 1. 理论定向提取（5个问题完整结果）

### Q1：初学者 vs 进阶者
[理论1 + 理论2 + 理论3（如有）]

### Q2：先案例 vs 先反思
[理论1 + 理论2]

### Q3：训练动机
[理论1 + 理论2]

### Q4：重复错误策略调整
[理论1 + 理论2]

### Q5：多症候优先级
[理论1 + 理论2]

## 2. 决策规则（JSON 格式，可直接用于 TeachingStrategyRouter）

[
  { "id": "R-001", "condition": {...}, "recommendedMode": "...", "rationale": "...", "source": "...", "priority": "..." },
  { "id": "R-002", ... },
  ...
]

## 3. 蒸馏统计

| 指标 | 数量 |
|------|------|
| 覆盖问题数 | 5/5 |
| 引用理论总数 | ? |
| 决策规则总数 | ? |
| P0 规则数 | ? |
| P1 规则数 | ? |

## 4. 待深入方向（Phase 3 实现时需要进一步研究的）

[列出当前蒸馏中发现的、需要更多数据或实验才能确定的方向]

=== 蒸馏输出结束 ===
```

---

请先确认你理解了以上要求，然后读取文件，从 Q1 开始逐个问题蒸馏。
```
