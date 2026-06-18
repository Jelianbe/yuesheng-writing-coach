# D 阶段蒸馏验证 — 外部 AI 审查 Prompt

## 项目背景

你正在审查一个**写作教练 AI**（"月笙"）的配置数据。该教练系统基于症候诊断式教学法，通过识别用户写作中的"症候"（P001~P010），匹配对应"教学动作"（A001~A004）和"技法"（100+ 条），安排"训练"（练习）。

核心教学流程：
1. **诊断**：分析原文 → 识别症候（P001~P010）
2. **策略**：根据症候、态度档位选择教学路径
3. **执行**：运用匹配的教学动作指导用户修改
4. **训练**：安排针对性练习巩固

---

## ⚠️ 重要：项目实际使用的是 P 体系症候

项目代码库中**不存在 "V-01~V-09" 症候体系**。实际使用的症候体系如下（P001~P010）：

| ID | 症候名称 | 类型 | 描述 |
|:--:|:---------|:----:|:-----|
| P001 | 世界观膨胀 | motivation_deficit | 大量世界观设定但主角模糊 |
| P002 | 角色工具化 | expressive_deficit | 角色行为缺乏动机或前后不一致 |
| P003 | 情绪标签化 | expressive_deficit | 直接用情绪词概括，无具体描写 |
| P004 | 信息硬塞 | structural_disorder | 设定通过旁白交代而非角色日常 |
| P005 | 视角漂移 | structural_disorder | 写了主角看不到/听不到的信息 |
| P006 | 节奏停滞 | structural_disorder | 连续多段没有推进或冲突 |
| P007 | 阅读结构单一 | structural_disorder | 文本结构缺乏变化，通篇同一句式 |
| P009 | 角色动机缺失 | motivation_deficit | 角色行为缺乏内在驱动力 |
| P010 | OC平面化 | expressive_deficit | 原创角色缺乏立体感和独特性 |

3 种类型分型：
- **motivation_deficit**（动机缺失型）：P001, P002, P009
- **expressive_deficit**（展示力不足型）：P003, P010, P002
- **structural_disorder**（结构/视角失控型）：P005, P006, P004, P007

**所有审查任务都使用 P 体系，不要引入 V 体系。**

---

## 任务 1 (D-02)：症候映射蒸馏

### 输入文件
文件：`syndrome-type-map.json`
结构：3 种 type（expressive_deficit / structural_disorder / motivation_deficit），每种包含症候列表 + coreIssue + recommendedEntry + rationale。

### 验证项目

逐项检查：

#### 1. 症候完整性
验证以下症候是否全部存在且分类正确：
- P001: 世界观膨胀 → motivation_deficit ✅
- P002: 角色工具化 → expressive_deficit ✅
- P003: 情绪标签化 → expressive_deficit ✅
- P004: 信息硬塞 → structural_disorder ✅
- P005: 视角漂移 → structural_disorder ✅
- P006: 节奏停滞 → structural_disorder ✅
- P007: 阅读结构单一 → structural_disorder ✅
- P009: 角色动机缺失 → motivation_deficit ✅
- P010: OC平面化 → expressive_deficit ✅

#### 2. 命名一致性
检查各文件中同一症候的 name 是否一致：
- `syndrome-type-map.json` 中的 `types.*.syndromes` 数组
- `syndrome-action-map.json` 中的 `syndromeName`
- `training-library.json` 中的 `entries.*.syndromeName`
- `technique-library.json` 中的 `applicableSyndromes`

**已知不一致**：
- P003 在 syndrome-action-map 中叫"情绪标签化"，但在 training-library 中叫"动词匮乏"——确认哪个正确

#### 3. 幽灵引用
检查是否引用了不存在的症候：
- `training-library.json` 的 `categories` 中 expressive_deficit 的 `syndromeIds` 包含 ["P003","P004","P005","P006","P007","P008","P010","P011"]
- **P008 和 P011 在 syndrome-type-map.json 中不存在** → 这是幽灵引用吗？还是需要补充定义？

#### 4. structural_deficit 空缺
`training-library.json` 中 structural_deficit 类的 `syndromeIds: []` 为空——structural 类的症候（P004/P005/P006/P007）没有对应的训练分类。这是设计决定还是需要补充？

