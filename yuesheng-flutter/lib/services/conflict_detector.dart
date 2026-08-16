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
List<ConflictObservation> detectCharacterConflicts(
  List<CharacterFactInput> characters,
) {
  final observations = <ConflictObservation>[];

  for (final character in characters) {
    final byAttribute = <String, List<CharacterAssertion>>{};
    for (final assertion in character.assertions) {
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
