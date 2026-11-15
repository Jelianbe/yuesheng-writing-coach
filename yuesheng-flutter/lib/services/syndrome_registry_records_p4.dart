// ─────────────────────────────────────────────────────────────
// syndrome_registry 数据分片：records p4/4 · P031–P039（9 条） · R-019 ≤300 行
// 逐字迁移自 syndrome_registry.dart，零行为变更。
// 增删症候仍改这里（不要改 registry 宿主）。
// ─────────────────────────────────────────────────────────────
part of 'syndrome_registry.dart';

/// kSyndromeRegistry 数据段（P031-P039，9 条 · 原三段之三后半）
const List<SyndromeRecord> _syndromeRegistryP4 = [
  SyndromeRecord(
    id: 'P031',
    name: '题材边界感缺失',
    shortName: '题材边界感缺失',
    keyword: '题材边界模糊',
    oneLine: '不清楚写什么题材/题材边界不清晰，选了不擅长不商业的方向，或题材内部混搭失焦',
    typeLine: '题材定位缺失，读者找不到类型预期',
    trainingLine: '题材边界缺失——不知道自己写的是哪个赛道、目标读者是谁，题材内部混搭失焦（言情里硬塞科幻设定、历史里硬塞系统文）',
    type: SyndromeType.commercialAppeal,
    level: SkillLevel.l4,
    group: MaxAttemptsGroup.structure,
    presentationGroup: PresentationGroup.plot,
    position: 'global',
    techniques: ['T008', 'T017', 'T009'],
    actions: ['A007', 'A003'],
    role: '读者',
  ),
  SyndromeRecord(
    id: 'P032',
    name: '翻译腔/外来语干扰',
    shortName: '翻译腔/外来语干扰',
    keyword: '翻译腔/外来语',
    oneLine: '句子带着翻译腔（长定语、名物化、被动堆砌、It is…式抽象）或被外来语/音译词打断语流',
    typeLine: '句式翻译腔化，语流不自然',
    trainingLine: '翻译腔/外来语干扰——长定语前置、名词化堆叠、被动句滥用、生硬音译词打断中文语感，读起来像机翻不像人写',
    type: SyndromeType.expressiveDeficit,
    level: SkillLevel.l2,
    group: MaxAttemptsGroup.expression,
    presentationGroup: PresentationGroup.description,
    quantityTag: QuantityTag.wordChoice,
    position: 'chapter',
    techniques: ['T002', 'T003', 'T019'],
    actions: ['A019', 'A006', 'A011'],
    role: '内容',
  ),
  SyndromeRecord(
    id: 'P033',
    name: '冲突未升级/模式重复',
    shortName: '冲突未升级',
    keyword: '冲突模式重复未递进',
    oneLine: '同一模式重复多次但强度未递增，读者第二次就摸清规律，后续只是音量调大',
    typeLine: '冲突结构重复，威胁/信息量/情绪未递进',
    trainingLine:
        '连续场景/段落结构相同（如都是"异常→紧张→虚惊一场"），但威胁程度、信息量、情绪强度没有递增——读者第二次就摸清规律，第三次只是把音量调大',
    type: SyndromeType.structuralDisorder,
    level: SkillLevel.l2,
    group: MaxAttemptsGroup.structure,
    presentationGroup: PresentationGroup.plot,
    quantityTag: QuantityTag.overwritten,
    position: 'serial',
    techniques: ['T017', 'T008', 'T018'],
    actions: ['A026', 'A003', 'A007', 'A009'],
    role: '结构',
  ),
  SyndromeRecord(
    id: 'P034',
    name: '代词指代不清/零回指过载',
    shortName: '零回指过载',
    keyword: '零形回指/指代不明',
    oneLine: '连续两个以上小句主语/宾语均省略且就近可及候选≥2，读者需回看上段才确认"他/她/它"或零主语指谁',
    typeLine: '零形回指缺乏话题锚，指称解歧负担转嫁读者',
    trainingLine: '在示范对比模板里展示"有话题锚 vs 无话题锚"两种零回指，让学员自己判断哪处读者会卡住',
    type: SyndromeType.structuralDisorder,
    level: SkillLevel.l2,
    group: MaxAttemptsGroup.structure,
    presentationGroup: PresentationGroup.description,
    quantityTag: QuantityTag.overwritten,
    position: 'global',
    techniques: ['T012'],
    actions: ['A017', 'A002'],
    role: '读者',
  ),
  // ── ADR-0003 阶段一新增3 条（2026-10-05）──
  // ⚠️ P035/P036/P037 三号在 0.3.6 之前曾被用作**别的实体**的别名键：
  //   旧 P035 = 对话注水症（并入 P009 对话疲劳症）
  //   旧 P036 = 流水账叙述症（并入 P004 信息倾泻症）
  //   旧 P037 = 心理内耗症（幸存为现行 P026 心理内耗症）
  // 退役档案里三条的 `kind` = `RetirementKind.recycled`（槽位待复用，非实体合并）。
  //
  // ★ 2026-10-05（层 2 单轨收口批）**同号跨代歧义已彻底消除**：
  //   ① 读路径归一（`kSyndromeMergeMap` / `effectiveSyndromeId`）**整张删除**
  //      ⇒ 本文件成为ID 的**唯一**运行时权威，查不到就是查不到。
  //   ② v46 迁移**已退役**（`database.dart` 调用点删除）—— 它那张平铺表**含**
  //      这三条（`P035→P009` 等），单轨下执行它会把撞文同质化症的历史数据
  //      静默改成「对话疲劳症」，是最隐蔽的一种数据损坏。
  //   ③ 用户手动重装即全新库，无 legacy 行 ⇒ 无需任何清库代码。
  //
  // ⚠️ §4-136（同一字符串跨年代承载多种含义）的教训仍留在这里作为警示。
  //   ★ ADR-C147（2026-10-11）裁定修正：renumber/merge 腾空的号可复用，
  //   新号从 **P038** 起（P038–P049 内容已并入现行 P001–P037，号已腾空）。
  //   真正永不复用的只有 ghost 号（H001/H002，见 `syndrome_retirement.dart`）。
  //   若将来想复用某个号，先确认它是不是 ghost 号（`kSyndromeRetirement` 查）。
  SyndromeRecord(
    id: 'P035',
    name: '撞文同质化',
    shortName: '撞文同质',
    keyword: '模板化撞文/陌生感缺失',
    oneLine: '遮掉地名与人名后，读者认不出写的是哪部作品——场景可与同题材任意一部互换，缺少只属于这一处的具体性',
    chunkEvidenceClause:
        '。报本条须先指认可无损移植之处（逐字摘引）；但仅因结构通用、可被替换（通用件承担递进辨识）不判本条，须遮名后找不到任何只属于这一处的具体性才报。命中记 excluded「①通用件」。',
    typeLine: '细节可任意置换说明文本只消费了类型标签，未落到具体对象的独有属性上',
    trainingLine: '做「遮名测试」：遮掉人名地名与专有名词，若段落能原样搬到另一部同类作品里，说明撞文',
    type: SyndromeType.commercialAppeal,
    level: SkillLevel.l5,
    group: MaxAttemptsGroup.deep,
    presentationGroup: PresentationGroup.plot,
    position: 'global',
    needsCrossWorkReference: true,
    techniques: ['T016', 'T020', 'T024'],
    actions: ['A004', 'A011'],
    role: '内容',
  ),
  SyndromeRecord(
    id: 'P036',
    name: '细节失真',
    shortName: '细节失真',
    keyword: '生活逻辑断裂/物象缺失',
    oneLine: '只有形容没有物象——关键生活细节经不起一次设问追问（那时她没有女佣使唤吗），逻辑链在常识层断裂',
    typeLine: '细节是表达的承重结构；抽掉物象后只剩评价，读者会在常识层察觉被糊弄',
    trainingLine: '对每处抽象形容追问一句「具体是什么样」；补一个可被角色实际使用的物象，而非更华丽的形容词',
    type: SyndromeType.expressiveDeficit,
    level: SkillLevel.l1,
    group: MaxAttemptsGroup.expression,
    presentationGroup: PresentationGroup.description,
    quantityTag: QuantityTag.underwritten,
    position: 'local',
    techniques: ['T003', 'T012', 'T027'],
    actions: ['A006', 'A002', 'A005'],
    role: '内容',
  ),
  SyndromeRecord(
    id: 'P037',
    name: '故事核缺失',
    shortName: '故事核缺失',
    keyword: '主线失焦/剪裁无主干',
    oneLine: '素材都好但彼此散落，找不到贯穿全篇的单一矛盾或红线——每个单场都合格，合起来不成篇',
    typeLine: '故事核是取舍的裁决依据；缺它时作者无法判断哪场该留，剪裁就退化为删减字数',
    trainingLine: '用一句话写出「主角此刻最想得到什么、谁挡着」；写不出就把当前素材按这句话重排，删掉不服务它的',
    type: SyndromeType.structuralDisorder,
    level: SkillLevel.l4,
    group: MaxAttemptsGroup.structure,
    presentationGroup: PresentationGroup.plot,
    quantityTag: QuantityTag.underwritten,
    position: 'global',
    techniques: ['T001', 'T017', 'T030'],
    actions: ['A013', 'A001', 'A006'],
    role: '结构',
  ),
  // ── 需求 3 新增（2026-10-11）：描写顺序失序症 ──
  SyndromeRecord(
    id: 'P038',
    name: '描写顺序失序',
    shortName: '描写顺序失序',
    keyword: '空间/时间描写顺序错乱',
    oneLine: '空间感官或时间感官的描写顺序与因果/感知顺序不符——先写结果后写过程、空间跳接无过渡、时间倒错无提示，读者需自行脑补顺序',
    typeLine: '描写顺序应遵循感知或因果的自然流向；顺序错乱让读者反复回看才拼出「先发生了什么」',
    trainingLine: '把描写按「感知到达顺序」或「因果发生顺序」重排：先过程后结果、先近后远或先整体后局部、倒叙须有明确提示',
    type: SyndromeType.expressiveDeficit,
    level: SkillLevel.l1,
    group: MaxAttemptsGroup.expression,
    presentationGroup: PresentationGroup.description,
    position: 'local',
    techniques: ['T027', 'T022'],
    actions: ['A018', 'A009', 'A006'],
    role: '结构', // 边界：观测方式（U4 温）；P003 为评的直接对象，防互推；跨面标注不改值
  ),
  // ── ADR-C150（E-7 拆分）：信息密度缺失症 ──
  // 自 P018 子情形 B「内容稀碎」拆出（P018 保留语言层重复/文法瑕疵）。
  // ID 取 P039：ADR-C147 裁定 P038–P049 已腾空可复用，且 ID 连续递增约束
  // （four_libraries_consistency_test #1）要求新条目取 P038 之后的下一个号。
  SyndromeRecord(
    id: 'P039',
    name: '信息密度缺失',
    shortName: '信息密度缺失',
    keyword: '句句正确但无信息增量',
    oneLine:
        '句子单独看语法都正确，但一段读完没传递任何实质信息——没有新事实、没有情绪推进、没有画面变化，每句都"没错"，合起来"什么都没说"',
    typeLine: '不是"该展开的地方一笔带过"（P017），而是"根本没有信息"——删到只剩骨架后剩余信息量≈0',
    trainingLine: '把每句主语+谓语提取出来检查是否构成"信息增量链"；凡删掉后叙事不受影响的句子即为稀碎，重写或合并',
    type: SyndromeType.expressiveDeficit,
    level: SkillLevel.l2,
    group: MaxAttemptsGroup.expression,
    presentationGroup: PresentationGroup.plot,
    quantityTag: QuantityTag.overwritten,
    position: 'local',
    techniques: ['T003', 'T022'],
    actions: ['A011', 'A005'],
    role: '内容',
  ),
];
