// ─────────────────────────────────────────────────────────────
// syndrome_knowledge_base 数据分片：L2 索引 + L3 症候诊断手册（kSyndromeIndexContent / kSyndromeManualContent）（P3 知识减负 · 数据/逻辑分离）
// 逐字迁移自 syndrome_knowledge_base.dart，零行为变更。
// ─────────────────────────────────────────────────────────────
part of 'syndrome_knowledge_base.dart';

/// L2 索引：写作问题→症候 ID 映射表（对应 RN SYNDROME_INDEX_CONTENT）
/// 映射表行由注册表渲染（b9 批次28），输出与手写逐字一致。
final String kSyndromeIndexContent =
    r'''# SKILL: 写作问题→症候 ID 映射表

> 定位：你已凭认知锚点识别出写作问题后，用此表为问题标注症候 ID。
> 这是"名分"映射，不是诊断标准——你的判断在前，ID 在后。

## 使用方法

1. 先凭你的写作判断力识别问题（参考"写作认知锚点"）
2. 用自然语言描述问题
3. 在下表中找到最匹配的 ID，标注在问题描述后
4. 如果同一段文本同时存在多个独立问题（如开篇既有信息倾泻又无钩子），
   分别标注为独立的问题，不要合并

## 映射表

| 症候 ID | 问题类型关键词 | 一句话描述 |
|---------|--------------|-----------|
''' +
    kSyndromeRegistry
        .where((s) => s.retired != true)
        .map(_syndromeIndexRow)
        .join('\n') +
    r'''
## 严重度三维标定

- L1 轻微：局部/不影响理解/改几句即可
- L2 重要：整章多处出现/打断阅读节奏/需调整段落
- L3 严重：贯穿全文/直接导致读不下去/要重写

## 诊断输出规范

1. 先凭你的写作判断力识别问题（参考"写作认知锚点"）
2. 为每个问题标注最匹配的症候 ID
3. 给出严重度（L1/L2/L3）
4. 不限制问题数量——识别到多少就报多少
5. **每个独立问题必须单独成条，禁止合并**：即使多个问题出现在同一段文本里，也要分开标注。例：同一段既有"情绪标签"又有"视角越界"，必须分成两条独立问题，不能合并为"情绪+视角"复合问题。
6. **精准定位**：每个问题必须引用原文片段（5-20字），不能只说"在文本中"。例："原文：'他很愤怒。他很失望。他很困惑。他很痛苦。'"
7. **说明判断理由**：简要说明为什么这是问题（或为什么看似问题但实际合理）
8. 如果有"看似问题但实际合理"的写法，简要说明

## 输出格式

先输出一段自然的诊断说明（给作者看的），然后输出 [YS_DIAGNOSIS] 标记包裹的 JSON 数据。

### 自然说明部分
[用自然的语言向作者说明你识别到的主要问题，这是给作者看的对话内容]

### JSON 数据部分

[YS_DIAGNOSIS]
{
  "syndromes": [
    {
      "syndrome_id": "P0XX",
      "name": "症候名称",
      "severity": "L1 | L2 | L3",
      "evidence": ["原文片段1（5-20字）", "原文片段2（5-20字）"],
      "explanation": "问题描述 + 判断理由（合并写，自然语言）",
      "reader_impact": "可选：这个问题对读者的影响"
    }
  ],
  "suggested_actions": ["A0XX"],
  "confidence": 0.0-1.0,
  "feedback_summary": "可选：整体反馈摘要",
  "root_cause_analysis": "可选：根因分析",
  "next_focus": "可选：下次聚焦点",
  "teaching_plan": {
    "current_teaching_focus_id": "可选：当前教学焦点症候 ID（如 P019，必须从 syndromes 中选取）",
    "focus_reason": "可选：为什么选这个 focus（一句话）",
    "next_step": "可选：训练目标/下一步动作（自然语言）"
  }
}
[/YS_DIAGNOSIS]

## JSON 字段说明

- **syndromes**: 识别到的所有问题（不限制数量）
  - **syndrome_id**: 从映射表匹配的 ID
  - **name**: 症候名称（从映射表取）
  - **severity**: L1/L2/L3
  - **evidence**: 原文片段数组（5-20字，精准定位）
  - **explanation**: 问题描述 + 判断理由（自然语言，合并写）
  - **reader_impact**: 可选，说明对读者的影响
- **suggested_actions**: 推荐动作 ID 数组（可为空数组）
- **confidence**: 诊断置信度 0-1
- **feedback_summary**: 可选，整体反馈
- **root_cause_analysis**: 可选，根因
- **next_focus**: 可选，下次聚焦（向后兼容字段，建议改用 teaching_plan.next_step）
- **teaching_plan**: 可选，结构化教学计划子对象
  - **current_teaching_focus_id**: 当前教学焦点症候 ID（如 P019）。必须从本轮 syndromes 中选取。代码会以此驱动 L3 完整定义+技法注入。
  - **focus_reason**: 为什么选这个 focus（一句话）。下一轮会被注入到 system prompt。
  - **next_step**: 训练目标/下一步动作（自然语言）。是 next_focus 的进化版。

## 排除的"伪问题"

如果文本中有"看起来像问题但实际是合理写法"的地方，在自然说明部分提及，
简要说明为什么不是问题。JSON 中不需要包含排除项。''';

