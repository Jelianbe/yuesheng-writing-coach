// ─────────────────────────────────────────────────────────────
// 症候元数据注册表（真源，b9 批次27）
// 设计稿：docs/2026-08-11-b9-syndrome-registry-design.md
//
// 本文件是症候「元数据」的唯一真源：
//   - 增删症候 = 在此增删一条 SyndromeRecord（另需编写手册段 + 训练段）
//   - 各库 markdown 表格行 / 计数 / ID 列表 / 测试断言从此派生
// 内容型段落（手册正文/训练知识/重叠规则）不在此处，保留各库人工编写。
// ─────────────────────────────────────────────────────────────

// ADR-C70：原本 import 的是 syndrome_skill_levels.dart，但那边反过来依赖
// 本文件的 kSyndromeSkillLevelsDerived，形成循环。这里只需要 SkillLevel
// 这个类型，改指向类型层文件即解开——依赖变为 registry → types（单向）。
import 'syndrome_skill_types.dart'; // SkillLevel

// ─── R-019 数据分片（≤300 行）：39 条 kSyndromeRegistry 记录字面量
// 按 13/13/13 拆至 syndrome_registry_p1/p2/p3.dart（const 列表分段，宿主拼接）
/// 症候类型（症候库「症候类型速查」表使用；skill_registry 类型分组表
/// 的「语言表达类」由渲染函数按 P008/P022 特例映射，见批次30）
enum SyndromeType {
  motivationDeficit('motivation_deficit'),
  expressiveDeficit('expressive_deficit'),
  structuralDisorder('structural_disorder'),
  commercialAppeal('commercial_appeal');

  final String value;
  const SyndromeType(this.value);
}

/// maxAttempts 分组（skill_registry「轮次上限」：表达≤3 / 结构≤5 / 深层≤5）
enum MaxAttemptsGroup {
  expression('表达类'),
  structure('结构类'),
  deep('深层类');

  final String label;
  const MaxAttemptsGroup(this.label);
}

/// 症候退役原因（b11 设计稿：docs/2026-08-11-b11-syndrome-retirement-design.md）
enum SyndromeRetiredReason {
  /// 并入其它症候（须填 mergedInto）
  merged('merged'),

  /// 删除，不再教学
  removed('removed');

  final String value;
  const SyndromeRetiredReason(this.value);
}

/// 症候元数据（增删症候的唯一入口）
class SyndromeRecord {
  /// 症候 ID（P0XX，ID 永不复用，新 ID 连续递增）
  final String id;

  /// 全名（手册标题 / 训练段标题 / 索引关键词可用时，含合并注释）：
  ///   如 P004 '信息倾泻症（含原 P001 世界观膨胀子类型）'
  final String name;

  /// 精简名（training-templates-index / 技法 L3 表用）：
  ///   如 P004 '信息倾泻症'
  final String shortName;

  /// 索引表「问题类型关键词」列（独立字段，非名称）：
  ///   如 P028 '画面感缺失'
  final String keyword;

  /// 一句话描述（索引表一句话 / 类型速查核心问题共用）：
  ///   如 P028 '通篇抽象概述无场景化呈现，读者无法脑内成像'
  final String oneLine;

  /// 类型速查「核心问题」短句（症候库「症候类型速查」列，与 oneLine 不同源）：
  ///   如 P003 oneLine 为索引表句，typeLine 为 '描写缺乏细节'
  final String typeLine;

  /// training-templates-index「核心本质一句话」（skill_registry 教学知识索引，
  /// 与 oneLine / typeLine 均不同源）：
  ///   如 P003 '用情绪词替代具体感官描写，读者被"告知"而非"感受到"'
  final String trainingLine;

  /// 症候类型（症候库类型速查表）
  final SyndromeType type;

  /// 技能层级（L1-L5，复用 syndrome_skill_levels 的 SkillLevel）
  final SkillLevel level;

  /// maxAttempts 分组（训练轮次上限）
  final MaxAttemptsGroup group;

  /// position_sensitivity（chapter / serial / global / beginning / middle / end / local）
  final String position;

  /// 推荐技法 ID 列表（首选在首位，可含备选；与 kTechniquesBySyndrome 一致）
  final List<String> techniques;

  /// 推荐教学动作 ID 列表（首选在首位，可含备选；与 v1 动作映射一致）
  final List<String> actions;

  /// v1 动作映射（coaching-actions）专用名：与 name 不同时设置
  ///   （如 P004 v1 用 '信息倾泻症（含原 P001 子类型）'，手册名含 '世界观膨胀子类型'）
  final String? v1ActionName;

