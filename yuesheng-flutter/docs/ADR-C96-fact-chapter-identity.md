# ADR-C96 · fact 层章号**写入侧另存身份**（`R1′` 的实施）

- **日期**：2026-09-18
- **性质**：**口径裁定 + 实施形状裁定**；本 ADR **只裁定并实施 phase 1（写入侧）**，phase 2 被 `S1/S2/S3` 阻塞
- **触发**：`N12-F3b`（`N12-F3` 侦察立、`N12-F3a` 交付后接续实施）
- **硬约束**：R-009（用户主权）· R-019（函数 ≤50 行）· R-020（循环依赖零容忍）· R-027（Prompt 改动需确认）· AGENTS.md §7（**DB schema 语义 ⇒ 必须先写 ADR**）
- **上游（**本 ADR 不得与之冲突**）**：
  - `ADR-C95-chapter-number-convention.md` §4-2/§4-3（`sort_order` 是身份键、AI 自报值**不是章号**）· §5（**R1 推荐已于 2026-09-18 被实测推翻**）
  - `.ai/DECISIONS.md §2`「fact 层章号 = **R1′**」行 —— **不覆盖、不篡改已存值；写入时另存身份；展示时解析为序位**
  - `.ai/DECISIONS.md §2`（2026-09-18）「`schemaVersion` 下一次 bump 的落地形状」行 —— `kSchemaHead` + 13 个迁移测试改引用
  - `lib/services/fact_stale_service.dart:38-51` —— 「章号不足以定位、以 hash 兜底」的**既有先例**
- **标注纪律**：【事实】= 有 `file:line` 或实测佐证；【推断】= 我方推导，显式标注。
- **侦察全文**：`.ai/reports/2026-09-18-N12-F3b-侦察.md`

---

## §0 一句话结论

fact 层三个章号载体是**一列多源**（机器写身份 / AI 写标称号 / 用户手填），**读时无法分辨**；
唯一出路是**在写入侧另存一个「身份」载体**，把「身份」与「AI 原值」**物理分开**。
**身份的取值 = 「诊断所针对的那一章」优先**，解析失败也取当前章（因为同行的 `chapter_hash`
本就是这么假设的）—— **永不编造一个不存在的章**。
**本 ADR 只做写入侧**（行为零可见变更）；展示侧切换被存量读取口径 `S1/S2/S3` 阻塞，**不得默认实施**。

---

## §1 为什么必须另存，而不能在展示层修（复核 §2 的机制证据）

### 1.1 同一列有**四种**写入方

| 写入方 | 位置 | 写入值 |
|:--|:--|:--|
| 本地链路 | `diagnosis_committer.dart:796` / `:635` | `chapter.sortOrder`（**身份**） |
| AI 抽取（断言） | `diagnosis_committer.dart:817` ← `fact_validator.dart:236` 原值透传 | **标称号**（来自章标题） |
| AI 抽取（事件 / 支线） | `diagnosis_committer.dart:878` / `:925` | `AI 号`，AI 缺字段时**退回身份** ⇒ **同一列两基号** |
| 用户手工编辑 | `character_dialogs.dart:100-104` · `:201`（「章节（可选，如：7）」） | **用户自己填的数**，基数**未定义** |

⇒ 读到一个 `int` **无从知道**它是身份、标称号，还是用户随手填的数。**展示层不可修。**

### 1.2 AI 为什么答「标称号」——不是算错，是**上下文里真有两个号**

【事实】`chat_context_builder.dart:898` / `:942` 在引用**卷 / 作品**时注入的目录格式是
**`  ${ch.sortOrder}. ${ch.title}（N字）`** ⇒ 形如 `0. 第一章`：
**0 基身份与标题里的标称号同屏并列**。而单章引用（`:856`）**只给标题**。
协议（`diagnosis_committer.dart:535`）只说「`chapter` 为该断言出现的**章节序号**」，
**未定义是哪一种**。⇒ AI 报哪个都是合规作答。

### 1.3 读取方按**互不相同的基数**在读

| 读法 | 站点 | 现状后果 |
|:--|:--|:--|
| 当**身份** 查库 | `character_detail_page.dart:509`（跳转）/ `:533`（查看原文）· `character_editor_service.dart:164` | AI 给号时**跳错章**；末章**直接查不到** |
| 当**身份** 做 SQL 比较 | `fact_stale_service.dart:50/238/316` · SQL `:102/139/169` | 见 §1.4 |
| 当**序位** 渲染 | 9 处（侦察 §3） | 删章后失真仍照显示 |
| 当**数值** 做减法 | `subplot_closure_detector.dart:65`（`currentChapter` = `sortOrder`，`message_injector.dart:1501`） | **基线不一致 ⇒ 阈值判据偏移** |

