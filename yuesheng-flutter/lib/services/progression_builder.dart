// ─────────────────────────────────────────────────────────────
// progression_builder — Progressions 章节演进纯逻辑（第三批）
//
// 把「断言 + 事件 + 首见章节」聚合为按章节升序的时间轴节点。
// 角色与世界观共用（两者断言同为 CharacterAssertion）。
//
// 约定：
//   - 无章节的断言/事件不进时间轴（章节为序，无处置放）
//   - firstSeenChapter 若该章已有断言则不重复插「首次出现」
//   - 空输入 → 空列表（区块据此隐藏）
// ─────────────────────────────────────────────────────────────

import '../../data/database/database.dart';
import '../../types/character_types.dart';

/// 单个时间轴节点（一个章节）。
class ProgressionPoint {
  final int chapter;

  /// 该章条目：'首次出现' / '属性: 值' / '事件名'。
  final List<String> items;

  const ProgressionPoint({required this.chapter, required this.items});
}

/// 聚合为章节时间轴（升序）。
List<ProgressionPoint> buildProgressions({
  required List<CharacterAssertion> assertions,
  List<EventFact> events = const [],
  int? firstSeenChapter,
}) {
  final byChapter = <int, List<String>>{};

  if (firstSeenChapter != null) {
    byChapter[firstSeenChapter] = ['首次出现'];
  }
  for (final a in assertions) {
    final ch = a.chapter;
    if (ch == null) continue;
    byChapter.putIfAbsent(ch, () => []).add('${a.attribute}: ${a.value}');
  }
  for (final e in events) {
    final ch = e.chapter;
    if (ch == null) continue;
    byChapter.putIfAbsent(ch, () => []).add(e.name);
  }

  if (byChapter.isEmpty) return const [];

  final chapters = byChapter.keys.toList()..sort();
  return [
    for (final ch in chapters)
      ProgressionPoint(chapter: ch, items: byChapter[ch]!),
  ];
}
