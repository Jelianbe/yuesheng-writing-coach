# 蒸馏成果 + V2 提示词系统 — 后续方向评估

> 创建日期：2026-06-21
> 来源：桌面文件 `新建 文本文档.txt` + 代码库已有成果盘点
> 目的：为后续 Sprint 规划提供决策依据，防止遗忘

---

## 一、已有成果盘点

### 1.1 V2 提示词系统（已落地）

| 文件 | 版本 | 说明 |
|:-----|:------|:------|
| `resources/prompts/teaching-agent-prompt-v2.md` | V2 | 教学提示词，引入能力节点（AB-XXX），症候→能力→技法映射 |
| `resources/01-diagnosis/diagnosis-agent-prompt-v2.md` | V2 | 诊断提示词，P001→P012 扩展，461 条蒸馏信号，经典原则注入 |
| `resources/03-teaching/prompts/teaching-agent-prompt-v2.md` | V2 | 新版架构下的 V2 教学提示词 |
| `resources/prompts/yuesheng-prompt-v3.md` | V4 (名 v3 实 v4) | Skill 工程化：5 个独立 Skill + 动态组装 |
| `resources/prompts/skills/` | V4 | 5 个 Skill 文件（IDENTITY/TEACHING/VALIDATION/FEEDBACK/SCENARIO） |

### 1.2 蒸馏素材（已落地）

| 文件 | 条数 | 内容 |
|:-----|:----:|:-----|
| `写作蒸馏素材-200条-避雷与教学指导` | 200 | 写作避雷 100 条（反面）+ 教学指导 100 条（正面） |
| `写作蒸馏素材-扩展第2批-实战困境与习惯养成200条` | 200 | 实战困境 + 习惯养成 |
| `写作蒸馏素材-扩展第3批-情节场景对话补充61条` | 61 | 情节/场景/对话补充 |
| **合计** | **461** | **分布在 `resources/distillation-versions/` 和 `resources/01-diagnosis/signals/`** |

蒸馏素材已用于：
- Diagnosis Agent V2 的信号表（每批次从素材提炼 3-6 条结构化的高频识别信号）
- P001-P012 症候检测的权重体系
- classical-map 经典原则对照

### 1.3 能力图谱数据体系（已落地但未工程化接入）

以下文件构成了完整的能力图谱数据基础设施，**当前以静态 JSON/MD 形式存在，尚未被代码引擎消费**：

| 数据资产 | 文件 | 结构 | 说明 |
|:---------|:-----|:-----|:------|
| **能力图谱** | `resources/knowledge-graph/ability-atlas.json` | 8 能力节点 + 10 症候 + 20 训练任务 | 节点含依赖关系（ABL-005 依赖 ABL-001），症候→能力→任务三角映射 |
| **能力节点原型** | `resources/02-prescription/ability-nodes/ability-node-prototypes.json` | 5 个原子节点（AB-001~005） | 每个节点含教学翻译、真实教学案例、教学路径、关联经典原则 |
| **症候识别手册** | `resources/01-diagnosis/syndromes/syndrome-manual.md` | P001-P010 详案 | 含信号类型/权重/严重度分级/触发条件/真实案例 |
| **症候-经典映射** | `resources/01-diagnosis/syndromes/syndrome-classical-map.json` | 9 条症候映射 | 每条含诊断逻辑(diagnosisLogic)、提问方向(questionDirection)、经典原则引用 |
| **症候-动作映射** | `resources/01-diagnosis/syndromes/syndrome-action-map.json` | 9 条动作映射 | 每条含 triggerSignal/triggerTemplate/coachingQuestion，供 TeachingStrategyRouter 消费 |
| **症候类型映射** | `resources/01-diagnosis/syndromes/syndrome-type-map.json` | 症候类型分类 | motivation_deficit / expressive_deficit / structural_disorder |

#### ability-atlas.json 核心能力节点

