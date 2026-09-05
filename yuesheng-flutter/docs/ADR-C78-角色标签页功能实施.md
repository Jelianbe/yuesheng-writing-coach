# ADR-C78 · 角色标签页（Character 管理）功能实施

- **状态**：**Accepted（2026-09-05 21:3x，舰长已批复四项裁决 + 恢复处置）** → 批次 1 可开工
- **真源**：`docs/plans/角色标签页功能方案-2026-09-05.md`（v1.3，含 D-1~D-8 定稿）
- **本 ADR 内容** = 方案 §四（技术方案）+ D-3 prompt 变更单列（R-027 高风险）+ 执行提示词「必须补的实现细节」三条 + 侦察发现的三处冲突裁决项
- **适用**：`yuesheng-flutter`（Flutter 3.44.8 / Dart 3.12.2 / drift / Riverpod）

---

## 0. 开工前状态核实（执行纪律 1）

| 项 | 实测 | 结论 |
|---|---|---|
| 工作树 | **不干净**：① `docs/plans/角色标签页功能方案-2026-09-05.md` 已就地升 v1.3（未提交）；② 未跟踪 `docs/plans/写作机优化-功能方案与路线图-2026-09-05.md` | ① 方案 v1.3 先独立提交（真源归位）；② 见下方 ⚠️ |
| ⚠️ 重复真源 | 未跟踪的 `写作机优化` 方案 §4.3–4.4 是**同一功能的旧草稿**（只有 D-1~D-5，**缺 D-6 stale / D-7 确认入口 / D-8 事件侧**），与 v1.3 真源矛盾 | ✅ **舰长已批：按我判断处理**。处置 = **隔离出工作树**（移入 `_c78_isolated/`，不删、可回溯），不按其落地、不提交进仓库。理由：它是**同一功能的更早草稿**，留着会形成第二份互相矛盾的真源；但直接删不可逆，故先隔离 |
| ADR 编号 | C78 全仓未占用（最新为 C77） | 取 **C78** |
| 测试基线 | `flutter test --exclude-tags live,external` → **2442 用例全绿，0 失败**（01:59） | AGENTS.md 写的「2298」已过期，台账一并更正 |
| R-019 基线 | `tool/r019_baseline.json` = **160 条 / 293 文件**（AGENTS.md 写 235，过期） | 同上更正 |
| 循环依赖基线 | `tool/circular_baseline.json` **为空**（ADR-C70 已清全部环） | 门禁 3 是**全量卡口**，本批不得引入任何新环 |
| 测试命令 | 沙箱缺 `PROGRAMFILES(X86)` → 直跑 `flutter test` 报「environment variable not found」且 exit 1 零输出；剥代理后又撞 WebSocket 劫持 | 统一用 `bash scripts/_run_flutter_test.sh`（V4.22 已封装两者） |
| **六道门禁基线** | **改动前 `bash scripts/gate.sh` → EXIT=0，6/6 全绿**（2026-09-05 20:43，报告 `outputs/gate/gate-report.md`） | ✅ **零回归的比对基准已取证**，批次 4 收尾须拿最终态与之对比 |
| 🚫 并行工作流 | **规则迁移（R-001..R-030 → Flutter）已由舰长叫停**：「文档已经足够多，先别写了」（2026-09-05） | 本 ADR **不承载**规则迁移内容；此前已迁移部分保持现状，不再新增。待办台账中该工作流转 `暂停` |

---

## 1. 决策落地表（D-1~D-8 逐条对应实现）

| # | 决策 | 本批实现口径 |
|---|---|---|
| D-1 | 别名走代码侧 | 别名存 `CharacterFacts.aliases`（JSON `String[]`），匹配 = 主名 ∪ 别名。**不碰 prompt 语义** |
| D-2 | 枚举仅 confirmed/rejected | `CharacterAssertion.status` 仅两值，缺省 `confirmed`；**无 pending** |
| D-3 | 协议增 evidence | 见 §2 单列（动注入 prompt，R-027 高风险） |
| D-4 | source: ai\|user | 断言级字段，缺省 `ai`；UI 展示 `[AI]` / `[手]` 标记 |
| D-5 | 最小「并入主角色」 | 目标页发起 → 源角色断言迁移（source 保留）→ **源行 `status='merged'`** → **源名自动收进目标 aliases**；不动历史 `EventFacts.participants` |
| D-6 | 重复诊断 = 标记制 | 断言带 `chapterHash`；同章 hash 变 → 旧断言标 `stale`（保留不删）→ F05 排除 stale + rejected；角色页一键「清除本章旧版」；章节删除/回收站同标 stale；**恢复不自动解除 stale** |
| D-7 | 确认入口 = 静默沉淀 + 批次视图 | 不做 AI 协议内嵌确认卡；诊断消息尾部由系统渲染提示卡；拒绝理由 chips 可选不强制 |
| D-8 | 事件侧同语义（同批） | `EventFacts` 加 `stale` + `chapterHash` 列；F07（`detectCausalityBreaks`）只消费非 stale。**实测牵连很浅**（typedef +1 字段、循环 +1 守卫、1 处调用点），**不降级，按同批完整实现** |

### 1.1 提示词「必须补的实现细节」三条（已并入设计）

1. **`CharacterFacts` 行级 `status` 列**：方案 v1.3 只写了 aliases 列，但 D-5「来源行软删」没有载体 → 本迁移**同时加 `status`（`active` / `merged`，默认 `active`）**。
2. **合并时源名自动收进目标 aliases**：`unique(manuscriptId, name)` 下源行保留（`status='merged'`），其名写入目标 `aliases`；历史 `EventFacts.participants` **一个字都不改**——D-1 的主名∪别名匹配天然兼容全部历史事件。
3. **`EventFacts` 行级 stale 列随同一迁移加**（D-8）。

---

## 2. ⚠️ D-3：`[YS_FACT]` 协议增 evidence（动注入 prompt，R-027 高风险，单列）

### 2.1 变更内容

`lib/services/diagnosis_committer.dart` → `buildFactProtocolContext()`（445–490 行）中
`characters.assertions[]` 格式块（约 461 行）：

```
改前：{"attribute":"…","value":"…","chapter":3}
改后：{"attribute":"…","value":"…","chapter":3,"evidence":"原文摘录（≤30字）"}
```
并在 `characters` 规则段补一句说明：evidence 为该断言在正文中的**原句摘录**（非转述、非概括），
无对应原文时**省略该字段**（不填空串）。

### 2.2 风险实证（前任会话已核实，本批复核确认）

