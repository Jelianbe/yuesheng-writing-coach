# ADR-C93 世界观设定层判据（批次 E1-b）

- 状态：**已接受（Accepted）· 已冻结**——舰长 2026-09-12 裁定「接受推荐」，
  四项议题全部定案（见 §五「裁定记录」）
- 日期：2026-09-12
- 决策者：主 Agent 提出 → 舰长裁定
- 关联：`docs/designs/2026-09-12-manuscript-level-growth-plan.md`（批次 E1-b 定义）／
  ADR-C78（`character_fact` 实体化 + F05 幽灵治理）／ADR-C90（单一真源）／ADR-C91（新增表范式）
- 前置：**批次 E1-a 已交付**（commit `dc3a93ca`）——`world_fact` 表 + `WorldFactRepository`
  + stale 治理，schemaVersion 30→31

---

## 一、背景

### 1.1 方案对 E1-b 的原始要求（两条硬约束）

`manuscript-level-growth-plan.md` §E1 写死：

> - **本批次不得直接复用 F05 判据**，需独立设计（**建议另立 ADR**）
> - `conflict_detector.dart:211` 是**判据唯一入口纪律** → 新判据必须在那里实现，
>   **不得在调用点分叉**

方案给出的理由：世界观是**规则**，不是事实。F05 判据是「同属性不同值 → 时序矛盾」
（`conflict_detector.dart:53-59`），它对**个体**成立（一个人不能同时是「独生子」和「有妹妹」），
但规则**天然带例外**——「灵气稀薄」+「此地有灵脉」不是矛盾，是世界观的层次感。

### 1.2 事实基线（本轮实测，含方案未记录项）

| # | 事实 | 位置 | 含义 |
|---|---|---|---|
| F1 | `world_fact` 表已存在 | `tables.dart`（`WorldFacts`，编号 22） | 断言数组同构 `character_fact`，**chapter 锚定** |
| F2 | `WorldFactRepository` 已存在 | `lib/data/repositories/world_fact_repository.dart` | upsert / list / get / parse 齐备 |
| **F3** | **`upsertWorld` 在 `lib/` 下零调用** | 全仓 grep；仅 `test/` 引用 | **表恒空——不存在生产写入路径** |
| F4 | character 侧写入链完整 | `diagnosis_committer.dart:774` → `upsertCharacter` | 诊断提交即写库，世界观无对应分支 |
| **F5** | **断言无 `pending` 态** | `character_types.dart:26`：「无 pending，存量断言默认 confirmed」 | **AI 抽取一经写入即参与检测，零缓冲** | ⚠️ 已修订（⚠️ 已被 2026-09-16 设定资料库第一批修订（pending 四态），见 `docs/designs/2026-09-16-setting-library-first-batch.md` §1）
| **F6** | **「世界观膨胀」已属 P004** | `syndrome_registry.dart:228`（信息倾泻症含原 P001 子类型） | 它早已是**文本层**症候，非待建设定层信号 |
| F7 | F05 已内置免责句式 | `chat_context_builder.dart:446`：「若这些矛盾**确属**事实性错误（而非角色刻意隐瞒或剧情转折）」 | 系统已承认「机械定位 + AI 复核」两段式姿态 |

### 1.3 本轮暴露的三个问题（方案未覆盖）

**问题 1：判据没有数据源（F3）。**
`upsertWorld` 零调用 ⇒ 判据写出来也只能检测一个**恒空的表**。E1-b 若只定义判据，
交付的是「一段永不执行的代码」。写入路径属于 E1-b 的必要组成部分，方案未列。

**问题 2：「设定层」的口径在方案内部不自洽。**
方案 §3.4 把设定层定义为「**还没写出来的**设计」；但 E1-a 建成的表是 **chapter 锚定**的
（F1），记的是「**已经写进正文的**设定」。二者不是同一批数据：

| 口径 | 断言来源 | `chapter` | 可诊断的问题 | 需要的新能力 |
|---|---|---|---|---|
| **I. 文本层·设定维度** | 正文抽取（同角色管线） | 非空 | 「灵气前后不一致」 | 仅判据 |
| **II. 设计层·待落地清单** | 对话中用户口述 / 手动录入 | `null` | 「设计 12 条只落地 2 条」 | **对话侧写入路径（新工程）** |
| III. 双层 | 两者都记 | 混合 | 两者 | 全部 |

E1-a 实际建成的是 **I 的数据结构**（chapter 锚定 + 章节级 stale 治理）。
II 需要一条**目前不存在的写入时机**（AI 在对话中判断「用户正在设计设定」→ 落库），
属于独立决策面。

