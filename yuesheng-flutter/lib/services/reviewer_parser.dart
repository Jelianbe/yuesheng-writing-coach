// ─────────────────────────────────────────────────────────────
// Reviewer Parser
// 复刻 yuesheng-android/src/services/reviewer-parser.ts
//
// 从完整回复文本中提取 [YS_REVIEW]...[/YS_REVIEW] 包裹的 JSON。
// 纯函数，无副作用，不 throw。
// ─────────────────────────────────────────────────────────────

import 'package:writingcoach/services/json_parser_utils.dart';
import 'package:writingcoach/services/reviewer_validator.dart';

const String kReviewerStart = '[YS_REVIEW]';
const String kReviewerEnd = '[/YS_REVIEW]';

class ReviewerParseResult {
  final String displayContent;
  final ReviewerResult? review;
  const ReviewerParseResult({required this.displayContent, this.review});
}

/// 从文本中提取审稿门控 JSON。
///
/// 纯函数，无副作用，不 throw。
ReviewerParseResult parseReviewerReview(String rawText) {
  final startIndex = rawText.indexOf(kReviewerStart);
  if (startIndex == -1) {
    return ReviewerParseResult(displayContent: rawText, review: null);
  }

  final displayContent = rawText.substring(0, startIndex).trimRight();

  final endIndex = rawText.indexOf(
    kReviewerEnd,
    startIndex + kReviewerStart.length,
  );
  if (endIndex == -1) {
    // 缺少结束标记
    return ReviewerParseResult(displayContent: displayContent, review: null);
  }

  String jsonStr = rawText
      .substring(startIndex + kReviewerStart.length, endIndex)
      .trim();
  jsonStr = stripMarkdownFence(jsonStr);

  Object? parsed;
  try {
    parsed = parseJsonLenient(jsonStr);
  } catch (_) {
    return ReviewerParseResult(displayContent: displayContent, review: null);
  }

  final validation = validateReviewerSchema(parsed);
  if (!validation.valid || validation.data == null) {
    return ReviewerParseResult(displayContent: displayContent, review: null);
  }

  return ReviewerParseResult(
    displayContent: displayContent,
    review: validation.data,
  );
}

/// 检查 fullContent 尾部是否匹配 [YS_REVIEW] 的某个前缀。
/// 用于流式拦截，防止分隔符跨 chunk 到达时误转发。
int getReviewerPendingMarkerPrefix(String fullContent) {
  const marker = kReviewerStart;
  // 从最长前缀开始检查（排除完整匹配）
  for (int len = marker.length - 1; len > 0; len--) {
    if (fullContent.endsWith(marker.substring(0, len))) {
      return len;
    }
  }
  return 0;
}
