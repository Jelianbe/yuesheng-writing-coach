# ADR-C97 · 会话粒度（书籍级 vs 章节级）：**前提订正 + 零 schema 裁定**

- **状态**：Accepted（2026-09-18，舰长总授权「**全盘接受你的推荐方案，直接按推荐实施即可，无需再逐一确认**」）
- **类型**：会话生命周期 / 诊断聚合（核心模块，按 `AGENTS.md §7` 先 ADR 后动手）
- **来源**：`DECISIONS §2 Q4`（「授权：走 ADR 先行」）· `.ai/reports/2026-09-17-module-gap-audit.md:90`（G2）
  · `.ai/reports/2026-09-17-方案与排期.md:45`（N5 登记）/ `:83`（批 4 ADR 先行）
- **关联**：**`ADR-C81`（章节会话懒创建）· `ADR-C71`（跨会话教学状态延续）** —— 两者均**先于**本 ADR 且**直接约束**本议题
- **影响模块**：`lib/data/repositories/session_repository.dart` · `lib/services/manuscript_scope.dart`
  · `lib/data/repositories/diagnosis_repository.dart` · `lib/services/chat_service.dart`
  · `lib/services/message_injector.dart`
- **结论先行**：**N5 的登记前提「动 schema + 迁移」不成立。** 三项登记内容中
  **① 诊断聚合已交付**、**② 跨章 phase 断裂经 `ADR-C71` 显式裁定为有意设计**、
  **③ 剩余只是死代码与一项产品决策** ⇒ **本 ADR 裁定：不动 schema。**

---

## 1. 登记前提（原文照录，便于对账）

| 出处 | 原文 |
|:--|:--|
| `module-gap-audit.md:90` | G2 \| **会话按书籍隔离（IA 决策 1 根治）** \| 遗骸 `getOrCreateSessionForManuscript` 在，实际章节级 \| 补决策：改书级 vs 维持章节级（涉及 session 迁移 + **诊断聚合** + **设定↔诊断联动修复**），**动 schema，须 ADR** |
| `方案与排期.md:45` | N5 \| **会话按书籍隔离** \| 内部 G2 + 外部 \| ✅ **真（结构项）** \| ① 跨章教练上下文断裂是真实痛点；② 外部 AI 记忆全作品级（Sudowrite Story Bible）；③ **动 schema + 迁移，须 ADR + 裁定** \| **P1** \| 批4（ADR 先行） |
| `external-module-benchmark.md:114` | G2 … 章节级隔离是**我们的独创**且导致**跨章教练上下文断裂** \| **外部强烈支持落地 G2** |

⇒ 登记把它描述为**一次性结构改造**：`schema 迁移` + `诊断聚合` + `设定↔诊断联动修复` 三项打包。

---

## 2. ★ 前提订正（三项实测，全部推翻了「未做」的隐含前提）

### 2.1 订正一：**「诊断聚合」已经交付，且已投产** —— 并非待做项

`module-gap-audit.md:90` 把「诊断聚合」列为**待做**。实测**已存在**：

| 能力 | `file:line` | 状态 |
|:--|:--|:--|
| 书籍级会话集合（三源并集） | `lib/services/manuscript_scope.dart:23` `collectManuscriptSessionIds` | **已抽出、有动机注释**（`:1-16` 明写「为消除同语义双实现」） |
| 本书全部诊断 | `diagnosis_repository.dart:442` `listDiagnosesForManuscript` | 已实现 |
| **本书跨会话活跃症候聚合** | `diagnosis_repository.dart:460` `listActiveProblemsForManuscript` | **已实现且已投产** |
| 本书症候复发聚合 | `diagnosis_repository.dart:483` `getSyndromeRecurrencesForManuscript` | 已实现 |
| **消费方** | `lib/providers/manuscript_growth_provider.dart:63` | **成长页在调** |

`manuscript_scope.dart:1-16` 的抽出动机更是直接写明：「书籍级诊断聚合（`DiagnosisRepository`）同样需要它——
若不抽出而各自实现一遍，就会出现『相关对话 Tab 显示 3 条、成长统计只算 1 条』的**同语义双实现**」。

⇒ **「聚合读路径」不只是存在，而是已被当作「共享单一真源」刻意建设过。**
登记写的「诊断聚合（待做）」**与代码不符**。

### 2.2 订正二：**「跨章教学状态断裂」是 `ADR-C71` 的有意裁定，不是缺陷**

`ADR-C71`（2026-09-04，**Accepted，舰长授权**）§2 裁定表原文：

