"""ADR-0003 判据 9体积红线的可执行检查（阶段一）。

背景
----
ADR-0003 §5 判据 9 原文：「阶段一注入后 diagnosis 组体积实测，**不得回涨到C99 减编前水平**」。

⚠️ **2026-10-05 判据 9 措辞已改写（原措辞不可执行）**：
   原句的「C99 减编前水平」经查 `docs/ADR-C99-diagnosis-skill-pruning.md` §4
   只记「diagnosis 组常驻 tokens 从 ~12k → ~8k」，**没有任何字符数**；
   而本脚本量的是快照 `prompt[*].len`（**整条 system prompt**，当前 5.5万）。
   两者口径差 **4.5 倍**（12,000 vs 54,285）⇒ 照字面判，**注入前就已"超了 4.5 倍"**，
   该判据恒红且无意义。
   ⇒ 改写为：**「不得超本脚本 `REDLINE` 常量」**，并在此把 REDLINE 的来源钉死。
   这是 `DECISIONS §4-155` 的实例：规格里的「不得回涨到 X」若X 是**另一口径的
   估计值**，它只是措辞、不是约束。

红线沿革（红线的每次变更都须有舰长裁定 + 逐键对账）
------------------------------------------------
· 2026-10-05 第一次：舰长裁「不超当前实测 53,907」→ 实测三条新症候索引行
  自动渲染致 54,285（+378）→ 二次请裁 → 「认可增量，基准上移至 54,285」。
· 2026-10-05 第二次（A2/A3 批）：舰长批准五块注入（裁定 2/4/5/6/7），
  预估 +1,058 → **实测 +1,077**（diagnosis 两组同增）⇒ 基准上移至 55,362 /
  53,579。
· 2026-10-05 第三次（判据 8 自查批）：**下调 1 字符**至 55,361 / 53,578。
  ⚠️ **方向是「修缺陷导致的回落」，不是新增预算**
  —— 修 `buildSyndromeIndexContent` 的既有拼接缺陷后，
  diagnosis 两组各**降 1 字符**（数据行末尾与 footer 首行之间补了
  显式换行 ⇒ 少一个重复的 `\n`）。
· 2026-10-05 第四次（判据 8 补修批）：**上调 1 字符**至 55,362 / 53,579。
  方向：补修 **同型第二处接缝**（`footer ↔ADR 块`）——上一批只修了「数据行 ↔ footer」，遗漏下游接缝。
  ⚠️ 本次上调**不是新增预算**，而是修一个**已存在的格式错误**；但纪律不因此放宽：**读数变了红线就贴回实测值**。
· 2026-10-06 第五次（注入源方向冲突批 · 甲-1）：**三条受控组 + 七个对照组全部 +111**
  （diagnosis 55,362→55,473 · p1 53,579→53,690 · force 66,237→66,348；
    beginner 6 组 64,167/64,154/64,022/63,845/65,628/65,628 各 +111 ·
    none_p0 29,812→29,923）。
  方向：甲-1 在 `skill_dispatcher.dart` 的 `_kPromptBoundary` 增加「★ 例外清单优先」
  让位条款（R-027 已批准 · 舰长 2026-10-05「都按你推荐做掉」）。
  ★ **+111 是全域均匀增长** ⇒ 该常量确实进了**每一条** system prompt；
    三张锚点快照实测逐键同为 +111（`skill_prompt_anchor` 44 处 /
    `message_sequence` 18 处），且 `p2_yuesheng_diagnosis` 与
    `p2_yuesheng_diagnosis_fulltext` 的新 fnv **完全同值**（`463a6150125812dc`）
    ⇒ 两个独立观测面互为印证。
  ⚠️ **对照组基线本次必须一并上移**（此前 A2/A3 批刻意不上移，理由是那批实测
    对照组逐个不变；本批它们**确实变了**且变化已验证 ⇒ 不上移会让门禁永久红，
    等于把判据变成装饰）。**区分点**：不是「改动该不该做」，而是「读数有没有变」。

· 2026-10-12 第六次（D1 体积实测治理批 · 舰长「批」批准 D1.5）：
  **受控组 diagnosis 两组各 +572**（55,473→56,045 · 53,690→54,262）、
  **对照组 6 组各 +70、beginner_gentle +91**（64,278→64,369）。
  ⚠️ **方向 = 清偿存量越线，不是新增预算**。这批把「第五次之后本脚本长期假绿」
  的账一次算清（详见 `.ai/reports/2026-10-12-D1-prompt体积实测与预算治理判定.md`）：
  甲-1 之后 7 个改 prompt 的批次重冻了锚点、**无一回跑本脚本**（纪律①无执行点
  ——本脚本不在 gate.sh ⇒ 门禁 18/18 绿也从未跑它）。逐键对账（c3d38668→HEAD）：
  - diagnosis +572 = a04fcf83 −8（断固定夸一句）+ a5ed6f4b −148（撤回裁定 6 实现）
    + 724a6adf +53（正面反馈证据触发）+ 1fe595da +47（取缔 confirmation 固定话术）
    + c6fbfc29 +460（P038）+ d3263e21 +30（P018 扩）+ 4b145aa0 +138（P039）；
  - 对照组 +70 = a04fcf83 −8 + 724a6adf +53 + 4b145aa0 +25（P039 进
    `skills_l1_core_p1` L1 公共分类表 ⇒ 每组公共层同增，实测合理）；
  - beginner_gentle 多出的 +21 = a04fcf83 单独 +13（gentle 口吻配额描述调整，
    同提交其他组 −8 ⇒ 差 21）。
  本次同步把本脚本接入 `scripts/gate.sh`（消灭「硬约束无执行点」形态），
  并登记覆盖缺口：运行时 system 消息注入通道（F07/后续 D2 画像）不经
  skill dispatcher ⇒ **不在本脚本计量面内**，其增量须在触该通道的批次单独实测。

· 2026-10-14 第七次（D-6 协议收敛 + 2a 遗留对齐 · 均为舰长批准）：
  **受控组 diagnosis 两组各 +122**（56,045→56,167 · 54,262→54,384）、
  **force 组 66,348→66,296（下调 52）**、**对照组 7 组各 +26**。
  逐键对账（0761efc2→HEAD，三份快照实测互证）：
  - diagnosis +122 = fa9360c4 +170（D-6 协议收敛五处注入段：输出规范第 4 条 /
    JSON 括注 / 主次排序尾注等）+ b02172b4 −74（舰长基线措辞对齐精简）
    + 3423d0c1 +26（2a 的 skills_l1_core_p2:326 对齐，L1 常驻进所有组）；
  - 对照组 +26 = 3423d0c1 同源（L1 常驻）；D-6 两轮对照组实测逐键为 0
    （协议改动全部落在 diagnosis 组专属的 _kIndexFooter，不在对照组注入面）；
  - force −52：起点勘误——甲-1 贴的 66,348 之后已有批次实际回落至 66,270
    （0761efc2 实测）未贴线（存量漂移），2a +26 ⇒ 66,296。本次重贴为收紧。
  ⚠️ 与前两次「必须上移」同判据：读数确实变了（三份锚点快照互证），不上移
    会让门禁永久红。方向均已获舰长批准（D-6 改协议 + 2a 落实）。

· 2026-10-16 第八次（W-19-B prompt 层注入批 · R-027 舰长批「除了18b都批」）：
  **受控组 diagnosis 两组各 +63**（56,167→56,230 · 54,384→54,454）、
  **对照组与 force 组均 +0**（实测逐键零增长）。
  方向：B 案范围说明一行（报批稿 §二③）进 `_kIndexFooter` 诊断输出规范
  第 4 条末尾（3 空格缩进 + 全文 + 换行 = 63 字符，两键同增同值互证：
  fnv 1a4ee75d…→239760e… / 2c31b291…→1bbde47d…，三份快照实测一致）。
  ⚠️ 勘误登记：报批稿称该副本「从不注入」，锚点实测 `syndrome-diagnosis-index`
  **被注入** diagnosis 组 prompt（len +63 实证）——注入场景下 B 案文案内容
  仍准确（单次路径确实不输出 intervention_value），已写入施工报告诚实边界。

· 2026-10-18 第九次（活性审查 D1 裁7② · R-027 舰长批「都批」）：
  **受控组 diagnosis 两组各 +107**（56,230→56,337 · 54,447→54,554）、
  **对照组与 force 组均 +0**（实测逐键零增长）、l3_entry_anchor 0 处。
  方向：confidence 废除字段降级**注释**两处（`syndrome_kb_content.dart:92`
  协议模板内 + `progressive_diagnosis.dart:377` merge 必填行）——
  §1-20 已废除的模型自报置信度自本批起解析降级可选（缺省 0.0，坏值仍拒）。
  ⚠️ 注释进 prompt 模板即计费面（+107 为两处注释净增，锚点 fnv 三快照互证）；
  本批同时把「必填」改为「可省略」= prompt 对模型的行为要求**收紧**（少要一个
  废除字段），注释是给读代码者的一致性锚。

· 2026-10-20 第十次（治理续批第二批 · 路 α + 形态字段 · R-027 舰长批「都批」）：
  **受控组 diagnosis 两组各 +875**（56,337→57,212 · 54,554→55,429）、
  **对照组 7 组与 force 组均 +0**（实测逐键零增长）。
  方向：**本批 = 新增 prompt 内容**（路 α 让单次链输出 intervention_value +
  形态字段双要素）——⚠️ 与前九次「修缺陷回落/注释澄清」**方向不同**：
  前九次是回落或零语义增量的澄清，本次是**新增两段规范 + 三行字段契约**。
  逐键对账（字符，构成完全可解释）：
  · S3 三判据正文 359 + 标题空行 16 = 375
  · 形态字段段正文 260 + 标题空行 19 = 279
  · JSON 格式块三行（intervention_value / form_fact_count / form_structure）= 198
  · 范围注改写净增（62→80）= 18
  · 小计 870 + 拼接换行 5 = **实测 875**（两键同增同值互证）
  · 对照组 +0：本次改动全部落在 diagnosis 组专属面（`_kIndexFooter`），
    不在对照组注入面 ⇒ 「本批不该动的组确实没动」得证。
  `skillContent.syndrome-diagnosis-index` 同步 +875（5,202→6,077）——
  该 skillContent 即单次链的 L2 索引正文，与 prompt 同源互证。

· 2026-10-24 第十一次（T-20261024-05 批 1 · 四字段进 suffix · 舰长「都批」`§4-248①`）：
  **受控组 3 组 + 对照组 7 组逐键全部 +0** ⇒ **红线常量与对照组基线本次一律不动**
  （按「钉到实测值」口径：实测值未变 ⇒ 维持原值，本次**不产生任何新预算**）。
  方向：`lib/services/chat_service.dart` 的 `kDiagnosisProtocolSuffix` 补
  `reader_impact` / `intervention_value` / `form_fact_count` / `form_structure`
  四字段（**实测 +213 code point**：613→826）。
  ★ **为何逐键 0 变化**：本脚本量的是 `skill_prompt_anchor.json` 的 `prompt[*].len`
  = `buildSystemPromptV2` 产出的 **system prompt**；而该 suffix 只拼在**当轮 user
  消息**上（`diagnosis_injection_service.dart` · ADR-C82）⇒ **根本不在本脚本计量面内**。
  ⇒ 报批稿 §1.1「任何字符级注入都会当场破线」对本次改动**不成立**（该判断隐含
  「注入面 = system prompt」这一前提）；本次的红线一次都没被触发，不是「忘了钉」。
  ★ 该注入面的体积读数落在**另一份快照**：`test/snapshots/message_sequence_anchor.json`
  的 `p2_yuesheng_diagnosis_fulltext[3].len` **1219 → 1432（+213，fnv
  159bca7faec86ef0 → 3a5146a7b4fc0194）**，结构与常量实测 +213 **互为印证**（两个
  独立观测面同值）。
  ⚠️ 登记缺口（不是本批解除项）：**user 侧注入面只有快照漂移断言，没有红线上限**。
  后续批若要给 user 侧设体积上限，须另立读数口径（本批不扩面、不改判据逻辑）。
  ★★ **2026-10-25 该缺口已闭合（U5 裁定 `§4-265`），但名称须订正**：实测该块
  **不是 user 消息，是 role=system 的独立消息**（`message_sequence[...][1]`）；
  role=user 那条是**学员正文**（22 / 1583 字符）。若照「user 侧」这个误称去卡，
  卡住的会是学员正文（3000–4000 字是正常输入，立项书 U1）⇒ 方向反了。
  真名 = **旁路系统注入面**（`buildSystemPromptV2` 之外的 system 消息），
  上限见下方 `BYPASS_REDLINE`，判定函数与上面同一套（`act <= lim`，余量 +0）。

· 2026-10-25 第十四次（U5 裁定 · **新增覆盖面，非新增预算** `§4-265`）：
  **旁路系统注入面首次钉值** —— `p1_yuesheng_diagnosis[1]` / `p2_yuesheng_diagnosis[1]` /
  `p2_yuesheng_diagnosis_fulltext[1]` 各 **9,327**（三例同块，实测等长）。
  ★ 三条受控组与对照组 7 组**一律不动**（本批零 prompt 改动、零 lib 改动）。
  ★ 为何必须钉：B3b 要动的「判据进注入面 / 首筛上限 18-of-39」全部落在这块上，
  而它此前在本脚本计量面外（本脚本只量 `skill_prompt_anchor.json` 的 `prompt[*].len`
  = `buildSystemPromptV2` 产物 = 消息序列 `[0]`）。实测：4 条判据 9,327 →
  18 条按升序取最小 18 **20,992**、按降序取最大 18 **36,065**、39 条全量 **61,388**
  （探针 `tool/probe_user_face_volume.dart`）⇒ 一次批最多可涨 **3.9×**，无人拦。
  ★ 结构自检三条（防「索引漂移后静默量错东西」）：该块 role 必须 system ·
    三例必须等长 · 必须 ≥1000 字符。任一不满足 ⇒ rc=1。
  ⚠️ 覆盖**不完整**（如实声明）：同面另两条 system 消息（148 / 290）只登记读数、
    不钉值 —— 无明确变化来源，钉了是噪声红灯。

· 2026-10-24 第十二次（T-20261024-07 症候命名统一去症 · R-025/R-026 舰长批
  `§4-257` 范围案 A）：**受控组 diagnosis 两组各 −15**（57,212→57,197 ·
  55,429→55,414）、**对照组 7 组与 force 组均 −0**（实测逐键零漂移）。
  方向：`lib/services/syndrome_registry.dart` 39 条记录的 `name`/`shortName`/
  `v1ActionName` 三字段去「症」后缀（带症 31/24/1 条，实测）——**零逻辑改动**，
  派生 6 注入面自动跟随（类型速查表 −31 · 手册技法映射表 −24 ·
  training-templates-index −24 · coaching-actions-v2 −15 · F-block×5 −5 ·
  kChunkSystemPrompt −31，合计 −130；负对照 4 面实测零变化）。
  逐键对账（重冻 diff 22+12 处逐条一致）：
  · diagnosis 两组 −15 = 两组均加载 skill `coaching-actions-v2`（行渲染
    `skill_registry.dart:200` → `skills_training_p4.dart:257`，消费
    `v2ActionName ?? shortName`），该 skill 内容 3846→3831（−15）；
  · training 组 −39（锚点键、非红线键）= coaching-actions-v2 −15 +
    training-templates-index −24（2706→2682；该 skill 仅 training 组加载）；
  · advanced / outline 各 −15（锚点键）= coaching-actions-v2 同源；
  · 对照组 7 组与 force 组 −0：快照 skills 字段实测均**不加载**
    coaching-actions-v2 ⇒ 诊断/训练组专属面之外零触及。
  ⚠️ **本方向 = 删除字符**（每个症名 −1），**不是新增预算**；按「贴实测值、
  不留余量」口径下钉。F-block×5 与 kChunkSystemPrompt −31 **不在本脚本计量面内**
  （前者经 message_injector 走 system 消息、后者为分块诊断系统提示），
  其漂移由 `chat_context_builder_observation_test` 字节级断言等锚点外测试覆盖。

· 2026-10-25 第十三次（B3a 撤销通道可判化批 · 舰长 2026-10-25 00:33「全批」授权
  `§4-263①`）：**受控组 diagnosis 两组各 +410**（57,197→57,607 · 55,414→55,824）、
  **force 组 +0**（66,296 不变）、**对照组 7 组各 +0**（实测逐键零漂移）。
  逐键对账（锚点重冻 diff，构成完全可解释）：
  · `skills_diagnosis_p3.dart`（skill `writing-style`，1,208→1,482，**+274**）
    = ① P017 误判对照行第三列替换（16→148 字符，**+132**）
    + ② P016 新增行（141 字符 + 换行 1 = 142，`''',` 4 字符由上一行移到新行末 ⇒ **净 +138**）
    + ⑤ ①的「标 pending」改写为「仍报 P017（不得因前一问通过而免报）」，**+4**
  · `syndrome_kb_content.dart`（skill `syndrome-diagnosis-index`，6,077→6,213，**+136**）
    = ③ 诊断输出规范第 7 条下新增一行（3 空格缩进 + 全角括号 2 + 正文 119 = 124 字符 + 换行 1）
    + ④ 该行的「输出 uncertain」改写为「不进 syndromes 数组 + 缺证据写自然说明」，**+11**
  · diagnosis 两组 +410 = 274 + 136（两 skill 均在该组注入面内，`skill_layers.dart:80/:84`）；
  · `advanced_p4_yuesheng` / `advanced_sensei` 各 **+274**（锚点键，非红线键）：
    `skill_layers.dart:117` 显示 advanced 组**也**加载 `writing-style`、但**不**加载
    `syndrome-diagnosis-index` ⇒ 只吃到 ①②③⑤，是「改动只落在预期面」的旁证；
  · 对照组 7 组 + force 组 +0：这些组均不加载上述两个 skill ⇒ 「本批不该动的组确实没动」得证。
  ⚠️ `manual_3.dart` 去重 **−126 字符**落在 user 侧首轮判据块（`kSyndromeManualContent`），
    该面**无红线上限**（`§4-263③`）⇒ **不得用于抵扣本批 +410**。
  方向 = 把两条「窗口内不可判的撤销条件」换成「可指认的」——**新增 prompt 内容**
  （与前几次「修缺陷回落 / 澄清性注释」方向不同），已获舰长授权。
  ★★ **本批中途修正一处（主理人核出，施工者确认后改）**：初稿两处新文本要求模型输出
  `uncertain` / `pending`，而**短链 `[YS_DIAGNOSIS]` 协议字段全表里没有这两个字段**
  （实测 19 个字段；它们是**分块链** `ChunkNote.uncertain` / `[YS_REVIEW]` 的概念）
  ⇒ 指令会落空，且落空方向是「不报」= **漏报**。⇒ **不新增协议字段**（那是 L2 协议变更、
  超 B3a 范围），改用短链已有的合法表达：
  · `syndrome_kb_content.dart`：「输出 uncertain …」⇒「该条不得报出（不进 syndromes 数组），
    缺哪类证据写在自然说明部分」（**+11**，计入 ④）；
  · `skills_diagnosis_p3.dart`：「无 ⇒ 标 pending，不得据此不报」⇒「无 ⇒ 仍报 P017
    （不得因前一问通过而免报）」（**+4**，计入 ⑤）。
  ⇒ 红线读数随之由 +395 修正为 **+410**，本沿革与下方常量均按**修正后**实测重贴。

⚠️★ **2026-10-06 实测发现的根因：本脚本可能长期处于「假绿」**（读数纪律升级）
  数据源 = `test/snapshots/skill_prompt_anchor.json`（`:80` `ANCHOR` + `:105`
  `json.load`），**它从不构建 prompt** ⇒ 快照不重冻时读数永远是**上一次重冻时的旧值**。
  ⇒ 甲-1 落地后锚点测试实测 `diagnosis_yuesheng = 55,473`（真实构建），
    而本脚本仍报 `55,362 / 余量 +0` ⇒ **那个「余量 +0」是假的**。
  这是 `.ai/DECISIONS §4-96`（「门禁报无新增 ≠ 本批没欠债」）的又一形态：
  **基线型门禁的 rc 是「相对基线的变化」，不是「当前真实值」。**
  ⇒ **纪律（新增三条）**：
  ① 任何改动 `lib/services/skill_*.dart` / `skill_registry.dart` / 知识库分片 /
     `skill_dispatcher.dart` 内常量的批次，**重冻锚点后必须立刻回跑本脚本**，
     否则它的「余量」毫无意义；
  ② 引用本脚本读数时**必须写明「读的是哪一次重冻的快照」**，
     不许把它当「当前代码的实时体积」；
  ③ 判「某块是否真的进了 prompt」时**以锚点测试的实测漂移为准**
     （它真正经过 prompt 构建），**不以本脚本为准**。

⚠️ **红线必须贴住实测值，不留余量**（2026-10-05 判据 8 自查批实证）：
  若沿用 55,362 / 53,579，红线会比实测**高 1**，
  等于免费送出 1 字符预算 —— 下次有人加 1 个字符，
  门禁照样绿。**判据只有在「恰好贴线」时才具备牙齿**；
  留任何余量都会让判据退化成「小于某个更大的数」。
  ⇒ 纪律：红线变更**无论增减**都要重贴实测值，
  且必须写明方向与理由。

⚠️ **为什么必须做成脚本而不是只写进文档**：
   规格里每个「不得 / 必须 / 恰」都要有一条**能变红**的判据，
   否则它只是措辞。本脚本就是判据 9 的执行体。

口径
----
· 权威数据源 = `test/snapshots/skill_prompt_anchor.json` 的 `prompt[*].len`
  （与 ADR 判据 7 的「skill_prompt_anchor 重冻」同一口径）。
· 单位 = **字符数**。
· ⚠️ **只对 diagnosis 组设红线**，不对全项目最大组设——
  实测training(68,475) / beginner(64,167) 等组在 ADR 阶段一**之前就已超 53,907**
  （HEAD 值即超），拿它当全局红线会让判据一开局就红、且与本批无关。
  真正的判据语义是「**不得回涨**」（相对变化），不是「绝对值须小于某数」。
· **受控组 vs 对照组**：`MUST_NOT_GROW` 是「本批不该动」的组；
  `REDLINE` 是「本批允许增长但有上限」的组。

force 分支的覆盖缺口（A2 批补上）
--------------------------------
`_kDiagnosisSceneFirst` 的注入条件是
`l2Mode == diagnosis || ctx.forceDiagnosisSceneFirst`，而该 flag 由
「用户消息措辞是否触发诊断协议」决定（`chat_service.dart:1255`）、**与 l2Mode 无关**
⇒ 非 diagnosis 组也会注入它。
★ 原 13 个快照用例**全不带**该 flag ⇒ 该路径**零体积基线覆盖**。
A2 批已补 `beginner_p3_yuesheng_forceSceneFirst`（66,237 = 65,628 + 609），
并列入 `REDLINE` 受控（给它上限，而不是当对照组 —— 它本来就该随该块增长）。

用法
----
    python tool/check_prompt_volume.py            # 读数 + 判定
    python tool/check_prompt_volume.py --json     # 机器可读
退出码：0 = 通过；1 = 超红线。
"""

