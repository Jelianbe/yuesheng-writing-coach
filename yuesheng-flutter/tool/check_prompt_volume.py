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

· 2026-10-25 第十五次（T-20261024-16 next_focus/next_step 口径统一 · 报批稿
  经 `DECISIONS §4-324`「该批就批」授权范围内）：**受控组 3 组 + 对照组 7 组
  全部 +33**（diagnosis 57,607→57,640 · p1 55,824→55,857 · force
  66,296→66,329；对照组 7 组逐键 +33，none_p0 30,019→30,052）。
  方向：`lib/services/skills_l1_core_p2.dart:123` L1 声明改写——「两者都有且
  不一致时以谁为准」由 `teaching_plan.next_step` 改为 `next_focus`（与
  validator 链 `diagnosis_validator.dart:458-460` 口径一致，`DECISIONS §4-260④`），
  同批改 `lib/services/diagnosis_parser.dart:446` 兼容性策略（`??` 两侧换序）。
  **生产行为零变化**（生产链落 validator 产物，口径本就 next_focus 优先；
  parser 的 rawParse 只进 displayContent 等展示路径，见报批稿 §2.1）。
  逐键对账（锚点重冻 diff 44 处 = 14 prompt 组 ×3 + teaching-strategy ×2）：
  · L1 声明句净增 **+33 字符**（整行含缩进 105 → 138，实测）；
  · skill `teaching-strategy` 11,782→11,815（+33，fnv
    5c5c594679ce3769 → 6daaed20900af35e）——它是 **L1 常驻** ⇒ 进每一条
    system prompt ⇒ 10 组红线/基线键全部同增同值（+33）互证；
  ⚠️ 本方向 = **prompt 文本改写**（净 +33），非修缺陷回落；按「贴实测值、
  不留余量」口径下钉。锚点重冻（`UPDATE_SNAPSHOTS=true` 独立命令）与本红线
  重钉**同批完成**：上方读数是重冻后从快照实测，不是推算。

· 2026-10-26 第十六次（T-20261025-05 批一a · 删 P011/P012 两条例外行 · 舰长
  2026-10-25 00:33「全批」授权 `DECISIONS §4-263`，归类**修正类**（消除互斥）
  而非新增类）：**常量级两键各 −92**（kChunkSystemPrompt 5562→5470 ·
  chunkExceptionGuideBlock 2544→2452）、**kDiagnosisProtocolSuffix +0**
  （977 不变、fnv 亦不变）。**REDLINE 三组 / 对照组 7 组 / BYPASS 三键 /
  USER_FACE 一键全部 +0** —— chunk system prompt 只进分块链
  （`progressive_diagnosis.dart` 的 analyzeChunk），不在 `buildSystemPromptV2`
  产物与 chat_service 消息序列计量面内（6 份快照 grep 实测：chunk prompt
  特征串零命中）。
  逐键对账：两行原文 57 + 33 = 90 字符 + 2 个行尾换行 = **−92**（两键同减
  同值互证：fnv 6964d2b095cc197b→468fb21c18aae951 /
  11cd34270acab7f→342437de83973c2d；`prompt_const_anchor.json` 同批重冻，
  meta exceptionIds 33→31 · exceptionLineCount 33→31 · guideLineCount
  36→34，P033 仍在册）。
  ⚠️ 任务卡 §三 预期值记 5472 / 2454（按 −90 算）——那是把 2 个换行吞进了
  90 里；实测 −92。按卡面纪律以**运行时打印值**为准，预期值不当读数用。
  方向 = **删除字符**（消除同一份 prompt 内「例外」与退化集「片内不可判」的
  互斥身份，卡 §一；非新增预算）。

· 2026-10-26 第十七次（T-20261025-03 B3b-1 · 10 条例外行「须指认」改写 · 舰长已批，
  报批稿 `.ai/reports/2026-10-26-报批稿-B3b1-10条须指认.md` §2，归类**新增类**）：
  **常量级两键各 +88**（kChunkSystemPrompt 5470→5558 ·
  chunkExceptionGuideBlock 2452→2540）、**kDiagnosisProtocolSuffix +0**（977 不变、
  fnv 亦不变）。**REDLINE 三组 / 对照组 7 组 / BYPASS 三键 / USER_FACE 一键全部 +0**
  —— chunk system prompt 只进分块链（`progressive_diagnosis.dart:1355` 的
  analyzeChunk），不在 `buildSystemPromptV2` 产物与 chat_service 消息序列计量面内
  （6 份快照实测：含 `Chunk` 键名的仅 `prompt_const_anchor.json`；例外表正文
  `例外情况指引` / `上面未列出的症候` 在 6 份快照里 **0 命中** —— 钉的是 len+fnv
  指纹，不是文本，故「只 grep 正文」会误判为无影响）。
  逐键对账（10 条 old→new，不含换行）：P008 82→82 (+0) · P023 82→77 (−5) ·
  P024 77→87 (+10) · P025 72→100 (+28) · P026 76→70 (−6) · P027 51→69 (+18) ·
  P028 89→103 (+14) · P030 68→75 (+7) · P031 71→82 (+11) · P038 81→92 (+11)
  ⇒ 10 条合计 749→837 = **+88**，与两键实测 Δ 逐位一致。
  两键同增同值互证：fnv 468fb21c18aae951→7335b37c4e8212d4 /
  342437de83973c2d→4be0415a38d9f824（`$_kChunkExceptionGuide` 在装配式
  `progressive_diagnosis.dart:580` 只出现 1 次）。
  meta 三值不变：exceptionIds 31 · exceptionLineCount 31 · guideLineCount 34
  （10 条均为原位单行替换，行数不动）。
  ⚠️ 报批稿 §2 合计行写「old 752 / new 840」——按其自身逐条值相加应为 749 / 837
  （两行各多算 3、方向相同 ⇒ Δ +88 不受影响）；一律以写模式运行时打印为准。
  方向 = **新增字符**（例外由「场景清单」改为「须指认 + 指不出即不成立」，使豁免
  附带可核位置；净增 88 落在批一a 释放的 92 额度内，且新值 2540 仍低于批一a
  之前的在产实测 2544 ⇒ 未越过任何历史在产水平）。