| 项 | 裁决 | 理由（原文节选） |
|:--|:--|:--|
| `beginnerLevel` | **新建会话时继承全库最新非空值** | 它是用户级学习属性 |
| `currentPhase` / `currentSubphase` / `attitudeLevel` | **不继承，维持 P0 起步** | 「阶段是**『这段教练关系』的属性**；新对话回到 P0（建立投入）本就是现有语义且被锚点/测试固化。**继承 phase 反而会把稿件 A 的 P3 带进与稿件 B 无关的新对话**」 |

且 `ADR-C71 §6 后续` 明确预留：「**P 线阶段跨会话延续（视真实使用数据）**」。

⇒ 登记写的「跨章教练上下文断裂是**真实痛点**」，在 `ADR-C71` 的口径下是**已被裁过的取舍**：
**「不继承」是选择，不是疏漏**，且其**必要性的举证责任在「真实使用数据」**（`ADR-C71 §6`）。

### 2.3 订正三：**`getOrCreateSessionForManuscript` 确为死代码**（登记此项属实）

| 事实 | 证据 |
|:--|:--|
| 定义 | `session_repository.dart:110-176`（67 行） |
| `lib` 内生产调用 | **0 处**（全仓仅命中定义处 + `manuscript_scope.dart:15` 的注释 + `test/`） |
| 生产实际入口 | `getOrCreateSessionForChapter`（`:183`）· 2 处调用（`writing_coach_panel_teaching.dart:112` · `writing_coach_panel_chat_runner.dart:43`） |
| 既有裁定 | `ADR-C81 §3.4`：「**不动** `getOrCreateSessionForManuscript`（lib 内无生产调用点，仅 test；懒创建语义天然覆盖——若未来接线，按同一时机纪律）」 |

⇒ 登记属实，但**`ADR-C81` 已裁定过它的处置**（不动），且理由与今日实测一致。

### 2.4 订正小结

| 登记项 | 登记口径 | 实测 |
|:--|:--|:--|
| ① 诊断聚合 | 待做 | ✅ **已交付且已投产**（§2.1） |
| ② 跨章上下文断裂 | 「真实痛点」⇒ 支持改书级 | ⚠️ **`ADR-C71` 已裁为有意设计**；改书级需先推翻该裁定（§2.2） |
| ③ 设定↔诊断联动修复 | 待做 | 🔶 **门控机制存在且是单点**（§3.2），但**当前不构成缺陷** |
| ④ `getOrCreateSessionForManuscript` 死代码 | 属实 | ✅ 属实，且 `ADR-C81` 已裁定「不动」（§2.3） |
| ⑤ **动 schema** | 必须 | ❌ **前提不成立**（§4 推荐零 schema） |

---

## 3. 真实剩余（逐项带 `file:line`）

### 3.1 写侧：会话仍是**章级**（事实，非缺陷）

| 事实 | `file:line` |
|:--|:--|
| `sessions` 表同时有 `manuscriptId` / `chapterId` 两个**可空** FK（`ON DELETE SET NULL`） | `tables.dart:93-118` |
| `session_reference.refType ∈ {manuscript, chapter, file}`，`UNIQUE(sessionId, refType, refId)` | `tables.dart:313-335` |
| 生产创建路径 = **章级** | `session_repository.dart:183` `getOrCreateSessionForChapter` |
| 索引：有 `idx_sessions_manuscript` | `database.dart:104` |
| 索引：**无** `chapter_id` 索引 | `findSessionForChapter`（`:196`）按 `chapter_id` 查 ⇒ 当前为**全表扫** |

**★ 但「无 `chapter_id` 索引」不构成待修项**：`sessions` 行数量级 = 用户的会话条数（十~百级），
全表扫代价可忽略；而加索引需走 `onUpgrade` ⇒ **bump `schemaVersion`** ⇒ 与 §4 的「零 schema」目标直接冲突。**收益 < 代价，不做。**

### 3.2 设定↔诊断联动的**单点门控**（改造风险面，不是当前缺陷）

`lib/services/message_injector.dart` 的 `refType` 门控：

| 形态 | 处数 | 行号 |
|:--|:--:|:--|
| `primaryRef?.refType != 'chapter'` ⇒ **提前 return** | **16** | `:961` `:1009` `:1029` `:1112` `:1147` `:1193` `:1236` `:1275` `:1322` `:1348` `:1395` `:1429` `:1481` `:1544` `:1567`（+ `:1092` 为 `== 'chapter'` 分支） |
| 其它文件 | 3 | `diagnosis_committer.dart:580` `:691` · `diagnosis_flow_handler.dart:911` |

**★ 这是本 ADR 最重要的风险登记**：所有 `_inject*` 系列注入（含设定库事实协议）
**以「主引用是 chapter」为前置**。若把会话主引用改成 `manuscript`，
**这 19 处会全部静默失效**（`return`，不报错、不抛异常、不留痕）——
即「设定↔诊断联动」会在无任何报警的情况下**整体断链**。

