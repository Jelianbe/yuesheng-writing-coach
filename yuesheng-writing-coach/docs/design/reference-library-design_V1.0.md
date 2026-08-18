# 月笙写作教练 · 后备资料库总体方案（Reference / Knowledge Library）

> 版本：V1.0 ｜ 日期：2026-08-17 ｜ 作者：AI 协作（深度研究 + 设计 + 实现）
> 配套代码：`resources/06-reference-library/`（已落地，typecheck 通过、demo 自检通过）
> 检索说明：`resources/06-reference-library/retrieval-spec.md`

---

## 一、背景与目标

月笙写作教练的核心功能是「让 AI 引导用户学习小说创作」，定位是**教练而非助手**——
不替用户写句子、不替用户做决定、帮用户找到根因。现有资源管线已经覆盖了
「诊断（01）/ 处方（02）/ 教学（03）/ 验证（04）/ 复盘（05）」，但缺少一层
**系统化的「创作知识底座」**：当教练要讲解一个原理、展示好/坏范例、或决定「该怎么引导」
时，它应当从一个**成体系、可检索、有出处**的资料库取数，而不是凭 LLM 即时生成、容易臆断或前后不一致。

本方案设计并实现一个**后备资料库（Reference Library）**，作为 AI 教学时的**补充数据（supplementary data）**，
在不同教学场景下被精准检索与调用，使教练输出「准确、系统、可溯源」。

**设计目标**
1. **内容成体系**：覆盖小说创作关键主题（故事结构 / 人物塑造 / 世界观 / 情节冲突 / 视角文风 / 对话 / 误区）。
2. **结构可机读**：每条知识是带检索元数据的「知识卡」，既给人审校，也给程序检索。
3. **调用可路由**：诊断症候、教学场景、自由查询三条主路径加权合并，精准命中。
4. **哲学可守**：所有「教学提示」强制体现教练姿态，引用遵守项目既有纪律（不编造原文）。

---

## 二、总体架构

资料库位于既有资源管线的「知识底座」位置，与诊断/处方/教学协同：

```
01-diagnosis ──(症候 P00x)──┐
02-prescription ─(技法 TQ/能力 AB)─┤
                              ├─→ 03-teaching（教练话术生成）
06-reference-library ──(知识卡 REF-Cx)─┘        ↑ 取用 availableReferences
                              └─→ 04-validation / 05-retro
```

- `01-diagnosis` 回答「哪里错了」；`02-prescription` 回答「练什么」；
  **`06-reference-library` 回答「这条原理是什么、好/坏范例长什么样、教练该怎么讲」**。
- Teaching Agent 在生成话术前调用 `getForTeachingContext(ctx)`，将命中的知识卡以
  `availableReferences` 注入上下文，与原有 `availableTechniques` 并列。

---

## 三、内容分类（7 大模块 + 子分类）

分类遵循用户指定的关键主题，并细化为可检索的子树（ID 约定：`C1`–`C7` 一级，`Cx.y` 二级）。

| 一级 | 模块 | 二级子分类 |
|:---|:---|:---|
| **C1** | 故事结构 | 三幕式 · 英雄之旅 · 救猫咪节拍表 · 故事圆环/起承转结 · 结构选择 |
| **C2** | 人物塑造 | 人物弧光 · 动机设计 · 立体人物 · 配角与反派 |
| **C3** | 世界观构建 | 设定层级 · 力量/魔法体系 · 信息释放 · 世界一致性 |
| **C4** | 情节与冲突 | 冲突类型 · 悬念与张力 · 场景结构 · 节奏 |
| **C5** | 叙事视角与文风 | 视角类型 · 视角距离 · 展示与告知 · 文风节制 |
| **C6** | 对话写作 | 对话功能 · 潜台词 · 语音个性化 · 节奏与标签 |
| **C7** | 常见创作误区 | 信息倾泻 · 玛丽苏/工具人 · 机械降神 · 开头乏力/节奏 · 视角混乱/杂项 |

> 研究校验：三幕式（Syd Field）、英雄之旅十二阶段（Campbell / Vogler《作家之旅》）、
> 救猫咪 15 节拍（Blake Snyder）、故事圆环（Dan Harmon）、起承转结（Kishōtenketsu）；
> 人物弧光三型 + 想要/需要 + 谎言/创伤/真相 + GMC（K.M. Weiland / 许荣哲《小说课》）；
> 桑德森魔法三定律（硬/软魔法）；展示与告知、信息倾泻、玛丽苏、机械降神等标准误区。
> 权威参考亦在 `externalRefs` 中以「仅书名/作者/框架」方式标注（遵循 `external-resources.json` 纪律）。

---

## 四、条目结构（知识卡 Schema）

每条目是一个结构化知识卡，定义见 `schema.ts`。核心字段：

