// P0 验证 · evidence 子串锚定（P0-a）
//
// 规格：`.ai/reports/2026-10-20-语文知识体系研究/05-P0规格-断言粒度与锚定.md` §2
// 约束：纯函数、无 IO、无网络、无 LLM；不改任何既有调用点（§6）。
//
// 存在的全部意义：分清「**引了原文**」与「**原文真有**」。
// ⇒ 宁可判 fail，不可判"差不多对"：不简繁转换、不同义改写、不去标点、不做编辑距离兜底。

import 'assertion.dart' show stripQuotes;

/// 工作阈值（`工作阈值·未标定`）。正文只写符号，数值只在此处与 `04` §5.9 各一处。
class AnchorThresholds {
  const AnchorThresholds({
    this.tooShortChars = 6,
    this.tooShortRateMax = 0.15,
    this.ambiguousOccurrences = 3,
    this.ellipsisMinRatio = 0.6,
  });

  /// 引文短于此长度判 `too_short`（既不判 ok 也不判 fail，**但进分母**）。
  final int tooShortChars;

  /// `too_short_rate` 超过此值 ⇒ `AER` 判 `未测`，不许当作有效读数。
  final double tooShortRateMax;

  /// 命中处数超过此值判 `ambiguous`（取首处，**不进 ELA**）。
  final int ambiguousOccurrences;

  /// 省略号拼段的命中比例下限。
  final double ellipsisMinRatio;
}

/// 单条 evidence 的锚定状态（§2.4 全状态枚举，不许合并）。
enum AnchorStatus {
  okExact,
  okWs,
  okWidth,
  okJoined,
  ambiguous,
  tooShort,
  fail,
  failJoined,
}

extension AnchorStatusX on AnchorStatus {
  /// 是否"锚定成功"（计入 `AER`/`M7` 分子）。
  bool get isAnchored =>
      this == AnchorStatus.okExact ||
      this == AnchorStatus.okWs ||
      this == AnchorStatus.okWidth ||
      this == AnchorStatus.okJoined ||
      this == AnchorStatus.ambiguous;

  /// 是否进 `ELA` 的可用定位（只有三级精确命中可进）。
  ///
  /// `ambiguous` 的首处不一定是金标那处（概率约 `1/k`），
  /// `ok_joined` 的 span 跨过了省略号挖掉的空洞 —— 二者算进 `ELA` 都会把
  /// "这段文字本身重复度高/被省略号切断"读成"模型定位能力差"，归因反了。
  bool get isElaEligible =>
      this == AnchorStatus.okExact ||
      this == AnchorStatus.okWs ||
      this == AnchorStatus.okWidth;

  String get code => switch (this) {
    AnchorStatus.okExact => 'ok_exact',
    AnchorStatus.okWs => 'ok_ws',
    AnchorStatus.okWidth => 'ok_width',
    AnchorStatus.okJoined => 'ok_joined',
    AnchorStatus.ambiguous => 'ambiguous',
    AnchorStatus.tooShort => 'too_short',
    AnchorStatus.fail => 'fail',
    AnchorStatus.failJoined => 'fail_joined',
  };
}

/// 一条 evidence 的锚定结果。
class AnchoredEvidence {
  const AnchoredEvidence({
    required this.raw,
    required this.status,
    this.span,
    this.occurrences = 0,
    this.matchLevel,
    this.droppedParts = 0,
  });

  final String raw;
  final AnchorStatus status;

  /// **原文坐标**（`[start, end)`）。归一化坐标绝不允许出现在这里。
  final List<int>? span;

  final int occurrences;

  /// `exact` / `ws` / `width` / `joined`；未命中为 null。
  final String? matchLevel;

  /// 省略号拼段时被丢弃的短段数（单列 `dropped_parts`，**不进分母**）。
  final int droppedParts;

  @override
  String toString() => '${status.code}${span == null ? "" : " $span"} | $raw';
}

/// 锚定结果汇总（**分母口径写死在这里，任何调用方不得自算** §2.6）。
class AnchorAggregate {
  const AnchorAggregate({
    required this.total,
    required this.okCount,
    required this.ambiguousCount,
    required this.tooShortCount,
    required this.failCount,
    required this.failJoinedCount,
    required this.elaEligible,
    required this.tooShortRateMax,
  });

