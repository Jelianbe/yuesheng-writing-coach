# ADR-C95 · 章号展示口径统一（`sort_order` 是身份键，不是展示号）

- **日期**：2026-09-18
- **性质**：**口径裁定**（跨层语义统一）＋ 分阶段落地；**本 ADR 只落地第一阶段**
- **触发**：批次 N12 带出的缺陷 `N12-F1`（**现网可见**：大纲抽屉来源章标显示「**第0章**」）
- **硬约束**：R-009（用户主权）· R-019（函数 ≤50 行）· R-020（循环依赖零容忍）· AGENTS.md §7（核心模块需 ADR）
- **上游**（**本 ADR 不得与之冲突**）：
  - `docs/ADR-C78-角色标签页功能实施.md` §5.2（`:327-333`）—— 已记载「`CharacterAssertion.chapter` 是
    **AI 自报值**，写入路径**不校验也不覆写**」，并据此把 stale 判据定为 **hash ∪ 章号 并集**
  - `lib/services/fact_stale_service.dart:38-51` —— 上述并集判据的实现
  - `lib/services/export_service.dart:61-64 / 112-115` —— 既有的**序位 + 1** 展示惯例
- **标注纪律**：【事实】= 有 `file:line` 或 **数据库实测**佐证；【推断】= 我方推导，显式标注。

---

## §0 一句话结论

`chapters.sort_order` 是**0 基、可不连续、可被交换/跨卷移动**的内部**身份/排序键**；
而 `第N章` 的 N 在本项目里唯一合理的定义是「该章在**作品当前章节列表**中的**序位 + 1**」。
**任何把 `sort_order` 直接渲染、或 `sort_order + 1` 的做法都是错的**——后者只在
「无删除且无重排」时才偶然相等。

---

## §1 现象与最小复现

【事实】舰长设备上 2 条大纲印象的来源章标均渲染为「**第0章**」。

调用链（全部实测）：

| 环节 | 位置 | 代码 |
|:--|:--|:--|
| ① 生成 | `lib/data/repositories/chapter_repository.dart:41` | `order = (max(sort_order) ?? -1) + 1` ⇒ **首章 = 0** |
| ② 直传 | `lib/services/diagnosis_committer.dart:635` | `sourceChapterNo: chapter.sortOrder` |
| ③ 落库 | `lib/data/repositories/outline_repository.dart:121` | `sourceChapterNo: Value(sourceChapterNo)` |
| ④ 渲染 | `lib/widgets/outline_content_view.dart:338` | `label: '第${impression.sourceChapterNo}章'` |

②③④ 全程**原值直传、零归一化** ⇒ 0 基的 `0` 直接变成「第0章」。

---

## §2 决定性证据（数据库实测，非推断）

转储两份真实库（`.ai/tmp/n11/dev.db`、`yuesheng-flutter/outputs/ys2.db`）：

**证据 A —— 0 基确认**

| 库 | `chapters.sort_order` | `outline_impression.source_chapter_no` |
|:--|:--|:--|
| `dev.db` | `0` | `0`（2 条，即舰长所见「第0章」） |
| `ys2.db` | `0, 1` | `1` |

**证据 B —— 同一章、同一界面体系，两个字段给出不同的数**（**这才是问题的本质**）

稿件 `5026cdfb-…` 只有一章：`title = 「第二章西藏酒后故事」`，`sort_order = 1`。

| 字段 | 值 | 来源 |
|:--|:--:|:--|
| `character_fact.first_seen_chapter` | **1** | 本地 `chapterNo = chapter.sortOrder`（`diagnosis_committer.dart:796`）|
| `assertion.chapter`（该角色 3 条断言全部）| **2** | AI 抽取，原值透传（`fact_validator.dart:236`）|
| `event_fact.chapter`（该稿 4 条全部）| **2** | 同上 |
| `outline_impression.source_chapter_no` | **1** | `chapter.sortOrder` |

