// P0 验证 · 锚定观测探针（P0-a 接线层）
//
// 规格：`.ai/reports/2026-10-20-语文知识体系研究/05-P0规格-断言粒度与锚定.md` §2 / §6
// 上游纯函数：`anchor.dart`（零 IO）。本层是它在生产链路上的唯一入口，
// 也是这个目录里唯一允许 IO（`debugPrint`）的地方。
//
// 三条纪律写死在类型里，不靠调用方记：
//   1. **只观测**：不删条、不降级、不改诊断内容 —— 接线后行为零变更；
//   2. **未测 ≠ 0 命中**：读不到原文时给 `skippedReason`，绝不返回一份全 0 的报告；
//      同理 `AER` 为 `null`（太短率超限 / 无引文）时打印 `n/a`，不打印 `0.000`；
//   3. **分母口径只有一个**：一律走 `aggregateEvidence`，本层不得自算比率。
//
// ⚠️ 本层**不产生能力读数**。它给出的只是「模型引的句子有多少真在原文里」的
//    分布；那是不是「诊断对不对」的证明，取决于标注集（06-P002标注语料）。
//
// ★ 它为什么必须存在（而不是「报告里多一个数」）：
//   `evidence_confidence.dart` 判「引文具体度」用的是
//   `evidence.first.trim().length >= 6` —— 只看第一条、只看长度、**不接触原文**。
//   1 条 ≥6 字即 0.55，阈值 `kWeakEvidenceConfidence = 0.4`，直接过线；
//   而 `listActiveProblems` 正是按 `>= 0.4` 放行。⇒ 编一条够长的假引文，
//   收益是「让错误症候进入用户的教学焦点」。在那个函数里编造与真实同价。
//   本层的 `AER` 是它唯一可能的反证通道 —— 因为只有这里手上有原文。

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;

import 'anchor.dart';

/// 读不到原文时的跳过原因（具名常量，不许空串 —— 空串无法被日志检索）。
const String kAnchorSkipNoSource = 'no_source_text';

/// 落库 payload 的版本号。**口径一变就进位**。
///
/// 没有版本号，两批记录的 `aer` 用不同算法算出来会被读成「指标变了」，
/// 而不是「算法变了」——判据自己会腐，历史也得标清楚自己是哪一代。
const int kAnchorPayloadVersion = 1;

/// 引文 head 截断长度。
///
/// 引文是用户的正文。本地库虽不上传，也没有理由把整段小说复制进观测日志：
/// 定位「是哪句」24 字足够，复算交给 `l`（原始长度）与症候 ID。
const int kAnchorHeadChars = 24;

/// 一次诊断的锚定观测报告。
class AnchorProbeReport {
  const AnchorProbeReport._({
    required this.items,
    required this.aggregate,
    required this.bySyndrome,
    required this.syndromeCount,
    required this.emptyEvidenceCount,
    required this.sourceChars,
    required this.thresholds,
    this.skippedReason,
  });

  /// **未测**：读不到原文。与「测了但 0 条引文」是两种不同状态，不得合并
  /// （合并的后果是把「没测」读成「零命中」，方向恰好相反）。
  factory AnchorProbeReport.skipped(
    String reason, {
    required int syndromeCount,
    required int sourceChars,
    AnchorThresholds thresholds = const AnchorThresholds(),
  }) {
    return AnchorProbeReport._(
      items: const [],
      aggregate: aggregateEvidence(const [], thresholds: thresholds),
      bySyndrome: const {},
      syndromeCount: syndromeCount,
      emptyEvidenceCount: 0,
      sourceChars: sourceChars,
      thresholds: thresholds,
      skippedReason: reason,
    );
  }

  /// **已测**：`sourceText` 非空，`items` 可能为空（诊断一条 evidence 都没给）。
  factory AnchorProbeReport.measured({
    required List<AnchoredEvidence> items,
    required Map<String, List<AnchoredEvidence>> bySyndrome,
    required int syndromeCount,
    required int emptyEvidenceCount,
    required int sourceChars,
    AnchorThresholds thresholds = const AnchorThresholds(),
  }) {
    return AnchorProbeReport._(
      items: items,
      aggregate: aggregateEvidence(items, thresholds: thresholds),
      bySyndrome: bySyndrome,
      syndromeCount: syndromeCount,
      emptyEvidenceCount: emptyEvidenceCount,
      sourceChars: sourceChars,
      thresholds: thresholds,
    );
  }