- `buildFactProtocolContext` **未被任何测试快照冻结**（全仓检索无断言其输出串的用例）；
- `test/snapshots/skill_prompt_anchor.json` 只覆盖 `buildSystemPromptV2` 输出，**不含 fact 协议**
  → **预期零锚点漂移**；若实测出现漂移即属越界，停下排查（执行纪律 5）；
- `lib/services/fact_validator.dart` 为宽松解析（name 非空 + `CharacterAssertion.tryFromJson`，
  未知字段无害穿透）→ 加 evidence 只需改协议文本 + `tryFromJson`，**无需改校验器白名单**；
- 输出 token 增量：每断言 ≤30 字，单次诊断通常 ≤10 条断言 → ≤300 字，可控。

### 2.3 验收

协议解析测试覆盖「evidence 缺失」「evidence 存在」「evidence 为空串」三分支；
锚点测试零漂移；六道门禁全绿。

---

## 3. ⚠️ 三处代码现实与方案冲突（需舰长裁决，裁决前不动代码）

### 冲突 A｜入口位置：写作页**没有**底部 tab

> **✅ 舰长已裁决（2026-09-05 20:5x）：入口放写作页，不新开页面。**
> 以下 A1/A2/A3 三案**均作废**，改走 §3.0 的写作页 Sheet 方案。原论证保留存档：
> 它证明了「底部 tab / 独立全屏页 / 抽屉 tab 化」三条路各自的代价，是选型的依据。

### 3.0 定案：写作页 AppBar ⋮ 菜单 → **独立路由页**（舰长裁决 2026-09-05）

> **✅ 舰长裁决**：入口挂写作页 ⋮ 菜单，但形态用 **独立路由页（`MaterialPageRoute`）**，
> **不用 Sheet**。理由：Sheet 适合紧凑工具（文风 / 统计 / 快捷短语 / 回收板），
> 而角色管理是**页面级内容**（列表 + 详情 + 分组断言 + F05 + 相关事件 + 合并），
> 塞进弹层会局促。两者改动成本同为 3 处，均不碰 provider / FAB / 测试锁。

**入口落点**：写作页 AppBar ⋮ 菜单（`WritingMenuSheet.show`，`writing_page.dart:770`）
是**回调驱动的入口列表**，已有 9 个 `onOpen*`。加第 10 个与既有模式完全一致。

**改造点 3 处**（不含新增文件）：

| # | 位置 | 改动 |
|---|---|---|
| 1 | `writing_page.dart` ≈:442 后 | 新增 `_handleOpenCharacters()` → `Navigator.push(context, MaterialPageRoute(builder: (_) => const CharacterPage(...)))`（3 行） |
| 2 | `writing_page.dart` ≈:787 | 菜单传参加 `onOpenCharacters: _handleOpenCharacters,`（1 行） |
| 3 | `WritingMenuSheet` 组件 | 加 `onOpenCharacters` 参数 + 一个菜单项（与其余 9 项同款） |

新增文件：`lib/widgets/character_page.dart`（列表 → 详情栈式导航，`IndexedStack` 或内部 `Navigator`）。

**三个被排除方案及理由**：

| 方案 | 排除理由 |
|---|---|
| **Sheet 弹层**（`CharacterSheet.show`） | **舰长否决**：角色管理是页面级内容，弹层局促。Sheet 只用于表单/展示型紧凑工具（文风、统计、快捷短语、回收板） |
| **复用右侧面板槽位**（`isAiPanelOpen`） | 要动 `WritingState` → `copyWith` → `toggleAiPanel()` → `_buildEditorWithPanel` → `:547` FAB 条件共 5 处；且 **`test/providers/writing_providers_test.dart:85,173-200` 已锁死** `isAiPanelOpen`/`toggleAiPanel` 既有语义，动即挂测试 |
| **作品详情页第 4 个 tab**（原推荐 A1） | 舰长要求入口在写作页；角色管理需与写作动作就近 |

> 取舍如实记录：路由页打开时**看不到编辑器**（全屏覆盖）；面板槽位方案则可与编辑器同屏。
> 若后续要求「边写边看角色档案」，需重开此议题并连带改测试。本批按舰长裁决取路由页。

- 方案 §3.3 决策 3 / §4.3 写「写作页底部 tab『角色』，与大纲并列」。
- **现实**：`lib/widgets/writing_page.dart`（1182 行）**无底部 tab**。
  写作页结构 = 左抽屉 `ChapterTreeDrawer`(557) + 右抽屉 `OutlineDrawer`(572) + AppBar(583)
  + body Stack(589)。大纲的真实入口是 AppBar ⋮ 菜单 `onOpenOutline`(≈779) 打开**右侧抽屉**。
  全仓唯一 `TabBar` 在 `lib/widgets/manuscript_detail_page.dart:265`（章节 / 文件 / 相关对话）。
  App 级 `NavigationBar`（`lib/router/app_router.dart:263-290`）只有 3 分支：书架 / 对话 / 成长。
  Scaffold 的 `endDrawer` **只有一个槽位**，无法再挂一个并列抽屉。
  **写作页底部也已被占满**：`_buildSaveStatusBar`(1103) + `PunctuationBar`(1104，36dp)
  + 可拖动 FAB 浮层（604-662）→ 再加底部 tab 会挤压本就紧张的编辑区（窄屏已有
  改底部抽屉的先例，673-706）。**「写作页底部 tab」在代码上没有落点，确认不可行。**

- **建议裁决（推荐 A1）**：
  - **A1（推荐）**：「角色」作为**作品详情页第 4 个 tab**（章节 / 文件 / 相关对话 / **角色**）。
    理由：① 角色是作品级数据（`CharacterFacts.manuscriptId`），作品详情页正是作品级容器且已有 TabBar 基建，零新增脚手架；② 与竞品一致（阅文妙笔/口袋写作的角色档案库都在作品内）；③ 不压缩写作页正文区（写作页加底栏会挤压编辑器，布局风险高）；④ FR-10 提示卡从聊天页跳转 → 到作品详情页并选中角色 tab，链路自然。

    **A1 改造点精确清单（已逐行核实，仅 3 处）**：
    - `manuscript_detail_page.dart:98` `TabController(length: 3)` → `4`；
    - `:276-280` `tabs:` 末尾加 `const Tab(text: '角色')`；
    - `:284+` `TabBarView.children` 末尾加角色页。
    - ✅ `:237` `if (_tabController.index == 0)` 门控的是「+ 新建卷」，index 0 仍是章节 tab，
      **加第 4 tab 不影响它**——无隐藏耦合。
  - **A2**：写作页 ⋮ 菜单加「角色」→ `Navigator.push` 独立全屏页（**不做** tab，纯路由页）。
  - **A3**：右侧抽屉 tab 化（大纲｜角色双 tab 共用一个 endDrawer 槽位）——空间仅约 320px，
    详情页（断言分组 + 相关事件 + F05 + 别名 + 合并）放不下，不推荐。
  - 备注：A1/A2 **不互斥**，可 A1 为主入口 + A2 为写作页快捷入口。

