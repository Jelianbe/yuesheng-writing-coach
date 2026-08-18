# 设计：文笔画像 → 技法旁路路由（Style-Technique Bypass Routing）

> 日期：2026-08-18
> 状态：待舰长确认
> 决策背景：诊断链路有两层产出（feedbackSummary 内容总结层 + styleProfile 文笔分析层，批次 53），但技法路由（T001–T031）纯症候驱动，styleProfile 五维发现落库后不参与技法召回——文笔精修阶段无技法支撑。经选项评估选定**方案 A：旁路补充路由**（不拆管线、不加 LLM 调用）。

## 1. 问题陈述

### 现状链路

```
诊断 LLM 调用（单次）
  ├─ feedbackSummary ──→ 症候 syndromes ──→ getTechniquesBySyndrome() ──→ 技法注入 ✅
  └─ styleProfile ──→ student_model.style_profile 落库 ──→ student_profile 画像文本注入（描述性） 
                                                        └─→ 技法路由 ❌ 断裂
```

### 具体断裂点

- `chat_service_send.dart` L1253：styleProfile 落库后无技法消费
- `student_profile.dart` L305 `_formatStyleProfile`：五维坐标仅作为描述文本注入 LLM，LLM 无法据此召回技法（技法按症候 ID 注入，画像无 ID 关联）
- 结果：文笔精修阶段（症候不活跃但风格有提升空间）教学回复只能泛泛而谈

## 2. 设计原则（约束）

1. **教练哲学不破**：一次只聚焦一个技法，旁路只补充候选、不并行教学
2. **不加 LLM 调用**：全本地路由（纯 Dart 判定），不加重双次调用延迟
3. **症候主路由不动**：旁路优先级低于症候路由，症候活跃时不抢占焦点
4. **R-021 映射表禁令规避**：维度值→技法 的对应关系作为**教学知识**放在技法知识库真源文件（technique_knowledge_base.dart）内，与 kTechniqueIndexContent 同源维护，不散落组件

## 3. 改动清单

### 3.1 技法 layer 标签（technique_knowledge_base.dart）

新增结构化常量 `kTechniqueLayers`（技法 ID → layer）：

| layer | 技法 | 依据 |
|:------|:-----|:-----|
| prose（文笔层） | T001 动态描写、T002 感官交织、T003 核心信息提取、T020 借景抒情、T021 动静烘托、T023 句速控制、T025 余韵收束、T013–T016 对话四法 | 作用于句子/段落文本本身 |
| content（内容层） | T008 因果动作链、T009 欲望三层法、T010 信息投喂、T011 角色中介、T017 悬念伏笔、T018 欲扬先抑、T019 线性变奏、T022 场景概述交替、T024 钩子开篇、T026–T029 结构四法 | 作用于故事结构/情节推进 |
| character（角色层） | T004 角色独白检测、T005 人味三问、T006 特征性对话、T007 意外测试、T030 人设锚定 | 作用于角色塑造 |

### 3.2 五维偏差 → 文笔层技法旁路映射（technique_knowledge_base.dart）

新增 `kStyleDimensionTechniques`（维度值 → 候选技法 + 一句理由）。

**关键设计**：五维坐标是「风格偏好」不是「错误」。spare 冷峻型不是病。因此映射按「该维度值指向的可提升方向」组织，且**只有当该维度值曾伴随相关症候出现，或用户主动询问文笔**时才触发旁路：

| 维度值 | 可提升方向 | 候选技法（prose 层） |
|:-------|:----------|:--------------------|
| rhythm=long | 长句从句嵌套，节奏单一 | T023 句速控制 |
| rhythm=short | 短句碎片化，缺乏呼吸感 | T021 动静烘托 |
| rhythm=repetitive | 排比过度，结构重复 | T023 句速控制 |
| sensory=visual/auditory/kinesthetic（单一型） | 感官通道狭窄 | T002 感官交织 |
| toneTexture=poetic | 修辞密集风险（关联 P008） | T003 核心信息提取 |
| narrativeDistance=intimate | 内心独白过多（关联 P003） | T001 动态描写（情绪外化） |
| narrativeDistance=editorial | 叙述者抢戏，告知倾向 | T020 借景抒情 |
| structure=fragmented | 跳跃无过渡（关联 P020） | T029 过渡桥接（注：T029 原属 content 层，此处跨层调用需标注） |

