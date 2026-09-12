// ─────────────────────────────────────────────────────────────
// conflict_detector — A6 首步：时序矛盾冲突检测（批次66 B62i）
//                     批次 E1-b：新增设定层判据（ADR-C93）
//
// 检测「同属性不同值」的时序矛盾（例：第3章「独生子」/ 第15章出现「妹妹」），
// 观察项挂 F05（OOC 检测 / P018 人设崩塌症）补充：行为偏离已建立的模式。
// 纯函数、无 IO，输入输出均为不可变数据，便于单测。
//
// ★ 本文件现有**两个并列判据**，共用骨架、语义不同（ADR-C93 D3）：
//   · [detectCharacterConflicts] —— 人物属性：个体事实不容两值并存 → 挂 F05/P018
//   · [detectWorldConflicts]     —— 设定主题：**规则天然带例外**（「灵气稀薄」+
//     「此地有灵脉」= 层次感，不是矛盾）→ 不挂 P 编号、不产症候、不进诊断面板
//   两者的分组/取值骨架共用 [_groupActive] / [_earliestTwoDistinct]，
//   防止同一语义出现两份实现导致口径分叉
//   （纪律来源：syndrome_recurrence.dart:1-7 记录的同款抽取动机）。
// ─────────────────────────────────────────────────────────────

import '../types/character_types.dart';

/// 时序矛盾观察项（挂 F05/P018 补充输入）
class ConflictObservation {
  /// 人物名
  final String characterName;

  /// 冲突属性名
  final String attribute;

  /// 按时间升序的冲突值（取最早出现的两个不同值）
  final List<CharacterAssertion> orderedValues;

  /// 人类可读描述（例：第3章「独生子」→ 第15章「妹妹」）
  final String description;

  /// 触发原文摘录（O11，批次6 6.5）：正文中最早断言值的首现片段；
  /// 数据源无正文时由调用方反查填入，不可得为 null（降级安全，不输出）
  final String? excerpt;

  const ConflictObservation({
    required this.characterName,
    required this.attribute,
    required this.orderedValues,
    required this.description,
    this.excerpt,
  });
}

/// 检测输入：人物名 + 该人物全部属性断言
typedef CharacterFactInput = ({
  String name,
  List<CharacterAssertion> assertions,
});

/// 同属性不同值 → 时序矛盾观察项
///
/// 规则（保守，纯字符串精确比较，不做语义相似度）：
///   1. 按 (人物, 属性) 分组；
///   2. 组内按 章节（null 排最后）→ 时间戳 升序排列；
///   3. 去重后不同值 ≥2 → 构成观察项，取最早出现的两个不同值。
/// 输出按 (人物名, 属性) 字典序稳定排序，便于测试与上下文注入。
///
/// C78 批次2b（§5.3）：只消费 [isActiveAssertion] 为真的断言——被用户否决的、
/// 以及所出章节已被删/已改写的（stale），一律不参与检测，否则报出来的是
/// **根本不存在的矛盾**（幽灵 F05）。
List<ConflictObservation> detectCharacterConflicts(
  List<CharacterFactInput> characters,
) {
  final observations = <ConflictObservation>[];

  for (final character in characters) {
    for (final entry in _groupActive(character.assertions).entries) {
      final ordered = _earliestTwoDistinct(entry.value);
      if (ordered == null) continue;
      observations.add(
        ConflictObservation(
          characterName: character.name,
          attribute: entry.key,
          orderedValues: ordered,
          description: ordered.map(_describeAssertion).join('→ '),
        ),
      );
    }
  }

  observations.sort((a, b) {
    final byName = a.characterName.compareTo(b.characterName);
    if (byName != 0) return byName;
    return a.attribute.compareTo(b.attribute);
  });
  return observations;
}

// ─────────────────────────────────────────────────────────────
// 设定层判据（批次 E1-b · ADR-C93 D3–D4）
//
// 世界观是**规则**，不是事实：规则天然带例外（「这个世界灵气稀薄」+
// 「此地有灵脉」不是矛盾，是层次感；「本门禁止用剑」+「反派用剑」不是矛盾，
// 是冲突设置）。直接套 F05 会产出与「幽灵事实」同形态的事故——**报告根本
// 不存在的不一致**（fact_stale_service.dart:4-7 记录过同款病根）。
// 故本判据独立成函数、独立输出类型、独立去向，仅在骨架上与 F05 共用。
// ─────────────────────────────────────────────────────────────