import io
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ANCHOR = os.path.join(ROOT, 'test', 'snapshots', 'skill_prompt_anchor.json')

# 舰长 2026-10-05 裁定的红线（= A2/A3 批落地后的实测值）
REDLINE = {
    # ★ 2026-10-16 第八次重贴实测值（各 +63，逐键对账见头注「红线沿革」
    # 第八次；方向 = W-19-B B 案范围说明一行（舰长批 R-027），不是新增预算）。
    # ★ 2026-10-18 第九次重贴实测值（各 +107：56230→56337 / 54447→54554；
    # 逐键对账 = 本批重冻 diff。方向 = §4-215 裁7② confidence 废除字段降级
    # 注释两处（syndrome_kb_content +107 内 / progressive_diagnosis 合并计入），
    # 舰长批 R-027「都批」——纯注释澄清，非新增预算）。
    # ★ 2026-10-20 第十次重贴实测值（各 +875：56337→57212 / 54554→55429；
    # 方向 = 治理续批第二批「路 α + 形态字段」进**单次链**——
    # ① 诊断输出规范增「干预价值（S3）三判据」段（359 字符正文 + 16 标题空行）
    # ② 增「形态字段（仅量形式症候评定）」段（260 + 19）
    # ③ JSON 格式块增 intervention_value / form_fact_count / form_structure 三行（198）
    # ④ 范围注改写净增 18（62→80）
    # 逐键对账合计 870 + 拼接换行 5 = 实测 875，两键同增同值互证；
    # 对照组 7 组实测 +0（本次改动只在 diagnosis 组专属面 _kIndexFooter）。
    # ⚠️ **本方向 = 新增 prompt 内容**（非「修缺陷回落」）——舰长 2026-10-20
    #   「都批」批准路 α 与形态字段（`DECISIONS §4-227`）；新增预算已获批准。
    # ★ 2026-10-24 第十二次重贴实测值（各 −15：57212→57197 / 55429→55414；
    # 方向 = T-20261024-07 症候命名统一去症（R-025/R-026 舰长批 §4-257 范围案 A），
    # diagnosis 组加载 skill coaching-actions-v2（派生表消费 v2ActionName ?? shortName），
    # 该 skill 内容随 registry 去症 −15 ⇒ 两组同降；逐键对账见头注「红线沿革」第十二次。
    # ⚠️ 本方向 = **删除字符**（非新增预算）：registry 39 条 name/shortName/
    #   v1ActionName 去「症」后缀，派生 6 注入面合计 −130。
    # ★ 2026-10-25 第十三次重贴实测值（diagnosis 两组各 +410：57197→57607 /
    # 55414→55824；force 组实测 +0 故不动；逐键对账见头注「红线沿革」第十三次）。
    # 方向 = B3a「撤销通道可判化」四处 prompt 注入（`skills_diagnosis_p3.dart`
    # P017 第三列替换 +132 + P016 新增行净 +138 + pending→仍报改写 +4
    # = writing-style +274；`syndrome_kb_content.dart` 诊断输出规范第 7 条下
    # 新增一行 +125 + uncertain→不进数组改写 +11 = syndrome-diagnosis-index +136），
    # 舰长 2026-10-25 00:33「全批」授权（`DECISIONS §4-263①`）。
    # ⚠️ 初稿曾要求模型输出 `uncertain` / `pending`——短链协议无此两字段，
    #    已按主理人裁定改用短链既有表达，本值为**修正后**实测。
    # ⚠️ `manual_3.dart` 去重 −126 落在**无红线上限的 user 侧判据块**，
    #   按 `§4-263③` **不得抵扣**本批增量。
    'diagnosis_yuesheng': 57607,
    'diagnosis_p1_yuesheng': 55824,
    # ★ A2 批新增：force=true 用例。609 = _kDiagnosisSceneFirst 全块长度
    # （66,237 − 65,628），是 A2 批实测的「该块在非 diagnosis 组里的真实体积」。
    # 2026-10-06 随甲-1 上移 +111（66,237 → 66,348）。
    # ★ 2026-10-14 重贴 66296：甲-1 后某批已实际回落至 66270 未贴线（存量
    #   漂移，非本批造成），2a 对齐 +26 ⇒ 66296。方向 = 下调收紧，贴实测。
    'beginner_p3_yuesheng_forceSceneFirst': 66296,
}
# 对照组：这些组本批不应增长（beginner 组不涉及新症候）
MUST_NOT_GROW = [
    'beginner_gentle', 'beginner_yuesheng', 'beginner_sensei',
    'beginner_p1_yuesheng', 'beginner_p3_yuesheng', 'beginner_p4_yuesheng',
    'none_p0_yuesheng',
]