/// L3 完整手册：症候诊断手册（对应 RN content，含 P003-P041 完整定义）
/// 头部「症候图谱」计数由注册表派生（b9 批次28），正文段落保留人工编写。
final String kSyndromeManualContent =
    r'''# SKILL: 症候诊断手册

> **来源**: yuesheng-prompt-v5.md §二 + syndrome-action-map.json
> **loadWhen**: P1+ 必加载（P0 不诊断，节省 token）
> **体积**: 约 2 万 tokens（含完整症候定义 + L2 索引 + L3 检索代码）

## 二、症候图谱（''' +
    kSyndromeIds.length.toString() +
    r''' 种写作问题的标准化定义）

> 以下 ''' +
    kSyndromeIds.length.toString() +
    _syndromeManualBody1 +
    _syndromeManualBody2 +
    _syndromeManualBody3 +
    _syndromeManualBody4 +
    _syndromeManualBody5 +
    _syndromeManualBody6 +
    _typeLookupTable() +
    r'''

---

## 诊断输出规范

### 动作选择指引

诊断完毕后，请将推荐的教学动作填入 [YS_DIAGNOSIS] JSON 的 `suggested_actions` 数组中。每个症候在本手册中已有"推荐教学动作"标注（首选+备选），按以下规则选择：

1. **首选动作**：默认填入 `suggested_actions`。一个症候对应一个动作
2. **备选动作**：当首选动作已完成、学员表示不适应、或你判断需要换方式时，替换为备选动作
3. **多症候时**：每个症候各选一个动作，合并后去重。例如 P003（首选 A004）+ P005（首选 A002）= `["A004", "A002"]`
4. **动作编号**：suggested_actions 中写 A001-A015 编号，不写中文名称（系统端负责映射）

### 写作技巧提示（技法库）

> **完整技法库**见 SKILL-technique-library（T001-T031，P2+ 加载）。
> 此处仅提供大纲性的症候↔技法映射，便于诊断环节快速引用。

对识别出的症候，可在输出诊断的自然语言中引用 1-2 条对应技法（引用技法名称即可，不暴露编号）：

| 症候 | 推荐技法 |
|------|---------|
''' +
    kSyndromeRegistry
        .where((s) => s.retired != true)
        .map(_techniqueMapRow)
        .join('\n') +
    r'''

---

## 诊断执行指引

本段仅适用于非渐进式路径（短文本 <4000 字，不走分片分析）。

**叙事合理性判定**（最终裁决步骤）：
在输出每条症候之前，请先回答以下问题：
"如果这段文本不被修改，读者体验会显著受损吗？"
只有当答案是"是"时，这条症候才进入最终输出。

**数量原则**：不限制输出问题数量——识别到多少就报多少。候选较多时按以下优先级排序输出（排序而非截断）：
1. 对读者体验影响最大的问题优先
2. 学员最可能愿意改的问题优先
3. 更基础的问题优先（如 P003 情绪标签化优先于 P008 语言堆砌）

**reader_impact 字段要求**：每条症候必须附上 reader_impact 字段，一句话说明"不改这段，读者会有什么体验影响"。示例："不改这段，读者会在前 200 字内走神，无法进入后续剧情。"

<!-- T-010: H001/H002 已合并注释已移除（H001/H002→P013，迁移记录见 git history）-->''';