### 1.4 ★ 本 ADR 立档前新发现的既有失效（**不是本项引入**）

`fact_stale_service.dart:233-239` 的 stale 判据是**三元与**：
`hash 非空` ∧ `hash ≠ currentHash` ∧ **`e.chapter == chapterNo`**。
第三项是**承重**的（hash 由正文算出，别的章的 hash 必然不等 ⇒ 只靠前两项会误标别的章）。
而 `chapterNo` = `sortOrder`、`e.chapter` = **标称号** ⇒ 干净稿上**差 1 即恒假**
⇒ **「章节改写 ⇒ 断言灰显」对 AI 抽取的断言失效**。
【样本】`outputs/ys2.db` 稿件 `5026cdfb`：断言 `chapter` **7/7 = 2**，`chapterNo = 1` ⇒ **7/7 不匹配**。
【未验证】全库命中率未探针，**不外推**。

⇒ **这一条是「必须存身份」的最强论据**：身份字段落地后，本判据应改为**比对身份**，失效自愈。
**修它属于 phase 1 的附带收益，不是额外扩张**（同一字段、同一写入点）。

---

## §2 裁定

### 裁定 1（载体：另存，**不改已存值**）

> 为三处各**新增**一个身份载体，**AI 原值原样保留**（`R1′`）：**已存值一个字节都不动**。

| 载体 | 新增 | 需 schema 变更 |
|:--|:--|:--|
| `CharacterAssertion` | JSON 字段 **`chapterSortOrder`** | ❌ 否（`assertions` 是 JSON 列） |
| `event_fact` | 列 **`chapter_sort_order`** | ✅ **v39**（幂等 `ADD COLUMN`，同 `v32` / `v38` 范式） |
| `subplot_fact` | 列 **`introduced_chapter_sort_order`** / **`resolved_chapter_sort_order`** | ✅ **v39**（同上） |

**理由**：`ADR-C95 §5` 的 **R2（保留 AI 值、仅展示时解析）不可行** —— 字段只有一个 `int`，
无法分辨它装的是哪种基号。⇒ **必须两个字段**。这同时满足 `R1′` 的「不篡改」与可判定性。

### 裁定 2（取值规则：**当前章优先**）★ 本 ADR 的核心

> 设 `cur` = 本次诊断所针对的那一章的 `sortOrder`（`diagnosis_committer` 已持有 `chapterNo`），
> `aiNo` = AI 报的数。身份 `id` 按下列顺序决定：

1. **`aiNo` 为空** ⇒ `id = cur`。（保留现行为；且与同行 `chapter_hash` 的假设一致）
2. **`aiNo` 命中 `cur` 的任一编码**（`cur` 的**标称号** / **序位** / **身份**）⇒ `id = cur`。
3. 否则把 `aiNo` 按 **标称号 → 序位 → 身份** 三编码解析到**某个真实章** ⇒ `id = 该章`。
4. 都解析不到 ⇒ `id = cur`（**与 `chapter_hash` 口径一致**；不等于「编造」——`cur` 是**正在被诊断、
>    且正文正被读取的那一章**）。

**为什么是「当前章优先」而不是直接上阶梯**：干净稿上 AI 的号**总是指向当前章**（三种编码里
必有一种命中）⇒ 第 2 步**总命中**，阶梯仅在**真正的跨章引用**时才被用到。
这消灭了「AI 报错 1 个数 → 被解析锚到**另一章**」的误锚风险（优先级阶梯单独使用会有此病）。

**为什么编码序是「标称号 → 序位 → 身份」**：
- 标称号 = AI 实际读到的文本（`chat_context_builder.dart:856` 只给标题）⇒ **首要证据**；
- 序位 = 用户语言，且 = 标题号（默认标题）；
- **身份放最后**：默认标题下 `身份 = 序位 − 1` ⇒ 若身份优先，会把「序位 2」错锚到第 3 章。

**为什么解析失败**不落 `NULL`：`NULL` 会让 `event_fact` / subplot 行**丢掉锚点**
（`subplot_closure_detector` 对无锚点支线直接跳过 ⇒ **F11 检测覆盖率回退**），
而 `cur` 是**确定成立的**（那一章的正文正是本次抽取的来源，`chapter_hash` 已如此断言）。

### 裁定 3（**分两阶段**，phase 1 不改任何可见行为）

> **phase 1（本 ADR 落地）= 只做写入侧 + 只把「读作身份」的判据改指身份字段**。
> **展示侧（9 处渲染）一行不动** ⇒ **行为零可见变更** ⇒ **不触碰 `S1/S2/S3`**。
> **phase 2 = 展示侧切到身份字段**，**被 `S1/S2/S3` 阻塞**（存量行无身份 ⇒ 章标会消失/或继续错位，
> 属**用户可见取舍**，按 R-009 相邻原则**未定之前不得默认实施**）。