  final int total;
  final int okCount;
  final int ambiguousCount;
  final int tooShortCount;
  final int failCount;
  final int failJoinedCount;
  final List<AnchoredEvidence> elaEligible;

  /// 与本次锚定**同一套**阈值。写死成常量会让调用方传入的阈值在汇总时被静默忽略。
  final double tooShortRateMax;

  int get denominator =>
      okCount + ambiguousCount + failCount + failJoinedCount + tooShortCount;

  /// `AER` / `M7`（**同一定义，只算一次**）。
  ///
  /// `null` 表示 **`未测`**：`too_short_rate` 超限时不许给出一个数。
  /// 理由：模型只要系统性只引 5 个字（短到无法证伪），这些条目就会既不是 ok
  /// 也不是 fail —— 若从分母删掉，`AER` 只在"长引用"里计算，**虚高且看不出来**。
  double? get aer {
    if (denominator == 0) return null;
    if (tooShortRate > tooShortRateMax) return null;
    return (okCount + ambiguousCount) / denominator;
  }

  double get tooShortRate => total == 0 ? 0 : tooShortCount / total;
  double get ambiguousRate => total == 0 ? 0 : ambiguousCount / total;
  double get unverifiedRate =>
      total == 0 ? 0 : (failCount + failJoinedCount) / total;
  double get joinedFailRate => total == 0 ? 0 : failJoinedCount / total;

  /// `NCR-anchored`（`M10` 的锚定版）：`evidence` 非空且至少一条 `ok_*`/`ambiguous`。
  ///
  /// ⚠️ 这不是 `NCR`（`04` §5.7，只问 `evidence >= 1`、不问是否锚上）。
  /// 不变量：`NCR-anchored <= NCR` 恒成立；反了 ⇒ 实现有 bug。
  bool get ncrAnchored => okCount + ambiguousCount > 0;
}

/// 汇总（分母口径的唯一实现）。
AnchorAggregate aggregateEvidence(
  List<AnchoredEvidence> items, {
  AnchorThresholds thresholds = const AnchorThresholds(),
}) {
  var ok = 0, amb = 0, ts = 0, fail = 0, fj = 0;
  final ela = <AnchoredEvidence>[];
  for (final e in items) {
    switch (e.status) {
      case AnchorStatus.okExact:
      case AnchorStatus.okWs:
      case AnchorStatus.okWidth:
        ok++;
        ela.add(e);
      case AnchorStatus.okJoined:
        ok++;
      case AnchorStatus.ambiguous:
        amb++;
      case AnchorStatus.tooShort:
        ts++;
      case AnchorStatus.fail:
        fail++;
      case AnchorStatus.failJoined:
        fj++;
    }
  }
  return AnchorAggregate(
    total: items.length,
    okCount: ok,
    ambiguousCount: amb,
    tooShortCount: ts,
    failCount: fail,
    failJoinedCount: fj,
    elaEligible: ela,
    tooShortRateMax: thresholds.tooShortRateMax,
  );
}

/// 归一化 + **下标映射**。
///
/// `offMap[i]` = 归一化串第 `i` 个字符对应的原文下标。
/// ⚠️ 归一化会改变字符串长度（折叠空白、全半角统一），`find` 返回的是归一化偏移。
/// 直接拿它当原文坐标，偏移只差几个字符，**`IoU` 仍可能 > 0.5，于是被误判为"定位正确"**
/// —— 错得像真的，比明显错更危险（§2.6）。
class _Normalized {
  const _Normalized(this.text, this.offMap);

  final String text;

  /// 长度 = `text.length`；末位回填时用 `offMap[end-1] + 1`。
  final List<int> offMap;
}

_Normalized _normalize(String source, int level) {
  // L0：原样
  if (level == 0) {
    return _Normalized(source, List<int>.generate(source.length, (i) => i));
  }

  // L1：折叠空白（两侧去 + 内部连续空白 → 单空格）
  final ws = _collapseWhitespace(source);
  if (level == 1) return ws;

  // L2：全半角统一（仅标点、数字、字母；**汉字不动**）—— 一对一映射，offMap 不变
  final buf = StringBuffer();
  for (var k = 0; k < ws.text.length; k++) {
    buf.write(_toHalfWidth(ws.text[k]));
  }
  return _Normalized(buf.toString(), ws.offMap);
}