def main():
    if not os.path.exists(ANCHOR):
        print('[FAIL] 锚点快照不存在：%s' % ANCHOR)
        print('       先跑 UPDATE_SNAPSHOTS=true flutter test '
              'test/services/skill_prompt_anchor_test.dart')
        return 1

    d = json.load(io.open(ANCHOR, encoding='utf-8'))
    prompt = d.get('prompt')
    if not isinstance(prompt, dict) or not prompt:
        print('[FAIL] 快照里没有 prompt 组 —— 口径变了？先核实再改本脚本')
        return 1

    #正对照：至少能读到若干组，且都带int len
    lens = {k: v.get('len') for k, v in prompt.items()}
    bad = [k for k, v in lens.items() if not isinstance(v, int)]
    if bad:
        print('[FAIL] 这些组缺 int型 len：%s' % bad)
        return 1
    if len(lens) < 5:
        print('[FAIL] 只读到 %d 组 ⇒ 扫描面过窄（正对照未过）' % len(lens))
        return 1

    out = {'redline': REDLINE, 'actual': {}, 'violations': []}

    print('=== 受控组（允许增长·有上限；上限来源：舰长裁定）===')
    for k, lim in sorted(REDLINE.items()):
        act = lens.get(k)
        if act is None:
            print('  %-24s ★快照中无此组' % k)
            out['violations'].append('%s: 快照缺该组' % k)
            continue
        out['actual'][k] = act
        ok = act <= lim
        print('  %-24s %6d  红线 %6d  余量 %+6d  %s'
              % (k, act, lim, lim - act, 'OK' if ok else '★超红线'))
        if not ok:
            out['violations'].append('%s: %d > 红线 %d（超 %d）'
                                     % (k, act, lim, act - lim))

    print('\n=== 对照组（本批不应增长）===')
    for k in MUST_NOT_GROW:
        act = lens.get(k)
        if act is None:
            print('  %-24s ★快照中无此组' % k)
            continue
        # 这些组的红线取「阶段一之前的 HEAD 值」——
        # 用 2026-10-05 实测的 HEAD 读数钉住，避免本脚本自己漂移。
        base = MUST_NOT_GROW_BASE.get(k)
        if base is None:
            print('  %-24s %6d  （无基线，仅读数）' % (k, act))
            continue
        ok = act <= base
        print('  %-24s %6d  基线 %6d  %+6d  %s'
              % (k, act, base, act - base, 'OK' if ok else '★增长'))
        if not ok:
            out['violations'].append('%s: %d > 基线 %d（增长 %d）'
                                     % (k, act, base, act - base))

    # U5（§4-265）：旁路系统注入面 —— 此前零上限，现按实测钉值
    _check_bypass(out)

    if '--json' in sys.argv:
        print('\n' + json.dumps(out, ensure_ascii=False, indent=2))

    print('')
    if out['violations']:
        print('[FAIL] %d 项超限：' % len(out['violations']))
        for v in out['violations']:
            print('  - ' + v)
        return 1
    print('[OK] 受控组均未超红线，且对照组零增长')