**理由**：phase 1 的收益是**结构性**的（数据从此可判定）与**自愈性**的（§1.4 的失效判据改指身份后恢复）；
而 phase 2 的收益才是**用户可见**的，也正是必须由舰长裁定的那部分。两者**必须解耦**，
否则要么把用户可见变更偷渡进技术批次，要么让技术批次被一个未定项无限期阻塞。

### 裁定 4（**一次 bump 做完**，不拆成 v39/v40）

> 三处新增**同批**落地为 **`schemaVersion 38 → 39`**，并**同时**执行 `DECISIONS §2` 预承诺的
> `kSchemaHead` 形状（`test/test_support/schema_head.dart` + 1 例 `user_version` 断言 + 13 个迁移测试改引用）。
> **不得**先加 `event_fact` 再加 `subplot_fact`（会产生第二次 bump + 第二次全量扫荡）。

### 裁定 5（不新增 Prompt 约束，**本期不动协议**）

> **不改** `buildFactProtocolContext`（`diagnosis_committer.dart:499-548`）的措辞。
> 现状下「让 AI 填身份」**没有意义**（它看不到稳定的身份；目录前缀只出现在卷/作品引用时）。
> ⇒ 本 ADR **不触发 R-027**（不构成 Skill / Prompt 变更）。
> **若将来要让 AI 直接回填身份** ⇒ **另立批次 + 独立 ADR + R-027 人工确认**。

---

## §3 被否方案（防复现）

| 案 | 内容 | 否因 |
|:--:|:--|:--|
| **R1** | 写入时用当前章**覆盖** AI 值 | **已于 `N12-F3` 撤回**（销毁用户手填输入 ⇒ R-009 硬边界）· 且 AI 值不是算错（§1.2） |
| **R2** | 保留 AI 值、**仅展示时**解析 | **不可行** —— 字段只有一个 `int`，无法分辨装的是哪种基号（`ADR-C95 §5`） |
| **R3** | 维持现状 | 即 §1.3 / §1.4 的多重失效态 |
| **R4**（本批新提） | 身份**恒 = 当前章**，不做编码解析 | ❌ 会让 `subplot_fact.introduced_chapter` **恒等于当前章** ⇒ `current − introduced ≡ 0` ⇒ **F11 情节闭环永不触发**（功能回退，见裁定 2 的解析必要性） |
| **R5**（本批新提） | 解析失败 ⇒ 身份落 `NULL` | ❌ 丢检测覆盖（裁定 2 末段）；且 `cur` 本就确定成立 |
| **R6**（本批新提） | 现在就改展示（phase 1 + phase 2 合并） | ❌ 会让**存量行章标消失或继续错位** —— 属 `S1/S2/S3`，**未定不得默认** |

---

## §4 落地改动清单（**下一批实施**，本 ADR 只定形状）

| # | 文件 | 改动 | 风险 |
|:--:|:--|:--|:--|
| 1 | `lib/data/database/tables.dart` | `EventFacts` +1 列 · `SubplotFacts` +2 列 | 需 `dart run build_runner` 重生成 `database.g.dart`（**勿手改**） |
| 2 | `lib/data/database/database.dart` | `schemaVersion 38 → 39` · `from < 39` 幂等 `ADD COLUMN`（判 `pragma_table_info` 存在 + 列缺失）· 守卫随之上移到 39（**守卫必须 == schemaVersion**，见 `:216-220` 契约） | 中（迁移是 DDL-only，本仓 **38 个版本零数据变换先例** ⇒ 不得开这个头） |
| 3 | `lib/types/character_types.dart` | 加 `chapterSortOrder`；**逐点**决定 `fromDbJson` / `withStaleMark` / `withStatus` / `withNegative` **保真**，`tryFromJson` **有意不读**（协议无此字段） | **高**（§6） |
| 4 | `lib/utils/chapter_number.dart` | 新增身份**解析器**（单实现点）：`resolveChapterIdentity(aiNo, chapters, currentSortOrder)` + 标称号提取（**复用** `chapter_title.dart` 的 `chineseNumberToInt`） | 中（须带正负例） |
| 5 | `lib/services/diagnosis_committer.dart` | 三处写入点填身份（`:817` 断言 / `:878` 事件 / `:925` 支线）；`_asAiPending` **保真**该字段 | 中 |
| 6 | `lib/services/character_editor_service.dart` | 用户入口填身份（`_appendUserAssertion`）· `_hashForChapter` **改吃身份**（§1.3 第 1 行的错绑）· `_withStatus` 补 `negative`（§6 潜伏缺口） | 中 |
| 7 | `lib/services/fact_stale_service.dart` | stale 判据与 `belongsToChapter` **改比身份**（§1.4 失效自愈）；SQL 站点同步 | **高**（承重判据） |
| 8 | `lib/services/subplot_closure_detector.dart` / `event_causality_detector.dart` | 消费方改吃身份（判据语义不变） | 中 |
| 9 | `lib/data/repositories/*` | `upsert*` 透传新列；`listSubplots` 等回读 | 低 |
| 10 | `test/test_support/schema_head.dart` | **新建** `kSchemaHead = 39` + 断言「== 空库 `user_version`」 | 低 |
| 11 | 13 个迁移测试 | 硬编码 `38` 改引用 `kSchemaHead`（**实测复核**处数与文件数，台账不是证据） | 中（扫荡，见 skill `version-bump-test-sweep`） |
| 12 | 新增测试 | 解析器正负例（含 §3 的 R4/R5 反例）· 三处写入点身份落库 · stale 判据改指身份后的正负例 | — |