| 编号 | 名称 | 分类 | 关联症候 | 前置能力 | 等级 |
|:-----|:-----|:-----|:---------|:---------|:----:|
| ABL-001 | 结构控制 | 叙事能力 | P001, P006 | ABL-002 | 2 |
| ABL-002 | 场景构建 | 叙事能力 | P004, P006 | — | 1 |
| ABL-003 | 角色塑造 | 角色能力 | P002, P009, P010 | ABL-002 | 2 |
| ABL-004 | 角色逻辑链 | 角色能力 | P002, P009 | ABL-003 | 3 |
| ABL-005 | 世界观工程 | 世界观能力 | P001, P004 | ABL-001 | 3 |
| ABL-006 | 视角控制 | 叙事能力 | P005 | ABL-002 | 2 |
| ABL-007 | 表达能力 | 语言能力 | P003 | — | 1 |
| ABL-008 | 阅读素养 | 学习能力 | P007 | — | 1 |

#### ability-node-prototypes.json 原子节点示例（AB-003 具象化能力）

```json
{
  "id": "AB-003",
  "professionalLabel": "情感具象化 / Emotional Concretization",
  "teachingTranslation": "删掉情绪词，用动作让读者感受到。",
  "manifestations": {
    "positive": "读者从字里行间感受到情绪",
    "negative": "直接命名情绪（伤心/难过/痛苦）"
  },
  "teachingApproach": {
    "primary": "感官替代法 — '删掉这个情绪词，用具体动作来替代'",
    "alternative": "三重对比法 — '空间对比+时间对比+情感对比'"
  },
  "relatedPrinciples": ["CHEKHOV_EMOTION", "WANG_ZENG_QI_ACCURACY"]
}
```

#### 关键发现：能力图谱的核心数据已基本完成，缺少的是「工程化接入」
- 症候→能力→训练任务的映射已完整（ability-atlas.json）
- 原子级教学节点原型已完成 5/8（ability-node-prototypes.json）
- 诊断逻辑和经典原则映射已完整（syndrome-classical-map.json）
- **缺失**：代码层（TypeScript）读取这些 JSON 数据的 loader，以及教学引擎/诊断引擎对此数据的消费逻辑

---

## 二、桌面文件中的范式迁移讨论（部分已落地，部分待实现）

你（月笙如歌）在与豆包、GPT、Claude 的多次对话中，讨论了更深层的架构升级：

### 2.1 核心范式：从"技法中心" → "能力中心"

```
当前（已实现）:         未来（待实现）:
诊断 → 匹配技法         诊断 → 识别能力短板 → 激活对应能力节点
    ↓                       ↓
  推荐技法学              帮学员"长能力"
    ↓                       ↓
  技法列表                 能力图谱（Capability Graph）
```

- 现有系统是"诊断出 P003 → 推荐 TQ-025/TQ-026"
- 目标是"诊断出 P003 = AB-003 具象化能力不足 → 激活能力节点 → 学员掌握该能力后，自然不需要再教"

### 2.2 去金句化（De-quotification）

已在 Teaching Agent V2 中体现（第 2 条：不暴露内部编号、不说"你错了"）
但更彻底的方向是：
- 不在 Prompt 中写"契诃夫说过..."
- 把经典原则内化为能力节点的训练逻辑
- 学员感受到的是"我在学本事"，不是"AI 在旁征博引"

### 2.3 原子技法拆解（28个核心原子）

从大师作品中蒸馏出的原子级技法（非传统的技巧分类）：
- 不是"感官替代法"这样的大分类
- 而是"用触觉替代视觉 → 用温度传递情绪"这样的原子级操作
- 每个原子技法对应一个能力节点的最小可训练单元

### 2.4 SPARK 模型（新 Prompt 架构）

一个五步式教学对话模型：
- **S**（锚定场景）— 锁定学员当前的具体场景
- **P**（探询感知）— 探索学员的认知状态
- **A**（激活选择）— 给选择，不给答案
- **R**（响应构建）— 学员自己构建方案
- **K**（肯定并链接）— 强化信心，链接到能力图谱

### 2.5 "写诊练问"闭环

| 阶段 | 描述 |
|:-----|:------|
| **写** | 学员自由创作 |
| **诊** | AI 诊断（现有系统） |
| **练** | 针对能力短板的微训练（现有系统） |
| **问** | 学员主动提问（新方向） |

### 2.6 UI 设计方案（三个方向）