#### 5. discoverable 合理性
`syndrome-action-map.json` 中每条症候有 `discoverable` 字段：
- `true`：P002(角色工具化), P003(情绪标签化), P009(角色动机缺失), P010(OC平面化)
- `false`：P004(信息硬塞), P006(节奏停滞), P007(阅读结构单一)
- `"partial"`：P001(世界观膨胀), P005(视角漂移)

判断每个症的 discoverable 标注是否合理（指是否适合"引导发现式"教学路径）。

### 输出格式
```
### D-02 Patch
#### [问题类别]
- 问题：...
- 建议修改：...
- 理由：...
```

---

## 任务 2 (D-03)：手法库交叉验证

### 输入文件
文件：`technique-library.json`
结构：包含 **128 个技法条目**，每个技法有 `techniqueId`、`name`、`category`（'rhetoric' | 'logic' | 'structure' | 'detail' | 'emotion' | 'comprehensive'）、`applicableSyndromes`（引用 P 体系）、`steps`、`example`、`difficulty`、`discoverable` 等字段。

### 验证标准
1. **归类合理性**：每个技法所属 `category` 是否与其本质匹配？
2. **技法完整性**：`steps` 是否可操作？`example` 是否提供具体示范？
3. **难度分级**：`difficulty`（'beginner'|'intermediate'|'advanced'）是否与技法复杂度匹配？
4. **discoverable 一致性**：若 `discoverable: true`，说明该技法适合"引导发现"教学路径——这个判断是否合理？

### 输出格式
```
### D-03 Patch
#### [技法ID] [技法名]
- 问题：...
- 建议修改：...
- 理由：...
```

---

## 任务 3 (D-05)：训练库内容填充

### 输入文件（骨架）
文件：`training-library.json`

实际结构：
```json
{
  "categories": [
    {
      "id": "motivation_deficit",
      "name": "动机缺失型",
      "syndromeIds": ["P001", "P002", "P009"],
      "entries": [ /* 训练条目 */ ]
    },
    {
      "id": "expressive_deficit", 
      "name": "表达不足型",
      "syndromeIds": ["P003", "P004", "P005", "P006", "P007", "P008", "P010", "P011"],
      "entries": [ /* 训练条目 */ ]
    },
    {
      "id": "structural_deficit",
      "name": "结构混乱型",
      "syndromeIds": [],
      "entries": []
    }
  ]
}
```

### 填充要求
为每条症候补充训练条目。每条训练条目格式：

```json
{
  "id": "TRAIN-P001-001",
  "syndromeId": "P001",
  "syndromeName": "世界观膨胀",
  "title": "简短标题",
  "difficulty": "easy / medium / hard",
  "mode": "narrow_focus / character_depth / word_refine / restructure",
  "tier": "surface / structural / deep",
  "constraint": "训练约束条件，描述用户需要做什么",
  "expectedOutcome": "预期学习成果",
  "techniques": ["技法的 techniqueId"],
  "exercises": [
    {
      "step": 1,
      "instruction": "练习步骤描述",
      "duration": "5min"
    }
  ]
}
```

### 分布要求
| 症候 | 建议分类 | 已有 | 需补充 |
|:----:|:---------|:----:|:------:|
| P001 世界观膨胀 | motivation_deficit | 2 条 | ≥1 |
| P002 角色工具化 | motivation_deficit | 1 条 | ≥2 |
| P003 情绪标签化 | expressive_deficit | 1 条 | ≥2 |
| P004 信息硬塞 | structural_disorder | 0 | ≥1 |
| P005 视角漂移 | structural_disorder | 0 | ≥1 |
| P006 节奏停滞 | structural_disorder | 0 | ≥1 |
| P007 阅读结构单一 | structural_disorder | 0 | ≥1 |
| P009 角色动机缺失 | motivation_deficit | 0 | ≥2 |
| P010 OC平面化 | expressive_deficit | 0 | ≥1 |

### 输出格式
输出完整的 `training-library.json` 文件，所有新增条目追加到对应分类的 `entries` 数组中（保留现有条目）。

---

## 任务 4 (D-06)：症候↔教学动作映射验证

### 输入文件
文件：`syndrome-action-map.json`
结构：9 条症候 → 各映射到一个 `primaryAction`（A001~A004）+ `discoverable` + 触发信号 + 教学话术模板。