【事实】`character_list_view.dart:400` 渲染 `第$ch章登场`（用 `firstSeenChapter`），
`character_assertion_tile.dart:173` 渲染 `第$ch章`（用 `assertion.chapter`）
⇒ **同一角色的两个数字会同时出现在用户面前，且必然不一致**。

**证据 C —— 两个存储值都不可靠**

上例该稿**只剩这一章**（`sort_order = 1`，`0` 号那章已被删）⇒ 它实际上是**第 1 章**。
- `first_seen_chapter = 1` → 「第1章」：**恰好对**（因为 sortOrder 恰好等于序位 0）
- `assertion.chapter = 2` → 「第2章」：**错**（AI 按标题「第二章」作答，而标题在删章后已失真）

⇒ **结论：`sort_order` 只提供「是哪一章」的身份，不提供「第几章」的展示号；
AI 自报值连身份都不提供（它只是个文本序数）。唯一正确的展示源是「当前列表中的序位」。**

---

## §3 为什么不能简单地 `sort_order + 1`

`sort_order` 的三个实测反例（均为**代码可达**路径，非理论）：

| # | 路径 | 后果 |
|:--:|:--|:--|
| 1 | `softDeleteChapter` / `purgeChapter`（`chapter_repository.dart:177/221`） | **删除不重编号** ⇒ 序位与 sortOrder 从此错位（证据 C 即此例） |
| 2 | `swapChapterSortOrder`（`:348`，卷内上移/下移） | 两章 sortOrder **互换** ⇒ 不再单调 |
| 3 | `updateChapterSortOrder`（`:368`，跨卷移动置末位） | 全局值**可能不连续**；`:346-347` 注释自陈「全局值可能不连续」 |

⇒ `sort_order + 1` 在**无删除、无重排**的干净稿上等于序位；其余情况一律错。
**本 ADR 明确禁止把它作为兜底公式。**

---

## §4 裁定

### 裁定 1（展示口径，唯一）

> **`第N章` 的 N = 「按 `sort_order` 升序、排除回收站（`status != 'archived'`）的章节列表中，
> 该章所处位置的序位」+ 1。**

- 列表定义 = `ChapterRepository.listChapters(manuscriptId)`（`chapter_repository.dart:129-138`），
  即 `chapterListProvider` 的底层数据源。
- **一致性依据**：UI 平铺顺序（`buildChapterSections`，`utils/volume_group.dart:77`）已按
  **全局顺序**；本口径与用户**实际看到的章节顺序**一致。
- **卷内编号**：`export_service.dart:61-64` 的**卷内** `e.$1 + 1` 是**另一套**编号。
  【裁定】**不采纳为全局口径**——`第N章` 是跨卷计数的用户语言，且比照「卷内重排」会让
  输出随卷结构变化。**记为既有不一致**（导出路径），不在本 ADR 范围内改动，另立观察项。

### 裁定 2（存储语义）

> **`sort_order` 是身份键**：唯一、稳定、0 基。**读取方不得直接渲染它**，
> 必须先经「序位解析」；已删章的引用**解析失败即不显示**，不得编造。

### 裁定 3（AI 自报章号）

> `assertion.chapter` / `event_fact.chapter` / `subplot_fact.*chapter` 中**由 AI 抽取**的值
> **不是章号**，是「模型按标题文本推的序数」。ADR-C78 §5.2 已把这一属性写进 stale 并集判据
> 的设计理由。**判定为缺陷**：修复需改**写入语义**（不是展示层能修的），见 §5。

### 裁定 4（本批范围）

> **第一阶段只修 `outline_impression.source_chapter_no` 的展示**。理由三条：
> ① 唯一 **live** 症状；② 唯一**单来源**字段（只由 `chapter.sortOrder` 写入，无 AI 混入）
> ⇒ 可用一条规则修对；③ 其余字段混装两基号，**在展示层无法区分**，必须先定写入语义。

---

## §5 未覆盖范围（下一阶段，另立批次）