⇒ 登记里写的「设定↔诊断联动**修复**」，真相是：**它现在是通的，改动它才是风险来源**。

### 3.3 教学链路仍按 session 查询（这是 §4 唯一真正的产品决策点）

| 消费点 | `file:line` |
|:--|:--|
| 主对话组装 | `chat_service.dart:957` `listActiveProblems(sessionId)` |
| 上下文注入 | `message_injector.dart:465` `listActiveProblems(sessionId)` · `:701` `getLatestDiagnosis(sessionId)` |
| 诊断提交 | `diagnosis_committer.dart:291` `:430` |
| 教学状态（session 一对一，`UNIQUE(session_id)`） | `chat_service.dart:255/339/716` · `teaching_state_repository.dart:140` |

⇒ 用户可感知的行为：**在 ch1 诊断出的症候，切到 ch2 后教练不再提起**。
`ADR-C71 §2` 已就同类问题（phase）裁定「不继承」，**理由是同一条**（避免把 A 稿的状态带进 B 稿）。

---

## 4. 方案选项与推荐

| 方案 | 内容 | schema | 风险 | 判定 |
|:--|:--|:--:|:--|:--|
| **A** | **零 schema 变更**：维持章级会话；`getOrCreateSessionForManuscript` 按 `ADR-C81` 处置；教学链路是否跨章聚合**另立产品决策** | **无** | 低 | ✅ **采纳** |
| B | 改书级会话（`sessions` 去 `chapter_id` 语义） | **须 bump + 迁移** | **极高** | ❌ **否决**（见下） |
| C | 教学链路读侧接 `listActiveProblemsForManuscript` | 无 | 中（**改动教学行为**） | 🔶 **登记待裁**（需产品证据，见 §5） |

### 4.1 为什么否决 B（这是本 ADR 的核心理由）

1. **须推翻 `ADR-C71 §2` 与 `ADR-C81 §3.4` 两条既有舰长裁定** —— B 的直接后果是
   「A 稿的 P3 阶段 / A 章的活跃症候进入 B 章的对话」，正是 `ADR-C71` 明确拒绝的场景。
2. **须 bump `schemaVersion`（现 39）** ⇒ 触发 `onUpgrade` 迁移链 ⇒ 触发 `_preMigrateBackup`
   ⇒ 触碰 `DECISIONS §2 X3`「`schemaVersion` 钉值」既有裁定。
3. **触发 §3.2 的 19 处静默失效面** ⇒ 「设定↔诊断联动」整体断链且**无报警**。
4. **收益未举证**：`ADR-C71 §6` 已把「跨会话阶段延续」的举证条件写为
   「**视真实使用数据**」—— 该数据**至今不存在**（无用户反馈样本）。
5. **读侧能力已具备**（§2.1）：即便将来要跨章叙事，**也不需要改 schema** ——
   `manuscript_scope` + 三个 `*ForManuscript` 已在，B 的结构改造是**冗余的**。

### 4.2 为什么 A 足够

- 登记的三项中 ① 已交付、② 已裁定、③ 只需登记 ⇒ **无「必须动 schema」的残余**。
- **零 schema ⇒ 零迁移 ⇒ 零 `_preMigrateBackup` ⇒ 不触碰 `X3` 裁定 ⇒ 回滚成本 0**。
- 判据同 `ADR-C96` 与 `N3` 设计稿的同一原则：**在有更便宜的实现路径能满足同一目标时，
  不为了「看起来更规范」去动 schema。**

---

## 5. 裁定

| # | 事项 | 裁定 |
|:--|:--|:--|
| **R1** | 是否动 schema（书级会话改造） | **不动。** 维持章级会话，`ADR-C71 §2` / `ADR-C81 §3.4` 两条既有裁定**继续有效** |
| **R2** | `getOrCreateSessionForManuscript`（死代码） | **维持「不动」**（`ADR-C81 §3.4` 原文）。不删（它记录了 manuscript 级会话的语义与时机纪律）、不接线（无需求） |
| **R3** | 「诊断聚合」登记项 | **就地关闭** —— 实测已交付（`manuscript_scope.dart` + 3 方法 + 成长页投产） |
| **R4** | 「设定↔诊断联动修复」登记项 | **就地关闭** —— 当前**无缺陷**；19 处 `refType` 门控是**改动的风险面**（已登记 §3.2），不是待修项 |
| **R5** | `chapter_id` 索引缺失 | **不做**（行数量级小；加索引须 bump schema，收益 < 代价） |
| **R6** | 教学链路是否跨章聚合活跃症候（方案 C） | **不在本 ADR 裁定范围内** —— 它改变**教学行为**且举证条件（真实使用数据）未满足。已登记 `DECISIONS §3` 待裁 |
| **R7** | `N5` 的优先级 | **下调**：原 `P1`「批 4 / ADR 先行」建立在「三项未做 + 动 schema」上 ⇒ 现真实增量 ≈ 0（本 ADR 即其全部交付） |