  /// 扁平的全部锚定结果（跨症候，按输入顺序）。汇总只用它，不用 bySyndrome。
  final List<AnchoredEvidence> items;

  /// 分母口径的唯一实现（`anchor.dart` §2.6）。
  final AnchorAggregate aggregate;

  /// 症候 ID → 该条诊断的锚定结果。用于回答「是哪条症候的引文锚不上」，
  /// **不参与汇总**（汇总走 [items]，避免漏算/重算）。
  final Map<String, List<AnchoredEvidence>> bySyndrome;

  /// 本次诊断的症候条数（**含 evidence 为空的条目**）—— 与 [evidenceCount]
  /// 是两个量：前者是「报了几条病」，后者是「引了几句话」。
  final int syndromeCount;

  /// 空白 evidence 条数。单列、**不进分母**：空白是「缺字段」，不是「引文太短」。
  final int emptyEvidenceCount;

  /// 被锚定的原文长度（UTF-16 code unit，与 `String.length` 同口径）。
  final int sourceChars;

  /// 与本次汇总**同一套**阈值（防调用方传一套、汇总用另一套）。
  final AnchorThresholds thresholds;

  /// 非 `null` ⇒ 本次**未测**。
  final String? skippedReason;

  bool get measured => skippedReason == null;

  /// 参与锚定的引文条数（= 分母的分子基数，不含空白 evidence）。
  int get evidenceCount => aggregate.total;

  /// `AER` / `M7`。**`null` = 未测**（跳过 / 无引文 / 太短率超限），不是 0。
  double? get aer => measured ? aggregate.aer : null;

  /// 一行汇总，供 `debugPrint` 与报表直接粘贴。
  ///
  /// 未测时**不打印任何比率** —— 打印 `0.000` 会让「没测」看起来像「全错」。
  String get summary {
    if (!measured) {
      return 'anchor:skipped($skippedReason) syndromes=$syndromeCount';
    }
    final a = aggregate;
    return 'anchor total=${a.total} ok=${a.okCount} amb=${a.ambiguousCount} '
        'short=${a.tooShortCount} fail=${a.failCount + a.failJoinedCount} '
        'empty=$emptyEvidenceCount shortRate=${_fmt(a.tooShortRate)} '
        'aer=${_fmt(aer)} src=$sourceChars';
  }

  static String _fmt(double? v) => v == null ? 'n/a' : v.toStringAsFixed(3);

  /// 落库用**明细** payload（JSON）。
  ///
  /// 为什么不存 `AER`：比率是明细的函数，存比率而丢原料，口径一改历史就
  /// 再也算不出来（本项目纪律：凡计数须可复算）。这里只存每一条引文的
  /// 裁决结果，`AER` 由消费方按 [items] 现算。
  ///
  /// 未测时**不写任何比率字段**，只写 `skip` —— 与 [summary] 同一条纪律：
  /// `aer: null` 和 `aer: 0` 是两件事，落库后更容易被读混，干脆不落。
  String toPayload() {
    final base = <String, Object?>{
      'v': kAnchorPayloadVersion,
      'src': sourceChars,
      'syn': syndromeCount,
      'emp': emptyEvidenceCount,
    };
    if (!measured) {
      base['skip'] = skippedReason;
      return jsonEncode(base);
    }
    // 按 bySyndrome 展开而不是 items：items 是扁平列表，丢了「哪条症候」，
    // 而「谁在编造」正是要回答的问题。
    base['n'] = items.length;
    base['items'] = [
      for (final entry in bySyndrome.entries)
        for (final e in entry.value)
          {
            's': entry.key,
            'k': e.status.code,
            'o': e.occurrences,
            'l': e.raw.trim().length,
            'h': _head(e.raw),
          },
    ];
    return jsonEncode(base);
  }