A. **创作工作台**（类似专业写作工具的左侧编辑器 + 右侧教练面板）
B. **学习 OS**（类似 Duolingo 的学习路径 + 成就系统）
C. **教师批注区**（类似 Word 批注 + 语文老师旁批风格）

**倾向：A+C 融合** — 左侧是干净的写作界面，右侧是教练面板 + 旁批注释。

---

## 三、后续方向评估

### 方向 A：能力图谱工程化接入（推荐最高优先级）

**关键修正**：能力图谱的核心数据**已基本完成**（ability-atlas.json 含 8 节点+10 症候+20 任务，ability-node-prototypes.json 含 5 个原子节点原型）。方向 A 的实际任务是**工程化接入而非重新构建**。

**做什么**：
- 编写能力图谱 JSON 的 TypeScript loader（读取 `ability-atlas.json` + `ability-node-prototypes.json`）
- 将症候→能力→训练任务的映射数据注入诊断引擎和教学引擎
- 将 JSON 中 3 个类型（`motivation_deficit`/`expressive_deficit`/`structural_disorder`）对应的教学策略路由代码化
- 将 `syndrome-action-map.json` 的 triggerTemplate/coachingQuestion 接入 TeachingStrategyRouter（已有消费方标注）
- 将 `ProgressWorkspace` 的能力画像展示与 `ability-atlas.json` 的真实数据打通
- 将蒸馏素材从 MD 文件移到 SQLite 或结构化 JSON，按能力节点重新索引

**关联现有代码/数据**：
- `resources/knowledge-graph/ability-atlas.json` — 能力图谱数据结构（已有 ✅）
- `resources/02-prescription/ability-nodes/ability-node-prototypes.json` — 原子节点原型（已有 ✅）
- `resources/01-diagnosis/syndromes/syndrome-classical-map.json` — 经典原则映射（已有 ✅）
- `resources/01-diagnosis/syndromes/syndrome-action-map.json` — 动作映射（已有 ✅，标注 TeachingStrategyRouter 消费）
- `resources/01-diagnosis/syndromes/syndrome-manual.md` — 症候详细手册（已有 ✅）
- `src/shared/types/types-growth.ts` — AbilityProfile 接口（已有 ✅）
- `src/renderer/components/right/workspaces/ProgressWorkspace/` — 能力画像展示组件（已有 ✅）

**预估工作量**：Medium（~1-2 个 Sprint），比之前评估的更轻

### 方向 B：V5 Prompt — SPARK 模型落地

**做什么**：
- 基于 V4 Skill 工程化架构，增加 SPARK 教学对话模型
- 开发一个新的 SKILL-SPARK.md 替代现有 teaching 流程
- 重构教学状态机以支持 SPARK 五步流转
- 保证向下兼容（现有 V2 提示词不受影响）

**预估工作量**：Small-Medium（~1 个 Sprint）

### 方向 C：UI 全面改版（写作工作台 + 教师批注）

**做什么**：
- 将当前聊天界面改为"左侧编辑器 + 右侧教练面板"布局
- 实现行内批注系统（类似 Word 批注）
- 能力画像可视化（能力雷达图 / 成长树）
- 教练面板上下文感知（随诊断/教学/验证阶段变化）

**关联现有代码**：
- `CenterPanel` 已有 editor/diagnosis/teaching 视图切换
- `ProgressWorkspace` 已有 0/N 进度 + 能力画像展示

**预估工作量**：Large（~3-4 个 Sprint）

### 方向 D：蒸馏素材工程化

**做什么**：
- 将 461 条蒸馏素材正式化为关系型数据（SQLite 表）
- 实现素材 → 能力节点 → 教学策略的自动化映射
- 建立素材版本管理（当前分布在 3 个 MD 文件中，难以管理）
- 为未来持续蒸馏（第 4 批、第 5 批）提供基础设施

**预估工作量**：Small（~0.5 Sprint，可并入方向 A 一起做）

---

## 四、推荐路线

```
Sprint N ──── 方向 A（能力图谱工程化）+ D（蒸馏素材工程化）
         ↓
Sprint N+1 ── 方向 A（能力画像增量更新）+ B（SPARK 模型）
         ↓
Sprint N+2 ── 方向 C（UI 改版第一阶段：写作工作台布局）
         ↓
Sprint N+3 ── 方向 C（教师批注系统）
```

