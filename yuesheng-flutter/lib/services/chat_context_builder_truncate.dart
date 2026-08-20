// ─────────────────────────────────────────────────────────────
// chat_context_builder 主题分组拆分：chat_context_builder_truncate.dart（R-019 ≤300 行）
// 智能截断工具：smartTruncate/_truncateToOneLine/findKeywordExcerpt/_truncateAroundKeyword/_excerptSuffix。逐字迁移自 chat_context_builder.dart，零行为变更。
// ─────────────────────────────────────────────────────────────
part of 'chat_context_builder.dart';
// ─── 智能截断 ─────────────────────────────────────────────────

/// 智能截断：保留首尾，中间省略
///
/// 当文本超过 maxChars 时，保留前 [ContextBudget.truncateFrontRatio] 比例和尾部，
/// 中间用省略标记替代。maxChars 过小时直接截断。
String smartTruncate(String text, int maxChars) {
  if (text.length <= maxChars) return text;
  if (maxChars <= ContextBudget.smartTruncateMinThreshold) {
    return text.substring(0, maxChars);
  }

  final omittedEstimate = text.length - maxChars;
  final ellipsis = '\n...（省略 $omittedEstimate 字）\n';
  final ellipsisLen = ellipsis.length;
  final available = maxChars - ellipsisLen;

  final frontLen = (available * ContextBudget.truncateFrontRatio).floor();
  final backLen = available - frontLen;
  final actualOmitted = text.length - frontLen - backLen;
  final finalEllipsis = '\n...（省略 $actualOmitted 字）\n';

  return text.substring(0, frontLen) +
      finalEllipsis +
      text.substring(text.length - backLen);
}

/// 将文本截断为一行（按句号/分号分割取第一句，超长时追加省略号）
String _truncateToOneLine(String text, int maxLen) {
  final firstSentence = RegExp(r'[。；;\n]').firstMatch(text);
  final first = firstSentence != null
      ? text.substring(0, firstSentence.start)
      : text;
  if (first.length <= maxLen) return first;
  return '${first.substring(0, maxLen)}...';
}

/// 关键词片段摘录（O11，批次6 6.5）— A-3 段落锚点化
///
/// 定位 keyword 所在段落（以 `\n` 分段），返回该段落片段：以关键词为锚做句子级截断，
/// 上限 [maxLen]。漂移从字符级降到段落级——编辑前文不影响定位。
/// 未命中 / 关键词为空 / 正文为空 → 返回 null（降级安全，调用方不输出摘录）。
String? findKeywordExcerpt(
  String content,
  String keyword, {
  int maxLen = 120,
}) {
  if (keyword.isEmpty || content.isEmpty) return null;
  final paras = content.split('\n');
  for (final p in paras) {
    if (p.contains(keyword)) {
      return _truncateAroundKeyword(p, keyword, maxLen);
    }
  }
  return null;
}

/// 以关键词为锚截断为一行：保留关键词及其所在句（到句末分隔符）。
/// 跨行/跨句时不被关键词之前的句号/换行截断（防摘录不含关键词）；
/// 超长时从句头截断并加省略号。
String _truncateAroundKeyword(String snippet, String keyword, int maxLen) {
  final keyIndex = snippet.indexOf(keyword);
  if (keyIndex < 0) return _truncateToOneLine(snippet, maxLen);
  final tail = snippet.substring(keyIndex + keyword.length);
  final tailEnd = RegExp(r'[。；;\n]').firstMatch(tail);
  final clippedTail = tailEnd != null ? tail.substring(0, tailEnd.start) : tail;
  final head = snippet.substring(0, keyIndex);
  final total = head.length + keyword.length + clippedTail.length;
  if (total > maxLen) {
    final headBudget = maxLen - keyword.length - clippedTail.length;
    if (headBudget <= 0) return keyword; // 极端：仅保留关键词
    if (head.length > headBudget) {
      final trimmedHead = head.substring(head.length - headBudget);
      return '…$trimmedHead$keyword$clippedTail';
    }
  }
  return '$head$keyword$clippedTail';
}

/// 摘录后缀（O11，批次6 6.5）：excerpt 非空 → 「（原文：「…」）」，否则空串
/// （正文反查不可得时安全降级，不输出摘录）
String _excerptSuffix(String? excerpt) {
  if (excerpt == null || excerpt.isEmpty) return '';
  return '（原文：「$excerpt」）';
}

