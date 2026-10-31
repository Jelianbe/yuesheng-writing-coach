// ─────────────────────────────────────────────────────────────
// `position_sensitivity` 七值语义表（T-20261025-06 件1 真源）
//
// 为什么单独成文件：注册表 `syndrome_registry.dart` 已顶到 R-019 的文件级
// 基线（容差 0），把语义表平铺进去会让它继续变胖。语义表是**消费者侧**的
// 说法（判据怎么读这个字段），与「症候元数据」不是一个职责 ⇒ 独立文件。
// ─────────────────────────────────────────────────────────────

/// `position_sensitivity` 七值 → 语义（T-20261025-06 件1 · 2026-10-31 舰长确认）。
///
/// 七值**不是七个平行刻度**，是两套轴混装：
/// - 位次轴 3 值：`beginning` / `middle` / `end` —— 问「这段文本处在作品的哪一段」；
/// - 通配 1 值：`global` —— **不问位置**，任何位置都适用
///   （`skill_dispatcher.dart:90` 官方语义原文）；
/// - 规模轴 3 值：`chapter` / `serial` / `local` —— 问「判它需要看多大范围的文本」。
///
/// 值逐字取自 `.ai/reports/2026-10-31-待确认-25-06-position七值语义映射表.md` §3
/// 的「判定问题」行。`beginning` 的「第 1 章 / 前三章」口径见该稿 §5-Q2
/// （**判定算法未改**，`buildKnownPositionBlock` 仍按 band 三档）。
const Map<String, String> kPositionSemantics = {
  'beginning': '本段是否处于作品开头',
  'middle': '本段是否处于作品中段（既非开头也非结尾）',
  'end': '本段是否处于作品结尾',
  'global': '不问位置，任何位置都适用',
  'chapter': '判它需要看完整一章',
  'serial': '判它需要看连续多章',
  'local': '判它只需章内局部片段',
};

/// 位次 band（T-20261025-06 Q2 乙 · 2026-10-31 舰长批）：`beginning` 覆盖前三章。
///
/// **顺序敏感**：`end` 先于 `beginning` —— 三章书里第 3 章同时满足
/// `order>=total` 与 `order<=min(3,total)`，必须先归结尾（Q2 乙的前提）。
/// 单章书（total<=1）⇒ `global`：开头/中段/结尾同真，无从区分（Q3 乙）。
String positionBandOf(int order, int total) {
  if (total <= 1) return 'global';
  if (order >= total) return 'end';
  if (order <= (total < 3 ? total : 3)) return 'beginning';
  return 'middle';
}

/// band ⇒ 本块允许参与判定的 `position` 值集合（Q1/Q2/Q3 乙）。
///
/// - 位次轴：只允许与 band 同档的那一个值（单章书三值全允许）；
/// - 通配 `global` / 规模轴 `chapter`、`local`：不约束位置 ⇒ 全部允许；
/// - `serial`：跨章证据，单章提交下**记为不可判**（仍注入、由分块侧标
///   `uncertain` 交合并）—— Q1 乙 的口径是「不入分母」，不是「不问」。
/// - `null`（拿不到位次）⇒ 全允许 = 现行为（不过滤）。
Set<String> allowedPositionsForBand(String? band) => switch (band) {
  'beginning' => const {'beginning', 'global', 'chapter', 'local', 'serial'},
  'middle' => const {'middle', 'global', 'chapter', 'local', 'serial'},
  'end' => const {'end', 'global', 'chapter', 'local', 'serial'},
  _ => const {
    'beginning',
    'middle',
    'end',
    'global',
    'chapter',
    'local',
    'serial',
  },
};

/// 两个字段齐全且合法（1 基、`total>=1`）才返回 band；否则 null（= 不过滤）。
///
/// 与 `_knownPositionBlockOrNull` 同一条 fail-closed 纪律：半截信息判不了位置，
/// 不得据此筛判据。
String? positionBandOrNull(int? order, int? total) {
  if (order == null || total == null || order < 1 || total < 1) return null;
  return positionBandOf(order, total);
}