**不在本批**：**展示侧 9 处一行不改**（phase 2）· 不改 Prompt 协议 · **不回写存量行** · 不新增 A→B 静态映射表。

---

## §5 验收判据

1. **正例（写读闭环）**：默认标题 3 章（`sortOrder` 0/1/2）诊断第 3 章，AI 报 `chapter = 3`
   ⇒ 落库 `chapter_sort_order = 2`，且 `chapter` **原值仍为 3**（`R1′`：不改已存值）。
2. **反例（杀死 R4「恒 = 当前章」）**：AI 在诊断第 3 章时报 `chapter = 1`（指向第 1 章）
   ⇒ 身份必须是 **0**（第 1 章），**不是** `2`。
3. **反例（杀死 R5「落 NULL」）**：AI 报 `chapter = 99`（无此章）
   ⇒ 身份必须为**当前章**（非 `NULL`）—— `subplot_closure_detector` 仍能参与判定。
4. **反例（杀死「阶梯直接上」）**：默认标题下 AI 报 `chapter = 2` 而当前章是第 2 章
   （`sortOrder = 1`）⇒ 身份必须是 **1**（**当前章优先**），**不是** 2（若身份编码优先会错锚第 3 章）。
5. **迁移**：v38 库升 v39 后三列存在；**最小 schema 库**（表不存在）不抛错（判表存在，同 `v32`/`v38`）。
6. **行为不变（phase 1 的关键判据）**：既有端到端网**未改写**仍全绿；**9 处展示渲染一行未改**。
7. **门禁**：12/12 全绿；R-019 **无新增**超限（**若搬迁/新增长函数，须逐键对账并重生成基线**）。
8. **负向验证**：至少 1 组「退回旧写法 ⇒ 精确转红」，且**产物必须落在断言行**（`DECISIONS §4-18`）。

---

## §6 高风险面（实施前必读）

1. **`CharacterAssertion` 无 `copyWith`，只有逐字段手写重建** —— 全仓 **8 个**重建点
   （侦察 §6 全表）。新增字段**必须逐点决定「保真 / 有意重置」并留注释**；漏一点就重演
   `fromDbJson` 注释里写的**批次 1 潜伏缺陷**（「一次读写往返即丢失」）。
2. **`dart run build_runner` 产物 `database.g.dart` 勿手改**（AGENTS.md §6）。
3. **迁移守卫契约**：`database.dart:216-220` 明确「守卫值必须**等于**当前 `schemaVersion`」
   —— 改 bump 时**必须同步上移守卫**，否则 `from ∈ [守卫, schemaVersion)` 的库被整段跳过。
4. **`v39` 必须是 DDL-only**：本仓 38 个版本**零数据变换先例**；一旦写 `UPDATE` 就是在开结构性首例
   （`DECISIONS §2` 已就 N10 回填事项裁定「若重启须走 ADR」）⇒ **本项不得开这个头**。
5. **承重判据改动**：`fact_stale_service` 的 stale 判定连着用户可见的「灰显」⇒ 改后必须补
   **正例 + 反例**（含「别章的断言不得被误标」）。

---

## §7 记录（防复现）

- `ADR-C95 §5` 曾推荐 **R1**；本 ADR 的前置侦察已**实测推翻**它（两项独立证据：AI 值是**第三个语义**
  而非算错；该列**有用户手填框**）。⇒ **引用 `ADR-C95 §5` 时必须连带引用该推翻**，否则会重跑 R1。
- 本 ADR **不实施**任何代码 —— 这是 AGENTS.md §7 的要求（DB schema 语义属核心模块），
  也让 `S1/S2/S3` 的待定不至于阻塞**零可见变更**的 phase 1。
- ★ **ADR 落点 `yuesheng-flutter/docs/` 被 `.gitignore:105` 整体忽略** ⇒ **本裁定必须在
  `.ai/DECISIONS.md §2` 留受控副本**（`DECISIONS §4-19`）。**只写在 `docs/` 里的裁定等于没有写。**
