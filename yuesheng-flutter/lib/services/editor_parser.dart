// ─────────────────────────────────────────────────────────────
// Editor Observation Parser
// 复刻 yuesheng-android/src/services/editor-parser.ts
//
// 从文本中提取 [YS_EDITOR]...[/YS_EDITOR] 包裹的编辑观察 JSON。
// 纯函数，无副作用，不 throw。
// ─────────────────────────────────────────────────────────────

import 'package:writingcoach/services/editor_validator.dart';
import 'package:writingcoach/services/json_parser_utils.dart';

const String kEditorStart = '[YS_EDITOR]';
const String kEditorEnd = '[/YS_EDITOR]';

class EditorParseResult {
  final String displayContent;
  final EditorResult? observation;

  /// 有起始标记但无结束标记（多为 max_tokens 截断）→ true。
  ///
  /// 此时 JSON 尾部大概率不完整：本 parser 已尝试「截取到末尾再解析」，
  /// 解析成功也仅代表抢救出了一部分（供上层标记 truncated 上报归因）。
  final bool truncated;

  /// 未取出 observation 的原因（成功为 null）：
  /// no_marker（无起始标记）/ truncated（缺结束标记，含抢救失败）/
  /// json_invalid（JSON 畸形）/ schema_invalid（字段不合 schema）。
  final String? failureReason;

  const EditorParseResult({
    required this.displayContent,
    this.observation,
    this.truncated = false,
    this.failureReason,
  });
}

EditorParseResult parseEditorObservation(String rawText) {
  final startIndex = rawText.indexOf(kEditorStart);
  if (startIndex == -1) {
    return EditorParseResult(
      displayContent: rawText,
      observation: null,
      failureReason: 'no_marker',
    );
  }

  final displayContent = rawText.substring(0, startIndex).trimRight();
  return _parseEditorBody(
    rawText,
    displayContent,
    startIndex + kEditorStart.length,
  );
}

/// 解析 [YS_EDITOR] 块体（R-019 拆出：parseEditorObservation）。
///
/// ADR-C88 观测增强（P1-1）：缺结束标记不再直接判死——截取到末尾再解析，
/// 抢救被 max_tokens 截断但仍可解析的 JSON；抢救失败也带 truncated 上报，
/// 使上层能把「被截断」与「模型没输出」分开。
EditorParseResult _parseEditorBody(
  String rawText,
  String displayContent,
  int bodyStart,
) {
  final endIndex = rawText.indexOf(kEditorEnd, bodyStart);
  final truncated = endIndex == -1;
  final bodyEnd = truncated ? rawText.length : endIndex;
  final jsonStr = stripMarkdownFence(
    rawText.substring(bodyStart, bodyEnd).trim(),
  );

  Object? parsed;
  try {
    parsed = parseJsonLenient(jsonStr);
  } catch (_) {
    return EditorParseResult(
      displayContent: displayContent,
      observation: null,
      truncated: truncated,
      failureReason: truncated ? 'truncated' : 'json_invalid',
    );
  }

  final validation = validateEditorSchema(parsed);
  if (!validation.valid || validation.data == null) {
    return EditorParseResult(
      displayContent: displayContent,
      observation: null,
      truncated: truncated,
      failureReason: truncated ? 'truncated' : 'schema_invalid',
    );
  }

  return EditorParseResult(
    displayContent: displayContent,
    observation: validation.data,
    truncated: truncated,
  );
}

int getEditorPendingMarkerPrefix(String fullContent) {
  const marker = kEditorStart;
  for (int len = marker.length - 1; len > 0; len--) {
    if (fullContent.endsWith(marker.substring(0, len))) {
      return len;
    }
  }
  return 0;
}