  /// 截断到 [kAnchorHeadChars]，截断时补 `…`。
  ///
  /// `…` 只做视觉提示：真实长度在 `l` 里，所以补了也不丢信息。
  static String _head(String raw) {
    final t = raw.trim();
    if (t.length <= kAnchorHeadChars) return t;
    return '${t.substring(0, kAnchorHeadChars)}…';
  }
}

/// 锚定一次诊断的全部 evidence（纯函数：零 IO / 零 LLM / 不改输入）。
///
/// [sourceText] 为 `null` 或空 ⇒ 返回 **未测**，不返回全 0 报告。
/// [evidenceBySyndrome] 的键是症候 ID，值是该条诊断的 `evidence` 原文列表。
AnchorProbeReport probeAnchors({
  required String? sourceText,
  required Map<String, List<String>> evidenceBySyndrome,
  AnchorThresholds thresholds = const AnchorThresholds(),
}) {
  final syndromeCount = evidenceBySyndrome.length;
  if (sourceText == null || sourceText.isEmpty) {
    return AnchorProbeReport.skipped(
      kAnchorSkipNoSource,
      syndromeCount: syndromeCount,
      sourceChars: 0,
      thresholds: thresholds,
    );
  }

  final items = <AnchoredEvidence>[];
  final bySyndrome = <String, List<AnchoredEvidence>>{};
  var empty = 0;
  for (final entry in evidenceBySyndrome.entries) {
    final quoted = <String>[];
    for (final e in entry.value) {
      // 空白 evidence 是「缺字段」不是「引文太短」。若混进 `too_short`，
      // `too_short_rate` 会被抬高到阈值以上 ⇒ 整份 `AER` 变 `null`，
      // 一份本来测得的报告会被读成「测不了」。
      if (e.trim().isEmpty) {
        empty++;
        continue;
      }
      quoted.add(e);
    }
    if (quoted.isEmpty) continue;
    final anchored = anchorEvidence(sourceText, quoted, thresholds: thresholds);
    bySyndrome[entry.key] = anchored;
    items.addAll(anchored);
  }

  return AnchorProbeReport.measured(
    items: items,
    bySyndrome: bySyndrome,
    syndromeCount: syndromeCount,
    emptyEvidenceCount: empty,
    sourceChars: sourceText.length,
    thresholds: thresholds,
  );
}

/// 单条观测记录。
class AnchorProbeRecord {
  const AnchorProbeRecord({
    required this.sessionId,
    required this.report,
    required this.atSec,
  });

  final String sessionId;
  final AnchorProbeReport report;

  /// epoch 秒（与台账时间口径一致）。
  final int atSec;
}

/// 会话级环形缓冲 + 日志。**进程内、重启即丢**：只用于当场看。
///
/// 长期读数走 `pilot_metric_event`（`PilotEventTypes.anchorProbe`），
/// 接线点在 `diagnosis_flow_handler.dart` 的 `_probeAnchors`。
/// 为什么不用 `error_logs`：那里的语义是「出错了」，`AER` 不是错误，
/// 混进去会污染错误率口径 —— 两个指标搅在一起，之后谁也说不清升的是哪一类。
class AnchorProbeLog {
  AnchorProbeLog._();

  static final AnchorProbeLog instance = AnchorProbeLog._();

  static const int capacity = 50;

  final List<AnchorProbeRecord> _recent = [];

  void record(String sessionId, AnchorProbeReport report) {
    _recent.add(
      AnchorProbeRecord(
        sessionId: sessionId,
        report: report,
        atSec: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      ),
    );
    if (_recent.length > capacity) _recent.removeAt(0);
    debugPrint('[AnchorProbe] ${report.summary} sid=$sessionId');
  }

  List<AnchorProbeRecord> get recent => List.unmodifiable(_recent);

  AnchorProbeReport? get latest => _recent.isEmpty ? null : _recent.last.report;

  @visibleForTesting
  void clear() => _recent.clear();
}
