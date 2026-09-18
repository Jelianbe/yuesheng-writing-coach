// ─────────────────────────────────────────────────────────────
// 章节版本快照保留策略（**共享叶子模块**）
//
// 为什么单独一个文件：
//   本策略有两个消费方 ——
//     · `lib/data/repositories/app_state_repository.dart` → `addChapterVersion`（唯一写入方）
//     · `test/data/repositories/version_retention_test.dart` → 纯函数单测（无需 DB）
//   若把实现放进 `app_state_repository.dart`（`ChapterVersion` 的定义处），
//   任何外部复用者与单测都要**反向 import 仓库** ⇒ 文件级环 ⇒ 门禁 3（循环依赖）零容忍。
//   ⇒ 本模块**不 import 任何项目内文件**（只依赖 `dart:convert`），靠**泛型 + 选择器**
//     （`savedAtOf` / `bytesOf`）工作，因此它**不认识** `ChapterVersion`。
//
// 策略来源：`.ai/reports/2026-09-18-N3-版本时间机器-设计.md §6.1.4`
//   时间桶（新→旧扫描）：近 24h 每 1h 桶留最新 1 条 · 近 7d 每 1d 桶留最新 1 条 ·
//   近 30d 每 7d 桶留最新 1 条 · 30d 以上每 30d 桶留最新 1 条；
//   硬上限：每章 ≤ 40 条 **且** 正文合计 ≤ 512 KB；保底：最新 1 条永不淘汰。
//
// ★ 两处**有意收窄**（相对设计稿原文的显式偏离）：
//   ① **优先**保留最新 `kRecentKeepFloor`(=10) 条，不受分桶影响；仅在**体积硬顶**
//      （`kMaxChapterVersionBytes`）下可被压低，但**至少保留最新 1 条**。
//      —— 硬顶是「必须」，保底是「尽量」：单条正文 > 约 1.75 万汉字（> 52,428
//         UTF-8 字节）时 10 条合计即撞 512 KB，实际保留条数会 **< 10**。
//      理由：分桶按**墙钟**切割，而快照按「每 200 字」触发 —— 用户在一次写作里连写
//      2000 字会产生 10 条快照，若严格「1 小时桶留 1 条」，这 10 条会坍缩成 1 条，
//      时光机在**最常用场景**下几乎无内容可看。加下限后：单次写作
//      （≤10 条**且正文 ≤ ~1.7 万字**）零退化，跨天/跨月的稀释效果不变。
//   ② 排序必须是**确定性**的：`savedAt` 降序，**同秒时按原下标升序**。
//      理由：Dart 的 `List.sort` **不保证稳定**，同秒多条时顺序会漂（会让测试 flaky）。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

/// 每章版本快照条数上限
const int kMaxChapterVersions = 40;

/// 每章版本快照总体积上限（UTF-8 字节）
const int kMaxChapterVersionBytes = 512 * 1024;

/// **优先**保留的最新条数（体积硬顶下可被压低，但至少保留最新 1 条）
const int kRecentKeepFloor = 10;

/// 单条快照的落库体积（UTF-8 真实字节数，**不是** String.length 的 UTF-16 码元数）
int chapterVersionBytes(String content) => utf8.encode(content).length;

/// 时间桶标识（桶内只留最新 1 条）。
///
/// `age = nowSec - savedAt`，为负（时钟回拨 / 未来时间戳）时钳到 0。
String versionBucketOf(int savedAt, int nowSec) {
  final rawAge = nowSec - savedAt;
  final age = rawAge < 0 ? 0 : rawAge;
  if (age <= 24 * 3600) return 'h${age ~/ 3600}';
  if (age <= 7 * 86400) return 'd${age ~/ 86400}';
  if (age <= 30 * 86400) return 'w${age ~/ 604800}';
  return 'm${age ~/ 2592000}';
}

/// 纯函数：返回应保留的条目（新→旧）。
///
/// 执行顺序：确定性排序 → 分桶 ∪ 最新 [recentFloor] 条 → 条数上限 → 体积上限。
/// 语义详见文件头「分级保留策略」与「两处有意收窄」。
List<T> retainVersions<T>(
  List<T> items, {
  required int Function(T) savedAtOf,
  required int Function(T) bytesOf,
  required int nowSec,
  int maxCount = kMaxChapterVersions,
  int maxBytes = kMaxChapterVersionBytes,
  int recentFloor = kRecentKeepFloor,
}) {
  final sorted = _sortNewestFirst(items, savedAtOf);
  final bucketed = _applyBuckets(
    sorted,
    savedAtOf: savedAtOf,
    nowSec: nowSec,
    recentFloor: recentFloor,
  );
  final capped = _applyCountLimit(bucketed, maxCount < 1 ? 1 : maxCount);
  return _applyByteLimit(capped, bytesOf: bytesOf, maxBytes: maxBytes);
}

/// 按 `savedAt` 降序排序；**同秒按原下标升序**。
///
/// 必须显式定序：Dart 的 `List.sort` 不保证稳定，同秒多条时顺序会漂。
List<T> _sortNewestFirst<T>(List<T> items, int Function(T) savedAtOf) {
  final order = List<int>.generate(items.length, (i) => i);
  order.sort((a, b) {
    final byTime = savedAtOf(items[b]).compareTo(savedAtOf(items[a]));
    return byTime != 0 ? byTime : a.compareTo(b);
  });
  return [for (final i in order) items[i]];
}

/// 分桶 + 优先保底：桶内只留最新 1 条；最新 [recentFloor] 条**优先**保留。
///
/// 「优先」而非「无条件」：本阶段之后的体积阶段（[_applyByteLimit]）仍会从尾部丢，
/// 可把结果压到 [recentFloor] 以下（最低 1 条）。见文件头 ★①。
///
/// 入参已按新→旧排好，故「首次出现即最新」；输出保持新→旧顺序。
List<T> _applyBuckets<T>(
  List<T> sorted, {
  required int Function(T) savedAtOf,
  required int nowSec,
  required int recentFloor,
}) {
  final seen = <String>{};
  final kept = <T>[];
  for (var i = 0; i < sorted.length; i++) {
    final item = sorted[i];
    final bucket = versionBucketOf(savedAtOf(item), nowSec);
    if (i < recentFloor) {
      kept.add(item);
      seen.add(bucket);
      continue;
    }
    if (seen.add(bucket)) kept.add(item);
  }
  return kept;
}

/// 条数上限：取前 [maxCount] 条（调用方已把 `maxCount` 钳到 ≥1）。
List<T> _applyCountLimit<T>(List<T> kept, int maxCount) =>
    kept.length <= maxCount ? kept : kept.sublist(0, maxCount);

/// 体积上限：从**最旧**（列表尾）开始丢，直到总量 ≤ [maxBytes]，但**至少保留 1 条**。
///
/// 只剩 1 条仍超预算 = 单条即超预算；保留它是设计选择（最新永不淘汰）。
List<T> _applyByteLimit<T>(
  List<T> kept, {
  required int Function(T) bytesOf,
  required int maxBytes,
}) {
  if (kept.isEmpty) return kept;
  var total = 0;
  for (final item in kept) {
    total += bytesOf(item);
  }
  var last = kept.length;
  while (last > 1 && total > maxBytes) {
    last--;
    total -= bytesOf(kept[last]);
  }
  return last == kept.length ? kept : kept.sublist(0, last);
}