### 冲突 B｜schema 版本号：v27 还是 v28

- **三个来源各执一词**：
  - 执行提示词：「v27 迁移（加 aliases 列）…EventFacts stale 列随同一 v27 迁移加」；
  - 方案 v1.3（真源）：「两表同批一次迁移到 **v28**（v26→v28）」，但同句又写「一次迁移避免二次 bump」；
  - 未跟踪的 `docs/plans/写作机优化-功能方案与路线图-2026-09-05.md:155`：「aliases 列，schema **v26→v27**」。
- **现实**：`lib/data/database/database.dart:55` 当前 `schemaVersion => 26`；**v27 从未被占用**。
  三份文档**都同意只做一次迁移**——方案 v1.3 的「v28」疑似「原计划两次迁移」的残留措辞。
- **✅ 舰长已裁决（2026-09-05）：B1 —— 单次迁移 v26 → v27。**
  同步 4 处硬编码（`database.dart:55` / `:178` / `test/widget_test.dart:58` /
  `migration_v24_test.dart` 终态断言）。v27 从未被占用，序列连续，不留空洞。

## 3 裁决汇总（舰长 2026-09-05 已全部批复）

| 项 | 裁决 | 落点 |
|---|---|---|
| **冲突 A** 入口 | 写作页 ⋮ 菜单 → **独立路由页 `MaterialPageRoute`**（非 Sheet、非面板槽位、非详情页 tab） | §3.0 |
| **冲突 B** 版本号 | **v26 → v27** 单次迁移 | §3 B |
| **冲突 C** 提示卡 | **内存态不落库**，重启后卡片消失——**如实标注**，不伪装成持久 | §3 C |
| 旧草稿去留 | 维持隔离在 `_c78_isolated/`，**不提交进 `docs/plans/`** | §0 |
- 无论取哪个号，需同步 4 处硬编码：`database.dart:55`（schemaVersion）、
  `database.dart:178`（`if (from >= N) return;` 守卫上移）、
  `test/widget_test.dart:58` 注释与断言、`migration_v24_test.dart` 的终态断言。

### 冲突 C｜批次提示卡（FR-10）的落库方式

- 方案 §4.2 写「事实落库处返回本次新增条数；chat 侧由系统渲染提示卡」，但**未定义计数存哪**。
- **现实**：`applyFactExtractionFromContent`（`diagnosis_committer.dart:605`）现返回 `void`；
  聊天消息从 DB 加载，若计数只存内存，重启后提示卡消失；若持久化需给
  `diagnosis_results` 加列（方案未列的第三次 schema 变更）。
- **✅ 舰长已裁决（2026-09-05）：C1 —— 内存态，不落库。**
  `messageId → 本轮沉淀条数`），渲染为消息尾部提示卡；重启后卡片自然消失。
  理由：FR-10 语义本身就是「**最近**批次」， transient 与语义一致；避免为提示卡再动 schema。
  **如实标注**：重启会话后旧消息的提示卡不再出现（「最近批次」视图仍可按断言 timestamp 过滤）。
  - C2（备选）：`diagnosis_results` 加 `fact_batch_count` 列持久化——多一次 schema 变更，不推荐。

---

## 4. 数据层方案（批次 1）

### 4.1 迁移：v26 → v27（版本号待冲突 B 裁决）

三个 `ALTER TABLE`，全部走 `PRAGMA table_info` 幂等守卫（与 v25 块同款）：

```sql
ALTER TABLE character_fact ADD COLUMN aliases TEXT NOT NULL DEFAULT '[]';
ALTER TABLE character_fact ADD COLUMN status  TEXT NOT NULL DEFAULT 'active';
ALTER TABLE event_fact     ADD COLUMN stale       INTEGER NOT NULL DEFAULT 0;
ALTER TABLE event_fact     ADD COLUMN chapter_hash TEXT DEFAULT NULL;
```

`tables.dart` 同步加列定义（带 `withDefault`，生成文件由 build_runner 重生成，**勿手改**）。

> 冒险点：`CharacterFact` / `EventFact` 数据类**无任何手工构造点**（全仓检索仅在
> `database.g.dart` 内构造），加默认值列**不会破坏编译**——已核实，无构造点破坏风险。

### 4.2 `CharacterAssertion`（`lib/types/character_types.dart`，JSON 内嵌，**无表迁移**）

新增 5 个可选字段，`tryFromJson` 宽松解析（缺失即默认值，向后兼容存量断言）：

| 字段 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `status` | String | `confirmed` | `confirmed` / `rejected`（D-2，无 pending） |
| `source` | String | `ai` | `ai` / `user`（D-4） |
| `evidence` | String? | `null` | 原文摘录（D-3） |
| `chapterHash` | String? | `null` | 抽取时该章内容指纹（D-6） |
| `stale` | bool | `false` | 旧版标记（D-6） |

> **硬约束（必守，否则 13 处构造点编译失败）**：5 个新字段一律声明为
> **带默认值的可选命名参数**（`this.status = 'confirmed'`），**不得为 `required`**。
> 全仓 `CharacterAssertion(` 构造点 **13 处**（lib 7 + test 6），多数只传 4 个老字段。
> 带默认值 → 13 处零改动；写 `required` → 13 处全崩，且与「向后兼容存量断言」的目标直接冲突。

**两条写入路径的字段归属（实测确认，决定 UI 怎么接）**：

| | AI 断言（诊断抽取） | 用户断言（UI 手动） |
|---|---|---|
| 入口 | 协议 JSON → `tryFromJson` → `upsertCharacter` | UI 直接构造 `CharacterAssertion` |
| `attribute` / `value` | AI 填 | **用户填（纯手动，无 AI 代填）** |
| `evidence` | **AI 填**（读 `json['evidence']`，D-3 新增） | **用户可选填**，可留 `null` |
| `status` / `source` | `confirmed` / `ai` | `confirmed` / **`user`** |
| `chapterHash` | 抽取时该章指纹 | 同（§5.1(c)，手写断言也参与 stale） |

