# V2.2 Prompt → 当前架构 迁移分析

> 目标：V2.2 是单一 Prompt 工程。本文件分析其 7 个"丢失块"在当前多 Agent + Service + Config 架构中应该去哪里。原则：**能进配置不进代码，能进代码不进 prompt**。

---

## 总览

| # | V2.2 内容 | 丢失程度 | 正确归属层 | 状态 |
|:-:|----------|:--------:|-----------|:----:|
| 1 | Layer 1 不可见铁律 | ❌ 完全丢失 | **diagnosis-agent-prompt** + **diagnosis-merger.service**（代码兜底）| 🔴 必须补 |
| 2 | 教学动作触发映射 | ❌ 完全丢失 | **新配置 syndrome-action-map.json** + **TeachingStrategyRouter** 消费 | 🔴 必须补 |
| 3 | 三阶段流程+检查清单 | ❌ 完全丢失 | **teaching-state-machine.ts**（映射到现有状态）| 🟡 可选优化 |
| 4 | 场景详细话术 | ⚠️ 弱化 | **coaching-templates.json**（扩展）+ **teaching-agent-prompt**（仅规则）| 🟢 渐改 |
| 5 | 教学边界声明 | ❌ 完全丢失 | **yuesheng-prompt-v3**（小段文本）| 🟢 一次改 |
| 6 | 外部资源提及规则 | ❌ 完全丢失 | **新配置 external-resources.json** | 🟡 可选 |
| 7 | 防幻觉死命令 | ❌ 完全丢失 | **所有 Agent Prompt**（安全护栏，不能代码化）| 🔴 必须补 |

---

## 逐一分析

### 1. Layer 1 不可见铁律

**V2.2 原文**：
```
用户永远看不到这一层。不要输出评分、不要输出病症编号、不要输出诊断报告。
铁律：这一层的结果只用于决定Layer 3问什么和Layer 4练什么，绝不直接输出给用户。
```

**为什么不能只改 prompt**：现在诊断是独立的 Diagnosis Agent，它只输出 JSON。但**Teaching Agent** 在消费这个 JSON 时可能不小心把病症编号说出来给用户。

**迁移方案**：

```
诊断 Agent（输出 JSON → 含 syndromeRef: ["P001"]）
  ↓
diagnosis-merger.service.ts → 过滤 syndromeRef，只保留 syndromeName
  ├─ 如果 AI 输出的 JSON 含有用户不可见字段，service 清洗掉
  └─ 输出给 Teaching Agent 的 {diagnosisResult} 不含编号
  ↓
Teaching Agent（只看到症候名，看不到编号）
```

| 层 | 改动 |
|----|------|
| **diagnosis-merger.service.ts** | 新增 `stripInternalIds()` 函数，过滤 syndromeRef/techniqueId 等内部编号 |
| **diagnosis-agent-prompt** | 追加约束："输出 JSON 中的 syndromeRef/techniqueId 仅供下游使用，不在任何对话中提及" |
| **teaching-agent-prompt** | 追加规则："不给直接输出诊断编号"（第 2 条已有"不暴露内部编号"，保留即可）|

---

### 2. 教学动作触发逻辑映射表

**V2.2 原文**：
```
| 问题类型 | 触发动作 | 教练提问方向 |
|---------|---------|-------------|
| 世界观膨胀/设定失控 | A001 缩小范围 | "先别考虑那么多。第一章发生什么？" |
| 视角漂移/上帝视角 | A002 回归主角 | "主角知道吗？主角能看到吗？" |
| 角色工具人化/情绪标签化 | A004 现实锚点 | "如果是真人，第一反应会是什么？" |
```

**为什么不能再塞进 prompt**：因为现在有 Diagnosis Agent 做结构化诊断输出，有 SyndromeId 作为桥梁。这个映射应该是**数据配置**，不是 prompt 文本。

**迁移方案**：

```
新建 syndrome-action-map.json：

{
  "P003": {
    "syndromeName": "情绪标签化",
    "type": "expressive_deficit",
    "primaryAction": "A004",
    "actionName": "现实锚点",
    "triggerTemplate": "如果是真人，{firstPerson}的第一反应会是什么？"
  },
  "P005": {
    "syndromeName": "视角漂移",
    "type": "structural_disorder",
    "primaryAction": "A002",
    "actionName": "回归主角",
    "triggerTemplate": "主角知道吗？{character}能看到{object}吗？"
  }
}
```

| 层 | 改动 |
|----|------|
| **resources/config/syndrome-action-map.json** | **新建**（含 9 个活跃症候的映射）|
| **TeachingStrategyRouter**（Phase 3） | 加载此配置，输出 targetAction + triggerTemplate |
| **teaching-agent-prompt** | 追加指令："{syndromeActionMap} 中的 triggerTemplate 可根据语境调整" |

---

### 3. 三阶段教学流程 + 检查清单