### 4 个教学动作定义
| 动作ID | 名称 | 适用场景 |
|:------:|:-----|:---------|
| A001 | 缩小范围 | 症候表现为"过多/过广"时，引导用户聚焦 |
| A002 | 回归主角 | 症候表现为"偏离主线/视角混乱"时，将用户拉回主角视角 |
| A003 | 五问法 | 症候表现为"缺乏深度"时，通过连续追问引导深入 |
| A004 | 现实锚点 | 症候表现为"空洞/标签化"时，用现实参照系替代抽象描述 |

### 验证标准
1. **映射合理性**：每条症候的 `primaryAction` 是否对症？
2. **触发信号精度**：`triggerSignal` 是否清晰可识别？
3. **话术可操作性**：`coachingQuestion` 是否可用作教练的真实提问？
4. **discoverable 一致性**：与 D-02 的 discoverable 判断保持一致

### 输出格式
```
### D-06 Patch
#### [症候ID]
- 当前 primaryAction: [A00X]
- 建议：...
- 理由：...
```

---

## 任务 5 (V4-DIST-1/2/6)：网络写作避雷搜索 + 症候缺口分析

### 背景
从写作社区采集真实写作问题素材，映射到 P 体系症候，发现覆盖缺口。

### 搜索方向
| 批次 | 关键词 | 目标 |
|:----:|--------|------|
| 1 | "写作课没用" "AI写作后悔" "写作班踩坑" | 识别的真实教学盲区 |
| 2 | "网文读者最讨厌什么" "小说开头劝退" | 读者视角的症候验证 |
| 3 | "新人写小说常犯错误" "写作新手踩坑" | 新手常见问题 → 症候覆盖度 |
| 4 | "网文签约技巧" "编辑审稿标准" "签约被拒原因" | 市场验证：症候是否覆盖编辑关注的问题 |
| 5 | "AI文检测" "如何避免AI味" "AI写作被看出来" | 防御点 F 素材 + 技法验证 |

### 输出格式
每条素材结构：
```json
{
  "source": "帖子标题或片段（匿名化）",
  "platform": "知乎/小红书/豆瓣/...",
  "keyword": "搜索关键词",
  "problem": "用户/读者描述的问题",
  "mappedSyndrome": "P00X 或 null（若无法映射）",
  "mappingConfidence": "high/medium/low",
  "mappingReason": "为什么映射到这个症候",
  "isGap": true/false,
  "gapDescription": "如果是缺口，说明症候库缺少什么"
}
```

```
### V4-DIST-1 素材库
[上述 JSON 数组]

### V4-DIST-2 缺口分析
- 已覆盖：哪些症候有真实案例支持
- 部分覆盖：哪些症候只有少量案例
- 完全缺失：哪些真实问题无法映射
- 建议新增：如需新增症候，定义其 P-ID/名称/描述/类型
```

---

## 任务 6 (反例样本)：5 剧本 × 3 变体

### 剧本结构
每个剧本包含：`scriptId`、`title`、`userText`（~200 字）、`targetSyndrome`（P体系）、3 种变体。

### 3 种变体
| 变体 | 说明 | AI 期望行为 |
|:----:|:-----|:-----------|
| A | good_case：AI 诊断正确、教学恰当 | 识别症候 → 匹配教学动作 → 给出可操作建议 |
| B | edge_case：边界案例，多种症候交界 | 合理研判主要矛盾，不强行套用单一症候 |
| C | bad_case：用户对抗/不配合 | 坚持教练定位 → 不替写 → 引导反思 → 降级或安全词 |

### 5 个剧本
| 剧本 | 症候 | 场景 |
|:----:|:-----|:------|
| S-01 | P001 世界观膨胀 | 用户大段写世界设定，主角无存在感 |
| S-02 | P003 情绪标签化 | 用户只用"他很伤心""她很感动"等情绪标签 |
| S-03 | P005 视角漂移 | 用户在同一段落内切换角色视角 |
| S-04 | P006 节奏停滞 | 用户连续 5 段无冲突和推进 |
| S-05 | P009 角色动机缺失 | 角色在剧情关键点做出无动机的突兀行为 |

### 输出格式
```
### 反例样本 — 完整剧本集
[5 个剧本，每个含 title/userText/targetSyndrome + 3 种 variant 的 AI 期望行为]
```

---

## 后续蒸馏补充项（2026-06-17 真实文本诊断发现）

以下维度在当前 P 症候体系（P001~P010）中**无充分覆盖**，建议纳入后续蒸馏。

