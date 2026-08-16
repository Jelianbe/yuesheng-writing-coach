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
  const EditorParseResult({required this.displayContent, this.observation});
}

EditorParseResult parseEditorObservation(String rawText) {
  final startIndex = rawText.indexOf(kEditorStart);
  if (startIndex == -1) {
    return EditorParseResult(displayContent: rawText, observation: null);
  }

  final displayContent = rawText.substring(0, startIndex).trimRight();

  final endIndex = rawText.indexOf(
    kEditorEnd,
    startIndex + kEditorStart.length,
  );
  if (endIndex == -1) {
    return EditorParseResult(displayContent: displayContent, observation: null);
  }

  String jsonStr = rawText
      .substring(startIndex + kEditorStart.length, endIndex)
      .trim();
  jsonStr = stripMarkdownFence(jsonStr);

  Object? parsed;
  try {
    parsed = parseJsonLenient(jsonStr);
  } catch (_) {
    return EditorParseResult(displayContent: displayContent, observation: null);
  }

  final validation = validateEditorSchema(parsed);
  if (!validation.valid || validation.data == null) {
    return EditorParseResult(displayContent: displayContent, observation: null);
  }

  return EditorParseResult(
    displayContent: displayContent,
    observation: validation.data,
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
