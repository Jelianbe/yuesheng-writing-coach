// ─────────────────────────────────────────────────────────────
// 症候元数据注册表（真源，b9 批次27）
// 设计稿：docs/2026-08-11-b9-syndrome-registry-design.md
//
// 本文件是症候「元数据」的唯一真源：
//   - 增删症候 = 在此增删一条 SyndromeRecord（另需编写手册段 + 训练段）
//   - 各库 markdown 表格行 / 计数 / ID 列表 / 测试断言从此派生
// 内容型段落（手册正文/训练知识/重叠规则）不在此处，保留各库人工编写。
// ─────────────────────────────────────────────────────────────

import 'syndrome_skill_levels.dart'; // SkillLevel

// ─── R-019 数据分片（≤300 行）：39 条 kSyndromeRegistry 记录字面量
// 按 13/13/13 拆至 syndrome_registry_p1/p2/p3.dart（const 列表分段，宿主拼接）
part 'syndrome_registry_p1.dart';
part 'syndrome_registry_p2.dart';
part 'syndrome_registry_p3.dart';

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