· 2026-10-26 第十八次（T-20261025-22 P003 原理落实 · 舰长已批，报批稿
  `.ai/reports/2026-10-26-报批稿-T22-P003原理落实.md` §2，归类**新增类**）：
  **常量级两键各 +196**（kChunkSystemPrompt 5558→5754 ·
  chunkExceptionGuideBlock 2540→2736）、**kDiagnosisProtocolSuffix +0**（977 不变、
  fnv 亦不变）。**REDLINE 三组 / 对照组 7 组 / BYPASS 三键 / USER_FACE 一键全部 +0**
  —— chunk system prompt 只进分块链（`progressive_diagnosis.dart` 的 analyzeChunk），
  不在 `buildSystemPromptV2` 产物与 chat_service 消息序列计量面内。
  逐键对账（单行换行前后不计）：`:409` old 115 字符 → new 311 字符 = **+196**，
  与两键实测 Δ 逐位一致（2540+196=2736 / 5558+196=5754，取自重冻写模式运行时
  打印值，非预估）。
  两键同增同值互证：fnv 7335b37c4e8212d4→764eb55cd9730fc9 /
  4be0415a38d9f824→b6b1a9f4eb405fd（`$_kChunkExceptionGuide` 在装配式
  `progressive_diagnosis.dart:580` 只出现 1 次，两侧分隔符固定）。
  meta 三值不变：exceptionIds 31 · exceptionLineCount 31 · guideLineCount 34
  （原位单行替换，行数 1456 → 1456 不变；★ 口径：只认 `wc -l` / `awk END{print NR}`，勿用语言层 `split('\n')` —— 末行有换行时会多算一个空尾元素，本项目已踩过一次）。
  ⚠️ **本批是真实提额，不是额度回收**：guide new 2736 越过历史在产峰值 2544
  （+192）；Δ +196 亦超 B3b-1 §6 的 92 额度上限（超上端 104）⇒ 已按报批稿 §3.3
  重新裁定后施工。
  ⚠️ **提额在门禁上不响**：`CONST_REDLINE` 无 `pin == actual` 断言 ⇒ 钉表被放宽
  1 时 violations 仍为 0。本批靠 T11 人工核对 + 逐键对账兜底；缺口由
  `T-20261026-01` 跟踪。
  方向 = **新增字符**（例外行由「场景清单」改为「首问置顶 + 三原理须指认 + 指不出
  即不成立 + 有标记/本窗全知仍困惑则仍判漂移」，把手册 `:221`/`:223` 三原理投影
  进分块链，消除两链路判据分叉；零新增症候、零题材词、行数不动）。

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

常量级 prompt 体积读数面（T-20261025-03 §二 · B3b-0）
-----------------------------------------------------
上面所有段落量的都是 `buildSystemPromptV2` 的产物与消息序列。**以下三块常量
一份快照都没覆盖**，本段补上（数据源 = `test/snapshots/prompt_const_anchor.json`，
由 `test/services/prompt_const_anchor_test.dart` 运行时生成，非源码正则）：

· `kChunkSystemPrompt` —— >4000 字文本走的分块链 system prompt
  （`progressive_diagnosis.dart:589`）。此前 `test/` 对它只有「症候 ID 覆盖 /
  子串存在」断言，**零体积断言** ⇒ 任何增长无拦截。
· `chunkExceptionGuideBlock` —— 上者内嵌的例外指引表（库私有
  `_kChunkExceptionGuide`，同文件 `:406`）。**B3b-1 要改的就是它。**
· `kDiagnosisProtocolSuffix` —— 拼在诊断轮次**旁路 system 消息**上的协议文本
  （`chat_service.dart:227`；`T-20261024-13` 缺口 1 的对象）。

**本段覆盖什么**：这三块常量的**字符数与字节指纹（FNV-1a 64）**是否变化、
是否超上限。等价于「体积与字节未变」这一条可判读。

★ 订正前方沿革：2026-10-24 第十二次条曾记「`kChunkSystemPrompt` −31 **不在本
脚本计量面内**」——那是**该批时的状态**。自本段起它已被覆盖，该句不再是当前事实，
但**保留原文不改**（沿革条目记的是当批读数，改了就成了伪史）。

**本段不覆盖什么**（如实声明）：
· 分块链的**行为**完全没有读数 —— 分块链 >4000 字真实语料实测 **0 条**
  （`T-20261025-03` §五 ①）⇒ 「例外表变长了」不等于「模型判得更准」；
· 不在计量面内的其它 prompt 常量（F-block×5、`manual_*.dart` 手册正文、
  `message_injector` 运行时注入段）仍无上限；
· 本段只证明静态度量，不证明「该常量真的被发送到模型」（生效性由
  `progressive_chunk_syndrome_coverage_test` 的接线断言负责）。

⚠️ **重冻纪律**：`prompt_const_anchor.json` 不重冻 ⇒ 本段读数恒为上次重冻时的
旧值（本脚本历史假绿即此形态，见上方 2026-10-06 条）。重冻后**必须**同步重钉
下方 `CONST_REDLINE` 并登记 `DECISIONS` 归因 —— 只重冻不重钉 ⇒ 红线变装饰。

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
    # ★ 2026-10-25 第十五次重贴实测值（三键各 +33：57607→57640 / 55824→55857 /
    # 66296→66329；逐键对账见头注「红线沿革」第十五次）。
    # 方向 = T-20261024-16 L1 声明改写（skills_l1_core_p2.dart:123，净 +33
    # 字符）——teaching-strategy 是 L1 常驻，进每条 system prompt，
    # 故受控三组与对照组 7 组同增同值互证。
    'diagnosis_yuesheng': 57640,
    'diagnosis_p1_yuesheng': 55857,
    # ★ A2 批新增：force=true 用例。609 = _kDiagnosisSceneFirst 全块长度
    # （66,237 − 65,628），是 A2 批实测的「该块在非 diagnosis 组里的真实体积」。
    # 2026-10-06 随甲-1 上移 +111（66,237 → 66,348）。
    # ★ 2026-10-14 重贴 66296：甲-1 后某批已实际回落至 66270 未贴线（存量
    #   漂移，非本批造成），2a 对齐 +26 ⇒ 66296。方向 = 下调收紧，贴实测。
    # ★ 2026-10-25 第十五次重贴 66329：T-20261024-16 L1 声明改写（L1 常驻
    #   进每组，净 +33），逐键对账见头注「红线沿革」第十五次。
    'beginner_p3_yuesheng_forceSceneFirst': 66329,
}
# 对照组：这些组本批不应增长（beginner 组不涉及新症候）
MUST_NOT_GROW = [
    'beginner_gentle', 'beginner_yuesheng', 'beginner_sensei',
    'beginner_p1_yuesheng', 'beginner_p3_yuesheng', 'beginner_p4_yuesheng',
    'none_p0_yuesheng',
]