### 缺口 1：人称一致性/人称视角失控

**现象**：同一段落/句子内，人称在"我"和"他"之间无预警切换（如"快递员把快递塞**给我**说"→"**刘波**愣了几秒钟问道"→"二人朝**我**看来"）。

**与现有 P005 的关系**：
- P005 视角漂移 = "写了主角看不到/听不到的信息"（信息边界问题）
- 本缺口 = "人称代词不一致"（语法/叙述人称问题）
- 两者不同：P005 是超出了角色的认知边界，本缺口是连角色本身的人称都没稳住

**建议**：
- 方案 A：P005 定义扩展，覆盖人称一致性
- 方案 B：新增 P-ID（如 P011 人称失稳）

### 缺口 2：人物出场方式薄弱

**现象**：新人物出场时无外貌/气质/环境氛围铺垫，仅通过"敲门→对话"交代（"咚咚的拍打声传来→刘波起身去开门→先看的是一张被晒的黝黑的脸"）。最有戏剧潜力的场景（快递员初次登门）没有被利用来塑造人物或制造悬念。

**与现有 P 体系的关系**：完全无覆盖。现有 P 症候都关注"写什么"而非"怎么写人物入场"。

**建议**：考虑新增症候（P012 人物出场扁平），或作为 P002 角色工具化的子扩展。

### 缺口 3：场景转换无过渡

**现象**：场景之间硬切，无任何连接文字（签完快递→直接坐在沙发上刷抖音→直接出门改衣服）。读者缺乏空间/时间过渡信号。

**与现有 P 体系的关系**：P007 阅读结构单一可能部分覆盖（文本结构缺乏变化），但 P007 更关注句式层面，而非场景层面。

**建议**：作为 P007 的扩展定义补充，或独立缺口标注。

### 缺口 4：时间标记粗糙（"天书式"时间推进）

**现象**：使用"六点钟一会儿…八点钟一会儿…九点半左右…10.30…"推进叙事，相当于把物理时间的每个段落均匀展开，读者感受不到节奏变化。

**与现有 P 体系的关系**：
- P006 节奏停滞 = "连续多段没有推进或冲突"（内容层面）
- P007 阅读结构单一 = "文本结构缺乏变化"（句式层面）
- 本缺口 = "时间标记层面"的节奏问题（时间轴层面）
- 三者不同但相关，这个缺口卡在 P006 和 P007 之间

**建议**：标注为 P006 和 P007 的交界地带，蒸馏时确认应该归入哪个，还是单独定义。

### 缺口 5：叙述语法口语化

**现象**：书面语中混入口语语法（"用微信扫码一下**啊**"、"店老板打量一**样**"、"王霞给刘波安排**的**任务"），以及句内多余字（"先看的**的**是一张被晒的黝黑的脸"）。

**与现有 P 体系的关系**：完全无覆盖。P 体系定位在"技法"（叙事技巧），"语法规范"不在诊断范围内。

**建议**：明确不做。如果刻意纳入会偏离"写作教练=教技法"的定位，变成"语文老师=改病句"。标注为"刻意不覆盖"。

### V4-DIST 映射

| 缺口 | V4-DIST-1 搜索关键词 | V4-DIST-2 映射 |
|:-----|:--------------------|:---------------|
| 缺口 1 | "小说人称混乱" "第一人称变第三人称" | P005 扩展或新增 P011 |
| 缺口 2 | "人物出场怎么写" "小说配角出场技巧" | 新增症候或 P002 子扩展 |
| 缺口 3 | "场景转换技巧" "小说转场怎么写" | P007 扩展 |
| 缺口 4 | "小说时间推进" "时间跳跃写法" | P006/P007 交界 |
| 缺口 5 | — | 刻意不覆盖 |

---

## 输出汇总

请按以下顺序输出：

1. **D-02 Patch** — syndrome-type-map.json 的验证结果
2. **D-03 Patch** — technique-library.json 的修正
3. **D-05 完整文件** — training-library.json 的补充条目
4. **D-06 Patch** — syndrome-action-map.json 的映射建议
5. **V4-DIST-1 素材库 + V4-DIST-2 缺口分析**
6. **反例样本剧本集** — 5 剧本 × 3 变体

每个 Patch 必须是可直接应用的 diff 格式（标明文件、位置、旧值→新值）。