**V2.2 结构**：
```
阶段一：建立投入 → 可验证标志：用户说"对"
阶段二：暴露问题 → 可验证标志：问题已被识别
阶段三：诊断与引导 → 核心：理解→训练→进步→新问题
```

**与当前 teaching-state-machine.ts 的映射**：

| V2.2 阶段 | 当前 S1/S2/S3/S4 | 差异 |
|-----------|-----------------|------|
| 阶段一（建立投入） | 无对应（诊断前阶段）| ❌ 丢失。当前机器没有"先建立关系再诊断"的阶段 |
| 阶段二（暴露问题） | S1_ANALYSIS → S2_REFLECTION | ⚠️ 弱化。当前有分析→反思，但缺少"让用户自然暴露"的引导 |
| 阶段三（诊断与引导） | S3_TEACHING → S4_PRACTICE | ✅ 基本对应 |

**迁移方案**：teaching-state-machine.ts 中 S1 之前插入一个轻量前置阶段。

| 层 | 改动 |
|----|------|
| **teaching-state-machine.ts** | S0_ENGAGE 阶段（目标是让用户确认问题），transition 条件：userSaysYes |
| **yuesheng-prompt-v3** | 补充"首次对话先建立投入"的流程指令 |

---

### 4. 场景详细话术

**V2.2** 有 6 个场景的完整对话示例（正反对照），V3.4 只有一句话规则。

**为什么要弱化 prompt**：这些对话示例在 V2.2 里是为了**唯一的一份 prompt 覆盖所有场景**。现在我们有专门的 Teaching Agent，它只需要知道规则，不需要背上千字示例。

**迁移方案**：

| 层 | 改动 |
|----|------|
| **coaching-templates.json**（已有) | 扩展场景话术模板（新增 辩驳/改写/自我暴露 模板）|
| **teaching-agent-prompt** | 保留规则（如"不用表格"、"先说好的再说坏的"），删除长示例 |
| **TeachingStrategyRouter** | toneProfile 输出引用 coaching-templates.json 模板 |

---

### 5. 教学边界声明

**V2.2 原文**：
```
每次首次对话必须声明：
我能帮你的是提升写作能力...但生活经验和阅读量需要你自己积累。
能教：观察力训练、思维方法、表达技术
不能教：生活经验、天赋
替代方案：写自己、采访真人、精读指定章节
```

**迁移方案**：

| 层 | 改动 |
|----|------|
| **yuesheng-prompt-v3** | §零、新增初始化块，包含首次对话声明 + 能教/不能教清单 |

这个确实不需要代码化——就几十个字，放在 prompt 里最合理。

---

### 6. 外部资源提及规则

**V2.2** 有 3 本书的提及话术和防幻觉命令。

**迁移方案**：

| 层 | 改动 |
|----|------|
| **resources/config/external-resources.json** | **新建**（书名/作者/适用场景/提及话术/防幻觉标签）|
| **teaching-agent-prompt** | 追加指令："允许提及的外部资源见 external-resources.json，不编造未列出的出版物内容" |

---

### 7. 防幻觉死命令

**V2.2**："不允许自行编造其他出版物的具体章节和页码。不确定就不要推荐。"

**迁移方案**：这个必须留在所有 Agent Prompt 里，安全护栏不能代码化。

| 层 | 改动 |
|----|------|
| **teaching-agent-prompt** | 追加防幻觉命令 |
| **diagnosis-agent-prompt** | 追加防幻觉命令 |
| **training-evaluator-prompt** | 追加防幻觉命令 |

---

## 执行计划

| 优先级 | 改动 | 量级 | 影响 |
|:------:|------|:----:|------|
| 🔴 P0 | #1 Layer 1 铁律 → diagnosis-merger.service 过滤 + 2 个 prompt 追加 | 小 | **防止诊断编号外泄到用户对话** |
| 🔴 P0 | #2 教学动作映射 → 新建 syndrome-action-map.json | 中 | **TeachingStrategyRouter 的关键输入** |
| 🔴 P0 | #7 防幻觉 → 3 个 Agent Prompt 追加 | 小 | **防止 AI 编造内容** |
| 🟡 P1 | #3 流程阶段 → teaching-state-machine 新增 S0_ENGAGE | 中 | 优化首次对话流程 |
| 🟡 P1 | #4 场景话术 → 扩展 coaching-templates.json | 中 | 提升话术质量 |
| 🟢 P2 | #5 边界声明 → yuesheng-prompt-v3 追加 | 小 | 提升首次对话质量 |
| 🟢 P2 | #6 外部资源 → 新建 external-resources.json | 小 | 防止幻觉 |

**总 prompt 膨胀**：
- yuesheng-prompt-v3：+3 行（声明词 + 流程指令）
- teaching-agent-prompt：+4 行（防幻觉 + 规则 + 配置引用）
- diagnosis-agent-prompt：+2 行（防幻觉 + 约束）
- training-evaluator-prompt：+1 行（防幻觉）
- **总计约 +10 行，膨胀率 < 5%**
