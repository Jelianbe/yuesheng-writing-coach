// ─────────────────────────────────────────────────────────────
// edit_diff — 位置级 diff 定位（ADR-C132 批1 埋点地基）
//
// 北极星研讨 §10-4：测量「反馈后用户是否在教练指认的位置做了修改」，
// 需要把章节「上次保存内容 → 本次保存内容」的变化定位到具体片段。
//
// 算法：前缀相同 + 后缀相同剥离，中段为变化段（O(n)，克制实现）。
// 已知取舍（写进文档，防后人误判为 bug）：
//  - 多段分离修改会合并为一段（不精确到每个编辑点）——对「锚定片段
//    是否落在变化段内」的命中判断无影响，且避免 O(n²) LCS；
//  - 纯增/纯删/清空/首次写入均返回一段（start/end 按 after 偏移）。
// ─────────────────────────────────────────────────────────────

/// 单个变化片段。
///
/// [start]/[end] 是变化段在 [afterText] 上的字符偏移（[start, end)
/// 前含后不含）；[before] 为变化前的原文，[after] 为变化后的文本。
class TextDiffSegment {
  final int start;
  final int end;
  final String before;
  final String after;

  const TextDiffSegment({
    required this.start,
    required this.end,
    required this.before,
    required this.after,
  });
}

/// 定位 [before] → [after] 的变化片段列表（无变化 = 空列表）。
///
/// 规则：
///  - before == after → []
///  - before 为空（首次写入）→ 一段 [0, after.length)，before=''
///  - after 为空（清空）→ 一段 [0, 0)，after=''
List<TextDiffSegment> locateTextDiff(String before, String after) {
  if (before == after) return const [];

  final sharedPrefixLen = _commonPrefixLength(before, after);
  final sharedSuffixLen = _commonSuffixLength(
    before.substring(sharedPrefixLen),
    after.substring(sharedPrefixLen),
  );

  final beforeMid = before.substring(
    sharedPrefixLen,
    before.length - sharedSuffixLen,
  );
  final afterMid = after.substring(
    sharedPrefixLen,
    after.length - sharedSuffixLen,
  );

  return [
    TextDiffSegment(
      start: sharedPrefixLen,
      end: sharedPrefixLen + afterMid.length,
      before: beforeMid,
      after: afterMid,
    ),
  ];
}

/// 公共前缀长度（逐字符比较；相同文本 = 全长）。
int _commonPrefixLength(String a, String b) {
  final max = a.length < b.length ? a.length : b.length;
  var i = 0;
  while (i < max && a.codeUnitAt(i) == b.codeUnitAt(i)) {
    i++;
  }
  return i;
}

/// 公共后缀长度（从末尾逐字符比较；相同文本 = 全长）。
int _commonSuffixLength(String a, String b) {
  final max = a.length < b.length ? a.length : b.length;
  var i = 0;
  while (i < max &&
      a.codeUnitAt(a.length - 1 - i) == b.codeUnitAt(b.length - 1 - i)) {
    i++;
  }
  return i;
}