  /// v2 动作映射（coaching-actions-v2）专用名：与 shortName 不同时设置
  ///   （如 P004 v2 用 '信息倾泻'，P007 v2 用 '句式单一'）
  final String? v2ActionName;

  /// 是否已退役（b11：false/null 为活跃；true 不再进诊断/检索/渲染，定义文本保留）
  final bool? retired;

  /// 退役原因（retired == true 时必须非空）
  final SyndromeRetiredReason? retiredReason;

  /// 并入的目标症候 ID（仅 retiredReason == merged 时非空，须指向活跃症候）
  final String? mergedInto;

  const SyndromeRecord({
    required this.id,
    required this.name,
    required this.shortName,
    required this.keyword,
    required this.oneLine,
    required this.typeLine,
    required this.trainingLine,
    required this.type,
    required this.level,
    required this.group,
    required this.position,
    required this.techniques,
    required this.actions,
    this.v1ActionName,
    this.v2ActionName,
    this.retired,
    this.retiredReason,
    this.mergedInto,
  });

  /// v1 动作映射显示名（coaching-actions）
  String get v1ActionDisplayName => v1ActionName ?? name;

  /// v2 动作映射显示名（coaching-actions-v2）
  String get v2ActionDisplayName => v2ActionName ?? shortName;
}

/// 注册表（真源）：39 条（P003-P041），按 ID 升序。
/// 增删症候时：
///   - 新增：追加一条记录（ID 连续递增）+ 在症候库/训练库编写手册段与训练段
///   - 删减：删除记录 + 删对应手册段与训练段（勿复用 ID）
/// R-019 拆分：39 条记录字面量移至 syndrome_registry_p1/p2/p3.dart，此处拼接。
final List<SyndromeRecord> kSyndromeRegistry = List.unmodifiable([
  ..._syndromeRegistryP1,
  ..._syndromeRegistryP2,
  ..._syndromeRegistryP3,
]);

// ── 派生（各库 / 测试消费）─────────────────────────────────
// 退役语义（b11 设计稿）：retired == true 的症候从活跃集合/渲染/诊断中剔除，
// 定义文本保留；kSyndromeMergeMap 供历史记录读取聚合归一（写入不归一一，保留原始 ID）。

/// 活跃症候 ID 有序列表（过滤退役；替代 skill_layers.syndromeIds 与
/// training_knowledge_base.kTrainingSyndromeIds 的手写列表）
List<String> get kSyndromeIds => List.unmodifiable(
  kSyndromeRegistry.where((s) => s.retired != true).map((s) => s.id),
);

/// 退役症候 ID 有序列表（b11：历史说明白名单 / 排查用）
List<String> get kRetiredSyndromeIds => List.unmodifiable(
  kSyndromeRegistry.where((s) => s.retired == true).map((s) => s.id),
);

/// 全部症候 ID（活跃 + 退役，保序；四库 #9 历史引用白名单用）
List<String> get kAllSyndromeIds =>
    List.unmodifiable([...kSyndromeIds, ...kRetiredSyndromeIds]);

/// 症候合并映射表（旧 ID → 新 ID，读取聚合前归一；写入不归一，保留历史可追溯）
const Map<String, String> kSyndromeMergeMap = {
  'P001': 'P004', // 信息倾泻症（历史合并，注册表从 P003 起）
  'P002': 'P009', // 角色空心化（历史合并）
  'H001': 'P013', // 更早编号系统的合并（b6 设计稿记载）
  'H002': 'P013',
};

/// 归一后的有效症候 ID（读取聚合：mergeMap[id] ?? id）
String effectiveSyndromeId(String id) => kSyndromeMergeMap[id] ?? id;

/// 症候 → 技能层级映射（活跃症候；替代 syndrome_skill_levels.kSyndromeSkillLevels
/// 手写 Map；四库一致性测试的权威集合来源）
Map<String, SkillLevel> get kSyndromeSkillLevelsDerived => {
  for (final s in kSyndromeRegistry)
    if (s.retired != true) s.id: s.level,
};

/// 症候 → 推荐技法映射（活跃症候；替代 technique_knowledge_base.kTechniquesBySyndrome）
Map<String, List<String>> get kTechniquesBySyndromeDerived => {
  for (final s in kSyndromeRegistry)
    if (s.retired != true) s.id: s.techniques,
};

/// 按 ID 查注册表记录（未知 → null）
SyndromeRecord? syndromeRecordOf(String? id) {
  if (id == null || id.isEmpty) return null;
  for (final s in kSyndromeRegistry) {
    if (s.id == id) return s;
  }
  return null;
}