/// 设定主题的断言输入（与 [CharacterFactInput] 同构）。
typedef WorldFactInput = ({String name, List<CharacterAssertion> assertions});

/// 设定不一致观察项（同一设定主题内、同一属性出现不同取值）。
///
/// 与 [ConflictObservation] 并列而**不复用**：后者是 F05/P018 的专属载体
/// （见其字段名与文件头定位），复用它会让世界观调用方继承「人物属性」的
/// 字段名与措辞。这与 E1-a 复用 [CharacterAssertion] 的取舍不同——后者自述是
/// 「通用 TKG 时间维度节点」（character_types.dart:9-12），本就是通用载体。
class WorldConflictObservation {
  /// 设定主题名（`world_fact.name`，如「灵气体系」）。
  ///
  /// 它**同时承担作用域角色**：跨主题的不同取值是层次感而非不一致，
  /// 故判据只在同一主题内比较（见 [detectWorldConflicts] 第 1 条）。
  final String themeName;

  /// 冲突属性名
  final String attribute;

  /// 按时间升序的冲突值（取最早出现的两个不同值）
  final List<CharacterAssertion> orderedValues;

  /// 人类可读描述（例：第3章「稀薄」→ 第20章「充沛」）
  final String description;

  /// 原文依据：**类型上非空**——[detectWorldConflicts] 的门槛要求参与检测的
  /// 断言必带 `evidence`（D4①），故直接取最早断言的摘录，无需反查正文。
  /// 这比 character 侧的 `String? excerpt` + `findKeywordExcerpt` 反查更强：
  /// 门槛机制同时充当了摘录来源。
  final String excerpt;

  const WorldConflictObservation({
    required this.themeName,
    required this.attribute,
    required this.orderedValues,
    required this.description,
    required this.excerpt,
  });
}

/// 同（设定主题, 属性）不同取值 → 设定不一致观察项。
///
/// **不挂 P 编号、不产症候、不进诊断面板**——去向只有 AI 上下文（ADR-C93 Q4）。
/// 与 [detectCharacterConflicts] 的四处差异（ADR-C93 D3/D4，逐条）：
///   1. **分组键含主题名**——`world_fact.name` 承担作用域角色，**跨主题不做比较**：
///      规则与例外（「灵气稀薄」+「此地有灵脉」）本就是不同主题下的两层；
///   2. **门槛更严**——除 [isActiveAssertion] 外还要求断言带 `evidence`（[_hasEvidence]），
///      无原文可核对的断言一律不参与，使「幽灵设定」在判据层不可能产出；
///   3. **同章豁免**——两条断言出自同一章时不报：同一章内的两种措辞不是
///      时序矛盾，F05 的时间维度语义在此不成立；
///   4. **输出类型独立 + 措辞为「不一致」**（不是「矛盾」）。
///
/// 输出按 (主题名, 属性) 字典序稳定排序，便于测试与上下文注入。
List<WorldConflictObservation> detectWorldConflicts(
  List<WorldFactInput> worlds,
) {
  final observations = <WorldConflictObservation>[];

  for (final world in worlds) {
    final grouped = _groupActive(world.assertions, extraGuard: _hasEvidence);
    for (final entry in grouped.entries) {
      final ordered = _earliestTwoDistinct(entry.value);
      if (ordered == null) continue;
      // D4③ 同章豁免：chapter 相同（含同为 null——无章节信息即无法判定为时序差）
      if (ordered[0].chapter == ordered[1].chapter) continue;
      observations.add(
        WorldConflictObservation(
          themeName: world.name,
          attribute: entry.key,
          orderedValues: ordered,
          description: ordered.map(_describeAssertion).join('→ '),
          // 非空由 [_hasEvidence] 门槛保证（同文件内不变式）。
          excerpt: ordered.first.evidence!,
        ),
      );
    }
  }

  observations.sort((a, b) {
    final byTheme = a.themeName.compareTo(b.themeName);
    if (byTheme != 0) return byTheme;
    return a.attribute.compareTo(b.attribute);
  });
  return observations;
}