def _pin_verdict(out, key, act, lim, word):
    """体积红线/上限的**两道**判据：① 超限（act > lim）② 钉表脱钩（act != lim）。

    ★ 为什么必须两条、且必须分开报（T-20261026-01 · pin == actual）
      旧判据只有 `act <= lim` ⇒ 把上限**抬到实测值之上**（1583 → 1584）时
      **rc=0 且打印「余量 +1 OK」**（柯有据 M6 实测，主理人独立复现）
      ⇒ 红线变成「可协商」，「重冻 ⇒ 同批重钉」这条联动失去牙齿。
      两个方向的病因**相反**，合成一句话就归因不了（§4-296 同族教训）：
        act > lim = 内容涨了、没重钉
        act < lim = 上限被抬高了 / 未贴实测（§4-159「贴实测不留余量」）

    ★ 为什么现在加不会假红：三张表实测 **17 项余量全 +0**
      （`python tool/check_prompt_volume.py`，2026-10-28）⇒ 等式与旧判据等价。

    返回 (ok, tag)：ok 保持旧语义（未超限）；tag 用于打印，区分三态。
    """
    if act > lim:
        out['violations'].append('%s: %d > %s %d（超 %d）'
                                 % (key, act, word, lim, act - lim))
        return False, '★超%s' % word
    if act < lim:
        out['violations'].append(
            '%s: 上限 %d ≠ 实测 %d（余量 %+d）⇒ 钉表与实测脱钩：'
            '抬线或未重钉（pin==actual，T-20261026-01）'
            % (key, lim, act, lim - act))
        return True, '★%s≠实测' % word
    return True, 'OK'


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
        _, tag = _pin_verdict(out, k, act, lim, '红线')
        print('  %-24s %6d  红线 %6d  余量 %+6d  %s'
              % (k, act, lim, lim - act, tag))

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

    # T-20261025-03 §二（B3b-0）：buildSystemPromptV2 之外的常量 —— 分块链 +
    # 例外表 + 协议 suffix。数据源是独立快照（运行时切片，非源码正则）。
    _check_consts(out)

    # T-20261024-13 缺口 1：注入后的 user 消息面 —— 有指纹、此前无上限。
    _check_user_face(out)
    # ADR-0009：整条只作松上限；**主量**在这里（按段）。
    _check_user_face_segments(out)

    # A 块 Q1（报批稿 2026-10-25）：覆盖扫描 —— 以快照为遍历面，反查
    # 「有 injection 却无上限 / 无 injection 却乱钉」。_check_user_face 只遍历
    # 钉表键，看不见钉表外的 user 消息；本调用补这个方向（仍在本道内，不加道数）。
    _check_user_face_coverage(out)

    if '--json' in sys.argv:
        print('\n' + json.dumps(out, ensure_ascii=False, indent=2))

    print('')
    if out['violations']:
        # 文案刻意不用「超限」：violations 里混着四类病因（超限 / 上限≠实测 /
        # fnv 不符 / 结构自检），只用「超限」会把「上限被抬高」也报成「超限」——
        # 那是**方向相反**的误归因（T-20261026-01 加牙时一并订正）。
        print('[FAIL] %d 项不合规（超限 / 上限≠实测 / 指纹不符 / 结构自检）：'
              % len(out['violations']))
        for v in out['violations']:
            print('  - ' + v)
        return 1
    print('[OK] 受控组均未超红线、钉表与实测逐项相等，且对照组零增长')

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
    # ★ 2026-10-25 第十五次重贴（7 组各 +33，与 REDLINE 三键同值互证；
    # 来源 = T-20261024-16 skills_l1_core_p2.dart:123 L1 声明改写——
    # L1 常驻进每组，整行含缩进 105→138 字符）。逐键对账见头注第十五次。
    'beginner_gentle': 64428,
    'beginner_yuesheng': 64394,
    'beginner_sensei': 64262,
    'beginner_p1_yuesheng': 64085,
    'beginner_p3_yuesheng': 65868,
    'beginner_p4_yuesheng': 65868,
    'none_p0_yuesheng': 30052,
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

# 五段读数的独立快照（ADR-0009 · T-20261024-13 A 块）。
# 不塞进 message_sequence_anchor.json：那份的顶层键集合受「双向键集合判据」
# 看守，加新键要动 fail-closed 判据 ⇒ 另立文件，零改动旧判据。
MSG_SEQ_SEGMENTS = os.path.join(
    ROOT, 'test', 'snapshots', 'injection_segments_anchor.json')