/// kSyndromeRegistry 数据段（P003-P015，13 条）
const List<SyndromeRecord> _syndromeRegistryP1 = [
  // ── L1 基础表达 ──────────────────────────────────────────
  SyndromeRecord(
    id: 'P003',
    name: '情绪标签化',
    shortName: '情绪标签化',
    keyword: '情绪词替代描写',
    oneLine: '用"愤怒/悲伤/害怕"等词直接告知情绪，无具体感官细节',
    typeLine: '描写缺乏细节',
    trainingLine: '用情绪词替代具体感官描写，读者被"告知"而非"感受到"',
    type: SyndromeType.expressiveDeficit,
    level: SkillLevel.l1,
    group: MaxAttemptsGroup.expression,
    position: 'global',
    techniques: ['T001', 'T002', 'T020', 'T031'],
    actions: ['A004', 'A006'],
  ),
  SyndromeRecord(
    id: 'P004',
    name: '信息倾泻症（含原 P001 世界观膨胀子类型）',
    shortName: '信息倾泻症',
    keyword: '设定信息旁白交代',
    oneLine: '世界观/背景以说明书方式直接陈述，非嵌在场景中',
    typeLine: '信息呈现方式不当',
    trainingLine: '设定以旁白方式直接交代，读者被"暂停故事"来学设定',
    type: SyndromeType.structuralDisorder,
    level: SkillLevel.l2,
    group: MaxAttemptsGroup.structure,
    position: 'beginning',
    techniques: ['T010', 'T011'],
    actions: ['A002', 'A008'],
    v1ActionName: '信息倾泻症（含原 P001 子类型）',
    v2ActionName: '信息倾泻',
  ),
  SyndromeRecord(
    id: 'P005',
    name: '视角漂移',
    shortName: '视角漂移',
    keyword: '视角越界',
    oneLine: '写了当前视角角色看不到/听不到/不知道的信息',
    typeLine: '叙事视角不统一',
    trainingLine: '写了当前视角角色不可能知道的信息，读者失去"谁在看"的确定感',
    type: SyndromeType.structuralDisorder,
    level: SkillLevel.l4,
    group: MaxAttemptsGroup.structure,
    position: 'global',
    techniques: ['T012'],
    actions: ['A002'],
  ),
  SyndromeRecord(
    id: 'P006',
    name: '节奏停滞',
    shortName: '节奏停滞',
    keyword: '叙事停滞无推进',
    oneLine: '连续多段无新事件/新冲突/新信息，故事原地打转',
    typeLine: '叙事推进过慢',
    trainingLine: '事件推进密度低，叙事静止，读者在想"然后呢"',
    type: SyndromeType.structuralDisorder,
    level: SkillLevel.l2,
    group: MaxAttemptsGroup.structure,
    position: 'middle',
    techniques: ['T008', 'T017', 'T018', 'T022'],
    actions: ['A003', 'A005', 'A009'],
  ),
  SyndromeRecord(
    id: 'P007',
    name: '句式节奏单一',
    shortName: '句式节奏单一',
    keyword: '句式结构重复',
    oneLine: '连续多句相同句式结构，缺乏长短/节奏变化',
    typeLine: '句式缺乏变化',
    trainingLine: '连续多句相同结构，读者在句法层面产生疲劳',
    type: SyndromeType.structuralDisorder,
    level: SkillLevel.l1,
    group: MaxAttemptsGroup.expression,
    position: 'global',
    techniques: ['T019', 'T023', 'T025'],
    actions: ['A009', 'A003'],
    v2ActionName: '句式单一',
  ),
  SyndromeRecord(
    id: 'P008',
    name: '语言堆砌',
    shortName: '语言堆砌',
    keyword: '描写密度过高',
    oneLine: '修饰词堆砌，有效信息被稀释，读者费力抓核心',
    typeLine: '表达缺乏效率',
    trainingLine: '描写密度超过叙事所需，核心信息被华丽辞藻稀释',
    type: SyndromeType.expressiveDeficit,
    level: SkillLevel.l1,
    group: MaxAttemptsGroup.expression,
    position: 'global',
    techniques: ['T003', 'T002', 'T021', 'T031'],
    actions: ['A006', 'A011', 'A016'],
  ),
  SyndromeRecord(
    id: 'P009',
    name: '角色空心化（含原 P002 角色工具化症状）',
    shortName: '角色空心化',
    keyword: '角色无驱动力',
    oneLine: '角色行为缺乏动机，换角色剧情依然成立',
    typeLine: '角色缺乏行为驱动力',
    trainingLine: '角色缺乏行为驱动力，动机不足、角色被工具化',
    type: SyndromeType.motivationDeficit,
    level: SkillLevel.l3,
    group: MaxAttemptsGroup.deep,
    position: 'global',
    techniques: ['T009', 'T004', 'T005'],
    actions: ['A003', 'A007'],
    v1ActionName: '角色空心化（含原 P002 子症状）',
  ),
  SyndromeRecord(
    id: 'P010',
    name: 'OC 平面化',
    shortName: 'OC 平面化',
    keyword: '角色无辨识度',
    oneLine: '角色缺乏独特特征，对话/行为可互换',
    typeLine: '角色缺乏立体感',
    trainingLine: '角色像模板人物，除外表外说不出"只有ta才会做的事"',
    type: SyndromeType.expressiveDeficit,
    level: SkillLevel.l3,
    group: MaxAttemptsGroup.deep,
    position: 'global',
    techniques: ['T006', 'T007'],
    actions: ['A003', 'A010'],
    v2ActionName: 'OC平面化',
  ),
  SyndromeRecord(
    id: 'P011',
    name: '对话疲劳症',
    shortName: '对话疲劳症',
    keyword: '对话无区分度',
    oneLine: '对话占过多篇幅且无潜台词、无动作支撑',
    typeLine: '对话缺乏表现力',
    trainingLine: '对话占过多篇幅且无区分度、无潜台词、无动作支撑',
    type: SyndromeType.expressiveDeficit,
    level: SkillLevel.l1,
    group: MaxAttemptsGroup.expression,
    position: 'global',
    techniques: ['T013', 'T014', 'T015', 'T016'],
    actions: ['A008', 'A006'],
  ),
  // ── L4 情节结构 ──────────────────────────────────────────
  SyndromeRecord(
    id: 'P012',
    name: '张力不足症',
    shortName: '张力不足症',
    keyword: '冲突无分量',
    oneLine: '主角不会输/无代价/无后果，读者不紧张',
    typeLine: '冲突缺乏分量',
    trainingLine: '冲突没有分量与代价，读者知道主角一定会赢',
    type: SyndromeType.structuralDisorder,
    level: SkillLevel.l4,
    group: MaxAttemptsGroup.structure,
    position: 'global',
    techniques: ['T017'],
    actions: ['A007', 'A003'],
    v2ActionName: '张力不足',
  ),
  SyndromeRecord(
    id: 'P013',
    name: '开篇平庸症',
    shortName: '开篇平庸症',
    keyword: '开篇无钩子',
    oneLine: '前300字无冲突/悬念/反常，读者3秒内流失',
    typeLine: '开篇缺乏钩子',
    trainingLine: '前300字无冲突/悬念/反常，读者3秒内没有读下去的理由',
    type: SyndromeType.structuralDisorder,
    level: SkillLevel.l4,
    group: MaxAttemptsGroup.structure,
    position: 'beginning',
    techniques: ['T024'],
    actions: ['A007', 'A001'],
    v2ActionName: '开篇平庸',
  ),
  SyndromeRecord(
    id: 'P014',
    name: '结尾乏力症',
    shortName: '结尾乏力症',
    keyword: '结尾仓促/烂尾',
    oneLine: '收束无满足感，机械降神或伏笔不回收',
    typeLine: '结尾缺少收束满足感',
    trainingLine: '收束仓促或机械降神，读者没有满足感',
    type: SyndromeType.structuralDisorder,
    level: SkillLevel.l4,
    group: MaxAttemptsGroup.structure,
    position: 'end',
    techniques: ['T025', 'T026'],
    actions: ['A007', 'A003'],
    v2ActionName: '结尾乏力',
  ),
  SyndromeRecord(
    id: 'P015',
    name: '高潮疲软症',
    shortName: '高潮疲软症',
    keyword: '高潮执行不到位',
    oneLine: '铺垫做好了但高潮段落无冲击力',
    typeLine: '高潮执行不到位',
    trainingLine: '铺垫做好了但高潮段落本身没有执行到位',
    type: SyndromeType.structuralDisorder,
    level: SkillLevel.l4,
    group: MaxAttemptsGroup.structure,
    position: 'middle',
    techniques: ['T027', 'T018'],
    actions: ['A007', 'A009'],
    v2ActionName: '高潮疲软',
  ),
];