- **⚠️ 5 个新字段在 `tryFromJson` 里是「不对称」的（易错点，务必按此实现）**
  `tryFromJson`（`character_types.dart:41-52`）当前只读 4 个字段。新增后：

  | 字段 | 是否在 `tryFromJson` 读 JSON | 说明 |
  |---|---|---|
  | **`evidence`** | ✅ **必须读** `json['evidence']` | **唯一**一个由 AI 写进协议 JSON 的新字段。不读 → evidence 恒 null → **D-3 整个功能静默失效** |
  | `status` / `source` / `chapterHash` / `stale` | ❌ 不读，由写入路径填值 | AI 不报这四项：`status` 默认 `confirmed`、`source` 由写入方知悉、`chapterHash` 由写入方按章节正文计算、`stale` 由写入方比对 |

  → `tryFromJson` 的改动**只有一处**：加一行 `evidence: json['evidence'] as String?`。
  其余 4 字段靠数据类默认值兜底，解析函数**一行不动**，向后兼容职责不变
  （老 JSON 缺 evidence → `null` → 走 §4.4 降级分支）。
- 因此 UI 侧**不存在「字段级不一致」**：`evidence` 归 AI、UI 只读不写；
  用户输入走 `source: user`，**只填 `attribute`/`value`**，不碰 `evidence`。

### 4.3 章节指纹

新增纯 Dart 的 FNV-1a 32-bit（hex）小工具，放 `lib/data/database/utils.dart`。
**不用 `String.hashCode`**——Dart 的字符串 hash 不保证跨版本/跨 isolate 稳定，
会让存量断言在升级后**集体误判为 stale**。**不引三方库**（`pubspec.yaml` 无 crypto，
且 AGENTS.md 禁止引入未使用的新库）。

### 4.4 `evidence` 采信策略（方案未定义，本批补）

D-3 只说「协议增 evidence 原文摘录」，**没说界面上怎么采信它**。这里有个必须先定的口径：
`evidence` 是 **AI 自报的一段自称摘自正文的文字**——它可能摘录不准，也可能日后章节被改写而失真。
直接无条件展示 = 把 AI 自报内容当原文给用户看，与项目「对用户诚实」的底线冲突。

> **规则出处更正**：子代理曾引用「R-006：不采信 AI 自报位置数据」——**查无此条**。
> R-006 实为《回退机制规范》（快照备份分级），与 evidence 无关。
> 本节策略是**工程判断**，不假托规则（决策档 B：低风险、双侧可逆，故自主决定并报备）。

**采信决策树（三分支）**：

| 情况 | 处置 | 理由 |
|---|---|---|
| `source == user` | **无条件采信** `evidence` | 用户手贴的原文，是自己主权范围内的事（R-009），不校验、不改写 |
| `source == ai` 且 `evidence != null` | **先校验**：`chapterContent.contains(evidence)`；命中 → 采信 | 一次子串判断，成本约 1 行。防止把 AI 幻觉的"原文"当原文展示 |
| 上面校验**未命中**，或 `evidence == null` | **降级** `findKeywordExcerpt(chapterContent, value)` | `value` 通常比 `evidence` 短，反而更易命中；降级路径天然更保守 |
| 降级也失败 | 显示 **「未定位到原文」** | 验收红线 2，**不得假装定位成功** |

- 为什么**不**无条件采信 AI evidence：会向用户展示其正文中可能并不存在的"原文"，
  这是对用户自己稿子的失真，触 R-009。
- 为什么**不**一律改为反查：那等于 D-3 白做——AI 摘录可能跨句、带省略，
  而 `findKeywordExcerpt` 只在**单段落内**子串匹配（`split('\n')` 后逐段 `contains`），
  覆盖不了 AI 能表达的摘录形态。校验命中就采信，是同时保住两边价值的唯一解。
- 校验用的 `chapterContent` = **该断言自己 `chapter` 对应的章节正文**（`getChapterByOrder`），
  **不是当前章**——同 §6 的绑定口径，避免重蹈 §5.3 那个恒 null 的坑。

---

## 5. 服务层方案（批次 2）

### 5.1 stale 语义（D-6/D-8 核心）

**写入路径**（`diagnosis_committer._persistCharacterFacts` / `_persistEventFacts`）：
1. 取当前章节内容 → `currentHash`；
2. 该章所有 `chapterHash != null && != currentHash` 的旧断言 / 旧事件 → 标 `stale`（保留不删）；
3. 新断言带 `chapterHash = currentHash`，`stale = false`，正常叠加。

**两个必须处理的细节（方案未写，本批补）**：
- **(a) 重新确认优先于 stale**：若 AI 改写后重新抽出**同一** `(attribute, value, chapter)`
  三元组，说明该断言改写后仍成立 → **用新断言替换旧的（不标 stale）**，而不是「标旧为 stale、
  新断言又被三元组去重吃掉」——否则会出现「断言仍在却永远灰显」的错误态。
- **(b) 用户裁决优先（R-009）**：三元组命中时，若既有断言是 `status='rejected'` 或
  `source='user'`，**保留既有、丢弃 AI 新断言**——AI 重复抽取不得复活已被用户拒绝的断言，
  也不得覆盖用户手写值。
- **(c) 手动补充的断言同样写入 `chapterHash`**（取该章当前内容指纹）→ 与 AI 断言统一 stale 规则，
  避免「手写断言永不灰显」的双重标准；用户**编辑**断言时清 `stale`（显式重申 = 解除）。

### 5.2 删除/回收站钩子（5 条路径，实测无遗漏）

新增 `lib/services/fact_stale_service.dart`：
- `markChapterStale(manuscriptId, chapterNo)`：该章断言 + 事件同标 stale；
- `clearStaleChapter(manuscriptId, chapterNo)`：删除该章 stale 断言 + stale 事件（**仅用户发起**）。

挂载点（**在仓储方法内部调用**，保证未来新增路径自动继承，且不动
`ChapterRepository(_db)` 构造签名——全仓 435 处构造点（**lib 44 + test 391**，
大头在测试侧），改签名违反 R-010）：

| # | 路径 | 文件:行 |
|---|---|---|
| 1 | `ChapterRepository.deleteChapter`（硬删） | `chapter_repository.dart:290` |
| 2 | `ChapterRepository.softDeleteChapter`（→回收站） | `chapter_repository.dart:160` |
| 3 | `ChapterRepository.purgeChapter`（彻底删除） | `chapter_repository.dart:184` |
| 4 | `VolumeRepository.deleteVolume`（**旁路**，卷内章节批量软删，绕过 1/2/3） | `volume_repository.dart:73`（调用点 `chapter_tree_drawer.dart:518`、`manuscript_detail_volume.dart:188`） |
| — | `restoreChapter`（恢复） | `chapter_repository.dart:172` — **刻意不解除 stale**（D-6，UI 如实标注） |

