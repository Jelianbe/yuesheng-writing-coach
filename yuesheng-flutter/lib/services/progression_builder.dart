// ─────────────────────────────────────────────────────────────
// progression_builder — Progressions 章节演进纯逻辑（第三批）
//
// 把「断言 + 事件 + 首见章节」聚合为按章节升序的时间轴节点。
// 角色与世界观共用（两者断言同为 CharacterAssertion）。
//
// ★ 分组键 = **身份**（`chapters.sort_order`），**不是**展示号
//   （`N12-F3b` phase 3，2026-09-18；裁定与取证见
//   `.ai/reports/2026-09-18-N12-F3b-phase3.md`、`utils/chapter_number.dart` 文件头）。
//   三个来源**一律取身份载体**，**禁止**取旧列（`assertion.chapter` /
//   `event_fact.chapter`）：那一列「一列三源」（机器身份 / AI 标称号 / 用户手填），
//   读时无法分辨 —— 把它当身份会渲染出**错的数字**（`ADR-C96 §3` 反例）。
//   ⇒ 本模块只产出 `chapterIdentity`；**「第N章」文案由展示侧经 `chapterLabel` 解析**。
//
// 约定：
//   - **无身份**（`chapterSortOrder == null`）的断言 / 事件**不进时间轴** —— 与既有
//     「无章节不进时间轴」同源：时间轴的位序**就是**章节，无位序则无处可放。
//     ⚠️ **不得**把它们塞进一个「章节未知」桶：那会伪造「同章 / 同时」的分组语义
//     （`DECISIONS §4-33`）。它们在**瓦片列表 / 事件列表**里照常可见（那一侧由
//     `S1` 渲染成「章节未知」），故本视图不承载任何独有信息。
//   - firstSeenChapter 必须**已是身份**（角色侧由 `N12-F3a` 在写入前归一）；
//     若该章已有断言则不重复插「首次出现」。
//   - 空输入 → 空列表（区块据此隐藏）。
// ─────────────────────────────────────────────────────────────

import '../../data/database/database.dart';
import '../../types/character_types.dart';

/// 单个时间轴节点（一个章节）。
class ProgressionPoint {
  /// 该节点所属章节的**身份载体**（`chapters.sort_order`，0 基、可跳号、可重排）。
  ///
  /// ★ **不是展示号**：展示侧必须 `chapterLabel(chapterNoMap, chapterIdentity)`，
  /// **禁止**直接当数字渲染（见文件头口径 3）。
  final int chapterIdentity;

  /// 该章条目：'首次出现' / '属性: 值' / '事件名'。
  final List<String> items;

  const ProgressionPoint({required this.chapterIdentity, required this.items});
}

/// 聚合为章节时间轴（按**身份**升序）。
///
/// `sort_order` 本身就是作品的排序键 ⇒ 按身份升序 = 作品当前章节顺序，
/// 时间轴方向正确；且**删除 / 交换 / 跨卷移动**后自动跟随（旧列做不到这一点：
/// 它是 AI 抄来的标称号，不随重排变化）。
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
    final ch = a.chapterSortOrder;
    if (ch == null) continue;
    byChapter.putIfAbsent(ch, () => []).add('${a.attribute}: ${a.value}');
  }
  for (final e in events) {
    final ch = e.chapterSortOrder;
    if (ch == null) continue;
    byChapter.putIfAbsent(ch, () => []).add(e.name);
  }

  if (byChapter.isEmpty) return const [];

  final chapters = byChapter.keys.toList()..sort();
  return [
    for (final ch in chapters)
      ProgressionPoint(chapterIdentity: ch, items: byChapter[ch]!),
  ];
}