/// D4① 硬门槛：断言须带**正文原文摘录**（非转述、非概括）才参与设定层检测。
///
/// 世界观条款是**命题式陈述**，比人物属性更易被 AI 从氛围描写中误抽
/// （「山风透着寒意」→「此地终年寒冷」），而 [CharacterAssertion] 又**没有
/// pending 态**（character_types.dart:26：枚举仅 confirmed/rejected，存量断言
/// 默认 confirmed）——AI 抽取一经写入即参与检测，零缓冲。
/// 判据层的这道门槛正是补这个缺口：无原文依据即不参与，且零类型改动。
bool _hasEvidence(CharacterAssertion a) => (a.evidence ?? '').isNotEmpty;

// ─────────────────────────────────────────────────────────────
// 判据共用骨架（唯一实现处——见文件头，勿在调用点重写）
// ─────────────────────────────────────────────────────────────

/// C78 批次2b（§5.3）：断言是否参与 F05 检测——**判据共用**的唯一定义处。
///
/// 两条各自成立的否决理由：
/// - `status != 'confirmed'`：用户已否决（D-2 枚举仅 confirmed / rejected）。
///   否决了还拿来做矛盾检测，等于替用户撤回决定（R-009 用户主权）。
/// - `stale`：该断言所出章节已被删除或已改写（D-6），原文都不在了，
///   它参与比较得出的矛盾是**幽灵矛盾**——正是本批要根除的病根。
///
/// 判据放这里而不散在调用点：F05 检测与 UI 侧灰显（批次 3）共用同一份定义，
/// 不会分叉出「检测算它、界面不显示」或反之的错位。
bool isActiveAssertion(CharacterAssertion a) {
  return a.status == 'confirmed' && !a.stale;
}

/// 按属性分组（仅含活跃断言）。
///
/// [extraGuard] 供设定层追加门槛（[detectWorldConflicts] 传 [_hasEvidence]）；
/// character 侧不传 → 与抽取前逐字等价，行为零变更。
/// 门槛写在判据内部而非调用点，是为了让它**不可被调用方绕过**。
Map<String, List<CharacterAssertion>> _groupActive(
  List<CharacterAssertion> assertions, {
  bool Function(CharacterAssertion a)? extraGuard,
}) {
  final byAttribute = <String, List<CharacterAssertion>>{};
  for (final assertion in assertions) {
    if (!isActiveAssertion(assertion)) continue;
    if (extraGuard != null && !extraGuard(assertion)) continue;
    byAttribute.putIfAbsent(assertion.attribute, () => []).add(assertion);
  }
  return byAttribute;
}

/// 按（章节 → 时间戳）升序取**最早的两个不同值**；不足两个不同值 → null。
///
/// 顺序不可调换：先按时间排序、再去重，才能保证留下的两个是「最早出现的」；
/// 若先去重会篡改「最早」的判定，把真矛盾洗成单值。
List<CharacterAssertion>? _earliestTwoDistinct(
  List<CharacterAssertion> values,
) {
  final sorted = List<CharacterAssertion>.from(values)..sort(_byTimeAsc);
  final seen = <String>{};
  final ordered = <CharacterAssertion>[];
  for (final v in sorted) {
    if (seen.add(v.value)) ordered.add(v);
    if (ordered.length >= 2) break;
  }
  return ordered.length < 2 ? null : ordered;
}

/// 断言时间序：章节（null 排最后）→ 时间戳
int _byTimeAsc(CharacterAssertion a, CharacterAssertion b) {
  final ca = a.chapter ?? (1 << 30);
  final cb = b.chapter ?? (1 << 30);
  if (ca != cb) return ca.compareTo(cb);
  return a.timestamp.compareTo(b.timestamp);
}

String _describeAssertion(CharacterAssertion a) {
  final chapter = a.chapter;
  return chapter != null ? '第$chapter章「${a.value}」' : '早期「${a.value}」';
}