| 项 | 字段 | 为何本批不做 |
|:--|:--|:--|
| **N12-F3-a** | `character_fact.first_seen_chapter` | **单一来源**（恒为 `sortOrder`）⇒ 可修；但展示点 ≥2 处（`character_list_view.dart:400`、`world_fact_*`），需与 `world_fact` 一并梳理 |
| **N12-F3-b** | `assertion.chapter`（人物/世界） | **双基号混装，展示层不可区分** ⇒ 必须改写入语义 |
| **N12-F3-c** | `EventFact.chapter`、`SubplotFact.introducedChapter/resolvedChapter` | 同上；且 `introducedChapter` 还与**读者可见的支线收束**文案相连（`subplot_closure_detector.dart:73`） |
| **N12-F3-d** | 存量数据归一化 | 见下 |

**推荐方案（提请下一批采纳，本 ADR 不做实施）**

- **R1（推荐）**：**入库时用「系统确切知道的那一章」覆盖 AI 自报值**。诊断调用方本就持有
  `chapter`（`diagnosis_committer.dart:700-723`）⇒ AI 的自报值是**冗余猜测**，覆盖后断言定位更准，
  且 stale 并集判据仍成立（hash 支不变）。
- **被否 R2**：保留 AI 值、仅展示时解析 —— **不可行**：字段只有一个 int，**无法分辨**它装的是
  AI 序数还是 sortOrder（证据 B 的 1 与 2 并存即是此困境）。
- **被否 R3**：`sort_order + 1` 兜底 —— 见 §3，三个可达反例。
- **存量归一化**：`aiValue → sortOrder` 的映射**不可逆**（AI 可能报 3 而实际只有 2 章）⇒
  归一化有信息损失。**须在 R1 落地时同批决定**：全量归一化 / 只对新数据生效（旧数据展示时
  解析失败即不显示）/ 加列区分来源。**未定，不得默认。**

---

## §6 落地改动（第一阶段，本批实施）

| # | 文件 | 改动 |
|:--:|:--|:--|
| 1 | `lib/utils/chapter_number.dart` | **新增**：`buildChapterNoMap` / `displayChapterNo` / `chapterLabel` —— 口径的**唯一实现点** |
| 2 | `lib/widgets/outline_content_view.dart` | 读 `chapterListProvider(msId)` → 建映射 → 逐层下传；来源章标改为**解析结果**，**解析失败不渲染标签** |
| 3 | `test/widgets/outline_drawer_test.dart` | 章标类用例改为**播种真实章节**；新增 F1 专项正负例（含 §3 反例） |

**不在本批**：不改写入路径、不改 DB schema、不改导出路径、不动 fact 层展示。

---

## §7 验收判据

1. **正例**：`sort_order = 0` 的章 ⇒ 章标为「**第1章**」（不再是「第0章」）。
2. **反例（杀死 `+1` 兜底）**：章节 `[1, 2]`（0 号已删）中 `sortOrder = 2` 的章 ⇒
   章标必须是「**第2章**」而**不是**「第3章」。
3. **反例（杀死 `sourceChapterNo != null` 直渲染）**：引用一个**已删章**的 `sortOrder`
   ⇒ **不渲染章标**（而非渲染一个数）。
4. **行为不变**：既有端到端网（`writing_page_test.dart` 的 `#83-6` / `#83-9` / `#87-4` 等）
   **一行不改**，仍全绿。
5. **门禁**：12/12 全绿；R-019 **无新增**超限。

---

## §8 记录（前车之鉴，防复现）

- 本缺陷在**批次 N12 侦察时已被发现**，当时判「拆成独立批次（自带正负例）」，**未顺手一起改** ——
  该判断在本次复查中被证明**必要且正确**：若当时随手 `+1`，会把 §3 反例 1 的情形改错，
  且**不会有任何测试拦住**（当时没有章号口径的测试）。
- 缺陷编号**不使用裸 `N<数字>`**：`N12-F1`（原因见 `.ai/DECISIONS.md` §2 命名规则裁定）。