/// kSyndromeRegistry 数据段（P016-P031，13 条）
const List<SyndromeRecord> _syndromeRegistryP2 = [
  SyndromeRecord(
    id: 'P016',
    name: '情节巧合过多症',
    shortName: '情节巧合过多症',
    keyword: '情节依赖巧合',
    oneLine: '推进靠偶然事件而非角色主动选择',
    typeLine: '情节驱动依赖巧合',
    trainingLine: '情节推动依赖巧合而非角色主动选择',
    type: SyndromeType.structuralDisorder,
    level: SkillLevel.l4,
    group: MaxAttemptsGroup.structure,
    position: 'global',
    techniques: ['T008', 'T009', 'T028'],
    actions: ['A013', 'A003'],
    v2ActionName: '情节巧合过多',
  ),
  SyndromeRecord(
    id: 'P017',
    name: '伏笔失效症',
    shortName: '伏笔失效症',
    keyword: '伏笔埋设/回收问题',
    oneLine: '伏笔裸露/烂尾/解释式回收',
    typeLine: '伏笔埋设/回收有问题',
    trainingLine: '伏笔埋设/铺陈/回收至少一个环节出问题',
    type: SyndromeType.structuralDisorder,
    level: SkillLevel.l4,
    group: MaxAttemptsGroup.structure,
    position: 'global',
    techniques: ['T026', 'T017'],
    actions: ['A012', 'A003'],
    v2ActionName: '伏笔失效',
  ),
  // ── L3 角色塑造 ──────────────────────────────────────────
  SyndromeRecord(
    id: 'P018',
    name: '人设崩塌症',
    shortName: '人设崩塌症',
    keyword: '角色中途崩坏',
    oneLine: '连载中角色行为偏离前期建立的模式',
    typeLine: '角色在连载中期崩坏',
    trainingLine: '角色连载中途行为未经铺垫地偏离前期形象',
    type: SyndromeType.structuralDisorder,
    level: SkillLevel.l3,
    group: MaxAttemptsGroup.deep,
    position: 'global',
    techniques: ['T030', 'T009'],
    actions: ['A015', 'A010'],
    v2ActionName: '人设崩塌',
  ),
  SyndromeRecord(
    id: 'P019',
    name: '情感失真症',
    shortName: '情感失真症',
    keyword: '情感反应不真实',
    oneLine: '角色情感与情境不匹配，像开关切换',
    typeLine: '情感反应不真实',
    trainingLine: '角色情感反应不符合正常人逻辑，读者无法共情',
    type: SyndromeType.expressiveDeficit,
    level: SkillLevel.l3,
    group: MaxAttemptsGroup.expression,
    position: 'global',
    techniques: ['T001', 'T020'],
    actions: ['A014', 'A004'],
    v2ActionName: '情感失真',
  ),
  // ── L2 叙事节奏 ──────────────────────────────────────────
  SyndromeRecord(
    id: 'P020',
    name: '过渡生硬症',
    shortName: '过渡生硬症',
    keyword: '场景切换生硬',
    oneLine: '过渡靠"镜头一转"，无感官/情绪连接',
    typeLine: '场景衔接不流畅',
    trainingLine: '场景衔接缺乏流畅感，切换产生断裂',
    type: SyndromeType.structuralDisorder,
    level: SkillLevel.l2,
    group: MaxAttemptsGroup.expression,
    position: 'global',
    techniques: ['T029', 'T022'],
    actions: ['A009', 'A006'],
    v2ActionName: '过渡生硬',
  ),
  SyndromeRecord(
    id: 'P021',
    name: '跳跃叙事/过度概括症',
    shortName: '跳跃叙事/过度概括症',
    keyword: '关键事件被概括',
    oneLine: '重要时刻被一两句带过，读者来不及感受',
    typeLine: '情节推进过快，关键事件被概括',
    trainingLine: '关键情节/情绪转折被过度概括，读者来不及"看见"和"感受"',
    type: SyndromeType.structuralDisorder,
    level: SkillLevel.l2,
    group: MaxAttemptsGroup.expression,
    position: 'global',
    techniques: ['T022', 'T008'],
    actions: ['A009', 'A005'],
    v2ActionName: '跳跃叙事',
  ),
  SyndromeRecord(
    id: 'P022',
    name: '重复用词/基础语病',
    shortName: '重复用词/基础语病',
    keyword: '重复用词/基础语病',
    oneLine: '相邻字重复/连续标点/高频词反复，基础文法问题',
    typeLine: '表达不够精炼',
    trainingLine: '相邻字重复/连续标点/高频词反复，基础文法问题分散注意力',
    type: SyndromeType.expressiveDeficit,
    level: SkillLevel.l1,
    group: MaxAttemptsGroup.expression,
    position: 'local',
    techniques: ['T019', 'T003'],
    actions: ['A016', 'A011'],
  ),
  // ── 批次15（D9 网文商业优先）：P023-P027 ────────────────
  SyndromeRecord(
    id: 'P023',
    name: '爽点乏力症',
    shortName: '爽点乏力症',
    keyword: '爽点乏力',
    oneLine: '关键胜利/优势展示无情绪回报，读者不"爽"',
    typeLine: '情绪回报机制缺失，读者不"爽"',
    trainingLine: '关键胜利/优势展示无情绪回报，读者不"爽"',
    type: SyndromeType.commercialAppeal,
    level: SkillLevel.l4,
    group: MaxAttemptsGroup.structure,
    position: 'chapter',
    techniques: ['T027', 'T018'],
    actions: ['A005', 'A013'],
  ),
  SyndromeRecord(
    id: 'P024',
    name: '期待感断裂症',
    shortName: '期待感断裂症',
    keyword: '期待感断裂',
    oneLine: '章末钩子不兑现/提前剧透，读者期待落空',
    typeLine: '悬念/承诺管理失衡，期待落空',
    trainingLine: '章末钩子不兑现/提前剧透，读者期待落空',
    type: SyndromeType.commercialAppeal,
    level: SkillLevel.l4,
    group: MaxAttemptsGroup.structure,
    position: 'serial',
    techniques: ['T017', 'T026'],
    actions: ['A012', 'A003'],
  ),
  SyndromeRecord(
    id: 'P025',
    name: '黄金三章失效症',
    shortName: '黄金三章失效症',
    keyword: '黄金三章失效',
    oneLine: '前三章未建立代入/冲突/金手指/目标，读者流失',
    typeLine: '开篇阅读契约未建立，读者流失',
    trainingLine: '前三章未建立代入/冲突/金手指/目标，读者流失',
    type: SyndromeType.commercialAppeal,
    level: SkillLevel.l4,
    group: MaxAttemptsGroup.structure,
    position: 'global',
    techniques: ['T024'],
    actions: ['A007', 'A001'],
  ),
  SyndromeRecord(
    id: 'P026',
    name: '章节钩子缺失症',
    shortName: '章节钩子缺失症',
    keyword: '章节钩子缺失',
    oneLine: '章末无悬念/反转/冲击，无翻页动力',
    typeLine: '章末悬念设计缺失，无翻页动力',
    trainingLine: '章末无悬念/反转/冲击，无翻页动力',
    type: SyndromeType.commercialAppeal,
    level: SkillLevel.l4,
    group: MaxAttemptsGroup.structure,
    position: 'chapter',
    techniques: ['T017', 'T027'],
    actions: ['A012', 'A009'],
  ),
  SyndromeRecord(
    id: 'P027',
    name: '追读动力不足症',
    shortName: '追读动力不足症',
    keyword: '追读动力不足',
    oneLine: '长线悬念/情感绑定/主线牵引弱，连载中弃书',
    typeLine: '长线留存结构缺失，连载中弃书',
    trainingLine: '长线悬念/情感绑定/主线牵引弱，连载中弃书',
    type: SyndromeType.commercialAppeal,
    level: SkillLevel.l4,
    group: MaxAttemptsGroup.structure,
    position: 'serial',
    techniques: ['T026', 'T017'],
    actions: ['A013', 'A012'],
  ),
  // ── 批次23-26（叙事基础空缺）：P028-P031 ────────────────
  SyndromeRecord(
    id: 'P028',
    name: '画面感缺失症',
    shortName: '画面感缺失症',
    keyword: '画面感缺失',
    oneLine: '通篇抽象概述无场景化呈现，读者无法脑内成像',
    typeLine: '通篇抽象概述，缺乏场景化呈现',
    trainingLine: '通篇抽象概述无场景化呈现，读者无法脑内成像',
    type: SyndromeType.expressiveDeficit,
    level: SkillLevel.l2,
    group: MaxAttemptsGroup.expression,
    position: 'chapter',
    techniques: ['T001', 'T002'],
    actions: ['A006', 'A004'],
  ),
];

