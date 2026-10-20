// P0 验证 · 码表零实例空码检查（G8④）
//
// 规格：`.ai/reports/2026-10-20-语文知识体系研究/05-P0规格-断言粒度与锚定.md` §3
// 约束：纯函数、无 IO、无网络、无 LLM；不改任何既有调用点（§6）。
//
// 存在的意义：防 `T000` 式「码在表里、没人用、无人发现」。
// 但它真正防的是**处置失准**：一个只用过一次、那次 `target` 越界的码，
// 若按原始实例数判 `remove`，删掉的是一个真在用的码 —— 而删掉之后再也不会有人去查它。

import 'anchor.dart';

/// 关系码表（`R_none` 是兜底，不是谓词 ⇒ 不计入）。
const List<String> kRelationCodes = [
  'R_antecedent',
  'R_reuse',
  'R_shared_ref',
  'R_info_gap',
  'R_time_offset',
  'R_none',
];

/// `R_none` 的处置是"例外"，不是 keep/reserved/remove 之一。
const String kRelationFallbackCode = 'R_none';

/// 一行 gold 标注（只取 G8④ 需要的字段，其余字段不参与计数）。
class GoldRow {
  const GoldRow({
    required this.relationCode,
    required this.target,
    required this.relationEvidence,
  });

  final String relationCode;

  /// 段号（1 起）。`null` 表示该行没有 `target` 或无法解析为整数。
  final int? target;

  final List<String> relationEvidence;
}

/// 单个码的统计与处置。
class CodeStat {
  const CodeStat({
    required this.code,
    required this.rawCount,
    required this.legalCount,
    required this.invalidTargetRows,
    required this.unanchoredRows,
    required this.disposition,
  });

  final String code;

  /// 该码在 gold 里出现的**行数**（含非法行）。
  final int rawCount;

  /// `target` 在文本范围内 **且** `relation_evidence` 锚定成功的行数。
  ///
  /// **处置判定只用这个数**，否则一个只用过一次、那次 `target` 越界的码会被判 `remove`。
  final int legalCount;

  /// `target` 缺失或越界的行数（单列，不洗进任何一边）。
  final int invalidTargetRows;

  /// `target` 合法但证据未锚定的行数（单列）。
  final int unanchoredRows;

  /// `keep` / `reserved` / `remove` / `exception`。
  final String disposition;

  /// `target` 合法率。**分母是原始实例数（含非法行）** ——
  /// 若把非法行先剔掉再算，这个率永远是 1.00，等于没测。
  double get targetValidRate => rawCount == 0 ? 0 : legalCount / rawCount;

  bool get entersM17aDenominator => disposition == 'keep';
}

/// 全码表统计报告。
class CodeCensusReport {
  const CodeCensusReport({
    required this.stats,
    required this.invalidTargetRows,
    required this.unanchoredRows,
    required this.goldRows,
    required this.historyScanned,
    required this.historyFileCount,
    required this.historyScannedAt,
    required this.segmentCount,
    required this.segmentMode,
  });

  final Map<String, CodeStat> stats;

  /// 全部 gold 行的 `target` 非法行数（跨码合计）。
  final int invalidTargetRows;

  /// 全部 gold 行的证据未锚定行数（跨码合计）。
  final int unanchoredRows;

  final int goldRows;
  final bool historyScanned;
  final int historyFileCount;

  /// 历史集扫描时刻（ISO 8601）。未扫描为 null。
  final String? historyScannedAt;

  final int segmentCount;

  /// 段切分模式；`line` 时 `M17` 目标校验必须记 `undecidable`（§1.1）。
  final String segmentMode;

  /// 段切分为 `line` 兜底 ⇒ 所有 `target` 都可能填 1 ⇒ 目标校验失去分辨力。
  bool get targetCheckUndecidable => segmentMode == 'line';

  List<CodeStat> get ordered => [
    for (final c in kRelationCodes)
      if (stats.containsKey(c)) stats[c]!,
  ];

  /// 渲染成 §3.4 要求的逐码一行表。
  String toMarkdownTable() {
    final buf = StringBuffer()
      ..writeln('| relation_code | 原始实例数 | 合法实例数 | target 合法率 | 处置 | 备注 |')
      ..writeln('|:--|--:|--:|--:|:--|:--|');
    for (final s in ordered) {
      if (s.code == kRelationFallbackCode) {
        buf.writeln('| ${s.code} | — | — | — | 例外 | 兜底，不进分母 |');
        continue;
      }
      final notes = <String>[];
      if (s.invalidTargetRows > 0) {
        notes.add('${s.invalidTargetRows} 条 target 越界');
      }
      if (s.unanchoredRows > 0) notes.add('${s.unanchoredRows} 条证据未锚定');
      if (s.legalCount == 0 && s.rawCount == 0) {
        notes.add(historyScanned ? '历史集亦无' : '历史集未扫描');
      }
      buf.writeln(
        '| ${s.code} | ${s.rawCount} | ${s.legalCount} | '
        '${s.targetValidRate.toStringAsFixed(2)} | ${s.disposition} | '
        '${notes.isEmpty ? "—" : notes.join("；")} |',
      );
    }
    return buf.toString();
  }
}