# 对照组基线 = **最近一次锚点重冻时的实测值**（读数变了就贴新值，理由见头注）。
#
# ⚠️ 沿革（两种「不上移」的理由必须分开看，否则会误抄）：
#· 2026-10-05 A2/A3 批：**刻意不上移** —— 实测那 6 个 beginner 组 + none_p0
#   **逐个不变**（扩写的 _kDiagnosisSceneFirst 只在 `force=true` 时进非 diagnosis 组，
#   而对照组 6 个用例都没设该 flag）⇒ 上移反而会**放松**对照，属越界。
# · 2026-10-06 甲-1 批：**必须上移** —— 锚点实测七个对照组**每个都 +111**
#   （`_kPromptBoundary` 的让位条款进了每一条 system prompt）
#   ⇒ 不上移会让本脚本下次跑就**永久红**，判据退化成装饰。
#
# ⇒ 区分点不是「改动该不该做」，而是「**读数有没有变**」（§4-159）。
MUST_NOT_GROW_BASE = {
    # ★ 2026-10-14 第七次重贴（7 组各 +26，逐键对账见头注「红线沿革」第七次；
    # 来源 = 3423d0c1 的 skills_l1_core_p2:326 收敛语义对齐——L1 常驻进每组）。
    'beginner_gentle': 64395,
    'beginner_yuesheng': 64361,
    'beginner_sensei': 64229,
    'beginner_p1_yuesheng': 64052,
    'beginner_p3_yuesheng': 65835,
    'beginner_p4_yuesheng': 65835,
    'none_p0_yuesheng': 30019,
}