但也可以根据当时的产品目标灵活调整。推荐从 **方向 A+D** 开始，因为：
1. 能力图谱是"写诊练问"闭环的**基础设施**
2. 蒸馏素材工程化是后续一切数据驱动的基础
3. A+D 不涉及 UI 变动，可以在当前代码结构上平滑推进
4. 完成后，V2 Prompt（teaching + diagnosis）可以直接使用能力图谱数据

---

## 五、外部研究趋势验证

以下来自 2025-2026 年的学术论文和行业报告，与我们的方向高度一致：

### 5.1 知识图谱 + 写作评估（PeerJ 2025）

**论文**：*Optimising AI writing assessment using feedback and knowledge graph integration* (Zhang, 2025)

- 提出 **dynamic relational knowledge graph**（动态关系知识图谱），将写作概念及其关系建模为图结构
- 使用 GNN（图神经网络）增强模型对复杂语义的理解
- 引入**迭代式用户反馈机制**，根据历史反馈和写作行为变化调整系统
- 结论：知识图谱集成后的系统在用户参与度和反馈质量上远超传统方法

**→ 我们的对应**：能力图谱（Capability Graph）本质上就是写作领域的动态关系知识图谱，AB-XXX 能力节点即为图节点，症候→能力映射即为边关系。

### 5.2 以作者为中心的教学法（arXiv 2026）

**论文**：*From Crafting Text to Crafting Thought: Grounding AI Writing Support to Writing Center Pedagogy*

- 提出 AI 写作支持应遵循三个核心原则：**Writer-Centered（以作者为中心）**、**Process-Oriented（过程导向）**、**Collaborative（协作式）**
- AI 不应替写，而应通过苏格拉底式提问引导作者自我发现
- 设计了一个左侧编辑器 + 右侧反馈面板的 UI（与我们的创作工作台方案完全一致）

**→ 我们的对应**：月笙的"不替写"原则、SPARK 模型的 S（锚定场景）+ P（探询感知）阶段、A+C UI 设计方案。

### 5.3 Prompt 工程进化：从提示词到系统设计（2026 行业共识）

多篇英文和中文文章共同指向一个趋势：
- Prompt 工程正在从"写提示词"进化到 **"设计 AI 系统交互协议"**
- Anthropic 的 Constitutional AI 框架 → 我们的 R-029 安全规则 + R-026 Prompt 工程规范
- 结构化指令设计（分层次/可测试/可版本管理） → 我们的 Skill 工程化（V4）
- 动态 Few-Shot / 自洽性采样 / 推理链工程化 → 未来可引入到 V5

**CARE / RACE / BAB 框架对比**：我们的 SPARK 模型（S-锚定/P-探询/A-激活/R-响应/K-肯定）与这些框架属于同一代产物，但更贴合"教练"而非"工具"的产品定位。

### 5.4 Skill 工程化成为行业标准（2026）

Anthropic 将 Agent Skills 发布为开放标准（2025-12），Microsoft/OpenAI/Cursor 等快速跟进：
- Skill = AI 的"岗位经验包"：指令 + 脚本 + 模板 + 工作流程
- 我们 V4 Prompt 的 5 个独立 Skill + 动态组装模式，正是这个方向的先行实践

**→ 启示**：未来可以将 SKILL-IDENTITY/TEACHING/VALIDATION/FEEDBACK/SCENARIO 从 MD 文件进化为**可执行的代码模块**。

### 5.5 写作教练 Agent 的分层反馈（CallSphere 2026）

**文章**：*Building a Writing Coach Agent: Grammar, Style, and Structure Feedback*

- 分层反馈模型：Structure（结构）→ Content（内容）→ Style（风格）→ Mechanics（语法）
- 结构化的 Feedback Data Model（dataclass 定义，含 category/severity/location/suggestion）
- 与诊断引擎的 P001-P012 症候分层理念一致

### 5.6 行业竞品趋势