/// 统计 gold 码表的零实例情况（§3.2–§3.3）。
///
/// [segmentCount] 是文本段数（`splitSegments(...).segments.length`），
/// 用于判定 `target` 是否在范围内 —— **段号必须与诊断输出引用的段号同源**，
/// 否则 `M17` 的目标校验会自己和自己打架。
///
/// [historyIndex] 是历史标注集里出现过的全部 `relation_code`（去重）。
/// **未扫描历史集时传 `historyScanned: false`**：此时任何"零实例"的码只能 `reserved`，
/// 不得 `remove` —— 「没有证据」不是「证据表明没有」。
CodeCensusReport censusGoldCodes({
  required List<GoldRow> gold,
  required int segmentCount,
  required String chunkText,
  Set<String> historyIndex = const {},
  bool historyScanned = false,
  int historyFileCount = 0,
  String? historyScannedAt,
  String segmentMode = 'blank',
  AnchorThresholds thresholds = const AnchorThresholds(),
}) {
  final tally = _CensusTally();
  for (final row in gold) {
    tally.add(
      row,
      segmentCount: segmentCount,
      chunkText: chunkText,
      thresholds: thresholds,
    );
  }

  final stats = <String, CodeStat>{
    for (final code in kRelationCodes)
      code: tally.statOf(
        code,
        historyScanned: historyScanned,
        historyIndex: historyIndex,
      ),
  };

  return CodeCensusReport(
    stats: stats,
    invalidTargetRows: tally.badTargetTotal,
    unanchoredRows: tally.unanchoredTotal,
    goldRows: gold.length,
    historyScanned: historyScanned,
    historyFileCount: historyFileCount,
    historyScannedAt: historyScannedAt,
    segmentCount: segmentCount,
    segmentMode: segmentMode,
  );
}

/// `censusGoldCodes` 的计数暂存。
///
/// 拆出来只为守住 R-019（函数 ≤50 行），并让"逐行归桶"与"单码处置"
/// 两件事各占一处 —— 它们是两个判断，混在一个循环里时容易互相借前提。
class _CensusTally {
  _CensusTally() {
    for (final code in kRelationCodes) {
      _raw[code] = 0;
      _legal[code] = 0;
      _badTarget[code] = 0;
      _unanchored[code] = 0;
    }
  }

  final _raw = <String, int>{};
  final _legal = <String, int>{};
  final _badTarget = <String, int>{};
  final _unanchored = <String, int>{};

  int get badTargetTotal => _badTarget.values.fold(0, (a, b) => a + b);

  int get unanchoredTotal => _unanchored.values.fold(0, (a, b) => a + b);

  /// 单行归桶：先数原始行，再判 target 是否在范围内，最后判证据能否锚上。
  void add(
    GoldRow row, {
    required int segmentCount,
    required String chunkText,
    required AnchorThresholds thresholds,
  }) {
    final code = row.relationCode;
    _raw[code] = (_raw[code] ?? 0) + 1;

    // `R_none` 是兜底，不参与合法/非法计数（它不是谓词）
    if (code == kRelationFallbackCode) return;

    final target = row.target;
    final targetInRange =
        target != null && target >= 1 && target <= segmentCount;
    if (!targetInRange) {
      _badTarget[code] = (_badTarget[code] ?? 0) + 1;
      return;
    }

    final anyAnchored = anchorEvidence(
      chunkText,
      row.relationEvidence,
      thresholds: thresholds,
    ).any((a) => a.status.isAnchored);
    if (anyAnchored) {
      _legal[code] = (_legal[code] ?? 0) + 1;
    } else {
      _unanchored[code] = (_unanchored[code] ?? 0) + 1;
    }
  }

  /// 单码处置（§3.3）。零实例分四档，其中两档都给 `reserved` ——
  /// 理由同一条：**「没有证据」不是「证据表明没有」**。
  CodeStat statOf(
    String code, {
    required bool historyScanned,
    required Set<String> historyIndex,
  }) {
    final r = _raw[code] ?? 0;
    final l = _legal[code] ?? 0;
    final String disposition;
    if (code == kRelationFallbackCode) {
      disposition = 'exception';
    } else if (l >= 1) {
      disposition = 'keep';
    } else if (r >= 1) {
      // 有行，但 target 越界或证据未锚定 ⇒ 不得 keep，也不得 remove
      disposition = 'reserved';
    } else if (!historyScanned) {
      // 历史集未扫 ⇒ 不能断言"从未出现"
      disposition = 'reserved';
    } else if (historyIndex.contains(code)) {
      disposition = 'reserved';
    } else {
      disposition = 'remove';
    }
    return CodeStat(
      code: code,
      rawCount: r,
      legalCount: l,
      invalidTargetRows: _badTarget[code] ?? 0,
      unanchoredRows: _unanchored[code] ?? 0,
      disposition: disposition,
    );
  }
}