**问题 3：误报风险点未被识别。**
方案只论证「F05 会误报」，未给出**防误报机制**。而 F5 说明现状是「零缓冲」——
世界观条款是**命题式陈述**（「灵气稀薄」），比人物属性（「独生子」）更易被 AI 从
氛围描写中误抽，且同一命题可被多章以不同措辞重复抽取。若不设门槛，
「幽灵事实」事故（`fact_stale_service.dart:4-7` 记录）会以新形态复发。

---

## 二、决策

### D1【口径】本批做口径 I（文本层·设定维度），口径 II 另案

- **做**：从正文抽取的设定断言（chapter 锚定），诊断「同一设定主题内取值前后不一致」。
- **不做**：设计态（chapter 为 null）的「设计→落地率」统计。它需要新的写入时机与
  统计口径，与本批的判据问题不同源。

**理由**：E1-a 的表结构、stale 治理、抽取管线全部指向口径 I；边际成本是「一个纯函数
+ 一条写入分支」。口径 II 的难点在「何时写库」（写入时机策略），不是判据，混入本批
会让一个可独立测试的问题耦合上未定义的策略问题。

**代价（明说）**：陷阱表四条（设定膨胀 / 为奇而奇 / 只建不拆 / 替代写作，
`skills_beginner_p7.dart:112-119`）**不是**本批能检出的——它们是**活动元信号**
（关于设计活动本身的度量），不是内容矛盾。且其中「世界观膨胀」已属 P004（F6）。
本批不宣称覆盖它们。

### D2【写入】新增诊断协议分支，与 character 侧同构

```
AI 诊断输出 → world_assertions 字段（新增）
  → fact_validator 世界观 schema 分支（新增，现有三类：人物/事件/支线）
  → diagnosis_committer._commitWorldFacts（新增，对齐 :774 的 _commitCharacterFacts）
  → world_fact 表（E1-a 已就绪）
```

**前置依赖（必须显式确认）**：诊断协议新增字段会触及 `skill_prompt_anchor.json`
锚点快照 → 依项目纪律，**锚点变更须舰长显式确认**。

**降级路径（若不批协议变更）**：判据先行（D3–D5 全部是纯函数，可用测试数据独立验证），
写入路径由 **E3 设定 Tab 的手动录入**（依赖批次 B）承担。此路径与批次 A 同型——
「读路径/判据先行，消费者后到」，不产生无消费者代码（判据有单测即消费者）。

### D3【判据】`detectWorldConflicts` —— 同（设定主题, 属性）分组的值冲突

新增函数与 `detectCharacterConflicts` **并列**，不改造后者：

- **分组键**：`(worldName, attribute)`——`worldName` 即 `world_fact.name`（设定主题名，
  如「灵气体系」），它天然承担**作用域**角色：不同主题之间**不做比较**（跨主题差异
  = 层次，不是矛盾）
- **过滤**：`isActiveAssertion`（**判据复用，与 F05 同一处定义**，`conflict_detector.dart:211`）
- **排序**：复用 `_byTimeAsc`（章节 → 时间戳）
- **命中**：去重后 ≥2 个不同 value → 观察项（取最早两个不同值）
- **输出**：稳定排序，便于测试与上下文注入

**与 F05 的差异（必须逐条落实）**：

| 维度 | F05 / `detectCharacterConflicts` | `detectWorldConflicts` |
|---|---|---|
| 挂载 | F05 → P018 人设崩塌症补充 | **不挂 P 编号**（E2 已定，防锚点快照连动） |
| 输出类型 | `ConflictObservation`（`characterName`） | **新建** `WorldConflictObservation`（`themeName`） |
| 措辞 | 「矛盾」 | 「**设定不一致**」 |
| 去向 | 诊断上下文 | AI 上下文 + 设定 Tab（批次 C），**不进诊断面板** |
| 计数 | 计入症候 | **不计数** |

**共用与不共用的边界**：判据**骨架共用**（抽私有 `_groupActive` /
`_earliestTwoDistinct`，消除逻辑双实现——项目纪律，`syndrome_recurrence.dart:1-7` 记得
同款动机），**输出类型各自独立**。理由：`ConflictObservation` 的类型自述是
「F05/P018 补充输入」（`conflict_detector.dart:19`），是 F05 专属载体；复用它会让
世界观调用方复用到「人物属性」的字段名与措辞。这与 E1-a 复用 `CharacterAssertion`
的取舍不同——后者自述是「通用 TKG 时间维度节点」（`character_types.dart:9-12`）。

