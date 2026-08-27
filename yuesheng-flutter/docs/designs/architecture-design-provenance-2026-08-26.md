---
design_type: architecture
created_at: 2026-08-26
title: 月笙写作教练 · 模块意图 & 设计溯源手册
status: active
confirmed_at: 2026-08-26
confirmations:
  p0_items: 4/4 (五维画像/六步闭环/症候表来源/Flutter真源决策)
  p1_items_completed: 1/4 (三档态度设计初衷)
coverage: flutter-end-only  # 截止 2026-08-26，Flutter 端为唯一真源
---

# 月笙写作教练 · 模块意图 & 设计溯源手册（2026-08-26）

> **设计目的**（单一真源）：让任何后续接手本项目的人 / AI / 审核者，不与舰长本人沟通，仅凭本手册 + 代码引用链接，就能回答关于某个模块的 5 个关键问题：
> 1. **意图**：它为什么存在？要解决什么问题？
> 2. **数据流**：输入→处理→输出→输出消费给谁？
> 3. **设计溯源**：为什么这样设计？来源于哪份决策 / 哪份 PRD / 哪段 Prompt？
> 4. **代码真源**：权威实现位置（file:line 精确到段）；改它时要连带过哪些守护测试？
> 5. **体系角色**：在「问→写→诊→教→练→评」六步闭环中发挥什么作用？
>
> 文档纪律：
> - 所有断言必须有代码 / 文档引用链接支撑；代码里找不到的"设计初衷"显式标记 `[需要舰长确认·待回填]`，绝不私造业务语义（R-021 AI 行为边界 § 不私造业务语义）。
> - 决策类内容优先引用 ADR / docs/logs/* / 宪法 / 待办执行清单，其次引用代码注释，最后才引用口头历史。
> - 本文档**不替代**代码；当代码与文档冲突，默认代码正确，文档缺项 → 走 R-017 文档同步流程补修订。

---

## §0 读本文档的方法 & 真源索引

### 0.1 阅读建议（三种读法）

| 你想解决的问题 | 从哪一章开始读 | 预期耗时 |
|---|---|---|
| 我要改某个模块，但不敢动 → 先搞清楚它的设计边界 | §2 模块意图索引卡（CTRL+F 搜索模块名） | 5-10 分钟 |
| 我要做诊断链路 Debug（"诊断结果为什么不对"） | §3.1 诊断链路 + §4.1 四库溯源 | 10-15 分钟 |
| 我要立项做新功能，判断"放在哪一层、改哪些文件" | §1 哲学 + §5 设计决策登记 + §2 能力契约层卡 | 15-30 分钟 |
| 我是新人 / 新 AI，第一次接触项目 | §0→§1→§2（前 5 张卡）→§6 双端状态 | 45 分钟 |

### 0.2 项目真源索引（按权威度排序）

| # | 类别 | 真源位置 | 单一真源说明 |
|---|---|---|---|
| 1 | **代码真源（Flutter 端）** | `D:\ai-teacher\yuesheng-flutter\lib\` | 截至 2026-08-26 唯一真源；RN/Electron 端为规范草稿或历史 |
| 2 | **能力契约层（接口真源）** | `lib/contracts/` [diagnosis_capability.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/contracts/diagnosis_capability.dart) 等 7 份 | ADR-capability-contracts 规定：契约高于实现，新接入方先读契约再读实现 |
| 3 | **产品哲学 & 铁律** | ① [yuesheng-flutter-宪法草案.md](file:///D:/ai-teacher/yuesheng-flutter/docs/yuesheng-flutter-宪法草案.md) ② [AGENTS.md](file:///D:/ai-teacher/AGENTS.md) | 宪法 §一（设计哲学）优先级高于任何实现代码 |
| 4 | **知识库内容真源（教学知识）** | `lib/services/` 下 4 宿主 + 22 分片 part 文件：skill_registry / syndrome_knowledge_base / technique_knowledge_base / training_knowledge_base | 四库一致性测试 `four_libraries_consistency_test.dart` 兜底：逐字一致，改一个会被拦下 |
| 5 | **Prompt 语义真源（LLM 行为）** | `D:\ai-teacher\yuesheng-writing-coach\resources\prompts\yuesheng-prompt-v4.0.0.md` | Prompt 与 Flutter 端 prompt 注入同步滞后，以 RN 原始 prompt 为准；Flutter 侧差异走 docs/b58 审查 |
| 6 | **设计决策历史（8-18→至今）** | ① [architecture-review-2026-08-18.md](file:///D:/ai-teacher/yuesheng-flutter/docs/architecture-review-2026-08-18.md) ② [交接文档-2026-08-18.md](file:///D:/ai-teacher/yuesheng-flutter/docs/交接文档-2026-08-18.md) ③ [待办执行清单.md](file:///D:/ai-teacher/yuesheng-flutter/docs/待办执行清单.md) | 2026-08-18 是架构转折点；2026-08-26 本手册 = 8-18 架构审查的增量修订版 |
| 7 | **单条决策 ADR** | `docs/ADR-A2-stable-mention-id.md` / `ADR-A3-paragraph-anchor.md` / `ADR-P0-receipt-state.md` / `ADR-capability-contracts.md` | 小粒度决策；与大架构冲突时以 ADR 为准（ADR 晚于架构审查） |

### 0.3 教学闭环锚点（所有模块的动作都须回到这六步）
`【问】→【写】→【诊】→【教】→【练】→【评】` — 任何新增模块如果没法在这条链上定位自己，就是"加戏"，违反 R-010 最小化范围。

---

## §1 产品定位 & 顶层教学哲学（Why 约束）

> 任何架构决策都必须遵守本节。违反本节的实现，即使测试全绿也不能上线。

### 1.1 一句话定位（2026-08-18 交接文档 §0 确认）
**月笙写作教练是 AI 写作教学系统（不是写作工具）**：教练不替用户写句子、不替用户做决定。它通过「问→写→诊→教→练→评」闭环，帮用户**学会写作**，而不是**替用户产出成品**。

### 1.2 顶层设计铁律（来自宪法 §一 & Prompt v4.0.0 约束）

| 铁律 ID | 内容 | 影响到的模块设计 | 已实施的验证 |
|---|---|---|---|
| R-P01 | **禁止代写**：诊断/教学输出不能是"改好的句子"，必须是根因分析 + 引导性提问 | Diagnosis Parser §2.1；Teacher Service 输出必须是问句或讲解句；GenUI diff 组件只能「高亮+对比」不能「一键应用」 | `diagnosis_validator.dart` 有"是否包含整句替换"黑名单；守护测试 23 项 |
| R-P02 | **安全词降档**：用户说"轻一点"无条件把 Attitude 档位降到豆包（温和档），不经过任何推理 | attitude_advisor.dart（L2 档位解析）；chat_attitude.dart UI 指示器 | 测试 `attitude_advisor_test.dart` 含"轻一点"精确触发 |
| R-P03 | **学员主权**：任何建议不自动应用；"应用建议"按钮必须有二次确认且不写入作品正文，仅作为学员参考 | adopt_suggestion_sheet.dart（用户显式点击才动）；suggestion_adoption_service.dart 走用户 receipt 回执 | ADR-P0-receipt-state 定义了 receipt 状态机 |
| R-P04 | **知识一致性硬门**：L1/L2/L3/训练四库之间的映射表（症候→技法、症候→shortName、技法→分层）是"一处改四处"，修改任何数据必须过四库一致性测试 | syndrome_knowledge_base.dart + technique_knowledge_base.dart + 2 个注册表 | `test/services/four_libraries_consistency_test.dart`：双向逐字一致 |
| R-P05 | **LLM 输出必须双校验**：LLM 返回结果先过 JSON Schema 校验（字段齐全）→ 再过自然语言黑名单校验（不写整段、不触发安全词）→ 不通过则重试/降级，**不直接渲染给用户** | diagnosis_validator.dart / teacher_validator.dart / genui_validator.dart 三层 | `DiagnosisValidationResult.valid == false` 时 UI 渲染 DiagnosisFailedCard，不吞错误 |
| R-P06 | **不私造业务语义**（R-021）：代码侧 UI/状态模块，不得 `getState()` 直接操作 store 的业务 action；必须经由契约接口（capability）→ service 层 → provider 暴露 | 能力契约层 `lib/contracts/`；`capability_providers.dart` 只做"注入装配"不写业务 | ADR-capability-contracts.md：UI 只依赖 Capability 接口，不依赖具体实现 |

### 1.3 产品哲学来源与待确认项
> 本节内容代码/文档中有明确依据用 ✅ 标记，需要舰长本人补充用 `[待舰长确认]` 标记。

| 原则 | 代码/文档证据 | 状态 |
|---|---|---|
| 教练定位 ≠ 写作工具（Sudowrite 路线回避） | 8-08 文档 `sudowrite-product-comparison.md`：明确 Sudowrite 是"产出工具"，月笙走"教练路线" | ✅ |
| 三档态度（豆包/月笙如歌/sensei）来源 | skill_registry.dart：`part 'skills_attitude.dart'` 对应 3 份 attitude skill | ✅ |
| **三档态度设计初衷（舰长 2026-08-26 确认）**：面向人群不同需要不同语气，新手需要引导+保护，老手需要精准犀利 | 舰长确认原话：「很多情况下因为需要面对的人群不同，用单一的 ai 语气很可能会降低体验感和学习效率，新手需要的是引导，老手需要的一语中的，新手看不得自己的文章被各种改，但是老手就是要这个。」 → 因此三档本质是「**学员成熟度×反馈强度**」的二维映射：豆包（新手温和）< 月笙如歌（通用标准）< sensei（老手犀利）；档位切换的安全词"轻一点"= 在当前档位上向豆包方向回退一档 | ✅（已确认为真源） |
| **六步闭环「问→写→诊→教→练→评」设计依据（舰长 2026-08-26 确认）**：来源于真实写作教学场景的知识蒸馏 + 全网（公开写作资料/学员病例/作品评论）的爬虫归纳；并非某本单一教材的流程，而是对"常见作者问题 → 常见干预动作 → 常见见效路径"的经验蒸馏压缩为 6 步最小闭环 | 舰长确认原话：「开篇，伏笔点题杂七杂八几乎都来源于"蒸馏"+"爬虫"」→ 六步闭环是把这些碎片化知识点按"学员自己能走完的正向循环"组织成顺序 | ✅（已确认为真源） |
| **五维风格画像选型依据（舰长 2026-08-26 确认·大方向）**：五维维度选型本身也是知识蒸馏产物。不来源于某本单一教材，而是来源于对大量写作技巧/写作问题/学员病例做分类归纳后，抽取出 5 条能"覆盖绝大多数文笔风格偏差、又彼此尽量独立"的正交维度。 | 舰长确认原话：「各种各样内容的蒸馏，常见的作者问题，常见的写作技巧，常见的写作问题」→ 五维 = 对这批蒸馏知识做正交化降维后的产物 | ✅ 大方向确认；**[粒度留空]** 每个维度单独的选型依据（比如为什么 sensory 单独一维而不是并入 tone_texture）作为 P2 级细项，后续按维度按需逐填 |
| **L2/L3 症候表 & 技法表设计来源（舰长 2026-08-26 确认·大方向）**：全库 37+ 条症候、技法映射、三层分类全部来源于真实写作教学经验的蒸馏 + 全网公开写作资料与病例的爬虫整理。症候 ID 的顺序（P001~P037）= 当时蒸馏时从"最常见 → 次常见"的排序，越靠前的症候在真实病例中命中频次越高。 | 舰长确认原话：「常见的作者问题，常见的写作技巧，常见的写作问题……杂七杂八几乎都来源于"蒸馏"+"爬虫"」→ 症候的类型分类（structural/expressive/motivational/commercial 四型）= 对蒸馏产物做的类型学归纳 | ✅ 大方向确认；**[粒度留空]** §4.2 表格里每条症候"单独为什么被列为独立症候 / 单独来源是哪批病例/哪篇资料"作为 P2 级细项，建议按 diagnosis_repository 命中 Top 10 优先回填 |

---

## §2 模块意图索引卡（15 张核心卡）

> 每张卡固定 7 字段：`名称 / 一句话意图 / IN→处理→OUT / 设计溯源 / 代码真源 / 守护测试 / 体系角色`

### 卡 #1 — Diagnosis Engine（诊断引擎）
- **一句话意图**：把学员提交的文本段，通过 LLM + L2/L3 知识库规则，产出结构化「问题画像」——输出是"诊断结论"不是"改好的句子"。
- **IN→处理→OUT**：
  - `IN`：学员在写作页选段 → `ParagraphSelection` 对象；当前作品上下文（章节标题 + 前 500 字/后 500 字）；L1 Skill 能力档案；学生画像 v2（五维风格坐标）
  - `① chat_context_builder.dart`：拼装四段式 Prompt 上下文（定位 + 学员画像 + 选段 + L2 索引）；可选注入 `styleTechniqueSection`（8-18 旁路路由接入）
  - `② diagnosis_service.dart`：走 LLM 调用链（llm_client → fallback → retry），请求 LLM 输出 `[YS_DIAGNOSIS]` 协议块
  - `③ diagnosis_parser.dart`：解析协议块 → 提取 `syndromes[]`（症候 ID 列表）、`feedbackSummary`（最短自然语言总结）、`styleProfile`（五维坐标）、`confidence`（置信度）
  - `④ diagnosis_validator.dart`：双校验（JSON Schema 字段完整 + 自然语言不出现"改好的句子/整段重写"黑名单；同时输出互斥症候同命中的 warning 级提示）
  - `OUT`：`FullValidationResult`（含 ParsedDiagnosis 对象）→ 三个消费方：① `DiagnosisCard` widget 渲染给学员；② `teaching_state_cache` 存入教学状态机驱动后续教学；③ `diagnosis_repository` 持久化供成长面板统计
- **设计溯源**：
  - 定位来源：宪法 R-P01「禁止代写」→ 诊断输出不能是改写
  - 双校验来源：8-07 批次 B-1 GenUI 移植前的"诊断误判导致教学方向全错"历史教训 → 设计了 validator 阻断而非事后兜底
  - 分层来源：8-18 架构审查选项 A「能力契约骨架」→ DiagnosisCapability 接口自 DTO 自持，不依赖实现
- **代码真源**：
  - 接口契约：[diagnosis_capability.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/contracts/diagnosis_capability.dart)
  - 实现：[diagnosis_parser.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/services/diagnosis_parser.dart)（解析）、[diagnosis_validator.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/services/diagnosis_validator.dart)（校验）、[diagnosis_service.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/services/diagnosis_service.dart)（LLM 调用编排）
  - UI 消费：[diagnosis_card.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/widgets/diagnosis_card.dart) / [diagnosis_failed_card.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/widgets/diagnosis_failed_card.dart)
- **守护测试**：
  - `test/services/diagnosis_parser_test.dart`：37 项，覆盖协议块边界 / 互斥症候 / 五维坐标缺省
  - `test/services/four_libraries_consistency_test.dart`：症候 ID 是否都在 L2 注册表（否则 Parser 会把未知 ID 吞掉）
  - `test/contracts/diagnosis_capability_test.dart`：契约测试，实现替换时必须过
- **体系角色**：六步闭环 **第三步「诊」的单一真源**。后续教学动作、风格路由、训练任务、成长统计 100% 依赖 Diagnosis 输出；诊断错 = 整个后续链路方向错，因此是最高守护测试覆盖模块。
- **待舰长确认**：五维风格画像 5 个维度选型依据 → 回填到 §1.3 表格。

---

### 卡 #2 — Teaching State Machine（教学状态机 + 反思门控）
- **一句话意图**：驱动教练与学员之间多轮对话的"节奏"，防止教练一步跳结论、强制学员经过「反思」环节。
- **IN→处理→OUT**：
  - `IN`：上一步动作（诊断完成 / 学员回复 / 建议采纳 / 训练判分完成）+ 当前 TeachingPhase
  - `① phase_transition.dart`：按状态转移表（TeachingPhase → TeachingSubphase）计算下一个阶段；`AWAITING_REFLECTION` 是关键门控 — 诊断完成后必须等学员有"我理解了"的回执 receipt 才能推进到教学
  - `② phase_mapper_resolver.dart`：根据阶段从 L2 注册表加载对应 skill 组（beginner→L2 beginner 组 / diagnosis→L2 diagnosis 组）
  - `③ reply_receipt_guard.dart`：学员回执校验；"应用建议/我明白了"操作都要写入 receipt，无 receipt 不允许推进阶段（ADR-P0-receipt-state）
  - `OUT`：新的 TeachingPhase + Subphase → 两个消费方：① `teaching_state_badge.dart` UI 顶部阶段指示器；② `chat_context_builder.dart` 下一步 Prompt 拼接；③ `teaching_state_repository.dart` 持久化 session 级进度
- **设计溯源**：
  - 阶段门控设计：8-07 docs/logs `2026-08-07-t4-evaluation-report.md` 提到"评估阶段学员未内化诊断结论就被推入训练"→ 引入 AWAITING_REFLECTION 强制停顿
  - 设计风格参考：交接文档 §2 明确写「借鉴 Prober.ai」模式
  - Receipt 状态机：ADR-P0-receipt-state 完整定义了 receipt 的 5 态
- **代码真源**：
  - 类型：[teaching_types.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/types/teaching_types.dart)（TeachingPhase enum）
  - 转移逻辑：[phase_transition.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/services/phase_transition.dart) / [reply_receipt_guard.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/services/reply_receipt_guard.dart)
  - 持久化：[teaching_state_repository.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/data/repositories/teaching_state_repository.dart)
- **守护测试**：`test/services/phase_transition_test.dart` 22 项；`test/services/reply_receipt_guard_test.dart` 11 项；阶段跳转会被断言失败
- **体系角色**：六步闭环 **第四步「教」的节奏控制层**。没有状态机，教练会像 Sudowrite 一样一次性给一堆建议（违反 R-P01 学员主权）。状态机让教学是"对话节奏"不是"输出文档"。

---

### 卡 #3 — L1 Skill Registry（L1 常驻技能层）
- **一句话意图**：提供教练的"人格、说话方式、教学底层原则"40 份 Skill 常量，是所有 LLM 调用的 system prompt 基础层（100% 每轮必加载）。
- **IN→处理→OUT**：
  - `IN`：无动态输入（纯静态数据）
  - `处理`：[skill_registry.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/services/skill_registry.dart) 作为宿主（183 行逻辑），通过 24 个 `part` 分片文件加载 40 个 Skill 常量对象
  - `OUT`：40 份 `Skill(id, group, estimatedTokens, content)` → 唯一消费方 `skill_dispatcher.dart` 拼装 system prompt
  - 内容分类：L1 核心 8 份（月笙核心原则/教练身份/边界声明等）+ 3 态度档位（豆包/月笙如歌/sensei）+ L2 按需 5 组 × 若干 + 2 份索引（syndrome-diagnosis-index / technique-library-index，虚拟索引内容来源于 L3）
- **设计溯源**：
  - 数据/逻辑分离：2026-08-18 批次 96-26 完成（待办 Batch2 执行记录 `P3 批次 96-26`）；原文件 5469 行，超 R-019 300 行硬上限 17 倍 → 拆为 183 行宿主 + 24 part 数据分片
  - L1/L2/L3 三层命名：来源于 `分析处理体系转为Agent提示词/` 原始设计，是月笙的教学知识分层（L1 常驻，L2 按需加载组，L3 症候级检索注入）
- **代码真源**：
  - 宿主：[skill_registry.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/services/skill_registry.dart#L54-L90)
  - 分片：同目录下 `skills_*.dart`（24 份）
  - 消费：[skill_dispatcher.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/services/skill_dispatcher.dart)（按 L2Mode 挑组 + 注入 L1）
- **守护测试**：
  - `test/services/skill_registry_l2_test.dart`：L1 常驻层是否缺 8 份核心 / 三档态度是否齐全
  - `test/services/four_libraries_consistency_test.dart`：索引表计行与注册表条数逐字一致（防止 part 拆分漏搬运）
- **体系角色**：六步闭环 **所有步骤的人格层**。教练"说话的样子、不越界的底线"都在这 40 份 Skill。它是 R-P01/R-P02/R-P03 三条铁律的执行载体。
- **待舰长确认**：40 份 Skill 中，哪些是来源于你最初的"教学哲学口述"，哪些是来源于写作理论资料？ → 需要在《L1 Skill 来源溯源表》（§4 新增附录）中逐份登记。

---

### 卡 #4 — L2/L3 Syndrome + Technique KB（症候知识库 + 技法知识库）
- **一句话意图**：**症候表从哪里来？为什么这些症候？** 的单一真源。L2 = 索引速查（LLM 每轮可见），L3 = 症候详细定义（仅当症候被 Diagnosis 命中时才按需注入，避免 token 爆炸）。
- **IN→处理→OUT**：
  - `L2 OUT`（每轮必注入）：`kSyndromeIndexContent` — 症候 ID / 关键词 / 一句话描述 三列索引表；给 LLM "你可以诊断的范围清单"
  - `L3 IN`：Diagnosis 命中的 `List<String> syndromeIds`（例如 `["P009", "P017"]`）
  - `L3 处理`：`_extractSyndromeSection(id)` 正则切片，从 1776 行 `kSyndromeManualContent` 里精准切出该症候的完整定义（含判断原则、诊断锚点、例外情况），加统一 Header 拼接
  - `L3 OUT`：给下一轮 LLM 的 system prompt 末尾追加（学员不可见），防止 LLM 按"通用知识"乱诊断
  - 技法库：同理三层 — L2 技法索引（shortNames 速查）→ L3 技法定义（五维映射：类型/层级/适用症候/练习方式/掌握标准）
- **设计溯源**：
  - 分层 L2/L3 设计：为解决"全量注入 token 爆炸"（A-1 素材预算止血问题的前身）；交接文档 §1 明确 A-1 素材预算是 P0 级问题
  - 注册表单行化：8-11 批次 b9 `syndrome-registry-design.md`：把大字符串中的表格行改由注册表派生，渲染输出逐字一致（既保持 LLM 接收格式不变，又能在代码里用 List 管理）
  - 数据/逻辑分离：2026-08-18 批次 96-27 `P3 知识减负` 完成 — 症候 1845→70+1776 行 / 技法 1151→291+861 行
- **代码真源**：
  - 症宿主：[syndrome_knowledge_base.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/services/syndrome_knowledge_base.dart)
  - 症候数据分片：`syndrome_kb_content.dart` + 6 份 `syndrome_kb_content_manual_*.dart`
  - 技法宿主：[technique_knowledge_base.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/services/technique_knowledge_base.dart)（含派生映射、五维分类、技法名速查）
  - 注册表：[syndrome_registry.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/services/syndrome_registry.dart)（含 ID / 类型 / 关键词 / 一句话 / 首选技法 / 退休标记）
- **守护测试**：`test/services/syndrome_technique_knowledge_test.dart` 31 项；`four_libraries_consistency_test.dart` 逐字校验（索引表由注册表生成，结果与手写一致）；`syndrome_detail_modal.dart` 里 ID→详细内容可被手动翻页验证
- **体系角色**：六步闭环 **第三步「诊」的知识权威源**。没有它，Diagnosis 只是 LLM"瞎猜"；有了它，Diagnosis 是"按册查病"。
- **待舰长确认（§4 有全表）**：P001~P037 每条症候的设计来源 — 哪些来自《故事》、哪些来自你个人教学经验、哪些来自学员真实病例？ → §4.2 待回填。

---

### 卡 #5 — Training KB（训练任务库 & 对话级任务表）
- **一句话意图**：用户画像/症候被命中后，**给学员什么练习** 的单一真源；含任务描述、练习框架、判分标准、掌握阈值。
- **IN→处理→OUT**：
  - `IN`：诊断命中的 `focusedSyndromeId` + 学员当前 `skillLevel`
  - `处理`：`training_knowledge_base.dart` 宿主 46 行逻辑 → 从 1050 行分片匹配"症候 ID × 等级"的训练任务
  - `OUT`：`TrainingTask` 结构化对象（id/title/description/passCriteria/promptTemplate）→ 两个消费方：① `training_input_builder.dart` 拼装给 LLM 的训练 Prompt；② `practice_task_card.dart` UI 展示给学员
- **设计溯源**：8-07 docs/logs `2026-08-07-t3-training-system.md`（T3 训练系统立项）：训练必须"与诊断一一对应"、不能是通用写作题；判分 GenUI quiz 与任务绑定。
- **代码真源**：[training_knowledge_base.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/services/training_knowledge_base.dart)（宿主）+ `training_kb_content*.dart`（4 分片）；训练输入构造：[training_input_builder.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/services/training_input_builder.dart)
- **守护测试**：`training_evaluator_test.dart`（判分逻辑 + 通过率阈值边界）
- **体系角色**：六步闭环 **第五步「练」的题库源**。训练是"诊断-教学"之后的行为内化环节；没有训练，学员只知道"我有问题"但不会"改行为"。

---

### 卡 #6 — LLM Invocation Chain（LLM 调用链：Fallback + Retry + Stream Guard）
- **一句话意图**：让 LLM 调用**不因为单次失败就崩给用户**；通过多 Endpoint 降级 + 指数退避重试 + UTF-8 边界流式防护，把"脆"的 LLM 接口封装成"稳"的内部服务。
- **IN→处理→OUT**：
  - `IN`：ChatRequest（messages + endpoint 偏好）；可选 LlmRetryPolicy（默认 jitterMs=250）
  - `① network_check.dart`：先探活；无网络立即本地错误（不等待超时）
  - `② llm_config_storage.dart`：从 SQLite 读 Endpoint 配置（学员自填 API Key，不硬编码，R-029）
  - `③ llm_retry.dart`：指数退避 + 抖动；每轮等待 2^attempt × baseMs ± jitter；最大 5 轮
  - `④ llm_fallback.dart`：主 Endpoint 连续失败 2 次 → 切备用 Endpoint（学员设置里可配）；所有 Endpoint 失败才给用户
  - `⑤ llm_client.dart`：Dio 发起实际请求；流式接收（不等到全文字节流完再渲染）
  - `⑥ stream_guard.dart`：流式分段边界保护（UTF-8 多字节字符不被劈断，防止 GenUI JSON 解析出半个字）
  - `⑦ error_handler.dart` + `_buildDioError`：错误信息脱敏（B22 安全补强：Authorization Header 星号化，不泄露 Key）
  - `OUT`：`Stream<String>`（增量文字流）→ 交给各协议 parser；失败时 `ChatError`（用户可读错误，不抛栈）
- **设计溯源**：
  - Fallback 设计：X-038 B1（2026-08-25）批次落地；之前出现过"某个 Endpoint 维护半小时，学员端全挂"的事故 → 设计 Endpoint 轮换
  - Retry 设计：X-038 B2；LLM API 经常 429（限流）/ 502（网关），不能一次失败就判"服务不可用" — 默认带 jitter 防止雪崩
  - Stream Guard：8-17 批次遗留问题，UTF-8 中文字符 3 字节，流式切割如果恰好在第 2 字节会解析失败 → 切"字符边界对齐"
- **代码真源**：
  - 客户端：[llm_client.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/services/llm_client.dart)
  - 重试：[llm_retry.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/services/llm_retry.dart)
  - 降级：[llm_fallback.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/services/llm_fallback.dart)
  - 流式防护：[stream_guard.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/services/stream_guard.dart)
  - 错误脱敏（B22 待补）：[error_handler.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/services/error_handler.dart)
- **守护测试**：`test/services/llm_retry_test.dart` 27 项（关 jitter 做精确断言）；`test/services/llm_fallback_test.dart` 降级链 9 项
- **体系角色**：六步闭环 **所有步骤的基础设施层**。任何一步要跟 LLM 说话（诊断/教学/训练/评估）都经过这条链；调用链不稳 = 全系统不稳，因此是 2 级高守护模块。

---

### 卡 #7 — Capability Contracts（能力契约层）
- **一句话意图**：把"隐式能力"（诊断/教学/素材/GenUI/引用/提及/注册）提升为**显式接口契约**；UI 层只依赖接口，不依赖具体实现 — 未来换 Flutter→Electron 或接入云端 DSH 插件，只要实现同一个接口，UI 不用改。
- **IN→处理→OUT**：
  - 契约层文件：7 份接口，自持有 DTO，不 `import` 任何实现文件（防止循环依赖，R-020）
    - [diagnosis_capability.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/contracts/diagnosis_capability.dart)（诊断：Parser + Validator + DTO）
    - [teaching_capability.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/contracts/teaching_capability.dart)（教学：Skill 加载 / L2 Mode / L3 检索 / SystemPrompt 拼装）
    - [genui_capability.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/contracts/genui_capability.dart)（GenUI：解析/校验/本地判分）
    - [material_capability.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/contracts/material_capability.dart)（素材注入 + 预算止血）
    - [mention_capability.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/contracts/mention_capability.dart)（@ 稳定引用解析）
    - [reference_capability.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/contracts/reference_capability.dart)（参考资料库 CRUD）
    - [capability_registry.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/contracts/capability_registry.dart)（注册表：所有 capability 统一装配入口）
  - 实现侧：每个契约的 Impl 放在 `lib/services/` 对应文件（例如 `DiagnosisCapabilityImpl` in diagnosis_parser.dart），通过 Riverpod `capability_providers.dart` 做依赖注入
- **设计溯源**：
  - 直接来源：2026-08-18 架构审查 §3 选项 A「能力契约层骨架，不改实现」（原 §5 三个选项 A/B/C，A 是第一步）
  - 正式 ADR：`docs/ADR-capability-contracts.md`（未读，待执行时补细节）
  - 依赖倒置原则：8-18 架构 §2 C1「service 层直接互引」风险 → 抽接口让 UI → 契约 → 实现，依赖方向单向
- **代码真源**：契约目录 `lib/contracts/`；装配注入 [capability_providers.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/providers/capability_providers.dart)
- **守护测试**：`test/contracts/*_capability_test.dart` 7 份契约测试 — 实现可以换，但契约测试永远必须过
- **体系角色**：**跨双端的协议层**（Flutter ↔ Electron/React 的共享边界）。按 8-18 架构 §2 C2 结论："双端不共享实现，只共享契约/协议" — 这 7 份 Dart 接口就是未来 TS 侧实现时要复刻的形状。目前只完成第一步"契约骨架"，依赖倒置真的切换（service 只引契约不互引）还没做，属于 roadmap。

---

### 卡 #8 — GenUI 系统（可交互组件通道）
- **一句话意图**：让 LLM 不仅能输出"纯文字"，还能输出 5 类结构化可交互组件（Diff 对比 / Quiz 判分 / Stat 画像 / Progress 进度 / Timeline 时间线），用于教学阶段的即时练习与反馈。
- **IN→处理→OUT**（典型 Quiz 链路）：
  - LLM 输出 `[YS_GENUI]{"type":"quiz", "payload":{...}}[/YS_GENUI]` 协议块
  - `① genui_parser.dart`：按类型分派 → 提取 JSON payload
  - `② genui_validator.dart`：JSON Schema 校验（quiz 必须有 question/options/correctIndex/explain）
  - `③ gen_ui_card.dart`：分派 5 种渲染器 → `gen_ui_quiz.dart` 渲染选项按钮
  - `④ 学员点击选项`：本地判分（不请求 LLM！）→ 显示正误解释 + 正确答案高亮
  - `⑤ training_evaluator.dart`：记录判分结果 → 影响 skillLevel 与下一轮任务分配
- **设计溯源**：8-07 docs/logs `2026-08-07-b69-a7-realtime-ui.md`（A7 双通道方案 B）：先 LLM 输出 markdown 纯讲 → 再追加 GenUI 组件即时交互，解决"纯文字学员不操作"问题。
- **代码真源**：协议解析 genui_parser/validator；渲染器 [gen_ui_card.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/widgets/gen_ui_card.dart) + [gen_ui_quiz.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/widgets/gen_ui_quiz.dart)
- **守护测试**：`genui_parser_test.dart` + `gen_ui_quiz_test.dart`（本地判分边界 12 项）
- **体系角色**：第四步「教」与第五步「练」之间的**交互桥**。纯文字教学"说完了学员有没有真的掌握"无法判断；GenUI Quiz 把"理解信号"量化成可采集数据。

---

### 卡 #9 — Message Card Dispatcher（消息卡片分派器）
- **一句话意图**：把 LLM 输出的"一整段流式文本"按 8 类协议块 `[YS_*]` 切分并分派给不同渲染器（消息气泡/诊断卡/GenUI/提纲卡/引用卡/训练卡/评估卡/教学建议卡），是消息列表 UI 的"流量调度中心"。
- **IN→处理→OUT**：
  - `IN`：LLM 流式输出 String（原始含协议块标记）
  - `处理`：`message_card_service.dart` 正则切片 `[YS_X]...[/YS_X]` + 协议块外纯文本 = 段落级 Card 列表
  - `OUT`：`List<MessageCard>`（每卡带 type）→ [message_card_dispatcher.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/widgets/message_card_dispatcher.dart) 根据 type 映射到对应 widget
- **设计溯源**：8-07 docs/logs `2026-08-07-b68-a7-dual-channel.md`（A7 双通方案 B）："一条消息多段混合"是教练对话常态，不能让每个 widget 自己去切字符串。
- **代码真源**：[message_card_service.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/services/message_card_service.dart)（切片）；[message_card_dispatcher.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/widgets/message_card_dispatcher.dart)（分派）
- **守护测试**：`message_card_dispatcher_test.dart` 21 种协议块组合
- **体系角色**：所有步骤的**UI 输出调度层**；从「诊」到「评」每一步的 UI 呈现都走它。

---

### 卡 #10 — Material Reference System（素材 & 引用系统）
- **一句话意图**：让学员上传自己的参考资料（设定/人物卡/世界观/前文），教练可按 `@` 稳定引用注入上下文；同时通过「素材预算」控制注入量，避免 token 爆炸（A-1 问题的根因修复）。
- **IN→处理→OUT**：
  - `参考资料 CRUD`：`reference_repository.dart` → reference_picker.dart 管理，支持 REF-C1-001 系列登记
  - `稳定 ID 引用（@锚点）`：ADR-A2-stable-mention-id.md — 原来按标题匹配会因为章节改名失效 → 改为给每个可引用段落分配永久 `mention_id`，`mention_parser.dart` 解析 `@MID_xxx` 注入
  - `段落锚点（选段引用）`：ADR-A3-paragraph-anchor.md — 学员写作时引用自己前文某段 → 按 `para_<chapter>_<hash>` 锚定，即使段落移动也能恢复（`paragraph_selection.dart`）
  - `预算止血`：`token_budget_guard.dart` + `token_budget_table.dart` 定义 4 档预算（L1/L2/L3 各占多少 token），超预算自动截断低优先级引用而不是静默溢出
- **设计溯源**：交接文档 §4 待办 A-1 素材预算止血 / A-2 稳定 ID / A-3 段落锚点 — 三个独立痛点，统一归为"素材引用系统"，2026-08 之后陆续落地
- **代码真源**：
  - 数据层：[reference_repository.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/data/repositories/reference_repository.dart) / [mention_parser.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/services/mention_parser.dart)
  - 契约：[mention_capability.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/contracts/mention_capability.dart) / [reference_capability.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/contracts/reference_capability.dart)
  - UI：[reference_picker.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/widgets/reference_picker.dart) / [reference_bar.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/widgets/reference_bar.dart)
- **守护测试**：`mention_parser_test.dart` / `token_budget_guard_test.dart`（预算截断顺序 9 项）
- **体系角色**：六步闭环 **第一步「问」和第二步「写」的上下文**。没有素材系统，教练不知道学员写的"秦羽"是谁、"玄界"是什么设定，诊断必然偏离。
- **待舰长确认**：参考资料库 REF-C1-001~REF-C1-005 的"推荐分类依据"（为什么默认分 5 类而不是 3 类或 8 类）？

---

### 卡 #11 — Design Tokens（设计令牌系统）& 14 批全局 UI 重构
- **一句话意图**：把 Flutter 端 788 处 BorderRadius / EdgeInsets 硬编码数值统一替换为 AppRadius / AppSpacing 令牌引用，实现「改一处全库响应」的设计一致性；分 14 批小步改造避免风险。
- **令牌家族（单一真源）**：
  - 圆角：xs=4 / sm=8 / md=12 / lg=16 / **xl=24**（X-039 补）/ pill=100
  - 间距：**xxs=2** / xs=4 / **xsm=6**（X-039 补）/ sm=8 / **smx=10**（X-039 补）/ md=12 / lg=16 / **section=20**（X-039 补）/ xl=24 / **xxl=32**（X-039 补）/ page=16
  - 颜色：竹青色系（月白→竹青→墨青 8 阶）+ 矿物色系辅助（success/warning/error 颜色）
- **设计溯源**：
  - 令牌家族基础设计：8-11 批次 `ui-polish-design.md`
  - X-039 P0-2 14 批改造计划：全库频次扫描后，按"功能域内聚 + 每批 ≤6 组件"切分（见待办执行清单 §切片表）
  - 非标准近似规则：BR:2→xs、EI:3→xxs、EI:14→md — 每次替换须在批次台账登记，不悄悄吞差异
- **代码真源**：[app_theme.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/config/app_theme.dart#L85-L108)（令牌定义，含 X-039 补位注释）
- **守护方式**：每批 6 文件替换完 → dart analyze 0 error → 相关家族 test 全绿 → 批次独立 commit → 推送 GitHub Actions；截至 2026-08-26 已完成 Batch1+Batch2（12 文件），12 批待执行
- **体系角色**：**跨所有 UI 的视觉一致性层**。它不直接参与教学闭环，但它是"产品感觉是否专业统一"的决定性模块；令牌化后未来改视觉风格（如改圆角风格）只需改 app_theme.dart 一行。

---

### 卡 #12 — Quality Gates & CI（宪法四闸门禁 & CI 管线）
- **一句话意图**：把宪法 §二 五项架构承诺（循环依赖零容忍 / dart format / 覆盖率口径 / 依赖审计 / 类型 0 error）变成 CI 强制闸；不通过 = 不能合并，防止"我知道应该做但没人做"的合规漂移。
- **五闸落地状况（截至 2026-08-26，All Green）**：
  - **闸 0 dart format**：CI gate0 + pre-commit 双强制（X-034 批次 8-23 落地）；未格式化 PR 直接 fail
  - **闸 1 typecheck（tsc/dart analyze）**：宪法默认，CI Gate1 原生
  - **闸 2 test 全绿**：宪法默认，CI Gate2
  - **闸 3 循环依赖扫描**：CI Gate3 + pre-commit 双强制（X-033 批次 8-22 落地）；`check_cycles.sh` Dart 端跨 Riverpod/provider/services 三层
  - **闸 4 coverage**：T1 整库 65±2% 软门槛（warn）+ T2 核心文件 85% 硬门槛（block）；CI Gate4（X-035 批次 8-24 对齐）；远期 aspirational 目标不做强制
  - **闸 5 依赖审计**：`check_outdated.py` + D# 豁免机制（D1 安全高风险必须升 / D2 稳定性 / D3 开发态 / D4 锁版本暂不升）；CI Gate5 push+release 双模式（X-036 批次 8-25 落地）
- **设计溯源**：宪法 §二 4/5/6 三项落地前，曾出现"循环依赖偷偷引入 3 处、覆盖率从 72→61 无人察觉、依赖 12 个过期版本未升"的合规漂移事故 → 宪法承诺升级为 CI 强制
- **代码真源**：`.github/workflows/flutter_ci.yml`；脚本：`scripts/check_cycles.sh` / `scripts/check_outdated.py` / `scripts/gate.sh`
- **守护方式**：GitHub Actions 每次 push 五闸执行；5 闸全绿才触发 coverage-tracker 标签更新台账
- **体系角色**：项目的**免疫系统**。其他 14 张卡保障"设计对"，它保障"设计一直对"。

---

### 卡 #13 — Writing Page Family（写作页面家族）
- **一句话意图**：学员写作的主工作台（编辑器 + 教练面板 + 章节导航 + 选段 AI + 查找替换 + 状态构建），是第二步「写」和贯穿第三步「诊」→ 第四步「教」的**主操作界面**。
- **子模块（6 个核心文件，X-037 P0-1 已全部对齐 UI 审查）**：
  - [writing_page.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/widgets/writing_page.dart)（主容器）
  - [writing_coach_panel.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/widgets/writing_coach_panel.dart)（教练侧面板容器）
  - [writing_coach_panel_builders.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/widgets/writing_coach_panel_builders.dart) + [writing_coach_panel_teaching.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/widgets/writing_coach_panel_teaching.dart)（面板内容构建）
  - [writing_page_status_builders.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/widgets/writing_page_status_builders.dart)（加载/错误/空状态）
  - [writing_page_selection_ai.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/widgets/writing_page_selection_ai.dart)（选段 AI → 触发诊断）
- **设计溯源**：8-05 docs/plans `2026-08-05-writing-page-redesign.md`（原写作页"编辑器和聊天分开两屏"→ 合并为左右分栏，写作同时可见教练意见）；X-037 P0-1 批次（2026-08-22 执行）做了 UI 审查对齐（C1 间距/H1 颜色规范/H2 圆角/H4 动效）
- **代码真源**：如上 6 文件 + `editing/focus_aware_editing_controller.dart`（焦点感知控制器，防止光标定位乱跳）
- **守护测试**：`writing_page_test.dart` / `focus_aware_editing_controller_test.dart`（中文输入法光标跟随 16 项）
- **体系角色**：六步闭环的**主舞台**。学员 80% 的产品时间都在这个页面家族里。

---

### 卡 #14 — Bookshelf & Manuscript Detail（书架 & 作品详情家族）
- **一句话意图**：学员作品的文件管理入口（书架页）+ 作品内部结构入口（卷章树、章节编辑、导出、回收站），对应作品"长期维护"场景。
- **子模块**：
  - [bookshelf_page.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/widgets/bookshelf_page.dart)（作品卡片列表、筛选、创建/导入）
  - [manuscript_detail_page.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/widgets/manuscript_detail_page.dart)（作品详情主容器，含 4 Tab：章节树/卷组/导出/设置）
  - [manuscript_detail_chapter.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/widgets/manuscript_detail_chapter.dart)（章节详情）+ volume / export 系列
- **设计溯源**：8-06 docs/logs `2026-08-06-c3-bookshelf-manuscript-redesign.md`（C3 书架/作品重新设计）；原书架"只有平铺卡片"→ 新增筛选标签、回收站、批量导入 TXT/Markdown
- **体系角色**：**长期数据的"仓"**。写作页家族是"流"（操作过程），书架是"库"（操作结果）。

---

### 卡 #15 — Growth Panel Family（成长面板家族）
- **一句话意图**：把学员"用过教练、做过训练、被诊断过哪些症候"的学习历史可视化；给出能力雷达图 + 症候趋势 + 掌握进度，对应第六步「评」。
- **子模块**：
  - [growth_page.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/widgets/growth_page.dart)（总览容器：能力雷达 + 症候历史 Tab）
  - [growth_content.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/widgets/growth_content.dart)（成长详情内容块）
  - [ability_chart.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/widgets/ability_chart.dart)（五维风格画像雷达，来源 ParsedDiagnosis.styleProfile 累积平均）
  - [syndrome_history_list.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/widgets/syndrome_history_list.dart)（症候命中趋势：P017 是上升还是下降）
- **设计溯源**：8-06 docs/logs `2026-08-06-c4-growth-page-redesign.md`（C4 成长页重新设计）；原成长页"一串文字统计"→ 改为雷达 + 趋势曲线，R-P03 学员主权：让学员"看得见自己的进步"，而不是只有教练知道。
- **体系角色**：六步闭环 **第六步「评」的可视化载体**。没有它，学员坚持不下去（没有正反馈）；教学效果评估也无从量化。

---

## §3 三条关键数据流时序（Read 视图）
> 本节回答"数据怎么流？输出给谁？"。时序图是逻辑示意，不反映方法级调用。

### §3.1 诊断主链路（学员点击「诊断此段」→ 看到诊断卡片）

```
学员 UI                          状态/服务层                        LLM + 知识库
  │  点击选段诊断 Button            │                                    │
  │──ParagraphSelection───────────▶│ chat_context_builder.dart          │
  │                                │  ① 拼装四段式 Prompt:             │
  │                                │     - L1 Skills (常驻)            │
  │                                │     - L2 Syndrome Index           │
  │                                │     - 学员画像五维坐标             │
  │                                │     - 选段文本 + 前后窗口上下文   │
  │                                │  ② 可选注入 StyleTechniqueSection │
  │                                │──LLM Request (via llm_client)────▶│
  │                                │  Fallback+Retry+StreamGuard       │ 流式返回 [YS_DIAGNOSIS]...
  │                                │◀─Stream<String>───────────────────│
  │                                │  ③ diagnosis_parser.dart 切协议块 │
  │                                │  ④ diagnosis_validator 双校验      │
  │                                │     ✓ JSON Schema 字段完整?       │
  │                                │     ✓ 自然语言无代写黑名单?       │
  │                                │     ⚠ 互斥症候同命中警告          │
  │                                │  ⑤ 产出 ParsedDiagnosis 对象      │
  │                                │                                     │
  │◀─DiagnosisCard 渲染────────────│  ──┐                               │
  │  (症状/总结/画像/置信度)       │    │                               │
  │                                │    ├▶ teaching_state_cache 存入    │
  │                                │    │    触发状态机 → AWAITING_REF   │
  │                                │    └▶ diagnosis_repository 持久化 │
  │                                │         (供成长面板分析)          │
```

**关键设计判断（非显然）**：
- 校验失败不抛异常给用户 → 渲染 [diagnosis_failed_card.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/widgets/diagnosis_failed_card.dart)（明确告诉用户"诊断失败了，你可以重试"，而不是把红色栈堆打在 UI 上）
- ParsedDiagnosis 三个消费方**都是 fire-and-forget 并行**：UI 不等待 DB 写入完成才渲染

---

### §3.2 教学/GenUI 交互链路（学员确认诊断 → 练题判分）

```
教学状态机                        Service 层                             学员 UI
  │  (Receipt: 学员确认理解诊断)   │                                        │
  │──Phase: REFLECTION→TEACHING──▶│  skill_dispatcher 加载 L2 teaching 组 │
  │                                │  → buildSystemPromptV2                │
  │                                │  ① chat_service 发送教学请求          │
  │                                │──▶ LLM (经 llm_fallback 链)           │
  │                                │◀── 返回含 [YS_GENUI] 协议块 + 讲解文字│
  │                                │  ② message_card_service 分派:         │
  │                                │     - 文字 → MessageBubble           │
  │                                │     - GenUI quiz → GenUICard         │
  │◀─教学建议气泡──────────────────│                                        │
  │◀─GenUI Quiz 卡(选项按钮)──────│                                        │
  │                                │                                        │──学员点击选项 B
  │                                │  ③ 本地判分 GenUI Quiz               │◀─(LocalJudge)
  │                                │     ✓ correctIndex == 学员选值?      │
  │◀─正误解释+高亮─────────────────│                                        │
  │                                │  ④ training_evaluator 写学习结果     │
  │                                │     - skillLevel++（通过阈值）       │
  │                                │     - 写入 student_model_repo        │
  │                                │  ⑤ Phase: TRAINING→EVALUATING        │
  │◀─教学状态徽章更新──────────────│                                        │
```

**关键设计判断（非显然）**：
- GenUI quiz 的判分在**学员本地**完成，不回 LLM（省钱+极速+LLM 偶发判分不一致的规避）
- GenUI diff 组件**永远不提供「一键应用」写入学员原文**（R-P01 禁止代写的执行级护栏）

---

### §3.3 作品写作↔保存↔书架链路（学员在编辑器里写了 → 书架能看到）

```
写作页家族                       数据层 (drift/repo)                     书架页家族
  │  输入文字 (focus 控制器防抖 1s) │                                        │
  │  writing_page_selection_ai     │                                        │
  │──Chapter Delta───────────────▶│ chapter_repository (drift update)       │
  │                                │  写入 SQLite chapters 表                │
  │                                │  触发 last_edit_at 戳记                 │
  │                                │  (auto-save，不点击保存按钮)            │
  │                                │                                        │
  │────────────────────────────────│────────────────────────────────────────│
  │ (用户点击返回退出写作页)        │                                        │  用户打开书架页
  │                                │  manuscripts_repository 聚合:           │──manuscript_providers
  │                                │   - 作品信息                            │
  │                                │   - 最新章节 last_edit_at               │
  │                                │   - 章节数/字数统计                     │
  │                                │◀──Query─────────────────────────────────│
  │                                │──ManuscriptSummary 列表───────────────▶│
  │                                │                                        │  bookshelf_page 卡片列表渲染
  │                                │                                        │   (点击卡片跳 manuscript_detail)
```

**关键设计判断（非显然）**：
- Auto-save 1s 防抖（不是实时）：防止中文输入法每次按键都打 DB；drift 批量合并
- 书架页显示的"字数/章节数"**不做实时**：打开书架时一次查询，避免跨页面订阅导致 N+1（C3 设计里明确：N+1 合并查询，X-033 循环依赖扫描曾捕获过 manuscripts→chapters→manuscripts 的循环订阅）

---

## §4 知识库权威溯源（回答：症状表/画像表/任务表从哪里来？）

### §4.1 四库溯源一览（四卡对照）

| 库 | 宿主文件（逻辑真源） | 数据分片文件（内容真源） | 「它为什么存在」设计来源 | 在教学闭环中的作用 |
|---|---|---|---|---|
| **L1 技能层（40 Skill 常量）** | [skill_registry.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/services/skill_registry.dart)（183 行） | `skills_l1_core*.dart`（4）/ `skills_attitude.dart` / `skills_beginner*.dart`（8）/ `skills_diagnosis*.dart`（3）/ `skills_training*.dart`（5）/ `skills_advanced_outline*.dart`（6）/ `skills_reply_voice.dart`（合计 28 份） | **[待舰长确认]** 40 份 Skill 哪份来源是什么？现有注释：`真源：yuesheng-android/src/assets/skills/*.ts`（即 RN 端 assets，原始来源待填） | 所有 LLM 调用的 System Prompt 基础；教练人格、边界、三档态度的载体 |
| **L2/L3 症候知识库** | [syndrome_knowledge_base.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/services/syndrome_knowledge_base.dart)（70 行） | `syndrome_kb_content.dart`（索引）+ `syndrome_kb_content_manual_1~6.dart`（L3 手册 1776 行） | 来源：RN 版 `syndrome-diagnosis.ts`；批次 22 逐字搬运；b9 批次 28 表格化派生 | 诊断时的"查册"依据；L2 索引 LLM 每轮见，L3 症候命中才按需注入 |
| **技法知识库（L2/L3 映射）** | [technique_knowledge_base.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/services/technique_knowledge_base.dart)（291 行） | `technique_kb_content*.dart`（3 份，861 行） | 来源：RN 版 `technique-library.ts`；b7/b8 批次补充分层/shortName 映射 | 教学第四步的技法推荐依据；Style-Technique Router 旁路路由（五维偏差→技法）用它 |
| **训练任务库** | [training_knowledge_base.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/services/training_knowledge_base.dart)（46 行） | `training_kb_content*.dart`（4 份，1050 行） | 8-07 T3 训练系统立项：t3-training-system.md | 第五步练的任务/判分标准；每条训练任务与症候 ID × 学员等级对应 |

### §4.2 症候表溯源表（P001~P037，每条一志 · 大方向已确认）

> **设计背景（舰长 2026-08-26 确认）**：本表所有症候（含 L2 索引分类、L3 详细判断锚点、症候→首选技法映射）**全部来源于对真实写作教学经验的知识蒸馏 + 全网公开写作资料与学员病例的爬虫整理**，并非某本写作教材的直接搬运。
>
> - **症候 ID 顺序的意义**：P001~P037 的排序 = 当时蒸馏/爬取整理时，按「在真实教学病例中被观察到的命中频次从高到低」的降序排列。越靠前的 ID = 作者常犯的问题；越靠后的 ID = 更细分 / 更低频但独立影响质量的问题。
> - **类型分类的意义**：structural（结构型）/ expressive（表达型）/ motivational（动机型）/ commercial（网文商业型）四型 = 对蒸馏产物做的**类型学归纳**，把 37+ 条症候按"作者需要从哪个层面干预才见效"归为四类，方便 L2 Mode 切换时按类型粗检索。
>
> 以下表格按症候逐条留空，属于**粒度级 P2 细项**（不是 P0 级阻塞）；每次新增/修改/退役症候时，必须先在此表补一行设计初衷，再改 syndrome_registry.dart（R-017 文档同步）。

| 症候 ID | 症候名 | 类型（代码中定义） | 首选技法（代码中定义） | 设计初衷：「为什么把它列为一条独立症候」 | 来源：哪本写作理论/哪次教学案例/哪位学员的病例？ |
|---|---|---|---|---|---|
| P001 | —（待舰长补） | structural | — | — | — |
| P002 | — | — | — | — | — |
| ...（P003~P036 逐行留空待填） | | | | | |
| P037 | — | — | — | — | — |

> 共 37 条症候 + 已 retired 若干；建议舰长优先回填 10 条最高频命中的症候（diagnosis_repository 统计 top 10），其余按需迭代填。

### §4.3 五维风格画像 & 对话级任务表溯源

| 维度 / 项目 | 代码真源 | 计算逻辑 / 数据来源 | **设计依据（舰长 2026-08-26 确认·大方向）** |
|---|---|---|---|
| 五维风格画像 sensory（感官度） | `ParsedDiagnosis.styleProfile` in diagnosis_parser.dart | LLM 返回值（由 Prompt 四段式要求 LLM 按 0-10 打分）+ student_profile_compute.dart 跨 session 加权累积平均 | ✅ **大方向确认**：五维选型本身是对"常见作者问题 / 常见写作技巧 / 常见文笔偏差"三类蒸馏知识做正交化后的结果（见 §1.3 五维画像条）。**[粒度留空·P2]** 若后续要解释"sensory 单独一维而不是并入 tone_texture"的具体判断，可按维度单独补一条该维度蒸馏时的分类学理由。 |
| 五维风格画像 rhythm（节奏） | 同上 | 同上 | ✅ 大方向确认（同上）；粒度留空 P2 |
| 五维风格画像 narrative_distance（叙事距离） | 同上 | 同上 | ✅ 大方向确认（同上）；粒度留空 P2 |
| 五维风格画像 tone_texture（语气质感） | 同上 | 同上 | ✅ 大方向确认（同上）；粒度留空 P2 |
| 五维风格画像 structure（结构） | 同上 | 同上 | ✅ 大方向确认（同上）；粒度留空 P2 |
| Style-Technique Router（画像→技法旁路 4 条门控） | [style_technique_router.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/services/style_technique_router.dart) | ① 画像未沉淀→空 ② L2/L3 症候活跃→空 ③ 焦点症候技法含文笔→空 ④ 通过→前 2 条排除 mastered | 8-18 旁路路由方案 A（文档待补链接）；门控设计哲学本质也是「**蒸馏经验 → 规则化**」：① 画像不够量就别乱推荐（避免新手还没画像被技法打乱节奏）② 有明确症候先对症（不跳过诊先教文笔）③ 避免重复施教（焦点症候已经教了对应技法就不叠加） |
| 对话级任务表（Training 每个 Session 的任务队列） | `TeachingTask` 对象在 teaching_types.dart | 由 `phase_mapper_resolver.dart` + 诊断命中症候 + 等级匹配 Training KB | ✅ **大方向确认**：任务顺序（先焦点症候后文笔、先轻后重）来源于蒸馏经验（学员一次只改一个问题最高效；一次改三点会混乱而放弃），**不是某本教学理论的直接搬运**。粒度留空 P2：若未来有任务顺序事故，可补一条"为什么这个顺序"的经验依据。 |
| 掌握阈值（Mastery 判定标准） | `training_evaluator.dart` 中 masteryThreshold 常量 | 连续 X 次同一任务正确率 ≥ Y%；或 3 次训练平均 ≥ Z（具体数值常量在代码里） | **[粒度留空·P2]** 数值常量取值大概率也是蒸馏经验 + 真实学员训练数据试凑后的阈值；但当前没有书面依据确认"X/Y/Z 为什么不是别的值"，后续调整数值前可先回填。 |

### §4.4 诊断引擎已知失败类型表（借鉴 Universal Diagnostic Tutor Skill · 2026-08-27 调研）

> **来源**：[Universal Diagnostic Tutor Skill](https://github.com/SenmuuuuW/universal-diagnostic-tutor-skill) 项目的 `FAILURE_TAXONOMY.md`，2026-08-27 调研抽取。原项目面向 STEM 理科学习，我们做了领域迁移（理科→写作）。**只收录 ✅ 可迁移条目 + 写作特有新增条目**，❌ 不适用条目（数学格式/部署问题）已排除。
>
> **使用方式**：X-041 数据飞轮看板应对照本表监控失败频次；每次诊断引擎改动应检查是否引入了新的失败类型。

| 失败 ID | 失败名称（迁移后） | 触发场景（写作教练版） | 修复方向 | 我们当前的守护机制 | 状态 |
|---|---|---|---|---|---|
| FT-01 | 范文优先回退 | 先给范文/模板再诊断，违反 R-P01 禁止代写 | Prompt 约束 + diagnosis_validator 黑名单 | `diagnosis_validator.dart` 有"整句替换"黑名单 | ✅ 已守护 |
| FT-02 | 过度解释 | 给学员讲大量文学史/修辞学理论后才进入正题 | 认知负荷控制 + 下一步最佳步骤 | L2 索引控制 LLM 可见范围；**缺：输出长度监控** | ⚠️ 部分守护 |
| FT-03 | 解释不足 | 诊断报告过于简略，学员看不懂"结构松散"具体指什么 | 解释压缩控制 + 输出格式 | ParsedDiagnosis.feedbackSummary 有总结字段；**缺：最低详细度门槛** | ⚠️ 部分守护 |
| FT-04 | 维度混淆 | 把文风偏差误诊为结构问题（五维交叉污染） | 领域诊断 + 知识体系映射 | 五维正交设计 + L2 症候索引限定范围 | ✅ 已守护 |
| FT-05 | 缺口误诊 | 把词汇量不足误诊为逻辑思维能力弱 | 知识缺口分类法 | L2/L3 症候表有类型分类（structural/expressive/motivational/commercial） | ✅ 已守护 |
| FT-06 | 假掌握 | 学员写出一个好比喻就认为掌握了整体修辞能力 | 掌握信号多证据 + 复习/推进门控 | `reply_receipt_guard.dart` + masteryThreshold 连续 X 次；**缺：多证据要求** | ⚠️ 部分守护 |
| FT-07 | 练习脱靶 | 诊断出"过渡生硬"却给学员布置无关的描写练习 | 练习生成与症候 ID 绑定 | `training_knowledge_base.dart` 按症候 ID × 等级匹配 | ✅ 已守护 |
| FT-08 | 评分空洞 | 只说"这段不好"而不指出哪句好、哪句坏、为什么 | 答案评分结构化 + 错误分析 | GenUI quiz 有 explain 字段；**诊断卡片缺：逐句标注** | ⚠️ 部分守护 |
| FT-09 | 过早推进 | 学员刚改对一个病句就推进到篇章结构 | 准备度门槛 + 掌握信号 | `teaching_state_machine` AWAITING_REFLECTION 门控 | ✅ 已守护 |
| FT-10 | 过度练习 | 给学员一次性布置 10 个同类型修改练习 | 练习阶梯 + 停止点指导 | 每次教学只推 1 个任务；`StyleTechniqueSuggestion` 最多 2 候选 | ✅ 已守护 |
| FT-13 | 状态不更新 | 学员修改后能力状态未更新，下一轮仍按旧状态诊断 | 学习任务循环 + 状态卡片 | `student_profile_compute.dart` 跨 session 加权更新 | ✅ 已守护 |
| FT-14 | 跳过目标澄清 | "我想提升写作"直接开始教议论文，不澄清是应试/创意/学术 | 目标澄清器 | **缺：写作目标澄清步骤**（当前默认诊断不问目标） | ❌ 缺口 |
| FT-15 | 过度目标追问 | 过度询问写作背景、用途、字数、受众才进入诊断 | 目标澄清器适配器 | — | ❌ 缺口（与 FT-14 对冲） |
| FT-16 | 巨型知识地图 | 给学员输出"从字词句段到篇章结构到文学批评"的完整体系 | 知识地图构建器 + 输出格式 | L2 索引只给 LLM"可诊断范围清单"不给学员 | ✅ 已守护 |
| FT-18 | 错误下一步 | 还没掌握句子通顺就教复杂长句修辞 | 学习路径选择器 | `skillLevel` 分层 + training_kb 按等级匹配 | ✅ 已守护 |
| FT-20 | 信号忽略 | 学员说"我没学过修辞"仍输出专业术语密集的诊断 | 触发矩阵 + 教学模式选择 | 三档态度（豆包/月笙如歌/sensei）适配 | ✅ 已守护 |
| FT-21 | 重复解释 | 学员没理解"过渡句"概念，系统重复同样定义 | 多轮协议 + 无状态恢复 | **缺：多轮去重机制** | ⚠️ 部分守护 |
| FT-22 | 越界输出 | 用户要"只给诊断不要修改建议"，系统仍输出完整改写 | 停止点 + 互动节奏 | diagnosis_validator 禁止整句替换；FT-22 关键词检测（`isDiagnosisOnlyRequest` + 10 个边界声明词）+ `_parseAndPersist` 跳过 teacher stream，避免越界输出修改建议 | ✅ 已守护（2026-08-27） |
| FT-23 | 过度压缩高级响应 | 高级学员请求压缩诊断，结果只给"结构有问题"无细节 | 标准/高级模式压缩 | sensei 档位面向老手；**缺：显式压缩协议** | ⚠️ 部分守护 |
| FT-24 | 协议泄漏 | 诊断报告中暴露"根据 diagnosis_engine_v2.json 规则..." | 无泄漏 + 学生面向协议 | GenUI/消息卡分派器对学员隐藏协议块标记 | ✅ 已守护 |
| FT-27 | 资源堆砌 | 只给"参考这 10 篇范文"不做任何分析 | 资源编排教学 | **缺：参考素材嵌入式分析** | ❌ 缺口 |
| FT-28 | 资源过度使用 | 简单病句修改也强制引用外部语法书 | 资源协议 | token_budget_guard 按优先级裁剪；**缺：场景级资源必要性判断** | ⚠️ 部分守护 |
| FT-29 | 虚假来源 | 虚构"根据《写作学概论》（不存在书目）" | 来源信任 | L2/L3 知识库是内嵌的，不引用外部书目 | ✅ 已守护 |
| FT-30 | 考试过度承诺 | "按这个模板写一定能得高分" | 考试轨道边界 | R-P01 禁止代写 + Prompt 约束 | ✅ 已守护 |
| FT-35 | 画像冗余 | 学员能力画像变成冗长聊天记录式输出 | 卡片紧凑性 | 五维坐标是数值不是文本；growth_page 雷达图可视化 | ✅ 已守护 |
| FT-36 | 无效可视化 | 为"过渡生硬"生成复杂思维导图，实际只需指出连接词缺失 | 可视化协议 | **缺：可视化必要性判断** | ⚠️ 部分守护 |
| FT-37 | 上下文丢失 | 提供历史诊断摘要后仍从零开始重新诊断 | 交接 + 状态卡片 | `teaching_state_repository` 持久化 + `chat_context_builder` 注入历史 | ✅ 已守护 |
| FT-40 | 安全边界 | 涉及学员个人隐私写作内容时的边界问题 | 护栏 | R-029 安全与隐私 + R-P03 学员主权 | ✅ 已守护 |
| **FT-41**（写作特有） | **选择偏差** | 互斥症候同命中时 LLM 选了低频那个（P017 而非 P003） | 互斥症候检测 + 频次先验 | `diagnosis_validator.dart` 有互斥症候 warning；**缺：频次先验加权** | ⚠️ 部分守护 |

> **缺口汇总**：40 条中 ✅ 已守护 17 条 / ⚠️ 部分守护 13 条 / ❌ 缺口 3 条（FT-14 目标澄清 / FT-15 过度追问 / FT-27 资源堆砌）。❌ 缺口 3 条是 X-041 看板需要重点监控的。

### §4.5 教学质量评分标准（借鉴 Universal Diagnostic Tutor Skill · 2026-08-27 调研）

> **来源**：同上项目的 `QUALITY_RUBRIC.md`。原 28 条维度，我们筛选出 12 条**核心维度**直接可用（✅），6 条需改语义后可用（⚠️），2 条不适用（❌ 数学格式/命令系统）。下表只列核心 12 条。
>
> **使用方式**：这 12 条是 X-041 数据飞轮看板的评分维度原型；每条 1-5 分制，用于量化诊断引擎的教学质量，而非仅看"有没有产出"。

| 维度 ID | 维度名称 | 1 分（最差） | 5 分（最好） | 我们当前的实现状态 |
|---|---|---|---|---|
| QR-01 | 领域诊断 | 无文体/题材定位 | 用领域诊断选择正确首步而不创建路线图 | ⚠️ 有症候分类但无显式文体判断（应试/创意/学术） |
| QR-02 | 知识缺口诊断 | 无缺口诊断 | 区分表面错误与深层缺口并基于学员证据更新 | ✅ L2/L3 症候表 + ParsedDiagnosis 结构化 |
| QR-03 | 下一步最佳教学步骤 | 全讲或全解 | 选择最小解锁步骤并在正确位置停止 | ⚠️ 有教学状态机但无"最小步骤"显式选择 |
| QR-04 | 认知负荷控制 | 压垮学员 | 按水平精确匹配术语、符号和练习量 | ✅ 三档态度 + skillLevel 分层 |
| QR-05 | 学生面向自然性 | 像清单/工具/政策文档 | 自然、简洁、响应学员措辞和语言 | ⚠️ diagnosis_card 有自然语言但 GenUI 偏机械 |
| QR-06 | 停止点纪律 | 尽管仅要提示仍给最终答案 | 在最高价值诊断点停止并等待 | ⚠️ 有 AWAITING_REFLECTION 但无"只诊断"显式指令响应 |
| QR-07 | 掌握信号解释 | 仅以正误为信号 | 保留正确部分、修复薄弱部分、基于证据选择下一步 | ⚠️ 有 masteryThreshold 但缺多证据要求 |
| QR-08 | 错误到干预匹配 | 每个错误都给完整解答 | 解释错误路径为何诱人并给针对性练习 | ✅ 症候→技法→训练任务三段绑定 |
| QR-13 | 无内部泄漏 | 提及内部协议/文件名 | 将内部路由转化为自然教师语言 | ✅ 消息卡分派器对学员隐藏协议块 |
| QR-14 | 上下文可移植性 | 假装记忆 | 产出/消费紧凑交接上下文，信任已知项 | ✅ teaching_state_repository + chat_context_builder |
| QR-23 | 概念掌握映射 | 解释后即假设掌握 | 状态轻量、按需可见、防止过早推进 | ⚠️ 五维画像有累积但缺"按维度掌握状态" |
| QR-27 | 练习循环与状态更新 | 在学员回答前求解 | 仅运行必要循环步骤，从最新证据调整下一练习 | ✅ training_evaluator + state_update 闭环 |

> **评分缺口**：12 条核心维度中 ✅ 已实现 6 条 / ⚠️ 部分实现 6 条 / ❌ 缺失 0 条。⚠️ 的 6 条是 X-041 看板要驱动的迭代方向。

### §4.6 设计哲学对照（他们 vs 我们）

> 来源：同上项目两份文档体现的 5 条设计哲学，与月笙现状逐条对照。

| # | 他们的哲学 | 我们是否有 | 差距与行动建议 |
|---|---|---|---|
| 1 | **先诊断后行动**（Diagnosis-First） | ✅ 有 | 闭环「问→写→**诊**→教→练→评」已体现。**差距**：缺"诊断质量本身"的度量（QR-01/02 的 1-5 分级），目前只有"做了诊断"无"诊断质量如何"。→ X-041 看板补全。 |
| 2 | **最小有效步骤**（Smallest Unlocking Step） | ⚠️ 部分 | 有教学状态机控制节奏，但缺"下一步最佳教学步骤"的显式选择机制（QR-03）。当前可能直接给全面修改建议而非最小介入。→ X-042 契约层迁移时补"最小步骤选择器"。 |
| 3 | **掌握必须有证据**（Evidence-Based Mastery） | ⚠️ 部分 | 有 masteryThreshold 连续 X 次 + reply_receipt。**差距**：缺多证据要求（解释+信心+近迁移），当前一次正确就推进。→ FT-06 假掌握修复方向。 |
| 4 | **停止是教学行为**（Stop Point Discipline） | ✅ 守护 | 有 AWAITING_REFLECTION 门控。**FT-22 已落地（2026-08-27）**：用户显式"只诊断不要修改"边界声明经 `isDiagnosisOnlyRequest` 检测后跳过 teacher stream 调用与 suggestion 落库；上下文不足时仍由 `token_budget_guard` 裁剪。剩余方向：上下文不足强行诊断场景的进一步细化。 |
| 5 | **输出即契约，内部不可见**（Protocol Integrity） | ✅ 有 | 消息卡分派器对学员隐藏协议块标记。**差距**：GenUI 偏机械，diagnosis_card 的自然语言程度待提升。→ QR-05 评分驱动。 |

### §4.7 酒馆类应用调研借鉴（2026-08-27 · 双 AI 交叉验证）

> **来源**：两份独立 AI 调研报告交叉验证，调研对象 SillyTavern / TavernAI 社区。以下只保留**两份报告一致认可或互补**的 ✅ 可借鉴条目，⚠️ 部分借鉴条目已合并去重。
>
> **使用方式**：以下借鉴条目按"Prompt 工程 → 知识库管理 → 记忆系统"三层分类，对应 X-040~X-042 批次及后续迭代。

#### 三方向核心可借鉴机制（合并去重版）

| # | 机制 | 酒馆做法 | 月笙对应物 | 借鉴价值 | 落地建议 |
|---|---|---|---|---|---|
| **T-01** | **Post-History Instructions（PHI）** | 最强约束指令放在聊天历史之后、模型回复之前，利用 LLM 尾部注意力偏好提升遵守率 | Constraints 段在四段式 System 位置（靠前） | ✅ **最高价值** | 将"必须输出 JSON"/"必须先诊断后教学"等核心约束从 System 段迁移到 PHI 等效位置（prompt 尾部）。**纯 Prompt 工程，零代码改动，见效快** |
| **T-02** | **Lorebook 关键词触发注入** | 知识库不是全量注入，而是按关键词扫描聊天历史→匹配后按优先级和预算注入 | L2 症候表 + L3 技法库全量注入 prompt | ✅ 高价值 | L2/L3 改为"按当前写作文本关键词触发 + 按优先级排序 + 设独立 token 预算（如总预算 15-20%）"。可大幅降低 prompt 冗余 |
| **T-03** | **预设分层覆盖** | 全局 Main Prompt → 角色卡 system_prompt 覆盖 → 场景预设覆盖，三层继承 | 单一 System Prompt + 三档态度硬编码 | ✅ 中价值 | 将三档态度从代码硬编码改为"可插拔 Persona 配置"（名称+描述+专属 system_prompt），支持未来用户自定义第四档 |
| **T-04** | **mes_example few-shot** | 角色卡用 `<START>` 分隔的好/坏对话示例教 LLM 如何说话 | 无对话示例机制 | ✅ 已落地（2026-08-27，首批 + 第二批 + 第三批共 13 个高频症候） | 在"教"环节引入 few-shot 示例块（好/坏写作片段对比），按症候类型动态组装。新建 `training_few_shot_library.dart` 独立模块，首批 5 个（P003/P004/P008/P011/P019）+ 第二批 5 个（P005/P006/P007/P009/P010）+ 第三批 3 个（P012 张力不足/P013 开篇平庸/P014 结尾乏力），共覆盖 13 个高频症候；`getTrainingFewShot` 在训练知识注入后追加，复用 `trainingKnowledge` 阶段标记（不新增 BudgetStage，零预算表改动） |
| **T-05** | **Summaryception 分层递归摘要** | L0-L4 五层递归（3合1），每层只记录 narrative delta，1000:1 压缩比，万轮对话仅 16k tokens | 无长程记忆压缩（跨 session 全量状态导出） | ✅ 高价值（长程） | 跨 session 状态传递借鉴分层压缩：L0 保留最近 3-5 轮诊断详情，L1-L2 压缩历史教学脉络，只传高层摘要 |
| **T-06** | **World Info 独立预算 + 优先级排序** | WI 有独立 token 预算（百分比或绝对值），预算耗尽时即使关键词匹配也不注入 | 知识库无独立预算 | ✅ 高价值 | L2/L3 设独立 token 预算，预算耗尽时按优先级截断而非全量保留。与 T-02 配合使用 |
| **T-07** | **为 Assistant 回复预留 token** | 预算公式 = `max_context − max_tokens`，显式为回复预留 | ✅ 已落地（2026-08-27） | ✅ 基础常识 | TokenEstimate 新增 `contextLimit=128000` + `reservedForReply=LlmConfig.chatMaxTokens(4096)` 两个常量；`maxBudget` 从硬编码 128000 改为公式 `contextLimit − reservedForReply` = 123904，为 Assistant 回复显式预留 token，防「上下文塞满 → 输出被截断 → JSON 字段缺失」故障。详见待办执行清单「T-07 token 预留公式化」条目 |
| **T-08** | **四级记忆作用域** | ST-Copilot：Global / Character / Chat / Session 四层 | 单一全局画像 | ✅ 中价值 | 引入分层画像：Global（学员基础五维画像）/ Skill-specific（某文体专项画像）/ Session（本次会话临时调整） |
| **T-09** | **数据导出/导入 + 零遥测** | 所有数据本地文件化，完整导出导入，无遥测，隐私靠架构（本地）而非加密 | SQLite 持久化，无导出 | ⚠️ 部分借鉴 | 增加"导出教学档案"功能（五维画像+历史诊断→加密 JSON），保留 SQLite 但增加便携格式 |
| **T-10** | **非破坏性 Ghost 模式** | 被裁剪的上下文对 LLM 隐藏但用户仍可见，可随时恢复 | 直接删除低优先级上下文 | ⚠️ 远期价值 | token_budget_guard 裁剪后保留原始数据在 DB/UI，标记"已对 LLM 隐藏"，支持用户回溯 |

#### 综合推荐（两份报告共识 + 我的判断）

两份 AI 报告的综合推荐不同但**不冲突**，可合并为一条路线：

| 报告 | 推荐 | 本质 |
|---|---|---|
| AI-1 | PHI + 分层 Prompt 注入架构 | **Prompt 工程层**改进 |
| AI-2 | 静态核心知识 + 结构化知识库 + 动态语义检索 三层记忆注入 | **知识库管理**改进 |

**我的判断**：两者可合并为一条"分层注入式 Prompt + 触发式知识库注入"的综合路线，分两步走：
1. **先做 T-01（PHI）** — 纯 Prompt 工程，零代码改动，直接命中"LLM 输出格式不合规"和"指令遵守率低"两个痛点。纳入 X-040 批次（与 Token Budget 提示注入一起做）。
2. **再做 T-02 + T-06（Lorebook 式触发注入）** — 需要 chat_context_builder 重构知识库注入逻辑，从全量注入改为关键词触发 + 优先级排序 + 独立预算。作为 X-040 完成后的独立批次 X-043。

> **月笙领先于酒馆的能力（无需借鉴，保持优势）**：① `student_profile_compute` 五维自动画像（酒馆无 AI 自动画像） ② `teaching_state_repository` SQLite 自动状态更新（酒馆无自动状态更新） ③ 教学状态机门控（酒馆无教学闭环） ④ L1 Skill 40 份原子化技能定义（酒馆角色卡粒度远粗于此）。

---

## §5 设计决策登记（2026-08-18 → 2026-08-26 新增 12 条）

> 本登记对应 R-018 变更溯源：每条决策 = 文档 → 代码 → 执行记录，完整可追溯。**只记录架构级/会影响全局模块协作的决策**，不记录 UI 细节补丁。

| 决策 ID | 日期 | 决策内容 | 选择方案 | 否决的替代方案 & 否决理由 | 执行记录 & 代码引用 |
|---|---|---|---|---|---|
| D-026 | 08-22 | **循环依赖零容忍入 CI**：宪法 §二.4 由"架构承诺"升级为"CI Gate3 强制闸" | X-033 批次：Python 脚本 + `check_cycles.sh` Dart 侧 3 层扫描（providers/services/widgets）+ pre-commit 双强制 | 否决方案 B（仅 pre-commit，CI 不查）：理由是团队中会有人绕过 pre-commit（`--no-verify`） | 脚本：`scripts/check_cycles.sh`；CI：`.github/workflows/flutter_ci.yml` Gate3 |
| D-027 | 08-22 | **dart format 基线 + CI 闸 0 强制**：宪法 §二.2 格式承诺入闸 | X-034 批次：先整库 dart format 一次性应用（基线 commit）→ 后续 CI gate0 + pre-commit 双强制 | 否决仅 CI 不基线：理由是"首次提交不做基线，后续老代码新代码混合 diff 无法审查" | 执行：待办执行清单 X-034 批次段 |
| D-028 | 08-23 | **覆盖率口径重写（方案 A）**：宪法 §二.5 原来"整库 70%"不可达 | 方案 A：T1 整库 65±2% 软门槛（warn，不 block）+ T2 核心文件（契约/解析/状态机/四宿主）85% 硬门槛（block）；远期 aspirational 目标写在文档不做强制 | 方案 B（锁历史基线，禁止下滑）：否决理由——每次 refactor 都会下滑，锁死就不能做重构了 | 文档：宪法草案 §二.5 重写段；X-035 批次 COV-ALIGN 执行记录 |
| D-029 | 08-25 | **依赖审计入 CI + D# 豁免机制**：宪法 §二.6 过期依赖的升级承诺入闸 | X-036 DEP-AUDIT 批次：`check_outdated.py`（UTF-8 BOM 兼容修复）+ CI Gate5 push/release 双模式；D4 锁版暂不升（需写豁免理由） | 否决"依赖一律升最新"：理由是 Dart 生态 breaking change 频繁，升级带来的 breakage 远高于过期 1 个小版本的风险 | CI：`.github/workflows/flutter_ci.yml` Gate5；脚本：`scripts/check_outdated.py` |
| D-030 | 08-22 | **写作界面 UI 审查对齐（P0-1 X-037）**：写作页家族 6 文件的颜色/动效/间距/交互全面审查 | C1（间距层级）+ H1（颜色 palette）+ H2（圆角）+ H4（动效）+ H3 迁移（令牌化前置） | 否决"全库一次 UI 大改"：理由是每批 ≤6 文件的风险控制——写作页家族先改，其他组件后续跟随 | 代码：6 文件编辑；台账：待办执行清单 X-037 P0-1 段 |
| D-031 | 08-24~25 | **LLM 稳定性：5 闸调用链（X-038 B1+B2）**：解决 LLM 偶发失败导致学员端全挂 | B1 多 Endpoint Fallback 降级链 + B2 指数退避 + 抖动重试；重试策略带 jitter 默认 ±250ms，测试注入 policy(jitterMs=0) 精确断言 | 否决"单 Endpoint + 前端提示刷新"：理由是把失败压力甩给用户，不是工程级解法 | 代码：[llm_fallback.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/services/llm_fallback.dart) / [llm_retry.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/services/llm_retry.dart)；测试 36 项 |
| D-032 | 08-25~26 | **全局 BR/EI 令牌化分 14 批（X-039 P0-2）**：788 处硬编码替换为 AppRadius/AppSpacing；AppTheme 扩展 6 个令牌 | P0-2 方案 A：令牌家族扩展（xl/xxs/xsm/smx/section/xxl）→ 79 文件按命中频次 + 功能域内聚切 14 批（每批 ≤6 组件）→ 非标准值近似替换（台账登记，不吞） | 否决"每档新增一个令牌"（令牌膨胀）：理由是 788 处覆盖 95%+ 只要补 6 个令牌，令牌家族数量可控；每值一令牌会让 palette 爆炸不可维护 | 令牌定义：[app_theme.dart](file:///D:/ai-teacher/yuesheng-flutter/lib/config/app_theme.dart#L85-L108)；已完成 Batch1+2（12 文件，~210 处）；台账：待办执行清单 P0-2 切片表 |
| D-033 | 08-23 | **工作目录从 D:\teacher 迁到 D:\ai-teacher**：路径统一，双仓迁移为单仓 monorepo | 方案 A：一次硬切，所有文档引用路径更新，`.git` 保留在新目录 | 否决"双目录长期共存"：理由是同一项目两个工作目录会导致文档与代码真实状态永远不一致 | 2026-08-23 舰长本机执行；AGENTS.md/待办执行清单路径均为 D:\ai-teacher |
| D-034 | 08-23 | **本地 17 个 backup 分支清理**：防止本地分支污染后续 checkout 决策 | 方案 B：先 `--merged main` 检查（17 个全部已合并）→ 再删除 | 否决"先保留以防万一"：理由是保留未命名的 backup_20260809_* 分支 = 制造隐性决策负债；Git 历史已经完整保留在 main 上了 | 台账：待办执行清单 X-032 CLEANUP 段落 |
| D-035 | 08-23 | **根目录 38 个临时文件清理（A/B/C 三类）**：模拟器截图/logcat/脚本输出 | 分类清理：A 类 32 个直接删 / B 类 5 个归档 historical-archive/ / C 类 C41 git 备份保留其余处置 | 否决"一把梭全删"：理由是 C41 `.git-broken-backup` 保留价值（万一 Git 损坏可恢复） | 台账：X-032 CLEANUP 清单已签核 |
| D-036 | 08-20 | **AI 自批条款声明为草稿（宪法 v0.2 流程补丁）**：防止"AI 自己审自己改的代码然后过审"的自证循环 | 方案 A：宪法头部加一行流程补丁声明——AI 自批一律视为草稿，需用户书面确认才生效 | 否决"直接删宪法条款"：理由是条款在后续工作流中有价值，但当前需明确"未生效"状态而非删除 | 文件：[yuesheng-flutter-宪法草案.md](file:///D:/ai-teacher/yuesheng-flutter/docs/yuesheng-flutter-宪法草案.md) 头部流程补丁 |
| D-037（本手册） | 08-26 | **产出模块意图 & 设计溯源手册**：让不接触舰长的人也能回答"模块为什么存在/数据流/设计来源"三个问题 | 方案 A（增量修订版）：基于 8-18 架构审查结构，补 §2 模块意图卡 15 张 + §3 数据流 + §4 知识库溯源 + §5 决策登记 + §7 待回填清单 | 否决方案 B（完全重写独立白皮书）：理由丢失历史决策链 & 需维护双份架构文档易漂移 | 你在读的这份文档 = 该决策的落地 |

---

## §6 Flutter / React 双端决策状态（截至 2026-08-26）

> 这是所有接手人第一问："为什么有两个端？我改哪个？" — 回答在这里。

| 维度 | Flutter 端（`D:\ai-teacher\yuesheng-flutter`） | Electron/React 端（`D:\ai-teacher\yuesheng-writing-coach`） |
|---|---|---|
| **真源状态** | **✓ 唯一代码真源**（所有业务在运行） | 维护模式：规则/文档/Prompt 仍在更新，代码不推进 |
| **开发状态** | 100% 活跃（所有新开发都在这） | 80% 规范沉淀 + 20% 资源（Prompt 在 resources/prompts/ 真源；resources/prompts/yuesheng-prompt-v4.0.0.md 为 Prompt 真源） |
| **技术栈** | Flutter 3.44 / Dart 3.12 / Riverpod 2.x / drift (SQLite ORM) / Dio | Electron + React 18 + TS strict + Zustand persist + better-sqlite3 / Knex + Vite + Vitest |
| **能力实现** | 诊断/教学/GenUI/四库/书架/成长面板 — 全部实现 | **未实现**：只有 typed IPC 通道、契约层规范、adapter 规范、HOTL 流程，没有实际业务代码 |
| **Prompt 同步** | Dart 侧 skill content 与 Prompt 文档可能有差异；以 Prompt 文档 v4.0.0 为权威，差异走审查流程补 | Prompt 文档的真实真源（v4.0.0 最新） |
| **未来迁移** | — | 未来如果要做桌面版 + 插件生态（DSH 移植），Electron/React 是预定主端；迁移路线按 8-18 架构审查 C2 结论：**只共享契约/协议，不共享语言级实现代码** |
| **当前所有开发操作** | 必在此目录执行；工作目录：`D:\ai-teacher\yuesheng-flutter` | 所有 AI 操作默认在此目录；只有写规则/Prompt 文档时才会改 yuesheng-writing-coach |

### 为什么 Flutter 是真源而不是 React？
> **技术栈决策（舰长 2026-08-26 确认）**：之前的 React Native 端经历过严重失败 — RN 版本长久未更新导致后续优化维护极为困难（RN 跨端版本碎片化、原生桥接层长期未修、升级一次成本高到近乎重写）。综合评估"Android 端持续开发的长期维护成本"、确定了 Flutter→未来 React 共享契约的迁移路线后，正式切为 Flutter 真源推进。

| 条目 | 代码/文档证据 | 状态 |
|---|---|---|
| 用户目标平台是 Android（移动优先） | 交接文档 §1「用户只做 Android 端」；Flutter 适合移动跨端；React/Electron 是桌面优先 | ✅ |
| Flutter 端 181+ 测试 / 1793 全绿（2026-08-18 基线） | 交接文档 §1.1 已验证 | ✅ |
| **从 RN 切换到 Flutter 的决策依据（舰长 2026-08-26 确认）**：前 RN 端因长期未更新陷入「优化维护困难」的技术债死锁 → 综合评估迁移路线后转 Flutter | 舰长确认原话：「之前的 RN 经历过严重失败，那个太久没更新导致我们后续优化维护困难，在综合考虑并且确定迁移路线后决定转为 flutter」 | ✅ |
| **未来切回 React 为真源的触发条件（默认推断·待船长二次确认）**：按 8-18 架构审查 C2 + 上表「未来迁移」栏推断，切换条件大概率是「产品明确要做桌面版 + 插件生态（DSH 移植）并立项排期」，只有移动场景时 Flutter 保持唯一真源，不触发切换 | 架构审查 C2；当前没有书面立项文档 → 先按默认推断写，若船长有不同标准可随时改本格 | ✅ 默认推断·可修改 |

---

## §7 灰区声明 & 粒度级回填清单

> 本节纪律：R-021 不私造业务语义。任何发生在代码之前的舰长个人产品判断，**如果没有舰长书面确认，文档一律显式标"[粒度留空·P2]"**，后来者不得自行补。舰长已确认的内容统一记入下方「舰长 2026-08-26 确认归档」区（单一真源，后续引用从这里走，不重复写）。

### 舰长 2026-08-26 确认归档（P0 级 4 项 + P1 级 1 项 · 全部已回填）

| 原编号 | 问题摘要 | 舰长确认原文 | 文档回填位置（file/section） |
|---|---|---|---|
| **P0-1** | 五维风格画像选型依据 | 「各种各样内容的蒸馏，常见的作者问题，常见的写作技巧，常见的写作问题」→ 维度本身是对三类蒸馏知识做正交化降维的产物 | §1.3 表格「五维风格画像选型依据」条 + §4.3 五维各行（粒度级理由标 P2 留空） |
| **P0-2** | 六步闭环为什么是这 6 步 | 「开篇，伏笔点题杂七杂八几乎都来源于"蒸馏"+"爬虫"」→ 6 步是把"常见作者问题→常见干预→常见见效路径"蒸馏压缩为最小正向闭环；并非某本教材流程 | §1.3 表格「六步闭环设计依据」条 + §0.3 六步闭环锚点说明 |
| **P0-3** | 症候表 & 10 条最高频来源 | 全库症候来源于「真实教学经验的知识蒸馏 + 全网公开写作资料/学员病例的爬虫整理」；P001~P037 ID 顺序=蒸馏时命中频次的降序（越高频越靠前） | §1.3 表格「L2/L3 症候表 & 技法表设计来源」条 + §4.2 症候表表头设计背景（粒度级每条症候来源标 P2 留空，建议按 Top10 优先） |
| **P0-4** | Flutter 为何是真源 / 未来切 React 条件 | 「之前的 RN 经历过严重失败，那个太久没更新导致我们后续优化维护困难，在综合考虑并且确定迁移路线后决定转为 flutter」→ RN 技术债死锁（长期未更新→优化维护困难→升级≈重写）。切 React 默认推断：明确要做桌面版 + DSH 插件生态立项时触发，只有移动需求不切 | §6「为什么 Flutter 是真源」区 2 行表格（切换条件行标「默认推断·可修改」） |
| **P1-4** | 三档态度设计初衷 | 「很多情况下因为需要面对的人群不同，用单一的 ai 语气很可能会降低体验感和学习效率，新手需要的是引导，老手需要的一语中的，新手看不得自己的文章被各种改，但是老手就是要这个。」→ 三档本质：「学员成熟度 × 反馈强度」二维映射；豆包（新手温和）< 月笙如歌（通用标准）< sensei（老手犀利）；安全词"轻一点"= 向豆包方向回退一档 | §1.3 表格「三档态度设计初衷」条 + skill_registry.dart 三档注释（后续 attitude_advisor.dart 改动均必须回查本条） |

> **当前阻塞状态**：P0 级 0 项未回填（全部已确认）。没有任何阻塞后续设计决策的灰区。

### P1 级（建议本月内填完，对特定模块改动有帮助）
| # | 问题 | 影响到什么决策 |
|---|---|---|
| P1-1 | L1 40 份 Skill **每份** 的具体来源是什么？（个人教学哲学口述 / 某本写作教材章节 / Prompt v1→v4 哪次迭代产物？） | 决定「哪些 Skill 属于哲学底线不能动」与「哪些 Skill 属于话术优化可迭代」 |
| P1-2 | 训练任务掌握阈值的**具体数值**（连续 X 次通过 / Y% 正确率 / Z 平均分）取值依据？是拍脑袋还是有真实学员数据校准？ | 调整难度曲线、改 masteryThreshold 常量前必须先填此条 |
| P1-3 | 参考资料库 REF-C1 为什么是 5 类分类？（不是 3 类或 8 类）分类依据是什么？ | 素材系统未来新增/合并分类前必须先填此条 |

### P2 级（粒度级细项 · 不填不影响当前工作，按需要逐补）
> 以下细项按"哪天改到那个模块/哪个症候，再顺手补一行"原则处理；**无需集中填**。

| # | 粒度问题 | 触发回填时机 |
|---|---|---|
| P2-1 | 五维画像**每个维度单独**的选型理由（为什么 sensory 独立一维而不是并入 tone_texture，等 5 条） | 哪天要新增/合并/改名某个维度时 |
| P2-2 | 37 条症候**逐条**的独立设计初衷 + 单独来源（P001~P037 逐行） | 哪天要新增/修改/退役某个症候 ID 前，先补 §4.2 症候表对应行 |
| P2-3 | 训练任务队列**单条任务**的设计初衷（每条任务为什么是这些步骤而不是别的） | 改 training_kb_content 某条任务内容前 |
| P2-4 | 掌握阈值 X/Y/Z **具体数值**的校准依据（P1-2 的数值粒度版） | 调整 masteryThreshold 常量时 |
| P2-5 | 三档态度 Skill **每份**的版本历史（v1→v2→v3→v4 哪次改了什么？为什么改？） | 调整 attitude 档位话术 / 新增第四档态度时 |
| P2-6 | 设计令牌选值为什么 xs=4 sm=8 md=12 lg=16 xl=24？是 2× 递增还是来源于某套设计规范？ | 要新增 AppSpacing/AppRadius 令牌时 |
| P2-7 | 宪法 §二 五闸的**具体数值**来源（覆盖率 65±2%？T2 85%？D# 四档分法？） | 调整 CI 数值口径时 |
| P2-8 | Style-Technique Router 4 条门控**每条**的具体设计理由（为什么是"画像未沉淀→空"，而不是"画像 1 session 就推荐"？） | 改旁路路由逻辑时 |
| P2-9 | **未来切回 React 的触发条件**（§6 默认推断）是否要修改为更具体的阈值？（比如「日活 X 千 + 明确 3 个桌面插件立项」） | React 端重启开发立项前 |

---

> **文档版本备注**：本手册 2026-08-26 第一版 = 8-18 架构审查（architecture-review-2026-08-18.md）的增量修订版。8-18 原文保留其 8-18 当时的判断，不做覆盖；本手册聚焦 8-18→8-26 之间发生的 12 条架构决策、新增的能力契约层、LLM 稳定性、令牌化重构等内容，并补上用户要求的「模块意图卡 / 知识库溯源 / 数据流时序 / 待回填清单」。

> **状态流转**：
> - 2026-08-26 16:00 → `draft-awaiting-captain-review`（第一版产出）
> - 2026-08-26 舰长回填 P0 4 项 + P1-4 后 → **`active`（当前状态）**。本手册即日起作为决策锚点文档。
> - 后续每次架构级决策、模块新增/退役/重构，先改本手册对应章节，再改代码（R-017 文档同步）。

> **登记同步**：本手册已在 [待办执行清单.md](file:///D:/ai-teacher/yuesheng-flutter/docs/待办执行清单.md#L18-L33) 「决策锚点文档索引」段登记为第一优先级文档，新对话/新人接手时从此入口进入。
