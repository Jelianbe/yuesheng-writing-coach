// ─────────────────────────────────────────────────────────────
// Teacher Parser
// 复刻 yuesheng-android/src/services/teacher-parser.ts
//
// 从文本中提取 [YS_TEACHER]...[/YS_TEACHER] 包裹的教学决策 JSON。
// 纯函数，无副作用，不 throw。
// ─────────────────────────────────────────────────────────────

import 'package:writingcoach/services/json_parser_utils.dart';
import 'package:writingcoach/services/teacher_validator.dart';

const String kTeacherStart = '[YS_TEACHER]';
const String kTeacherEnd = '[/YS_TEACHER]';

class TeacherParseResult {
  final String displayContent;
  final TeacherResult? teacher;
  const TeacherParseResult({required this.displayContent, this.teacher});
}

TeacherParseResult parseTeacherDecision(String rawText) {
  final startIndex = rawText.indexOf(kTeacherStart);
  if (startIndex == -1) {
    return TeacherParseResult(displayContent: rawText, teacher: null);
  }

  final displayContent = rawText.substring(0, startIndex).trimRight();

  final endIndex = rawText.indexOf(
    kTeacherEnd,
    startIndex + kTeacherStart.length,
  );
  if (endIndex == -1) {
    return TeacherParseResult(displayContent: displayContent, teacher: null);
  }

  String jsonStr = rawText
      .substring(startIndex + kTeacherStart.length, endIndex)
      .trim();
  jsonStr = stripMarkdownFence(jsonStr);

  Object? parsed;
  try {
    parsed = parseJsonLenient(jsonStr);
  } catch (_) {
    return TeacherParseResult(displayContent: displayContent, teacher: null);
  }

  final validation = validateTeacherSchema(parsed);
  if (!validation.valid || validation.data == null) {
    return TeacherParseResult(displayContent: displayContent, teacher: null);
  }

  return TeacherParseResult(
    displayContent: displayContent,
    teacher: validation.data,
  );
}

int getTeacherPendingMarkerPrefix(String fullContent) {
  const marker = kTeacherStart;
  for (int len = marker.length - 1; len > 0; len--) {
    if (fullContent.endsWith(marker.substring(0, len))) {
      return len;
    }
  }
  return 0;
}