/// L1：内部连续空白折叠为单空格、两侧去空白，`offMap` 逐字符回填原文下标。
_Normalized _collapseWhitespace(String source) {
  final buf = StringBuffer();
  final map = <int>[];
  var i = 0;
  while (i < source.length) {
    final ch = source[i];
    if (_isSpace(ch)) {
      final runStart = i;
      while (i < source.length && _isSpace(source[i])) {
        i++;
      }
      buf.write(' ');
      map.add(runStart);
    } else {
      buf.write(ch);
      map.add(i);
      i++;
    }
  }
  var text = buf.toString();
  var offMap = map;

  // 两侧去空白：同步裁 offMap（否则映射整体错位）
  var startTrim = 0;
  while (startTrim < text.length && text[startTrim] == ' ') {
    startTrim++;
  }
  var endTrim = text.length;
  while (endTrim > startTrim && text[endTrim - 1] == ' ') {
    endTrim--;
  }
  if (startTrim > 0 || endTrim < text.length) {
    text = text.substring(startTrim, endTrim);
    offMap = offMap.sublist(startTrim, endTrim);
  }
  return _Normalized(text, offMap);
}

bool _isSpace(String c) =>
    c == ' ' || c == '\n' || c == '\r' || c == '\t' || c == '\u3000';

/// 全角 → 半角（一对一，长度不变）。汉字原样返回。
///
/// ⚠️ U+FF01–FF5E 只覆盖「全角 ASCII」区段，**不覆盖弯引号与中文专用标点**
/// （`“”` U+201C/201D、`‘’` U+2018/2019、`「」` U+300C/300D、`。` U+3002）。
/// 规格 §2.2 点名要求 `“”` ↔ `""`，漏映射的直接后果是这类引文**永远判 fail**
/// —— 而 fail 会被读成"模型编造证据"，归因完全反了。
String _toHalfWidth(String c) {
  final code = c.codeUnitAt(0);
  if (code == 0x3000) return ' ';
  if (code >= 0xFF01 && code <= 0xFF5E) {
    return String.fromCharCode(code - 0xFEE0);
  }
  const map = {
    '。': '.',
    '、': ',',
    '「': '"',
    '」': '"',
    '『': "'",
    '』': "'",
    '“': '"',
    '”': '"',
    '‘': "'",
    '’': "'",
    '—': '-',
    '－': '-',
  };
  return map[c] ?? c;
}

/// 找所有出现位置（不重叠）。
List<int> _findAll(String haystack, String needle) {
  final out = <int>[];
  if (needle.isEmpty) return out;
  var from = 0;
  while (true) {
    final idx = haystack.indexOf(needle, from);
    if (idx < 0) break;
    out.add(idx);
    from = idx + needle.length;
  }
  return out;
}

/// 在单一归一化层级上锚定一条引文。
///
/// 连同 `offMap` 一起返回：调用方若要回填原文坐标，用的必须是**同一次**归一化的映射。
/// 再归一化一遍等于用两个可能不同的映射对同一偏移，错位不会报错，只会让 `IoU` 偏低。
({int level, List<int> occurrences, List<int> offMap, int needleLength})?
_anchorAtLevel(String chunkText, String raw, int level) {
  final nt = _normalize(chunkText, level);
  final nr = _normalize(raw, level);
  if (nr.text.isEmpty) return null;
  final hits = _findAll(nt.text, nr.text);
  if (hits.isEmpty) return null;
  return (
    level: level,
    occurrences: hits,
    offMap: nt.offMap,
    needleLength: nr.text.length,
  );
}

/// 省略号判定：`……` / `…` / `...`。
final RegExp _ellipsis = RegExp(r'……|…|\.\.\.');