# ─────────────────────────────────────────────────────────────
# 旁路系统注入面（U5 裁定 · `DECISIONS §4-265`）
#
# ★★ 名称订正：此前各方（含本脚本头注 :131）称之为「**user 侧**注入面」，**实测为误称**。
#   三例诊断快照里该块是 **role=system 的独立消息**（`message_sequence[...][1]`）；
#   role=user 的那条是**学员正文**（22 / 1583 字符）。
#   ⇒ 真名 = **旁路系统注入面** = `buildSystemPromptV2` 之外的 system 消息。
#   ⇒ 若按误称去设上限，卡住的会是**学员正文**（3000–4000 字是正常输入，U1），
#     而不是判据块 —— 方向完全反了。
#
# 覆盖范围（如实声明：**不是全覆盖**）：
#   · 钉值 = 首轮判据块（`buildFirstRoundCriteriaBlock`，B3b 要增长的就是它）；
#   · 同面另两条 system 消息（148 / 290）**只登记读数、不钉值** —— 它们没有明确
#     的变化来源，钉了只会变成噪声性红灯。这是已知的不完整覆盖，不是遗漏。
# ─────────────────────────────────────────────────────────────
MSG_SEQ = os.path.join(ROOT, 'test', 'snapshots', 'message_sequence_anchor.json')

