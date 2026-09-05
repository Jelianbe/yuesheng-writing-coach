// ─────────────────────────────────────────────────────────────
// conflict_detector — A6 首步：时序矛盾冲突检测（批次66 B62i）
//
// 检测「同属性不同值」的时序矛盾（例：第3章「独生子」/ 第15章出现「妹妹」），
// 观察项挂 F05（OOC 检测 / P018 人设崩塌症）补充：行为偏离已建立的模式。
// 纯函数、无 IO，输入输出均为不可变数据，便于单测。
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
    final byAttribute = <String, List<CharacterAssertion>>{};
    for (final assertion in character.assertions) {
      if (!isActiveAssertion(assertion)) continue;
      byAttribute.putIfAbsent(assertion.attribute, () => []).add(assertion);
    }

    for (final entry in byAttribute.entries) {
      final values = List<CharacterAssertion>.from(entry.value)
        ..sort(_byTimeAsc);
      // 按出现序保留最早的两个不同值
      final seen = <String>{};
      final ordered = <CharacterAssertion>[];
      for (final v in values) {
        if (seen.add(v.value)) ordered.add(v);
        if (ordered.length >= 2) break;
      }
      if (ordered.length < 2) continue;

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