| 字段 | 类型 | 说明 |
|:---|:---|:---|
| `id` | string | `REF-Cx-xxx` 全局唯一 |
| `title` | string | **标题** |
| `category` / `categoryLabel` | string | 一级分类 ID / 中文名 |
| `subcategory` | string? | 二级子分类 |
| `summary` | string | 一句话核心摘要 |
| `corePoints` | string[] | **核心要点**（3–6 条，成体系的知识点） |
| `examples` | `{context, excerpt, analysis}[]` | **示例片段**（含「为什么有效/失败」的分析，供对比展示） |
| `teachingTips` | string[] | **教学提示**（AI 教练如何用此知识引导，体现教练哲学） |
| `relatedSyndromes` | string[] | 关联诊断症候（P001–P012）→ 诊断路由 |
| `relatedTechniques` | string[] | 关联技法（TQ-/TC-）→ 练习链路 |
| `difficulty` | enum | beginner / intermediate / advanced |
| `retrievalKeywords` | string[] | 检索关键词 |
| `scenarios` | enum[] | 可服务的教学场景 |
| `externalRefs` | `{title, author, note}[]` | 外部参考（仅书名/作者/框架） |

**示例（节选自 REF-C2-002 动机设计）**

```json
{
  "id": "REF-C2-002",
  "title": "动机设计：想要 vs 需要 + 谎言/创伤/真相",
  "category": "C2", "categoryLabel": "人物塑造", "subcategory": "动机设计",
  "summary": "驱动人物的不是『目标』一个词，而是『意识层想要的东西』与『潜意识需要的东西』之间的张力……",
  "corePoints": [
    "想要（Want/外部目标）：人物自以为追求的东西，可被读者像记分牌一样追踪。",
    "需要（Need/内在真知）：人物真正必须学会的东西，往往与『想要』相反。",
    "谎言（Lie）：由过去创伤形成的错误信念，是内部冲突的发动机。",
    "创伤（Ghost）：故事开始前塑造谎言的事件，可用回避与过度反应暗示。",
    "真相（Truth）：谎言的反面、故事的主题。弧光=从谎言走向真相。"
  ],
  "examples": [{
    "context": "史莱克：想要 vs 需要",
    "excerpt": "史莱克的『想要』是独处（他的沼泽）；『需要』是学会自己值得被爱……",
    "analysis": "当他在结尾为朋友冒险而非固守沼泽，观众看到的不只是情节胜利，而是『需要压过了想要』的弧光兑现。"
  }],
  "teachingTips": [
    "动机缺失（P009）时，先问『ta做这个选择，是因为想要什么，还是因为害怕什么？』让学员回到人物内心。",
    "引导学员区分 Want/Need 并写出 From→To→Because 一句论，比列人物小传更有效。",
    "提示：谎言要『扎人』——不冒犯任何人的谎言，冲突就立不起来。"
  ],
  "relatedSyndromes": ["P009", "P002"],
  "relatedTechniques": ["TQ-045", "TQ-058"],
  "difficulty": "intermediate",
  "retrievalKeywords": ["动机", "want", "need", "想要", "需要", "谎言", "创伤", "真相", "ghost", "wound", "lie"],
  "scenarios": ["post-diagnosis", "in-flow-coaching", "pre-training", "browse"]
}
```

---

## 五、检索与调用机制

详细见 `retrieval-spec.md`。要点：

### 5.1 三条主路径（路由）

| 路由 | 触发 | API | 场景 |
|:---|:---|:---|:---|
| 症候路由 | 诊断给出 `primarySyndrome` | `getBySyndrome(id)` | 诊断后讲解根因 |
| 场景路由 | 进入某教学场景 | `getByScenario(s)` | 新用户引导、训练前铺垫 |
| 查询路由 | 用户自由提问 | `search(q)` | 对话内即时教练、扩展阅读 |

### 5.2 核心 API —— 加权合并

```
getForTeachingContext(ctx):
  症候命中  +10
  场景命中  +5
  查询命中  +2
  → 去重 → 按分数排序 → 取 Top-N（默认 6）→ 映射为 InjectableReference
```

权重设计保证：**诊断根因优先于泛讲**，场景资料兜底，查询补位。

### 5.3 注入形态（对齐现有契约）

Teaching Agent 输入在 `availableTechniques` 旁新增 `availableReferences`，结构与 `availableTechniques` 对齐。
教练据此：用 `corePoints` 校准知识点准确性；用 `examples` 做**对比展示**；用 `teachingTips` 约束姿态
（只引导、不代写）；且不向学员暴露 `REF-xxx` 内部编号（遵循既有纪律）。

### 5.4 检索实现

- `search()` 当前为**倒排索引 + 关键词/子串召回**（轻量、确定、可离线）。
  针对中文无空格特性，额外做「条目关键词是否为查询子串」匹配（CJK 友好）。
- **接口不变**前提下，可平滑替换为向量检索（embedding + ANN），无需改动 Teaching Agent。

### 5.5 教练哲学护栏（硬性）

1. **不替写、不替决定**：`teachingTips` 落点必须是「引导性提问 / 让学员自己试」。
2. **找根因**：知识卡必须能解释「为什么这是问题」，而非只给结论。
3. **引用纪律**：`externalRefs` 只写书名/作者/方法论框架，不编造章节、页码、原文。
4. **可溯源**：每条注入携带 `id`，复盘/调试可反查知识卡原文。