> **为什么钩子挂在仓储层而不是 UI/Provider 层**（两条实证）：
> ① `deleteVolume` 绕过 `softDeleteChapter` 直接改 SQL；
> ② `ChapterListStore.deleteChapter`（`chapter_providers.dart:244`）当前**零 UI 调用点（死入口）**，
> 但其调用的 `ChapterRepository.deleteChapter`（`:290`）是**活方法**——
> 一旦将来给它接上 UI，挂在 UI 层的钩子会当场漏标。挂在仓储层则未来任何接线自动覆盖。

> 另注：`character_fact` / `event_fact` 的外键挂在 **`manuscript_id`** 上（`tables.dart:512`/`:544`），
> **不是章节** → 删章节对人物/事件事实**零连带影响**，断言会全部孤儿化、永不 stale、
> 继续制造幽灵 F05/F07。这正是本批要消灭的病根，也说明钩子必须覆盖全部删除路径。

> 旁路 #4 是本次侦察**新发现**：`deleteVolume` 直接用 SQL 把卷内章节置 `archived`，
> 不走 `softDeleteChapter`。若只在 UI/Provider 层挂钩子，删卷会整卷漏标。

**标记判据 = 并集（侦察修正，方案未写）**：
`chapterHash == 被删章节的当前内容指纹` **∪** `chapter == 被删章节的 sortOrder`。

- 理由：`CharacterAssertion.chapter` 是 **AI 自报值**——写入路径（`upsertCharacter`）
  **不校验也不覆写**，`tryFromJson` 直接穿透 `json['chapter']`。只按章号匹配，会漏掉
  AI 报错章号的断言；hash 按章节正文指纹计算、与 AI 自报无关，两支取并集才补得上。
- 迁移前的存量断言 `chapterHash == null` → 由「章号」这一支兜底，不会漏。

**章节「改写」不设独立钩子**：`saveChapterContent`（`chapter_repository.dart:198`）
每次键盘输入都可能触发，在其上比对 hash 误伤面极大。改写引起的 stale **只由 §5.1 的
重诊落库时 hash 比对产生**——已覆盖，不另设钩子。

循环依赖自证：`fact_stale_service` → `lib/data/**`（database / character_fact_repository /
event_fact_repository）；`chapter_repository`、`volume_repository` 已在
`lib/data/repositories/` 内，新增 `lib/services/` 依赖与既有惯例一致
（`diagnosis_repository` 已 import `../../services/teaching_state_cache.dart`）。
`circular_baseline.json` 现为空 → 门禁 3 会**全量卡**，本批必须零新增环。

### 5.3 F05 / F07 过滤

- **F05 过滤放在纯函数 `detectCharacterConflicts`（`conflict_detector.dart:51`）内部**——
  只消费 `status == confirmed && !stale`。
  理由：与方案 §4.2 原话一致（「conflict_detector（纯函数）改为只消费…」）；纯函数内实现
  → 任何调用点自动生效；判据可直接单测（测试纪律 4 的三分支落在检测器上）。
  现状 41 行，+2 守卫 = 43 行，**R-019 安全**。

- **⚠️ 别名合并：方案漏掉的一环（本批补）**
  `detectCharacterConflicts` 按**人物名**分组（`conflict_detector.dart:57-60`）。
  `unique(manuscriptId, name)` 下同一人必然存在多行（主名行「林晚晴」+ 别名行「阿晴」），
  直接喂进去会被当作**两个人**，各自内部的矛盾**漏检**——D-1 的别名价值在 F05 侧等于没生效。
  新增纯函数 `lib/services/character_identity.dart`：
  `groupByIdentity(List<CharacterFact>)` → 按「主名 ∪ 别名」的交集判定同一性，
  合并多行断言后再交给检测器；键取主名（合并后的行按 `status='active'` 优先）。
  **同时它也是 D-5 合并前的「候选重复行」发现器**（详情页可提示「疑似同一人」）。

  > **⚠️ 勘误（2026-09-06 批次 2b 读码复核，输出形状必须明确）**
  > `groupByIdentity` 返回**扁平 `List<CharacterFactInput>`，「一行一身份」**——同一身份的
  > 主名行 + 别名行合并成**一个** input，与 `detectCharacterConflicts` 的输入形状
  > **逐字对齐**。判定依据（`conflict_detector.dart:56-83` 实读）：检测器是
  > `for (final character in characters)` 逐角色逐属性处理、**跨行不合并**——若输出保留
  > 多行，同一人的主名行与别名行会被当作**两个独立角色**各自内部检测，
  > **跨行矛盾照样漏检**，D-1 的别名价值在 F05 侧依然落空。
  >
  > 合并后 identity 的 `name` **取主名行**（`status='active'` 优先；无 active 行时取首行），
  > **别名进合并上下文**（`CharacterFact.aliases`）供 §5.4 事件关联用——**不进 `name`**，
  > 否则 §5.4 按「主名 ∪ 别名」匹配 `participants` 时别名侧命中不到。

- **唯一入口 `detectConflictsForFacts(List<CharacterFact>)`（防判据分叉，本批补）**
  `groupByIdentity` 与 `detectCharacterConflicts` **不得暴露给 UI 让调用方自行组合**——
  一旦 UI 侧漏了"先按身份合并"这一环，就会退化成按人物名分组，
  **别名行的矛盾重新漏检**，等于 D-1 在 F05 侧白做。
  → 对外只暴露**两个**共享纯函数（放 `lib/services/character_identity.dart`）：

  ```dart
  /// 判据：身份合并 + F05 检测。**不碰正文**，两个调用方共用，判据不可能分叉。
  List<ConflictObservation> detectConflictsForFacts(List<CharacterFact> facts) =>
      detectCharacterConflicts(groupByIdentity(facts));

  /// 摘录：给观察项填 excerpt。**与判据分离**，调用方各自决定用哪章正文。
  List<ConflictObservation> fillConflictExcerpts(
    List<ConflictObservation> observations,
    String content,
  ) => observations
      .map((o) => ConflictObservation(
            characterName: o.characterName,
            attribute: o.attribute,
            orderedValues: o.orderedValues,
            description: o.description,
            excerpt: findKeywordExcerpt(content, o.orderedValues.first.value),
          ))
      .toList();
  ```

  - **AI 侧**（`message_injector.dart:772-779`，`_injectConflictObservation` 现 48 行）：
    `detectConflictsForFacts(facts)` → `fillConflictExcerpts(raw, chapter.content)`。
    **逐行等价于现 :781-795 的 `.map()`，纯搬移、零行为变更**。
  - **UI 侧**（批次 3 详情页）：**只调 `detectConflictsForFacts`**，不调 `fillConflictExcerpts`
    ——UI 的「查看原文」走断言级 `evidence`（D-3），不需要冲突级 excerpt。
  - 返回 `ConflictObservation`（含判据结果），**不返回分组后的 inputs**——
    避免调用方拿到中间态自行判断。

  > **⚠️ 为什么不能合并成 `detectConflictsForFacts(facts, {required String chapterContent})`**
  > 那是把 AI 侧的**现成错误绑定**固化进共享接口。`findKeywordExcerpt` 的关键词取
  > **`orderedValues.first.value`（最早断言值）**，而 AI 侧喂进去的 `content` 是
  > **当前正在诊断的章节**（:779）——F05 的定义就是「同属性在不同章节有不同值」，
  > 于是「第 3 章『独生子』→ 第 15 章『妹妹』」在诊断第 15 章时，
  > 实际执行的是 `findKeywordExcerpt(第15章正文, "独生子")` → **恒为 null**。
  > 合并成一个函数 = 让 UI 侧也继承这个错误。拆开则两侧各自决定用哪章正文，错误不被扩散。