注：`rhythm=alternating`、`sensory=balanced`、`narrativeDistance=fluid`、`toneTexture=spare/elegant`、`structure=linear/circular/divergent` 为健康/中性值，不进映射。

### 3.3 旁路路由器（新文件 lib/services/style_technique_router.dart）

```dart
/// 文笔画像 → 技法旁路路由器
/// 输入：styleProfile + 活跃症候视图 + 教学焦点上下文
/// 输出：0–2 条候选文笔层技法（带理由），供 chat_context_builder 注入
///
/// 门控（按优先级短路）：
/// 1. styleProfile 为 null → 返回空（画像未沉淀）
/// 2. 存在 L2/L3 严重度活跃症候且其 layer ≠ prose → 返回空（内容层问题优先，不抢占）
/// 3. 焦点症候的技法已含 prose 层 → 返回空（主路由已覆盖，不重复）
/// 4. 通过门控 → 取维度值映射的候选技法，排除已 mastered 的，返回前 2 条
StyleTechniqueSuggestion routeStyleTechniques({
  required WritingStyleProfile? styleProfile,
  required List<ActiveSyndromeView> activeProblems,
  required Set<String> masteredTechniqueIds,
})
```

### 3.4 注入点（chat_context_builder.dart）

`buildStructuredSyndromeContext` 现有症候段之后追加条件段：

```
### ✒️ 文笔精修候选（画像旁路，按需提及，不与当前焦点并行教学）
- T023 句速控制：画像显示长句主导（rhythm=long），可在焦点症候巩固后引入
```

措辞遵守「不暴露编号」的现有用法说明——注入给 LLM 的文本含编号（同现有 techniqueSection 格式），LLM 对用户引用时说技法名。

### 3.5 mastered 判定数据源

复用现有 `student_model` 中技法掌握状态（若 v13 schema 无此表，则首版降级为不做 mastered 过滤，标记 TODO）。

## 4. 不做的事（边界）

- ❌ 不拆诊断 prompt（两份产出仍单次调用）
- ❌ 不改症候→技法主路由表
- ❌ 不给 styleProfile 增加新的 LLM 分析调用
- ❌ 不自动触发文笔教学——旁路只注入候选，是否教学由 LLM 按对话语境判断（教练主权在模型+用户，路由只供弹药）

## 5. 验证计划

1. 单测：style_technique_router 门控逻辑（4 条门控路径 + 健康值不触发）
2. 单测：kStyleDimensionTechniques 完备性（所有非健康维度值都有映射或显式豁免）
3. 集成：模拟 styleProfile(rhythm=long) + 无活跃症候 → context 文本含「文笔精修候选」段
4. 回归：有 L3 活跃症候时旁路段不出现
5. `flutter analyze` 零错误

## 6. 风险与开放问题

| # | 风险/问题 | 缓解 |
|---|----------|------|
| 1 | 五维映射的教学有效性未经真实学员验证 | 映射表注释标注「首版经验值，待学员数据校准」；改表不动代码 |
| 2 | T029 跨层调用（structure 维度→content 层技法）破坏 layer 纯度 | 映射表加 `crossLayer: true` 标注，接受跨层但显式声明 |
| 3 | mastered 技法数据可能不存在 | 门控 4 的 mastered 过滤做成可选参数，数据缺失时跳过 |
| 4 | 旁路段可能被 LLM 过度使用（每次都教文笔） | 注入文本明确「按需提及」；后续可加频控（同一技法 3 会话内不重复注入） |