# 键 = `快照名[消息下标]`；值 = 实测字符数（贴实测、余量 +0）。
# 三例同块 ⇒ 三值必须相等，且有结构断言兜底（见 _check_bypass）。
BYPASS_REDLINE = {
    'p1_yuesheng_diagnosis[1]': 9327,
    'p2_yuesheng_diagnosis[1]': 9327,
    'p2_yuesheng_diagnosis_fulltext[1]': 9327,
}


def _resolve_msg(d, key):
    """`case[i]` → 该条消息 dict；解析不到返回 None。"""
    if '[' not in key or not key.endswith(']'):
        return None
    name, idx = key[:-1].split('[')
    seq = d.get(name)
    if not isinstance(seq, list):
        return None
    try:
        i = int(idx)
    except ValueError:
        return None
    if i >= len(seq):
        return None
    return seq[i]


def _check_bypass(out):
    """旁路注入面：逐键比红线 + 三条结构自检（防「索引漂移后静默量错东西」）。"""
    print('\n=== 旁路系统注入面（U5 · 非 buildSystemPromptV2 的 system 消息）===')
    if not os.path.exists(MSG_SEQ):
        # fail-closed：与门禁 18 对缺失快照的口径一致（缺失 = 事故，不是常态）
        print('  ★快照缺失：%s' % MSG_SEQ)
        out['violations'].append('message_sequence 快照缺失 ⇒ 旁路面不可判')
        return
    d = json.load(io.open(MSG_SEQ, encoding='utf-8'))

    seen = {}
    for key, lim in sorted(BYPASS_REDLINE.items()):
        msg = _resolve_msg(d, key)
        if msg is None:
            print('  %-40s ★快照中无此路径' % key)
            out['violations'].append('%s: 快照缺该路径' % key)
            continue
        act = msg.get('len')
        role = msg.get('role')
        if not isinstance(act, int):
            print('  %-40s ★缺 int 型 len' % key)
            out['violations'].append('%s: 缺 int 型 len' % key)
            continue
        seen[key] = act
        out.setdefault('bypass_actual', {})[key] = act
        ok = act <= lim
        print('  %-40s %6d  红线 %6d  余量 %+6d  %s'
              % (key, act, lim, lim - act, 'OK' if ok else '★超红线'))
        if not ok:
            out['violations'].append('%s: %d > 红线 %d（超 %d）'
                                     % (key, act, lim, act - lim))
        # 结构自检①：该块必须是 system（名称订正的依据；若迁到 user 侧即口径变了）
        if role != 'system':
            print('  %-40s ★role=%s（应为 system）' % (key, role))
            out['violations'].append(
                '%s: role=%s 应 system ⇒ 旁路面定义已失效，须先核装配再改本脚本'
                % (key, role))

    # 结构自检②：同一块在三个 case 里必须等长（不等 ⇒ 下标指向了别的东西）
    if len(set(seen.values())) > 1:
        detail = ', '.join('%s=%d' % (k, v) for k, v in sorted(seen.items()))
        print('  ★三例同块长度不一致：%s' % detail)
        out['violations'].append('旁路块三例不等长（%s）⇒ 下标漂移' % detail)

    # 结构自检③：读数下限（防「量到一条近乎空的消息也判绿」）
    for k, v in seen.items():
        if v < 1000:
            print('  %-40s ★%d 字符，低于 1000 下限' % (k, v))
            out['violations'].append('%s: %d 字符低于下限 1000 ⇒ 疑量错对象'
                                     % (k, v))


if __name__ == '__main__':
    sys.exit(main())