- **F07**：`EventFactInput`（`event_causality_detector.dart:38`）typedef 加 `bool stale`；
  循环内 `if (event.stale) continue;`（现 31 行，+1 = 32 行，安全）。

  > **⚠️ 连带改动 10 处，不盯死必漏（实测坐实）**
  > Dart 的 **record 类型要求命名字段精确匹配**，`detectCausalityBreaks(List<EventFactInput>)`（:57）
  > 的实参是**无类型标注的字面量、靠参数上下文推断** → typedef 加字段后**全部编译失败**：
  > | 位置 | 处数 | 改动 |
  > |---|---|---|
  > | `message_injector.dart:820-829`（生产侧唯一构造点） | 1 | 加 `stale: e.stale` |
  > | `test/services/event_causality_detector_test.dart` 的 record 字面量 | **9** | 加 `stale: false`（stale 专项用例另写 `true`） |
  > | `:21` 的 `const []` | 1 | 空列表，**无需改** |
  >
  > **⚠️ 勘误（2026-09-06 批次 2b 实点）**：上表第二行的 **9 是 record 字面量「元素」数，
  > 不是调用点数**。原文列举的 `:26,45,59,80,104,132` 是 **6 个调用点**的行号——照它数会
  > 得到 6 处，**差 3 处**（@58 / @79 / @103 三个调用点**各含 2 个元素**）。
  > 元素级行号清单：`:27,46,60,67,81,88,105,112,133`；
  > 分布 = @25×1、@44×1、@58×2、@79×2、@103×2、@131×1。
  > **改的时候按元素改、不按调用点改**，否则每个多元素调用点都会漏掉后几个，
  > 且漏掉的是编译期才炸的 record 字段不匹配。
  > **不采用**「改在调用点 `.where((e) => !e.stale)`」的省事做法：生产侧目前只有 1 个构造点，
  > 但将来新增调用点会**静默漏过滤**、重新长出幽灵 F07——正是本批要根除的同一类 bug。
  > 把 `stale` 写进类型 = 让编译器强制每个构造点表态。

- **判据共用、措辞分家（F05 / F07 同构原则）**
  判据（谁参与检测）必须共用同一份纯函数；措辞（怎么念出来）**不得共用**——
  `buildConflictObservationsContext`（`chat_context_builder.dart:430`）的
  `ConflictObservation.description`（例：第3章「独生子」→ 第15章「妹妹」）是**给 AI 的注入文本**，
  UI 若直接显示会同时踩两个坑：渗进 prompt 工程措辞、prompt 一改 UI 文案跟着变。
  → UI 自渲染人话文案，**只复用判据，不复用 `description`**。

> **F05/F07 必须同批落地**：F05 侧判据来自 JSON 内嵌字段（零迁移），F07 侧 `stale` 是
> **行级表列**（drift 生成的 `EventFact` 当前没有该字段）→ **必须等 v27 迁移 + 重新生成
> `database.g.dart` 之后才能写**。只做 F05 会出现「角色侧消幽灵 F05、事件侧留幽灵 F07」
> 的半套行为（方案 :198 已警告），故两处过滤与迁移作为**同一变更集**落地。

### 5.4 匹配归一化与合并

> **【勘误 3（批次2b 侦察，2026-09-05）】`listCharacters` 是「改造」不是「新增」**
> 原文写「**新增** `CharacterFactRepository` 方法 `listCharacters(msId, {includeMerged})`」，
> 实测该方法**已存在**（`character_fact_repository.dart:144-149`，按 name 排序，
> **无 status 过滤、无 includeMerged 参数**），且已被 `message_injector.dart:771`
> 的 F05 注入路径调用。照「新增」动手会撞**重复定义**。
> → 正解：**改造**现有方法，加 `bool includeMerged = false` 可选参数
> （默认加 `where status != 'merged'`），既有调用点**零改动**自动获得排除语义。
>
> 连带：`groupByIdentity` 的入参契约是「调用方须传 `includeMerged: false` 的结果」。
> 合并后源行断言已拷进目标行，一并喂进来会双重计入——检测器按值去重，纯重复
> 不会凭空造矛盾，但没有理由依赖这个巧合（已写入 `character_identity.dart` 契约注释）。

- 改造 `CharacterFactRepository.listCharacters(msId, {bool includeMerged = false})`
  （默认**排除 `status='merged'`**——否则合并后源行断言会与目标的副本**双重计入 F05**，制造幽灵矛盾）。
- 事件关联：全量 `listEvents` 后内存过滤 `participants` 命中「主名 ∪ 别名」（作品级事件量小，
  几十条，无需 SQL LIKE）。
- 合并 `mergeCharacter(targetId, sourceId)`：事务内 ① 源断言迁移（source 保留原值）→
  ② 源名写入目标 `aliases`（去重）→ ③ 源行 `status='merged'`。

### 5.5 R-019 硬上限预警（本批一定会撞，先列分解预案）

| 函数 | 现状 | 处置 |
|---|---|---|
| `buildFactProtocolContext` | 46 行（445–490），**仅剩 4 行余量** | 格式块抽为私有常量/小构造器（真分解，非 `part` 伪拆分） |
| `fact_validator._parseCharacters` | **正好 50 行**（132–181） | 抽 `_parseOneAssertion`（evidence 读取独立成函数） |
| `CharacterFactRepository.upsertCharacter` | **正好 50 行**（24–73） | stale 逻辑抽 `FactStaleService` + 合并逻辑抽私有方法 |
| `diagnosis_committer._persistCharacterFacts` | 18 行，加 hash/stale 后超限 | 抽 `resolveChapterHash` / `applyStaleBeforeMerge` |
| `message_injector._injectConflictObservation` | **48 行**（756–803） | 搬 `.map()`（:781-795，15 行）为 `fillConflictExcerpts` 纯函数（§5.3）→ ~33 行。**真分解**（提取独立纯函数），非 `part` 伪拆分 |