**两级入口（对齐 C78 既有结构；实施期侦察补充）**：C78 批次2b 已立下「调用方不得
自行组合判据」的纪律——`character_identity.dart:73-79` 明写「对外**只暴露本函数**，
不允许调用方自行组合 groupByIdentity + detectCharacterConflicts」。世界观同款分两级：

| 级 | 落点 | 职责 | 是否碰 IO |
|---|---|---|---|
| **纯判据** | `conflict_detector.dart` | `detectWorldConflicts(List<WorldFactInput>)` | **否**——保持该文件「纯函数、无 IO，便于单测」的既定定位（文件头自述） |
| **适配入口** | **新建** `lib/services/world_setting.dart` | `detectConflictsForWorlds(List<WorldFact>)`：解析断言 JSON → 调纯判据 | 是（须 import `database.dart`） |

**为什么不把适配入口也塞进 `conflict_detector.dart`**：那会让该文件 import
`data/database/database.dart`，破坏其纯函数定位。
**为什么适配入口不放在调用方**：违反 C78 的「不得自行组合」纪律——漏掉「解析断言」
或「`evidence` 门槛」任一环都会**静默降级**（不报错，只是永不产出）。

**摘录不往返正文（与 character 侧的刻意差异）**：`CharacterAssertion.evidence` 的
定义就是「正文原文摘录（非转述、非概括）」（`character_types.dart:32-33`），且 D4①
已把它设为硬门槛 ⇒ 观察项**必然带原文**。故世界观侧**不需要** `findKeywordExcerpt`
反查正文那一步（character 侧因历史原因保留 `fillConflictExcerpts`，
`character_identity.dart:81-99` 记录了它的既有缺陷）。这条是 D4① 的额外红利：
门槛机制同时充当了摘录来源。

### D4【防线】三层误报防线，第一条是硬门槛

**① 硬门槛：无原文摘录（`evidence` 为空）的断言不参与检测。**

这是**项目内生**的判据，不是新概念：`CharacterAssertion.evidence` 的定义就是
「**正文原文摘录（非转述、非概括）**，供用户核对依据」（`character_types.dart:32-33`），
且 F05 的注入本就带 excerpt（O11 机制，`chat_context_builder.dart:421-424`）。
它直接消灭「AI 凭空概括」这一类误报，且**机械可测**（断言字段为空即跳过）。

**② `stale` 排除**：白拿 E1-a（章节被删/被改写 → 断言失效 → 不参与检测）。
与 F05 同款防线，`isActiveAssertion` 已覆盖。

**③ 同章豁免**：两条断言的 `chapter` 相同 → **不报**。同一章内的两种措辞不是
时序矛盾（可能是同段落的两种表述），F05 的时间维度语义在此不成立。

**被否的防线**：见 §三。

### D5【输出】沿用「机械定位 + AI 复核」两段式

新增 `buildWorldSettingObservationsContext`（与 `buildConflictObservationsContext`
并列，措辞必须区别于人物侧），沿用既有免责句式姿态：

> 「以下是设定条目内前后取值不一致的记录。若确属**规则与例外**（同一主题在不同范围
> 或时期下的层次），请忽略；若确属设定漂移，请温和提示学员（只定位，不代改正文）。」

**不产出症候、不进诊断面板、不参与严重度统计**。

### D6【延后】`scope` 维度作为 II 期增强

若 D4 上线后实测仍有误报（典型：抽取层把「全域规则」与「局部例外」归入同一
`world_fact.name`），再评估给断言加 `scope` 字段。**本期不做**——在抽取质量未经
验证前，`scope` 只是把「谁对」的判定从判据层转移到抽取层，不减少误报总量，
却先付一次共用类型的改动成本。

---

## 三、被否方案

| 方案 | 否决理由 |
|---|---|
| **直接复用 F05 判据** | 规则天然带例外，会产出「幽灵矛盾」（方案 §6 已列，本 ADR 补充：与 F5 的零缓冲叠加后，误报会直接进用户视野） |
| **词表豁免**（value 含「但／例外／唯独／仅」→ 不报） | 魔法字符串：脆弱、不可枚举、不可测试，且无法覆盖「同一主题内两种表述」的全部形态 |
| **给 `CharacterAssertion.status` 加 `pending`** | 会动摇 C78 D-2 的既定语义（`character_types.dart:26` 明写「枚举仅 confirmed / rejected」），在共用类型上引入世界观专属状态；D4① 用 `evidence` 已达成同效且零类型改动 |
| **本期加 `scope` 字段** | 见 D6——先付成本不减少总量 |
| **进 P 编号（如 P042）** | E2 已定：会拖动 `syndrome_registry` + `syndrome_kb_content_manual_*` + `r019_baseline` + `skill_prompt_anchor` 四处，且语义混编（文本层 vs 设定层） |
| **复用 `ConflictObservation` 类型** | 字段名 `characterName` 与其类型自述（F05 专属）会误导世界观调用方；骨架共用已消除逻辑双实现，DTO 独立不构成双实现 |
| **判据放在新建文件** | 违反方案 §E1 的「判据唯一入口纪律」（`conflict_detector.dart`）；该文件扩至约 190 行，未触 R-019 文件/函数限 |