/// kSyndromeRegistry 数据段（P032-P041，13 条）
const List<SyndromeRecord> _syndromeRegistryP3 = [
  SyndromeRecord(
    id: 'P029',
    name: '段落失控症',
    shortName: '段落失控症',
    keyword: '段落失控',
    oneLine: '段落过长无呼吸感或碎片化断行，阅读节奏失衡',
    typeLine: '段落组织失衡，阅读节奏被破坏',
    trainingLine: '段落过长无呼吸感或碎片化断行，阅读节奏失衡',
    type: SyndromeType.structuralDisorder,
    level: SkillLevel.l2,
    group: MaxAttemptsGroup.expression,
    position: 'chapter',
    techniques: ['T021', 'T019'],
    actions: ['A011', 'A009'],
  ),
  SyndromeRecord(
    id: 'P030',
    name: '节奏比例失衡症',
    shortName: '节奏比例失衡症',
    keyword: '节奏比例失衡',
    oneLine: '铺垫/高潮/收束比例失衡，该快的慢、该慢的快',
    typeLine: '铺垫/高潮/收束比例失衡，节奏错配',
    trainingLine: '铺垫/高潮/收束比例失衡，该快的慢、该慢的快',
    type: SyndromeType.structuralDisorder,
    level: SkillLevel.l4,
    group: MaxAttemptsGroup.structure,
    position: 'serial',
    techniques: ['T027', 'T025'],
    actions: ['A009', 'A013'],
  ),
  SyndromeRecord(
    id: 'P031',
    name: '设定矛盾症',
    shortName: '设定矛盾症',
    keyword: '设定矛盾',
    oneLine: '世界观设定前后冲突，规则/时间线/能力不自洽',
    typeLine: '世界观设定前后冲突，规则/时间线不自洽',
    trainingLine: '世界观设定前后冲突，规则/时间线/能力不自洽',
    type: SyndromeType.structuralDisorder,
    level: SkillLevel.l4,
    group: MaxAttemptsGroup.structure,
    position: 'global',
    techniques: ['T017', 'T026'],
    actions: ['A013', 'A012'],
  ),
  // ── 批次32（b10 三症候扩容：网文商业）：P032 ───────────────
  SyndromeRecord(
    id: 'P032',
    name: '金手指失衡症',
    shortName: '金手指失衡症',
    keyword: '金手指使用失衡',
    oneLine: '金手指迟迟不亮相/过强消灭冲突/规则前后崩坏，读者失去代入与期待',
    typeLine: '金手指设定或使用失衡，机制压过叙事',
    trainingLine: '金手指设定与使用失衡——亮相时机、强度上限、规则一致性至少一处出问题',
    type: SyndromeType.commercialAppeal,
    level: SkillLevel.l4,
    group: MaxAttemptsGroup.structure,
    position: 'serial',
    techniques: ['T017', 'T024', 'T026'],
    actions: ['A013', 'A009'],
  ),
  // ── 批次33（b10 三症候扩容：网文商业）：P033 ───────────────
  SyndromeRecord(
    id: 'P033',
    name: '升级节奏失衡症',
    shortName: '升级节奏失衡症',
    keyword: '升级节奏失衡',
    oneLine: '升级过快力量通货膨胀，或过慢读者失去期待，成长弧线失衡',
    typeLine: '成长/升级节奏失衡，积累感与期待感被破坏',
    trainingLine: '升级节奏失衡——过快导致力量通货膨胀，过慢导致读者失去期待',
    type: SyndromeType.commercialAppeal,
    level: SkillLevel.l4,
    group: MaxAttemptsGroup.structure,
    position: 'serial',
    techniques: ['T027', 'T008', 'T017'],
    actions: ['A009', 'A013'],
  ),
  // ── 批次34（b10 三症候扩容：配角群像）：P034 ───────────────
  SyndromeRecord(
    id: 'P034',
    name: '配角工具人症',
    shortName: '配角工具人症',
    keyword: '配角功能性过强',
    oneLine: '配角无独立性格/动机/记忆点，仅传话推剧情喊口号',
    typeLine: '配角群像工具化，缺乏独立辨识度',
    trainingLine: '配角仅为剧情服务——无独立动机、无辨识行为、无记忆点',
    type: SyndromeType.expressiveDeficit,
    level: SkillLevel.l3,
    group: MaxAttemptsGroup.deep,
    position: 'global',
    techniques: ['T006', 'T007', 'T004', 'T005'],
    actions: ['A010', 'A003'],
  ),
  // ── 批次40（b12 四症候扩容：叙事效率与结构硬伤）：P035 ──
  SyndromeRecord(
    id: 'P035',
    name: '对话注水症',
    shortName: '对话注水症',
    keyword: '对话信息冗余',
    oneLine: '对话大量寒暄客套/重复确认/无信息增量，看似推进实则灌水',
    typeLine: '对话叙事效率低，信息密度不足',
    trainingLine: '对话段落信息增量低——寒暄、客套、重复确认、明知故问，不推进剧情不升级矛盾',
    type: SyndromeType.structuralDisorder,
    level: SkillLevel.l2,
    group: MaxAttemptsGroup.structure,
    position: 'chapter',
    techniques: ['T013', 'T008', 'T016'],
    actions: ['A008', 'A009'],
  ),
  // ── 批次41（b12 四症候扩容：叙事效率与结构硬伤）：P036 ──
  SyndromeRecord(
    id: 'P036',
    name: '流水账叙述症',
    shortName: '流水账叙述症',
    keyword: '事件平铺无聚焦',
    oneLine: '按时间顺序平均罗列事件，无冲突聚焦与轻重缓急，像流水账',
    typeLine: '事件组织缺乏戏剧化结构，平铺直叙',
    trainingLine: '事件按时间平铺直叙，无冲突聚焦与详略分配，读者读不出重点',
    type: SyndromeType.structuralDisorder,
    level: SkillLevel.l2,
    group: MaxAttemptsGroup.expression,
    position: 'chapter',
    techniques: ['T022', 'T008', 'T018'],
    actions: ['A009', 'A011'],
  ),
  // ── 批次42（b12 四症候扩容：叙事效率与结构硬伤）：P037 ──
  SyndromeRecord(
    id: 'P037',
    name: '心理内耗症',
    shortName: '心理内耗症',
    keyword: '心理独白失控',
    oneLine: '角色内心反复纠结/自我怀疑/复盘过往，大段独白无进展',
    typeLine: '心理描写失控，无进展内耗',
    trainingLine: '心理独白篇幅失控——反复纠结、自我怀疑、复盘过往，无进展内耗稀释节奏',
    type: SyndromeType.expressiveDeficit,
    level: SkillLevel.l2,
    group: MaxAttemptsGroup.expression,
    position: 'chapter',
    techniques: ['T001', 'T009', 'T020'],
    actions: ['A011', 'A004'],
  ),
  // ── 批次43（b12 四症候扩容：叙事效率与结构硬伤）：P038 ──
  SyndromeRecord(
    id: 'P038',
    name: '支线涣散症',
    shortName: '支线涣散症',
    keyword: '支线偏离主线',
    oneLine: '支线剧情不服务主线/人设/爽点，被带跑后主线被搁置',
    typeLine: '支线意义缺失，主线牵引弱化',
    trainingLine: '支线缺乏存在意义——不推动主线、不丰富人设、不提供爽点，主线被搁置',
    type: SyndromeType.structuralDisorder,
    level: SkillLevel.l3,
    group: MaxAttemptsGroup.structure,
    position: 'serial',
    techniques: ['T008', 'T017', 'T022'],
    actions: ['A013', 'A002'],
  ),
  // ── 批次45（b13 角色驱动层扩容）：P039 ──
  SyndromeRecord(
    id: 'P039',
    name: '目标模糊症',
    shortName: '目标模糊症',
    keyword: '主角目标不具体',
    oneLine: '主角目标抽象模糊（想变强/要复仇），无数量/期限/代价，读者无可期待',
    typeLine: '角色驱动力不清晰，目标不可追踪',
    trainingLine: '主角欲望缺乏具体化——目标 + 数量 + 截止时间 + 失败代价至少缺两项，读者找不到可「替他着急」的点',
    type: SyndromeType.motivationDeficit,
    level: SkillLevel.l3,
    group: MaxAttemptsGroup.deep,
    position: 'global',
    techniques: ['T009', 'T004', 'T005'],
    actions: ['A003', 'A007'],
  ),
  // ── 批次46（b13 角色驱动层扩容）：P040 ──
  SyndromeRecord(
    id: 'P040',
    name: '被动主角症',
    shortName: '被动主角症',
    keyword: '主角无主动性',
    oneLine: '主角被剧情拖着走，无主动决策/权衡/反制，读者一眼出戏',
    typeLine: '主角主动性缺失，决策由剧情代劳',
    trainingLine: '剧情需要主角去哪主角就去哪——无理由、无顾虑、无权衡，角色所有动作必须有动机（内心渴望或外部逼迫）',
    type: SyndromeType.motivationDeficit,
    level: SkillLevel.l3,
    group: MaxAttemptsGroup.deep,
    position: 'global',
    techniques: ['T009', 'T005', 'T008'],
    actions: ['A002', 'A007', 'A003'],
  ),
  // ── 批次47（b13 角色驱动层扩容）：P041 ──
  SyndromeRecord(
    id: 'P041',
    name: '降智反派症',
    shortName: '降智反派症',
    keyword: '对手无利益动机',
    oneLine: '反派为坏而坏、降智送人头，无利益动机，冲突失真张力崩坏',
    typeLine: '对手塑造工具化，利益冲突缺席',
    trainingLine: '反派降智——放着自己的资源不用非要无脑死磕，高手博弈只为利益与活路，利益冲突到位矛盾自然爆发',
    type: SyndromeType.motivationDeficit,
    level: SkillLevel.l3,
    group: MaxAttemptsGroup.deep,
    position: 'global',
    techniques: ['T007', 'T005', 'T009'],
    actions: ['A003', 'A007'],
  ),
];