**禁止**用 `part` / `extension` 机械拆分服务层凑行数（AGENTS.md 明列，批次 X-025-ARCH 已定性伪拆分并回退 13 个 commit）。

---

## 6. UI 层方案（批次 3，入口形态待冲突 A 裁决）

- **列表页**：搜索 + 排序（首见章节 / 最近更新）+ 新建；断言摘要；**合并后源行不出现在列表**
  （`status='merged'` 过滤）。
- **详情页**：断言按属性分组；每条 `[AI]`/`[手]` 来源标记、拒绝 ✗（含可选理由 chips）、
  修正、补充（**纯手动输入，无 AI 代填建议值**——验收红线 R-009）、查看原文、stale 灰显 +
  一键「清除本章旧版断言」；别名标签编辑；相关事件（跳章节）；F05 矛盾提示；「并入主角色」入口。
- **灰显语义必须可辨**（验收红线）：
  - `rejected` → 删除线 + 灰 + `已拒绝` 角标；
  - `stale` → 灰 + `章节已改写` 角标（**无删除线**）——两者**不同义、不同样式**，不得混用一种灰。
- **查看原文诚实降级**：优先 `evidence`；缺失则 `findKeywordExcerpt(value)`
  （`chat_context_builder.dart:385`——**坐标已复核订正**，原稿误写 `:800-845`，
  该区间实为 `buildManuscriptDetailContext` 的 `metaLines` 拼接）反查；
  **两者都失败必须显示「未定位到原文」**，不得假装定位成功。

  > **⚠️ 反查必须用「该断言自己那一章」的正文，不是当前章（原稿漏写，必补）**
  > `findKeywordExcerpt(content, keyword)` 是纯子串匹配，喂错正文就恒 `null`。
  > 正确绑定：`getChapterByOrder(manuscriptId, assertion.chapter)`
  > （`chapter_repository.dart:275`）取该断言所属章节正文 → 再 `findKeywordExcerpt(content, assertion.value)`。
  > **不得**沿用 AI 侧 `message_injector.dart:779` 的写法（拿"当前诊断章"去反查"最早断言值"）
  > ——跨章场景下那是恒 null 的（详见 §9 缺陷登记 D-1）。
  > 边界：`assertion.chapter == null`（AI 未报章号）或取回章节为 null → **直接判「未定位到原文」**，
  > 不做兜底猜测。
- **「最近批次」过滤视图**：按断言 `timestamp` 落库时间过滤，不新增 batch 字段。
- **R-019**：页面按 ≤50 行拆函数；文件超 300 行登记债务（同现有 76 个超限文件）。

> **UI 现状：白纸一张（批次 3 无历史包袱）**
> 全仓 lib 侧 `CharacterFactRepository` 仅 **3 个注入点**（`session_providers.dart:126/152/219`），
> **零消费点**——没有任何既有 UI 读人物事实。
> → 批次 3 是纯粹新建，不存在"改旧 UI 怕踩坏"的风险；
> 且 `characterFactRepositoryProvider` **已装配完毕**（上述 3 处），批 3 直接 `ref.watch` 复用即可，
> **无需再动 provider 装配**。

> **F05 提示的措辞分家（承接 §5.3）**
> 详情页的「F05 矛盾提示」**只调用 `detectConflictsForFacts` 取判据**，
> **UI 自渲染人话文案**，禁止直接显示 `ConflictObservation.description`
> （那是 `buildConflictObservationsContext`（:430）给 AI 的注入文本——
> 含 prompt 工程措辞，且 prompt 一改 UI 文案会跟着变）。
> **禁止** UI 侧自行遍历断言比对——判据必须与 AI 侧同源于一个函数。

> **入口裁决影响范围极小（冲突 A 选 A1 的话）**
> 写作页连 TabBar 都没有（AppBar + 可拖动 FAB + 保存状态条 + PunctuationBar），
> 全仓唯一 TabBar 在 `manuscript_detail_page.dart`（:98 / :265 / :276 / :284）；
> A1 改造**只落 2 处**（:98 加 tab、:284 加 view），
> 且 :237 门控的是「+新建卷」按钮，与角色 tab 无关，不受影响。

---

## 7. 分批切片与提交纪律

### 7.1 回退方案（R-006 L1，**强制，开工前必须执行**）

R-006《回退机制规范》的 trigger 明列「**Skill 注入内容**或 **DB schema 变更**前」，
且 L1 完整备份的适用条件为「涉及 3+ 文件的改动、架构调整、**数据库 schema 变更**、
**Skill 注入内容变更**」——**本批两条全占**（D-3 动注入 prompt + v26→v27 schema 迁移），
enforcement 是「**无回退路径的改动将被阻止**」。故 L1 是**开工前置条件**，不是可选项。

```bash
git checkout -b backup/20260905-角色标签页功能     # 1 建备份分支
bash scripts/gate.sh                              # 2 确认备份点基线可用（已跑：EXIT=0）
git checkout 原分支名                              # 3 切回继续改动
```

**L1 要求记录的 4 项**（写入本节，随 ADR 归档）：

| # | 项 | 记录 |
|---|---|---|
| 1 | 备份时间戳 | 待批次 0 执行时填入（基线已取证：2026-09-05 20:43，六道门禁 EXIT=0） |
| 2 | 涉及文件完整列表 | 见 §附「关键坐标表」；批次 0-4 逐批追加实际改动文件 |
| 3 | 当前基线状态 | ✅ `flutter analyze lib` 通过、✅ 六道门禁 6/6 全绿（EXIT=0）、✅ 2442 用例 0 失败 |
| 4 | 预期改动范围 | 见 §7 批次表（批次 0-4）；**不含** §9.1 缺陷 D-1 的修复 |

- **恢复命令**：`git checkout backup/20260905-角色标签页功能`
- **回退触发条件（量化）**：任一批次 `bash scripts/gate.sh` 退出码非 0 且 30 分钟内未定位；
  或迁移测试出现数据丢失；或 R-019 新增 3 个以上超限函数（说明分解预案失效，需重新设计而非硬拆）。
- **每批次独立可回退**：每批一个 commit（`feat(character): 批次N`）→
  单批回退用 `git revert <hash>`，不必整批作废。