---

## 六、教学场景映射表

不同教学场景下，资料库被不同模块主导调用：

| 教学场景 | 主导模块 | 调用方式 |
|:---|:---|:---|
| **新用户引导（onboarding）** | C1 结构、C2 人物、C3 信息释放 | `getByScenario('onboarding')` 给基础全景 |
| **诊断后讲解（post-diagnosis）** | 由 `relatedSyndromes` 决定（如 P009→C2） | `getBySyndrome(P009)` 优先，解释根因 |
| **对话内即时教练（in-flow）** | 视上下文（如视角→C5、对话→C6） | `search(用户上下文关键词)` 补位 |
| **训练前铺垫（pre-training）** | 对应能力节点的知识（如动机→C2.2） | `getBySyndrome` + `getByScenario('pre-training')` |
| **对比展示（contrast-demo）** | 取 `examples` 做好坏对照 | 由命中条目的 `examples[].analysis` 提供 |
| **复盘（review）** | C7 误区 + 对应正面模块 | `getByScenario('review')` |

---

## 七、已交付实体内容（V1.0 = 25 条知识卡）

| ID | 标题 | 模块 |
|:---|:---|:---|
| REF-C1-001 | 三幕式结构：建置—对抗—结局 | C1 故事结构 |
| REF-C1-002 | 英雄之旅：十二阶段的心理蜕变 | C1 |
| REF-C1-003 | 救猫咪节拍表：十五个情绪路标 | C1 |
| REF-C1-004 | 故事圆环与起承转结 | C1 |
| REF-C2-001 | 人物弧光三型：正向/负向/平弧 | C2 人物塑造 |
| REF-C2-002 | 动机设计：想要 vs 需要 + 谎言/创伤/真相 | C2 |
| REF-C2-003 | GMC：目标—动机—冲突 三角 | C2 |
| REF-C2-004 | 立体人物：可共鸣+出众+真实缺陷 | C2 |
| REF-C3-001 | 世界观层级：从地理到潜规则的同心圆 | C3 世界观 |
| REF-C3-002 | 力量/魔法体系：硬与软 + 桑德森三定律 | C3 |
| REF-C3-003 | 信息释放节奏：滴灌而非倾倒 | C3 |
| REF-C4-001 | 冲突的类型：内外双线如何咬合 | C4 情节冲突 |
| REF-C4-002 | 悬念与张力：让读者想翻页 | C4 |
| REF-C4-003 | 场景单元：目标—冲突—转折 | C4 |
| REF-C5-001 | 叙事视角类型：第一/第二/第三人称 | C5 视角文风 |
| REF-C5-002 | 叙事距离与头跳 | C5 |
| REF-C5-003 | 展示与告知：让读者感受而非被告知 | C5 |
| REF-C6-001 | 对话的功能：不止于传递信息 | C6 对话 |
| REF-C6-002 | 潜台词：人物说的与想的不一样 | C6 |
| REF-C6-003 | 语音个性化：每个角色有自己的说话方式 | C6 |
| REF-C7-001 | 误区：信息倾泻（Info Dump） | C7 误区 |
| REF-C7-002 | 误区：玛丽苏 / 工具人 | C7 |
| REF-C7-003 | 误区：机械降神（Deus ex Machina） | C7 |
| REF-C7-004 | 误区：开头乏力与节奏失控 | C7 |
| REF-C7-005 | 误区合集：视角混乱/被动语态/紫废话 | C7 |

覆盖映射：症候 P001–P012 全部有对应条目；关键词倒排索引 256 个 token。

---

## 八、实施状态与验证

- ✅ 分类法与条目结构（`schema.ts`）定义完成
- ✅ 25 条知识卡实体内容（`entries/library-entries.json`）
- ✅ 索引（`library-index.json`，由 `scripts/build-index.mjs` 生成）
- ✅ 运行时检索 API（`library-loader.ts`，`tsc` 隔离类型检查**通过**）
- ✅ 路由演示 + 数据自检（`scripts/demo.mjs`，**PASS**：字段完整、ID 唯一、症候合法；P009/P005/查询路由均命中正确模块）
- ✅ 检索与调用机制说明（`retrieval-spec.md`）+ 本总体方案

**验证命令**
```bash
cd resources/06-reference-library
node scripts/build-index.mjs   # 重建索引
node scripts/demo.mjs          # 路由演示 + 自检
```

---

## 九、后续演进建议

1. **扩写条目**：当前每模块 3–5 条种子条目，建议按教学优先级补足至每子分类 4–6 条。
2. **向量检索**：`search()` 接口稳定后，可接 embedding 检索提升语义召回（尤其中文长句）。
3. **与训练工坊联动**：在 `centerMode='training'` 的训练工坊中，用 `relatedTechniques` 把「知识卡→训练任务」串成闭环。
4. **学员可浏览模式**：`getTaxonomy()` 输出的分类树可直接驱动 UI 的「创作知识」浏览页。
5. **引用增强**：`externalRefs` 可逐步接入更细的方法论框架索引，供教练在合适时机援引。