| 产品/方案 | 特点 | 与我们的差异 |
|:----------|:-----|:-------------|
| **Gakku.AI** | K-12 写作教练，Lesson Map + 游戏化，Raku 虚拟伙伴 | 目标群体不同（K-12 vs 网文作者），无能力图谱 |
| **QuillBot** | 改写/润色工具，2026 增强上下文理解和风格分析 | 工具型（改文本），非教练型（教写作） |
| **DeepWriter** | 基于离线知识库的多模态长文写作助手 | 生成型助理，非诊断+教学闭环 |
| **全能写作专家**（腾讯元器） | 工作流式写作 Agent，需求收集→规划→创作 | 一次性生成工具，无持续诊断和教学状态机 |

**→ 我们的独特定位**：目前市场上没有同时具备"深度诊断 + 能力图谱 + 教学状态机 + 写诊练问闭环"的 AI 写作教练产品。

---

## 六、2026-06-21 讨论：训练任务体系重构方向

### 6.1 当前训练任务的三个断层

| # | 断层 | 表现 |
|:--|:-----|:------|
| 1 | T001-T020 ↔ challenge-templates.json | 两套任务列表完全独立，T001 和 CH-P003-001 说的是同一件事但无 ID 关联 |
| 2 | AB-001~005 ↔ ABL-001~008 | 两套能力节点体系并行（教学原子 vs 能力图谱），无映射关系 |
| 3 | syndrome-action-map.json ↔ challenge-templates.json | 教学动作和训练任务之间缺乏衔接链 |

### 6.2 现有训练内容的四个不足

| # | 不足 | 说明 |
|:--|:-----|:------|
| 1 | 深度止步于技巧层面 | 任务只练"删情绪词"，不覆盖"会删但不敢删"的信心缺失型问题 |
| 2 | 与真实写作之间存在迁移断层 | 在假设场景里练完，回到学员自己五千字章节时没有迁移环节 |
| 3 | 难度梯度不明显 | T001 "紧张的人" vs T002 "愤怒的人" 更像是换了种情绪，不是真正的难度递进 |
| 4 | 与 461 条蒸馏素材缺乏对应关系 | 素材中有大量学员常见错误模式，但任务不是基于素材设计的 |

### 6.3 七阶段发展路径（已有，未工程化接入）

文件：`resources/02-prescription/learning-paths/development-path.json`

| 阶段 | 核心问题 | 经典根基 | 入门练习 |
|:-----|:---------|:---------|:---------|
| 1. 练眼 | 写什么？（素材从哪来） | 老舍"非有生活不可"、叶圣陶"精密观察"、沈从文"车零件" | 指定视角阅读、看烂书·找茬、看烂书·归类 |
| 2. 练笔 | 怎么写完整？ | 老舍"先练一人一事"、叶圣陶"每句话都有分量" | 一人一事、段落基石 |
| 3. 练字 | 怎么写准确？ | 汪曾祺"唯一标准是准确"、契诃夫"不命名情绪"、鲁迅"删可有可无" | 删可有可无、情绪标签替换训练 |
| 4. 练人 | 怎么写活人？ | 老舍"人物不是传声筒"、沈从文"贴着人物写"、Forster"圆形人物" | 动机冰山模型、人物动作先于对话 |
| 5. 练局 | 怎么写紧凑？ | 契诃夫"第一幕挂枪"、老舍"有话则长无话则短" | 得与失框架、冰山叙事法、信息分层释放 |
| 6. 练控 | 怎么控制读者感受？ | John Gardner"持续梦境"、Booth"修辞控制" | 读者视角互换、悬念设置 |
| 7. 练味 | 怎么写诚实而有味？ | 朱光潜"趣味是终极门槛"、汪曾祺"第二次平淡" | 高阶平淡练习、朱光潜十病自检 |

每阶段还包含：entryPractices（具体练习方法）、passCriteria（可量化通过标准）、associatedSyndromes。

### 6.4 提出的新方案：五步通用训练流

**问题**：当前"每个症候 x 难度 = 独立任务"模式不可持续，技法库膨胀会导致训练任务库跟着膨胀。需要将训练方法通用化。

**方案**：对每个大类技法，用统一的五步流程：

```
解说技法 → 例证展示 → 确认理解 → 主动尝试 → 修改反馈
```

#### 变化要点