---

## 四、验证（DoD）

1. **负向·隔离**：世界观断言**不产出** `ConflictObservation`；即使同名同属性不同值，
   也不进 F05 通道（E1-a 已有雏形测试，本批扩为「判据层隔离」断言）
2. **正向**：同 `(name, attribute)`、不同 value、均带 `evidence` → 产出 1 条
   `WorldConflictObservation`
3. **层次不误报**：不同 `name` 同 `attribute` → 不产出；同 `name` 不同 `attribute` → 不产出
4. **同章豁免**：两条断言 `chapter` 相同 → 不产出
5. **无摘录豁免**：`evidence` 为空 → 不产出
6. **stale 排除**：删除该章 → 断言标 stale → 不产出
7. **回归**：`detectCharacterConflicts` 行为零变化（既有 F05 全量测试全绿）
8. **门禁**：`dart analyze` 零问题 / R-027 门禁全绿 / R-019 基线零回归

---

## 五、裁定记录（**已全部定案 · 冻结**）

舰长 2026-09-12 裁定：「**接受推荐**」——下表四项全部按主 Agent 推荐定案。
本节已冻结：后续轮次**不得在此重开讨论**（确需推翻须另立 ADR 并说明新证据）。

| # | 议题 | **裁定** | 定案依据（推荐理由原文） |
|---|---|---|---|
| **Q1** | 口径：I 文本层 / II 设计态 / III 双层 | **I（文本层·设定维度）** | E1-a 的表结构已指向 I；II 的难点是「写入时机」策略而非判据，混入会让可独立测试的问题耦合未定义策略 |
| **Q2** | 是否批准诊断协议新增 `world_assertions` | **批准，分两步**：先合判据（E1-b-1/-2），再接协议（E1-b-3） | 判据有单测即为消费者，不产生无消费者代码；锚点变更独立成一次可回滚的动作 |
| **Q3** | 误报硬门槛：`evidence` 非空 / `pending` 状态 | **`evidence` 非空** | 零类型改动、项目内生概念（O11 同源）、机械可测；`pending` 会动 C78 已冻结的 status 值域 |
| **Q4** | 观察项本期是否用户可见 | **否——只进 AI 上下文** | 判据未经实测，先让 AI 复核兜底；可见化等误报率数据出来后再开，避免把未验证信号直接推到用户面前 |

**Q2 的「分两步」不解除锚点纪律**：E1-b-3 实施时仍须先呈报
`skill_prompt_anchor.json` 的具体 diff，由舰长确认后方可落盘。

---

## 六、实施顺序（**已冻结**）

```
E1-b-1  判据       conflict_detector.dart: WorldConflictObservation + WorldFactInput
                   + detectWorldConflicts（骨架共用 _groupActive / _earliestTwoDistinct）
                                                          ← 纯函数，可独立交付
E1-b-2a 适配入口   world_setting.dart（新建）: detectConflictsForWorlds  ← 依赖 b-1
E1-b-2b 注入文本   chat_context_builder.dart:
                   buildWorldSettingObservationsContext                  ← 纯函数，可独立单测
─────────────── 以下需舰长先确认 skill_prompt_anchor.json 的 diff ───────────────
E1-b-3  写入链     world_assertions 协议 + fact_validator 分支 + committer 分支
E1-b-2c 接线       message_injector._injectWorldSettingObservation
                   + MessageInjector 增 worldFactRepo + providers 装配
                   （**与 b-3 同批**：表恒空时接线零行为、无法验证；
                     且牵动 DI 装配，单独做只增一次无谓的改动面）
```

施工序：`A ✅ → E1-a ✅ →` **`E1-b-1 → E1-b-2a → E1-b-2b`** `→ 【锚点确认】→`
**`E1-b-3 + E1-b-2c`** `→ B（含 E3）→ C → D`
