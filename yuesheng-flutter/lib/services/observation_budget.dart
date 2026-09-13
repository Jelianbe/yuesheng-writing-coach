// ─────────────────────────────────────────────────────────────
// ObservationBudget — 观察段两级预算（S2 · R3/R4，X-043 镜像）
//
// 病灶：4 个事实表驱动的观察构建器（conflict/world/causality/subplot）
// 条数无上限、随资料库线性增长（侦察报告 P2）。本类把裁剪收敛为纯函数
//（ADR-C74：新逻辑进独立类，不塞进已千行的 chat_context_builder.dart）：
//
//   ① 条数上限 [ContextBudget.observationMaxItems] 砍尾
//      —— Q3 甲：输入已是判据稳定序（conflict_detector.dart 字典序，
//      判据禁改），本类**不重排、只砍尾**，零新增排序逻辑；
//   ② 段级字符预算 [ContextBudget.observationSectionBudgetChars]
//      按行累计、超限即停（X-043 同款「只计可变行」口径——固定骨架
//      标题/说明不计入预算）。
//
// 零行为变更面（R3-AC3）：未超限 → kept == 输入、dropped == 0，
// kept.join('\n') 与现输出逐字节一致。
// 留痕（R7 / C63 范式）：仅裁剪发生时 debugPrint 一条（含段名+丢弃数）；
// 未触发零日志。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';

import 'package:writingcoach/config/shared_constants.dart';

/// 裁剪结果：[kept] = 保留行（**保序**），[dropped] = 丢弃总条数
/// （条数上限 + 字符预算两级合计）
typedef KeptAndDropped = ({List<String> kept, int dropped});

/// 观察段两级预算（无状态，纯函数，无 IO）
abstract final class ObservationBudget {
  /// 对观察行 [lines]（判据稳定序）执行两级裁剪：先条数上限砍尾、
  /// 再按字符预算逐行累计超限即停。
  ///
  /// [section]：段名，仅用于裁剪留痕日志（R7），不参与裁剪判定。
  static KeptAndDropped apply(List<String> lines, {required String section}) {
    // ① 条数上限：> N 砍尾到 N（Q3 甲：不重排）
    final capped = lines.length > ContextBudget.observationMaxItems
        ? lines.sublist(0, ContextBudget.observationMaxItems)
        : lines;
    final droppedByCount = lines.length - capped.length;

    // ② 字符预算：逐行累计（只计可变行），超限即停，该行及之后全丢弃
    final kept = <String>[];
    var used = 0;
    var droppedByChars = 0;
    for (final line in capped) {
      if (used + line.length > ContextBudget.observationSectionBudgetChars) {
        droppedByChars = capped.length - kept.length;
        break;
      }
      kept.add(line);
      used += line.length;
    }

    final dropped = droppedByCount + droppedByChars;
    if (dropped > 0) {
      debugPrint('[ObservationBudget] $section 截断 $dropped 条');
    }
    return (kept: kept, dropped: dropped);
  }

  /// 条级知情截断提示（X-043 同款形态，US-4）：明示「已见部分非全部」，
  /// 由构建器在 dropped > 0 时追加在观察行之后。
  static String truncationNotice(int dropped) {
    return '### 观察截断提示\n'
        '由于本轮观察段预算 ${ContextBudget.observationSectionBudgetChars} chars / '
        '条数上限 ${ContextBudget.observationMaxItems} 条，'
        '另有 $dropped 条观察未列出。回复时不要把已列出的部分当作全部线索。';
  }
}