---

## 6. 不做的事（`R-010` 最小范围）

| 不做 | 理由 |
|:--|:--|
| 改 `sessions` / `session_reference` 的语义或 schema | §4.1 |
| 删 `getOrCreateSessionForManuscript` | `ADR-C81 §3.4` 已裁「不动」；且它是 manuscript 级会话时机的**唯一书面记录** |
| 在教学链路接 `listActiveProblemsForManuscript` | 改变教学行为，须舰长裁定（`R6`） |
| 加 `idx_sessions_chapter_id` | §5 R5 |
| 改 `message_injector` 的 19 处 `refType` 门控 | 当前行为正确；改动是纯风险（§3.2） |
| 改 `manuscript_scope.dart` / 三个 `*ForManuscript` | 已交付、已投产、单一真源，**无待做项** |

---

## 7. 风险与**反转触发条件**（何时应推翻本 ADR）

| # | 触发条件 | 触发后应做什么 |
|:--|:--|:--|
| **T1** | 真实用户反馈（≥3 例）表述为「**我在别的章说过的问题，教练在新章又当新问题重讲一遍**」 | 提级 `DECISIONS §3` 的 `R6`（方案 C），按「读侧聚合」实施（**仍不需动 schema**） |
| **T2** | 产品决定「章节只是排版单位，教学记忆必须按书」 | 同上，且须**先推翻 `ADR-C71 §2`** 并重跑其验收 |
| **T3** | `sessions` 行数出现**万级**增长（多用户导出合并等） | 再评估 `chapter_id` 索引（`R5`），届时按当时版本 bump |
| **T4** | 有人提议把会话主引用改成 `manuscript` | **先读 §3.2**：须同时改造 19 处 `refType` 门控，否则设定库注入**静默全断** |
| **T5** | `manuscript_scope.dart` 的三源并集被证实有漏/重 | 修正该文件（单一真源），**不在本 ADR 范围外另起实现** |

---

## 8. 诚实边界

1. **本 ADR 未改任何产品代码** —— 只出裁定与订正。
2. **§2.2 的「`ADR-C71` 已裁」是文档证据，不是行为实测** —— 未在真机上验证「切章后 phase 确实回到 P0」
   （`ADR-C71 §5` 声称有测试固化，**本 ADR 未复核那些用例**）。
3. **§3.2 的 19 处门控计数为静态检索结果**（`grep 'refType != \'chapter\''` / `== 'chapter'`），
   **未逐处核对运行时可达性**（部分可能被上游条件短路）。
4. **「真实使用数据不存在」这一断言未用脚本证明** —— 依据是 `.ai/` 与交付账中**未见**用户反馈样本，
   属**检索性否定**（`DECISIONS §4-58`：`git grep` 不搜被 ignore 的目录，故本结论范围**不覆盖** `yuesheng-flutter/docs/` 全文）。
5. **未评估 `N6` 与本议题的叠加**（`N6-施工.md:251-252` 登记过该风险）—— `N6` 已落地为只读投影，
   **不消费会话状态** ⇒ 实测无叠加（本条为本 ADR 复核结果，非推断）。
6. **方案 C 未做可行性细核**（未逐点算「哪些消费点可安全替换」）—— 因其**未获授权**，
   细核应在 `R6` 裁定为「做」之后进行。

---

## 9. 产物

| 文件 | 状态 |
|:--|:--|
| `yuesheng-flutter/docs/ADR-C97-session-scope-book-vs-chapter.md` | **新增**（本文件；`.gitignore:105` ⇒ 不入公仓，与 `ADR-C71/C81/C95/C96` 同惯例） |
| `.ai/DECISIONS.md §2` | **已登记** —— 新增小节「2026-09-18 `N5` 会话粒度：`ADR-C97` 签发 —— 前提订正 + 裁定『不动 schema』」（含 `R1`–`R7` 裁定表 + 三项前提订正表） |

> ★ **刻意不另建 `.ai/reports/` 报告**：`DECISIONS §2` 那一行已含全部裁定与实测 `file:line`，
> 另建报告会形成**同语义双副本**（本仓纪律：避免两套真源，见 `DECISIONS §4-41`）。
> ⇒ **跨会话/跨机的唯一入口 = `.ai/DECISIONS.md §2` 的 `N5` 小节。**