/// 锚定一条 evidence（§2.6 伪代码）。
AnchoredEvidence anchorOne(
  String chunkText,
  String evidence, {
  AnchorThresholds thresholds = const AnchorThresholds(),
}) {
  // 1) 剥引号（由外向内）；切分在剥离之后做
  final raw = stripQuotes(evidence);

  // 2) 太短 ⇒ too_short（**进分母**）
  if (raw.length < thresholds.tooShortChars) {
    return AnchoredEvidence(raw: raw, status: AnchorStatus.tooShort);
  }

  // 3) 含省略号 ⇒ 逐段独立锚定
  if (_ellipsis.hasMatch(raw)) {
    return _anchorJoined(chunkText, raw, thresholds);
  }

  // 4) 三级归一化，命中即停
  for (var level = 0; level <= 2; level++) {
    final hit = _anchorAtLevel(chunkText, raw, level);
    if (hit == null) continue;
    final occ = hit.occurrences.length;
    final first = hit.occurrences.first;
    // 回填原文坐标：归一化只用于匹配判断，绝不让归一化偏移流出本函数
    final span = [
      hit.offMap[first],
      hit.offMap[first + hit.needleLength - 1] + 1,
    ];
    final status = occ > thresholds.ambiguousOccurrences
        ? AnchorStatus.ambiguous
        : [
            AnchorStatus.okExact,
            AnchorStatus.okWs,
            AnchorStatus.okWidth,
          ][level];
    return AnchoredEvidence(
      raw: raw,
      status: status,
      span: span,
      occurrences: occ,
      matchLevel: ['exact', 'ws', 'width'][level],
    );
  }

  // 5) 三级都不中 ⇒ fail（不是"过滤掉"就完事，须回传到条目层）
  return AnchoredEvidence(raw: raw, status: AnchorStatus.fail);
}

/// 含省略号的 evidence：逐段独立锚定后按比例判定（`ok_joined` / `fail_joined`）。
AnchoredEvidence _anchorJoined(
  String chunkText,
  String raw,
  AnchorThresholds thresholds,
) {
  final parts = raw.split(_ellipsis).map((s) => s.trim()).toList();
  final anchorable = parts
      .where((p) => p.length >= thresholds.tooShortChars)
      .toList();
  final dropped = parts.length - anchorable.length;
  if (anchorable.isEmpty) {
    return AnchoredEvidence(
      raw: raw,
      status: AnchorStatus.failJoined,
      droppedParts: dropped,
    );
  }

  final hits = <AnchoredEvidence>[
    for (final p in anchorable) anchorOne(chunkText, p, thresholds: thresholds),
  ];
  final found = hits.where((h) => h.status.isAnchored).toList();
  final ratio = found.length / hits.length;
  // 首段必须命中：否则「开头都在原文里、后面全是编的」会被判 ok
  final firstFound = hits.first.status.isAnchored;
  if (ratio >= thresholds.ellipsisMinRatio && firstFound) {
    final startSpan = hits.first.span!;
    final lastSpan = found.last.span!;
    return AnchoredEvidence(
      raw: raw,
      status: AnchorStatus.okJoined,
      span: [startSpan[0], lastSpan[1]], // 粗定位，不进 ELA
      occurrences: 1,
      matchLevel: 'joined',
      droppedParts: dropped,
    );
  }
  return AnchoredEvidence(
    raw: raw,
    status: AnchorStatus.failJoined,
    droppedParts: dropped,
  );
}

/// 批量锚定。
List<AnchoredEvidence> anchorEvidence(
  String chunkText,
  List<String> evidence, {
  AnchorThresholds thresholds = const AnchorThresholds(),
}) {
  return [
    for (final e in evidence) anchorOne(chunkText, e, thresholds: thresholds),
  ];
}

/// 区间交并比（`M9` ELA）。
///
/// 只接受 `isElaEligible` 的锚定结果；调用方不得自行放宽。
double? ela(List<int>? goldSpan, List<int>? predSpan) {
  if (goldSpan == null || predSpan == null) return null;
  final a0 = goldSpan[0], a1 = goldSpan[1];
  final b0 = predSpan[0], b1 = predSpan[1];
  final interStart = a0 > b0 ? a0 : b0;
  final interEnd = a1 < b1 ? a1 : b1;
  final inter = interEnd - interStart;
  final unionLen = (a1 - a0) + (b1 - b0) - (inter > 0 ? inter : 0);
  if (unionLen <= 0) return null;
  return inter > 0 ? inter / unionLen : 0.0;
}