| 方面 | 当前模式 | 新模式 |
|:-----|:---------|:-------|
| 任务来源 | 每个症候独立设计场景 | 拉取学员自己原文中相关段落，在学员自己文本上练 |
| 示例展示 | 固定在 challenge-template 中 | 从 reading-library.json 取经典文学示例（鲁迅祥林嫂白描等），或让学员找自己读过的文 |
| 评估标准 | 每个任务独立写 evaluationCriteria | 统一评估：对比改前改后，学员文本是否更接近技法目标 |
| 技法库维护 | 新增技法 = 新增任务场景 | 新增技法 = 只需在 5 步流的"解说"和"例证"环节注入新内容 |

#### 对现有组件的影响

| 组件 | 变化 |
|:-----|:------|
| challenge-templates.json | 从"任务内容库"变为"技法示例库" |
| training-recommendation.service.ts | 从"匹配症候→模板"变为"匹配症候→决定训练阶段（解说/展示/尝试）" |
| training-evaluator-prompt-v1.md | 从"约束是否满足"变为"改前改后对比评估" |
| Teaching Agent | 新增训练流程编排能力 |

### 6.5 待定事项（用户将二次评估）

以下 7 条来自 V2 提示词对话分析，用户保持保留态度，待二次验证：

| 项目 | 优先级 | 说明 |
|:-----|:------:|:------|
| 信心缺失型学员识别与应对 | P0 | 高基础学员"会写但不敢写"，当前 prompt 无覆盖 |
| 边界校准教学动作 | P1 | 学员顿悟后走形风险的管控结构 |
| 跨语境迁移策略 | P1 | 用现代等价物类比古风设定的教学法 |
| 阶段认知机制 | P2 | 练笔 vs 结构阶段的阶段自检清单 |
| 挫败感多信号应对 | P2 | 三种不同挫败形态的差异化应对 |
| 真实案例替换虚构示例 | P3 | 阿元/琴玥无双/得与失/这维来特 → 注入 prompt |
| studentState 输出字段 | P4 | 输出格式增加学员状态元数据 |

---

## 七、关键文件索引（防止遗忘）

| 内容 | 路径 |
|:-----|:------|
| 桌面原始讨论（完整对话） | `C:\Users\月笙如歌\Desktop\新建 文本文档.txt` |
| **能力图谱（完整数据）** | `resources/knowledge-graph/ability-atlas.json` |
| **能力节点原型** | `resources/02-prescription/ability-nodes/ability-node-prototypes.json` |
| **症候识别手册** | `resources/01-diagnosis/syndromes/syndrome-manual.md` |
| **症候-经典原则映射** | `resources/01-diagnosis/syndromes/syndrome-classical-map.json` |
| **症候-动作映射** | `resources/01-diagnosis/syndromes/syndrome-action-map.json` |
| **症候类型映射** | `resources/01-diagnosis/syndromes/syndrome-type-map.json` |
| **经典原则库** | `resources/config/classical-principles.json` |
| 蒸馏素材第 1 批（200 条避雷+教学） | `resources/distillation-versions/v3.1+/写作蒸馏素材-200条-避雷与教学指导.md` |
| 蒸馏素材第 2 批（200 条实战困境） | `resources/distillation-versions/v3.1+/写作蒸馏素材-扩展第2批-实战困境与习惯养成200条.md` |
| 蒸馏素材第 3 批（61 条情节场景） | `resources/distillation-versions/v3.1+/写作蒸馏素材-扩展第3批-情节场景对话补充61条.md` |
| Teaching Agent V2 | `resources/prompts/teaching-agent-prompt-v2.md` |
| Diagnosis Agent V2 | `resources/01-diagnosis/diagnosis-agent-prompt-v2.md` |
| V4 Prompt（Skill 工程化） | `resources/prompts/yuesheng-prompt-v3.md` |
| 5 个独立 Skill | `resources/prompts/skills/` |
| 诊断升级日志 | `resources/prompts/DIAGNOSIS-UPGRADE-CHANGELOG.md` |
| 能力画像类型 | `src/shared/types/types-growth.ts` |
| 能力画像展示组件 | `src/renderer/components/right/workspaces/ProgressWorkspace/` |
| 能力图谱 JSON（共享类型） | `resources/config/ability-node-prototypes.json` |