| 批次 | 内容 | commit 前缀 |
|---|---|---|
| 0 | 方案 v1.3 落盘（清理工作树）+ ADR-C78 | `docs(plan)` / `docs(adr)` |
| 1 | 数据层：v27 迁移 + 断言五字段 + 协议 evidence + 指纹工具 + 迁移测试 | `feat(character): 批次1` |
| 2 | 服务层：归一化 + F05/F07 接入 + 合并 + stale 语义 + 5 条回收站钩子 + 批次计数 | `feat(character): 批次2` |
| 3 | UI：列表页 / 详情页 / 入口 tab | `feat(character): 批次3` |
| 4 | 收尾：全量验收 + 台账登记 | `docs(ledger)` |

- 每批一个 commit，消息带批次号；
- 每批结束跑 `bash scripts/gate.sh`（六道全绿）后再提交；
- 每批末尾**追加** `docs/待办执行清单.md`（台账可能被并行会话修改，动手前 `git status` 确认，
  只做末尾追加，不改写既有内容）。

## 8. 测试清单（对应方案 §6.2）

- 迁移：v26→v27 存量库升级（三列补齐 + 数据保留 + 二次打开幂等）；
- 协议解析：evidence 缺失 / 存在 / 空串三分支；
- detector 三判据分支：**rejected 不参与 / stale 不参与**（检测器内判据，直接单测）
  + **别名参与匹配**（`character_identity.groupByIdentity` 合并同人多行后再进检测器，
  单测覆盖「主名行 + 别名行的矛盾能被检出」「两个无关人物不被误合并」）；
- stale：同章改写 → 旧断言 + 旧事件 stale、新断言叠加、F05/F07 均排除、**重新确认不误标 stale**、
  **用户裁决不被 AI 复活**；
- 回收站钩子：**角色 + 事件双侧** × 5 条路径（含删卷旁路）；恢复不自动解除 stale；
- 合并：事务 / 源行软删 / 源名进 aliases / 合并后 F05 不双重计入；
- 两页面 widget 测试。

## 9. 风险登记

| 风险 | 等级 | 对策 |
|---|---|---|
| D-3 动注入 prompt | 🟡 中（低语义） | §2 单列；锚点零漂移验证；有漂移即停 |
| 迁移 v26→v27（三列两表） | 🟡 中 | 幂等守卫 + 存量库升级测试；生成文件不手改 |
| stale 语义改变 F05 既有行为 | 🟢 低（正向） | 消除幽灵矛盾；detector 判据级测试覆盖 |
| 回收站钩子漏路径 | 🟡 中 | 已实测枚举 5 条（含删卷旁路），仓储层内挂载 |
| R-019 顶格函数 | 🟡 中 | §5.5 预列分解方案，真分解不伪拆 |
| 并行会话改台账 | 🟡 中 | 只末尾追加，动手前 `git status` |

### 9.1 顺带发现的存量缺陷（**本批不修**，仅登记）

| # | 缺陷 | 证据 | 处置 |
|---|---|---|---|
| **D-1** | **跨章 F05 的 excerpt 恒为 `null`** → O11「原文摘录」在 F05 侧基本从不生效 | `message_injector.dart:779` 取**当前诊断章**正文，`:786-789` 却用 **`orderedValues.first.value`（最早断言值）** 做关键词。`_byTimeAsc`（`conflict_detector.dart:52`）按章节升序，故「第 3 章『独生子』→ 第 15 章『妹妹』」在诊断第 15 章时 = `findKeywordExcerpt(第15章正文, "独生子")` → `null`。仅当矛盾**同章内**才会命中 | **不在本批改**：属行为变更（会新增 token 注入、改变 AI 输出），且是存量问题非本批引入，改它违反 R-010。本批只做到**不扩散**（§5.3 拆函数，UI 侧不继承该绑定）+ **在 UI 侧用正确绑定**（§6）。**建议后续单开 ADR**（需决策「取最早章正文」还是「两个值各摘一段」） |

> 判别口径：`findKeywordExcerpt` 未命中返回 `null`（`chat_context_builder.dart:397`），
> `_excerptSuffix`（`:420`）遇 null/空返回 `''` → **静默不输出**，不报错、不崩溃。
> 这正是它长期没被发现的原因——**降级得太安静了**。

---

## 附：侦察核实的关键坐标（本批改动落点）

| 项 | 路径:行 |
|---|---|
| `[YS_FACT]` 协议文本 | `lib/services/diagnosis_committer.dart:445`（格式块 458–462） |
| 协议校验 | `lib/services/fact_validator.dart:113`（`_parseCharacters` 132–181） |
| 人物落库 | `lib/services/diagnosis_committer.dart:676`（`_persistCharacterFacts`） |
| 人物 DAO | `lib/data/repositories/character_fact_repository.dart:24`（`upsertCharacter`，正好 50 行） |
| 事件 DAO | `lib/data/repositories/event_fact_repository.dart:16` |
| F05 检测 | `lib/services/conflict_detector.dart:51`（调用点 `message_injector.dart:780`） |
| F07 检测 | `lib/services/event_causality_detector.dart:56`（typedef :38，调用点 `message_injector.dart:831`） |
| 断言类型 | `lib/types/character_types.dart:13`（`tryFromJson` :41） |
| 表定义 | `lib/data/database/tables.dart:506`（CharacterFacts）/ `:538`（EventFacts） |
| schema | `lib/data/database/database.dart:55`（版本）/ `:178`（守卫）/ `:716`（v26 块） |
| 反查兜底 | `lib/services/chat_context_builder.dart:385`（`findKeywordExcerpt`，**未命中返回 `null`**；:397 return null、:420 `_excerptSuffix` 静默降级为 `''`） |
| AI 侧 F05 注入 | `lib/services/message_injector.dart:756`（`_injectConflictObservation`，48 行；:779 取当前章正文、:786 关键词取 `orderedValues.first.value` → §9.1 缺陷 D-1） |
| AI 侧 F07 注入 | `lib/services/message_injector.dart:820`（`inputs` 构造，typedef 加字段后须补 `stale: e.stale`） |
| F05 注入措辞 | `lib/services/chat_context_builder.dart:430`（`buildConflictObservationsContext`——**AI 专用，UI 不得复用**） |
| 按章取正文 | `lib/data/repositories/chapter_repository.dart:275`（`getChapterByOrder`，UI 反查用） |
| UI provider | `lib/providers/session_providers.dart:126/152/219`（`CharacterFactRepository` 已装配，**批 3 直接复用**） |
| 迁移测试模板 | `test/data/database/migration_v24_test.dart:27` |