# 键 = `快照名[消息下标]`；值 = 实测字符数（贴实测、余量 +0）。
# 三例同块 ⇒ 三值必须相等，且有结构断言兜底（见 _check_bypass）。
#
# ★ 2026-10-28 第二十二次重贴实测值（`T-20261027-01` H11 B+C · `DECISIONS §4-359`）：
#   9,327 → **9,397**（三例同 Δ **+70**），fnv `66bcfe33cd8df033` → `51e1c8edabd233fa`。
#   来源：手册 P003 词条正文（`syndrome_kb_content_manual_1.dart:223`）单行内两处改动 ——
#   删「章节标题」（短链只注入 `chapter.content`，标题是独立列 ⇒ 无从观测的豁免）+
#   给「与此同时/而另一边」加**可辨感知者**限定（消除与 `:207` 交叉剪辑判据的同词互斥）。
#   同批：`l3_entry_anchor.json` 的 `syndrome.P003` 2,634 → 2,704（同一 +70）。
#   本表只钉 len（不钉 fnv）；fnv 差异由 `message_sequence_anchor.json` 看守。
BYPASS_REDLINE = {
    'p1_yuesheng_diagnosis[1]': 9397,
    'p2_yuesheng_diagnosis[1]': 9397,
    'p2_yuesheng_diagnosis_fulltext[1]': 9397,
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
        _, tag = _pin_verdict(out, key, act, lim, '红线')
        print('  %-40s %6d  红线 %6d  余量 %+6d  %s'
              % (key, act, lim, lim - act, tag))
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


# ─────────────────────────────────────────────────────────────
# 常量级 prompt 体积（T-20261025-03 §二 · B3b-0 · L0 读数面）
#
# 覆盖范围与不覆盖范围见模块头注「常量级 prompt 体积读数面」段。
# 数据源 = 独立快照，由 `test/services/prompt_const_anchor_test.dart` 在**运行时**
# 从 `kChunkSystemPrompt` 里切片生成 —— 不读源码文件做正则（源码文本 ≠ 运行时
# 注入字节，两者会在生成代码 / 转义变化时分家）。
# ─────────────────────────────────────────────────────────────
CONST_ANCHOR = os.path.join(ROOT, 'test', 'snapshots', 'prompt_const_anchor.json')

# 键 → (len 上限, 冻结时的 fnv)。**贴实测、余量 +0**。
# 沿革：2026-10-25 首次钉值（B3b-0，本批零 prompt 改动 —— 三值均为 HEAD 实测，
#       不是新增预算）。逐值来源 = `UPDATE_SNAPSHOTS=true flutter test
#       test/services/prompt_const_anchor_test.dart` 的写模式输出：
#         kChunkSystemPrompt        len=5562 fnv=6964d2b095cc197b
#         chunkExceptionGuideBlock  len=2544 fnv=11cd34270acab7f
#         kDiagnosisProtocolSuffix  len=977  fnv=609c7814d5bcc86d
#       ⚠️ 任务卡事实表称 suffix 为 1,157 字符，**实测为 977**（两路独立测量：
#          Dart 运行时 `String.length` + 源码字面量拼接解析，均 977；git 史
#          613 → 826 → 977 三档，从未出现 1,157）⇒ 以实测钉值，卡内数字待订正。
# ★ 2026-10-26 第十六次重贴实测值（kChunkSystemPrompt 5562→5470 −92 ·
#    chunkExceptionGuideBlock 2544→2452 −92；suffix 977 不动）：
#    方向 = T-20261025-05 批一a 删 P011/P012 两条例外行（`_kChunkExceptionGuide`，
#    舰长 2026-10-25 00:33「全批」授权 `DECISIONS §4-263`，修正类）——57+33=90
#    字符 + 2 换行 = −92，两键同减同值互证；逐键对账见头注「红线沿革」第十六次。
#    ⚠️ 卡 §三 预期 5472/2454（按 −90 算）吞了 2 个换行，以运行时打印 −92 为准。
# ★ 2026-10-26 第十七次重贴实测值（kChunkSystemPrompt 5470→5558 +88 ·
#    chunkExceptionGuideBlock 2452→2540 +88；suffix 977 不动）：
#    方向 = T-20261025-03 B3b-1「10 条须指认改写」（`_kChunkExceptionGuide`，
#    舰长已批 · 报批稿 `.ai/reports/2026-10-26-报批稿-B3b1-10条须指认.md` §2），
#    归类**新增类**：10 条例外行由「场景清单」改为「须指认 + 指不出即不成立」。
#    两键同增同值互证（装配式 `$_kChunkExceptionGuide` 在
#    `progressive_diagnosis.dart:580` 只出现 1 次，两侧分隔符固定）。
#    逐键对账（old→new，不含换行）：P008 82→82 (+0) · P023 82→77 (−5) ·
#    P024 77→87 (+10) · P025 72→100 (+28) · P026 76→70 (−6) · P027 51→69 (+18) ·
#    P028 89→103 (+14) · P030 68→75 (+7) · P031 71→82 (+11) · P038 81→92 (+11)
#    ⇒ 10 条合计 749→837 = **+88**，与两键实测 Δ 逐位一致。
#    ⚠️ 报批稿 §2 合计行写「old 752 / new 840」，按其自身逐条值相加应为
#    749 / 837（两行各多算 3，方向相同 ⇒ Δ +88 不受影响）；以运行时打印为准。
#    ⚠️ meta 三值不变：exceptionIds 31 · exceptionLineCount 31 · guideLineCount 34
#    （10 条均为原位单行替换，行数不动）。
# ★ 2026-10-26 第十八次重贴实测值（kChunkSystemPrompt 5558→5754 +196 ·
#    chunkExceptionGuideBlock 2540→2736 +196；suffix 977 不动）：
#    方向 = T-20261025-22 P003 原理落实（`:409` 单行，舰长已批 · 报批稿
#    `.ai/reports/2026-10-26-报批稿-T22-P003原理落实.md` §2），归类**新增类**：
#    例外行由「场景清单」改为「首问置顶 + 三原理须指认 + 指不出即不成立 +
#    有标记/本窗全知仍困惑则仍判漂移」，把手册 `:221`/`:223` 三原理投影进分块链。
#    两键同增同值互证（装配式 `$_kChunkExceptionGuide` 在
#    `progressive_diagnosis.dart:580` 只出现 1 次，两侧分隔符固定）。
#    逐键对账：`:409` old 115 字符 → new 311 字符 = **+196**，与两键实测 Δ 逐位一致。
#    ⚠️ fnv 照抄运行时打印串（`toRadixString(16)` **不补零**）⇒
#    chunkExceptionGuideBlock 打印 15 位 `b6b1a9f4eb405fd`
#    （真值 0x0b6b1a9f4eb405fd）；补零会让 fnv 比对恒红。
#    ⚠️ meta 三值不变：exceptionIds 31 · exceptionLineCount 31 · guideLineCount 34
#    （原位单行替换，行数不动）。
# ★ 2026-10-27 第二十次重贴实测值（kChunkSystemPrompt 5754→5785 +31 ·
#    chunkExceptionGuideBlock 2736→2767 +31；suffix 977 不动）：
#    方向 = T-20261026-01 T22 补遗 **裁定 B：回滚为甲**（舰长裁定 · 报批稿 §2.7 ·
#    `DECISIONS §4-343`）：方案乙 11 字「（该差异须为实质差异）」撤回，E1–E4 保留。
#    归类**新增类**：E1 首问绑「本窗正文中的感知来源句」· E2 ①改正向列举
#    （统摄性叙述句）· E3 回退句去「感知中心」「撞位」两个未定义谓词 ·
#    E4 删「章节标题/段落分隔」两个假凭据并把锁换成「切换前后各自的感知者且二者
#    不同」。
#    乙 未采用（撤回）：两份独立判定均指向负收益（判据结构=不可判 / 教学法=负收益，
#    见 §2.7；`DECISIONS §4-343`）。**「堵空档」的说法作废** —— 该空档未堵。
#    逐键对账：`:409` 311 字符 → 342 字符 = **+31**，与两键实测 Δ 逐位一致。
#    Δ 分解（逐处复算）：E1 +14 · E2 +11 · E3 +4 · E4 +2 = **+31**（乙 +11 = 已撤回）。
#    报批稿另有一版四段式（+14/+11/+4/+13）= 把 E4(+2) 与乙(+11) 合并计，
#    同量不同分组，非矛盾 —— **乙已撤回，该分组随之作废，仅存档**。
#    两键同增同值互证（装配式 `$_kChunkExceptionGuide` 在
#    `progressive_diagnosis.dart:580` 只出现 1 次，两侧分隔符固定）。
#    ⚠️ fnv 照抄运行时打印串（`toRadixString(16)` **不补零**）：本次 chunk 为 16 位，
#    guide 打印 **15 位** `7d632f716a1ea36`（真值 0x0d632f716a1ea36）——
#    **抄写时严禁补零**，补零会让 fnv 比对恒红（十九次的 `b6b1a9f4eb405fd` 即同型）。
#    ⚠️ meta 三值不变：exceptionIds 31 · exceptionLineCount 31 · guideLineCount 34
#    （原位单行替换，行数 1456 → 1456 不变；★ 口径：只认 `wc -l` / `awk END{print NR}`，勿用语言层 `split('\n')` —— 末行有换行时会多算一个空尾元素，本项目已踩过一次）。
#    ⚠️ **相对上一版是回收，相对批一a 之前的 2544 仍是提额**：guide new 2767
#    比上一版 2736 低 11（乙撤回），但比在产峰值 2544 高 223 ⇒ 两种口径要分清。
# ★ 2026-10-28 第二十一次重贴实测值（kChunkSystemPrompt 5785→5849 +64 ·
#    chunkExceptionGuideBlock 2767→2831 +64；suffix 977 不动）：
#    方向 = `T-20261027-01` **H4-A**（舰长「按你推荐走就行，都批」· 报批稿
#    `.ai/reports/2026-10-28-报批稿-H4-③强制两条锚定引文.md` §2 · `DECISIONS §4-358`）：
#    ③ 由「须指认切换前后各自的感知者且二者不同」升级为「**须在本窗正文中逐字
#    摘引两条句子**（切换前一条 / 切换后一条；不得同句、不得取自引号内人物台词），
#    再分别指出各自感知者」⇒ 新增四项**可锚定化**要求（两条句子 / 前后各一 /
#    不同句 / 非台词），**不新增任何豁免**。
#    归类**新增类**：`:409` old 342 字符 → new 406 字符 = **+64**，
#    与两键实测 Δ 逐位一致（2767+64=2831 / 5785+64=5849，取自重冻写模式运行时打印值）。
#    两键同增同值互证（装配式 `$_kChunkExceptionGuide` 在
#    `progressive_diagnosis.dart:580` 只出现 1 次，两侧分隔符固定）。
#    ⚠️ fnv 照抄运行时打印串（`toRadixString(16)` **不补零**）：本次两键**均为 16 位**
#    （chunk `670a18da88bcb786` / guide `257abc1bd89b48ec`）⇒ 补零或截断都会让比对恒红。
#    ⚠️ meta 三值不变：exceptionIds 31 · exceptionLineCount 31 · guideLineCount 34
#    （原位单行替换）。
#    ⚠️ **本批是真实提额**：guide new 2831 越过在产峰值 2767（+64），比批一a 之前的
#    2544 高 287 ⇒ 不得写成「额度回收」。
#    ★ 沿革记账位置：常量级重钉（第十九次起）只记在**本段**；表头那份「红线沿革」
#    列表停更在第十八次 —— 引用沿革序号时以本段为真源。
CONST_REDLINE = {
    'kChunkSystemPrompt': (5849, '670a18da88bcb786'),
    'chunkExceptionGuideBlock': (2831, '257abc1bd89b48ec'),
    'kDiagnosisProtocolSuffix': (977, '609c7814d5bcc86d'),
}

# 下限自检：读数低于此值 ⇒ 疑量到空串 / 别的对象（不是「省了字」）。
# 依据：kChunkSystemPrompt 含症候清单 + 五块常量；例外表实测 2,767（33 条例外行）。
# （2026-10-28 刷新：旧值 2,544 停在批一a 之前；现值取自 CONST_REDLINE 同一份脚本输出，
#   不手填 —— T-20261026-01 附带项②。）
CONST_FLOOR = {
    'kChunkSystemPrompt': 3000,
    'chunkExceptionGuideBlock': 2000,
}


def _check_consts(out):
    """常量级体积：逐键比上限 + 比字节指纹 + 下限自检。"""
    print('\n=== 常量级 prompt 体积（buildSystemPromptV2 之外 · B3b-0）===')
    if not os.path.exists(CONST_ANCHOR):
        # fail-closed：与 _check_bypass 对缺失快照的口径一致（缺失 = 事故，不是常态）
        print('  ★快照缺失：%s' % CONST_ANCHOR)
        print('     先跑 UPDATE_SNAPSHOTS=true flutter test '
              'test/services/prompt_const_anchor_test.dart')
        out['violations'].append(
            'prompt_const_anchor 快照缺失 ⇒ 常量级读数面不可判')
        return
    d = json.load(io.open(CONST_ANCHOR, encoding='utf-8'))

    for key in sorted(CONST_REDLINE):
        lim, fnv_frozen = CONST_REDLINE[key]
        node = d.get(key)
        if not isinstance(node, dict):
            print('  %-26s ★快照中无此键' % key)
            out['violations'].append('%s: 快照缺该键' % key)
            continue
        act = node.get('len')
        fnv = node.get('fnv')
        if not isinstance(act, int):
            print('  %-26s ★缺 int 型 len（实际 %r）' % (key, act))
            out['violations'].append('%s: 缺 int 型 len（%r）' % (key, act))
            continue
        out.setdefault('const_actual', {})[key] = act
        _, tag = _pin_verdict(out, key, act, lim, '上限')
        print('  %-26s %6d  上限 %6d  余量 %+6d  %s'
              % (key, act, lim, lim - act, tag))
        # fnv 一条专治「等长替换」与「重冻快照但没重钉上限」
        # —— 只比 len 的话，删 3 字加 3 字就能静默过关。
        if fnv != fnv_frozen:
            print('  %-26s ★fnv %s ≠ 冻结 %s' % (key, fnv, fnv_frozen))
            out['violations'].append(
                '%s: fnv %s ≠ 冻结 %s ⇒ 字节变了（等长替换或重冻未重钉红线）'
                % (key, fnv, fnv_frozen))

    # 下限自检（防「量到比对象短得多的东西也判绿」）
    for key in sorted(CONST_FLOOR):
        floor = CONST_FLOOR[key]
        act = (out.get('const_actual') or {}).get(key)
        if act is None:
            continue
        if act < floor:
            print('  %-26s ★%d 字符，低于下限 %d' % (key, act, floor))
            out['violations'].append(
                '%s: %d 低于下限 %d ⇒ 疑量错对象' % (key, act, floor))


# ─────────────────────────────────────────────────────────────
# 注入后的 user 消息面（`T-20261024-13` 缺口 1 · 2026-10-25 关闭）
#
# 缺口原文：「**user 侧注入面没有任何体积上限**」。本段之前的两次「以为关了」
# 都不是它（§4-265⑨ 已登记一次误认）⇒ 这里先把**对象**钉死：
#
#   真实对象 = `DiagnosisInjectionService:203` 拼出来的那条 user 消息：
#     '${m.content}$fullTextBlock\n\n$_diagnosisProtocolSuffix$directExplain$fadingBlock'
#   ⇒ 它由「学员正文 + 全貌块 + 协议后缀 + 直接解释块 + 渐隐块」**五段**拼成。
#   ⇒ 只钉其中一段（例如 977 的协议后缀，见 CONST_REDLINE）**不等于**钉住这条消息。
#
# 数据源：`message_sequence_anchor.json` 的 `p2_yuesheng_diagnosis_fulltext[3]`。
#   该用例 `chapterFullText` 非空、走真实 `sendMessage` + 诊断注入
#   （`chat_service_message_sequence_anchor_test.dart:150-151` 明写「把 user 侧注入
#   纳入有序指纹」）⇒ 实测 len=1583、role=user。
#   ⚠️ 注意量级关系：1583 > 977（协议后缀）且 > 22（另两例的学员正文原样）
#      ⇒ 这正是「注入确实发生了」的算术证据，也是本段下限自检的依据。
#
# 为什么既有锚点不够：锚点测试只做「**变了就红**」，而重冻（`UPDATE_SNAPSHOTS=true`）
#   一次即可把增量写进新基线 ⇒ **有指纹、没有上限**。本段补的就是上限：
#   `重冻 ≠ 获准增长`（重冻后不重钉本段 ⇒ 红灯，不是绿灯）。
#
# ★ 沿革（T-20261024-13 A1 甲案 · C2 补钉）：
#   此前钉表只有 `..._fulltext` 一例，而「学员只诊断一段粘贴文本 / 一句引用」
#   （**没有**章节全文）是唯一正常业务路径缺口、零覆盖。本轮补夹具
#   `p2_yuesheng_diagnosis_nofulltext`（与前者逐字段相同，仅 `chapterFullText` 为 null）
#   并**同批补两条钉值**（整条 + 五段），理由：
#     · 新例 len=1521 ≥ 977 ⇒ 覆盖扫描（`_check_user_face_coverage`）会判
#       「注入已发生却无上限」⇒ 不钉即红；
#     · 五段不钉 ⇒ 重冻快照即可让该路径的支架体积静默增长（`重冻 ≠ 获准增长`
#       对两例同等适用）。
#   余量 +0（钉值 = 实测值），与既有例同口径。
#
# 覆盖边界（如实声明，**不是全覆盖**）：
#   · 两例真的注入了协议后缀：fulltext len=1583 / nofulltext len=1521
#     （后者差 62 正是缺失的 `fullTextBlock` 段：8+0+977+349+185+2=1521）；
#   · `p1_yuesheng_diagnosis[3]` / `p2_yuesheng_diagnosis[3]` 实测 len=22
#     （学员正文原样、未注入）⇒ **不受本红线约束，也不代表注入面**（钉 22 只防误改）；
#   · 该例是否代表**全部**注入路径（例如 `directExplain` / `fadingBlock` 非空的分支）
#     = **未测**，不得据此声称「注入面已全部设限」。
# ─────────────────────────────────────────────────────────────

# 键 = `快照名[消息下标]`；值 = (实测 len 上限, 冻结时的 fnv)。贴实测、余量 +0。
USER_FACE_REDLINE = {
    'p2_yuesheng_diagnosis_fulltext[3]': (1583, '100f00a384794e7d'),
    'p2_yuesheng_diagnosis_nofulltext[3]': (1521, '49d7de888531ca6d'),
}

# 下限自检：注入后的 user 消息必须**至少**装得下协议后缀本体，否则说明
# 「量到的其实是学员正文」——即钉错对象（本缺口历史上已钉错两次）。
_USER_FACE_MIN_EXTRA = CONST_REDLINE['kDiagnosisProtocolSuffix'][0]

# ── 五段读数（ADR-0009 · T-20261024-13 A 块）─────────────────────────────
# 段 = **拼接边界**（`InjectionSegments`），不是文本分隔符：空行属于正文内容，
# 段数会随学员输入变化 ⇒ 上限钉不住。
#
# ★ 与 `USER_FACE_REDLINE`（整条 1583）的关系：整条**保留为松上限**
#   （防装配层爆量），但**不作主量** —— 整条里 1511 是系统注入，
#   学员正文一变长（3000–4000 字是正常输入）就顶红，而支架膨胀会被正文缩短
#   抵消 ⇒ 两个方向互相掩盖。
#
# ★ 下列值为**锚点实测**（本轮 `injection_segments_anchor.json` 写出，非手填）：
#   fulltext：8 + 62 + 977 + 349 + 185 = 1581，加装配 `\n\n` 2 = **1583**
#   ⇒ 与 `USER_FACE_REDLINE` 的整条值逐值吻合（差 2 就是那个分隔符）。
#   ★ 沿革（T-20261024-13 A1 甲案 · C2）：新增 `..._nofulltext` 五段钉值。
#     该例 `chapterFullText` 为 null ⇒ `fullTextBlock` 段长 **0**（fnv 为空串指纹），
#     其余四段与 fulltext 例**逐值相同**（8 / 977 / 349 / 185）—— 这正说明本轮只换了
#     「有无全文」一个维度；若哪天其余四段也变了，就不是 C2 而是另有变量混入。
USER_FACE_SEGMENTS = {
    'p2_yuesheng_diagnosis_fulltext': {
        'studentBody': (8, '2b56b05e131f4426'),
        'fullTextBlock': (62, 'f1d182190e275c1'),
        'protocolSuffix': (977, '609c7814d5bcc86d'),
        'directExplain': (349, '5d479de78f67ea3c'),
        'fadingBlock': (185, '10523563b3b11eaf'),
    },
    'p2_yuesheng_diagnosis_nofulltext': {
        'studentBody': (8, '2b56b05e131f4426'),
        'fullTextBlock': (0, '4bf29ce484222325'),
        'protocolSuffix': (977, '609c7814d5bcc86d'),
        'directExplain': (349, '5d479de78f67ea3c'),
        'fadingBlock': (185, '10523563b3b11eaf'),
    },
}

# 段名 = 拼接顺序的真源；必须与 `InjectionSegments.names` 逐字一致。
# 漂了就是「量错对象」⇒ 判据要红，不许静默跳过。
USER_FACE_SEGMENT_NAMES = (
    'studentBody',
    'fullTextBlock',
    'protocolSuffix',
    'directExplain',
    'fadingBlock',
)


def _check_user_face(out):
    """注入后的 user 消息：逐键比上限 + 比指纹 + role/下限结构自检。"""
    print('\n=== 注入后的 user 消息面（T-20261024-13 缺口 1）===')
    if not os.path.exists(MSG_SEQ):
        print('  ★快照缺失：%s' % MSG_SEQ)
        out['violations'].append('message_sequence 快照缺失 ⇒ user 注入面不可判')
        return
    d = json.load(io.open(MSG_SEQ, encoding='utf-8'))

    for key, (lim, fnv_frozen) in sorted(USER_FACE_REDLINE.items()):
        msg = _resolve_msg(d, key)
        if msg is None:
            print('  %-40s ★快照中无此路径' % key)
            out['violations'].append('%s: 快照缺该路径' % key)
            continue
        act = msg.get('len')
        role = msg.get('role')
        fnv = msg.get('fnv')
        if not isinstance(act, int):
            print('  %-40s ★缺 int 型 len' % key)
            out['violations'].append('%s: 缺 int 型 len' % key)
            continue
        out.setdefault('user_face_actual', {})[key] = act
        _, tag = _pin_verdict(out, key, act, lim, '上限')
        print('  %-40s %6d  上限 %6d  余量 %+6d  %s'
              % (key, act, lim, lim - act, tag))
        if fnv != fnv_frozen:
            print('  %-40s ★fnv %s ≠ 冻结 %s' % (key, fnv, fnv_frozen))
            out['violations'].append(
                '%s: fnv %s ≠ 冻结 %s ⇒ 字节变了（等长替换或重冻未重钉上限）'
                % (key, fnv, fnv_frozen))
        # 结构自检①：这条必须是 user 消息（若变 system ⇒ 下标指向了别的消息）
        if role != 'user':
            print('  %-40s ★role=%s（应为 user）' % (key, role))
            out['violations'].append(
                '%s: role=%s 应 user ⇒ 下标已漂移，须先核装配再改本段'
                % (key, role))
        # 结构自检②：长度必须装得下协议后缀本体（否则钉的是学员正文 = 钉错对象）
        if act < _USER_FACE_MIN_EXTRA:
            print('  %-40s ★%d < 协议后缀 %d，注入未发生'
                  % (key, act, _USER_FACE_MIN_EXTRA))
            out['violations'].append(
                '%s: %d < 协议后缀 %d ⇒ 该消息没有注入协议文本，'
                '本红线量错了对象（缺口 1 的真实对象是注入**之后**的 user 消息）'
                % (key, act, _USER_FACE_MIN_EXTRA))


def _check_user_face_segments(out):
    """注入后 user 消息的**五段**读数（ADR-0009 · T-20261024-13 A 块）。

    三道判据缺一不可：
      ① 快照缺失 ⇒ FAIL（缺失是事故，不是「没变化」）；
      ② 段名/段数不符 ⇒ FAIL（区分「没注入」与「没量到」，防只判前 N 段）；
      ③ 逐段 `len`（`pin == actual`，超限与脱钩分开报）+ 逐段 `fnv`。
    """
    print('\n=== 注入后 user 消息**按段**（ADR-0009 · T-20261024-13 A 块）===')
    if not os.path.exists(MSG_SEQ_SEGMENTS):
        print('  ★分段快照缺失：%s' % MSG_SEQ_SEGMENTS)
        out['violations'].append('分段快照缺失 ⇒ 分段判据不可判（缺失不是没变化）')
        return
    d = json.load(io.open(MSG_SEQ_SEGMENTS, encoding='utf-8'))
    for case, segs in sorted(USER_FACE_SEGMENTS.items()):
        node = d.get(case)
        if not isinstance(node, dict):
            print('  %-40s ★快照中无该 case' % case)
            out['violations'].append('%s: 分段快照缺该 case' % case)
            continue
        got_names = tuple(node.keys())
        if got_names != USER_FACE_SEGMENT_NAMES:
            print('  %-40s ★段名/段数不符：%s' % (case, got_names))
            out['violations'].append(
                '%s: 段为 %s，应为 %s ⇒ 拼接式变了或量错对象'
                % (case, got_names, USER_FACE_SEGMENT_NAMES))
            continue
        for name in USER_FACE_SEGMENT_NAMES:
            lim, fnv_frozen = segs[name]
            act = node[name].get('len')
            fnv = node[name].get('fnv')
            if not isinstance(act, int):
                print('  %-40s ★缺 int 型 len' % (case + '.' + name))
                out['violations'].append('%s.%s: 缺 int 型 len' % (case, name))
                continue
            _, tag = _pin_verdict(out, '%s.%s' % (case, name), act, lim, '上限')
            print('  %-40s %6d  上限 %6d  余量 %+6d  %s'
                  % (case + '.' + name, act, lim, lim - act, tag))
            if fnv != fnv_frozen:
                print('  %-40s ★fnv %s ≠ 冻结 %s'
                      % (case + '.' + name, fnv, fnv_frozen))
                out['violations'].append(
                    '%s.%s: fnv %s ≠ 冻结 %s ⇒ 该段字节变了'
                    % (case, name, fnv, fnv_frozen))


def _check_user_face_coverage(out):
    """覆盖扫描（A 块 Q1 · 报批稿 §1）：快照里**全部** role=user 消息的反向核对。

    `_check_user_face` 只遍历 `USER_FACE_REDLINE` 的**钉表键** ⇒ 某个 case 悄悄
    开始往 user 消息注入内容（len 超过协议后缀本体）却没有任何上限时，它无法变红
    （R1 实证：HEAD 代码对该变异 rc=0）。本函数以**快照为遍历面**补这个方向：
      · len ≥ 协议后缀本体（977）⇒ 注入已发生 ⇒ 该消息**必须**在钉表里
        （钉了 = 有上限；未钉 ⇒ 红）；
      · len < 977 ⇒ 没有注入 ⇒ **不许**在钉表里（钉了 ⇒ 红，且会同时撞
        `_check_user_face` 结构自检②「量错了对象」）。
    ⚠️ 不引入任何新的下限（`DECISIONS §4-312④`：注入面不设非退化下限）——
      977 是协议后缀的**既有实测长度**（`CONST_REDLINE` 的 fnv/length 双钉值），
      此处只用作「注入是否已发生」的判据，不是给注入面设体积下限。
    ⚠️ 覆盖边界（如实声明）：只扫 `message_sequence_anchor.json` 里已入库的用例；
      快照外的运行时注入路径不在本扫描面内（与 `_check_bypass` 同款声明）。
    """
    print('\n=== user 消息覆盖扫描（A 块 Q1 · 有注入必须有上限）===')
    if not os.path.exists(MSG_SEQ):
        # fail-closed：与 _check_user_face 对缺失快照的口径一致（缺失 = 事故）
        print('  ★快照缺失：%s' % MSG_SEQ)
        out['violations'].append('message_sequence 快照缺失 ⇒ user 覆盖扫描不可判')
        return
    d = json.load(io.open(MSG_SEQ, encoding='utf-8'))

    pinned = set(USER_FACE_REDLINE)
    threshold = _USER_FACE_MIN_EXTRA  # = 协议后缀本体 977（注入已发生的判据）
    n_user = n_big = 0
    for case in sorted(d):
        seq = d[case]
        if not isinstance(seq, list):
            continue  # meta 等非消息列表键
        for i, msg in enumerate(seq):
            if not isinstance(msg, dict) or msg.get('role') != 'user':
                continue
            key = '%s[%d]' % (case, i)
            act = msg.get('len')
            n_user += 1
            if not isinstance(act, int):
                print('  %-40s ★缺 int 型 len' % key)
                out['violations'].append('%s: 缺 int 型 len' % key)
                continue
            if act >= threshold:
                n_big += 1
                if key in pinned:
                    print('  %-40s %6d  已钉上限 OK' % (key, act))
                else:
                    print('  %-40s %6d  ★有注入却无上限' % (key, act))
                    out['violations'].append(
                        '%s: len=%d ≥ 协议后缀 %d ⇒ 注入已发生却无上限'
                        '（未列入 USER_FACE_REDLINE）' % (key, act, threshold))
            elif key in pinned:
                print('  %-40s %6d  ★无注入却列入钉表' % (key, act))
                out['violations'].append(
                    '%s: len=%d < 协议后缀 %d ⇒ 没有注入却钉了上限（钉错对象）'
                    % (key, act, threshold))
            else:
                print('  %-40s %6d  未注入未钉 OK' % (key, act))
    print('  扫描 %d 条 role=user 消息，其中 %d 条 len ≥ %d（协议后缀本体）'
          % (n_user, n_big, threshold))


if __name__ == '__main__':
    sys.exit(main())
