// ─────────────────────────────────────────────────────────────
// Editor Service
// 复刻 yuesheng-android/src/services/editor-service.ts
//
// 用 streamChat 调 editor-observation skill，
// 流式拦截 [YS_EDITOR] 块（不转发给用户），
// 结束后 parseEditorObservation + validateEditorOutput 完整校验。
//
// 失败处理（不 throw）：
//   - API 错误 → 兜底文案 displayContent，observation = null
//   - 解析失败 → 去标记原文 displayContent，observation = null
//   - 校验失败 → 同解析失败
// ─────────────────────────────────────────────────────────────

import 'package:dio/dio.dart';
import 'package:writingcoach/services/agent_skills.dart';
import 'package:writingcoach/services/editor_parser.dart';
import 'package:writingcoach/services/editor_validator.dart';
import 'package:writingcoach/services/llm_client.dart';

class EditorStreamResult {
  final String displayContent;
  final EditorResult? observation;
  const EditorStreamResult({required this.displayContent, this.observation});
}

/// 调用 Editor Agent 对文本做叙事层编辑观察。
///
/// 真源：editor-service.ts callEditorStream
///
/// [onStream] 收到的是去除 [YS_EDITOR] 块的自然语言部分。
/// [extraSystemMessages]（批次68 A7）：轻通道可附加额外 system 约束
///（如轻量观察表达密度约束），默认空不影响既有调用。
Future<EditorStreamResult> callEditorStream(
  LlmClient llmClient,
  String text,
  void Function(String delta) onStream, {
  CancelToken? cancelToken,
  List<ChatMessage> extraSystemMessages = const [],
}) async {
  try {
    final accumulator = _EditorStreamAccumulator(
      onStream,
      messages: _buildEditorMessages(text, extraSystemMessages),
    );
    await llmClient.streamChat(accumulator.messages, (response) {
      if (response.isDone) return;
      if (response.content.isEmpty) return;
      accumulator.add(response.content);
    }, cancelToken: cancelToken);
    return _finalizeEditorResult(accumulator.fullContent);
  } catch (_) {
    // API 错误 → 返回兜底文案，不抛出
    return const EditorStreamResult(
      displayContent: '审稿通过，但生成编辑观察失败，请稍后重试',
      observation: null,
    );
  }
}

/// 构建编辑观察请求消息（R-019 拆出：callEditorStream）。
List<ChatMessage> _buildEditorMessages(
  String text,
  List<ChatMessage> extraSystemMessages,
) {
  final userPrompt = '请对以下小说文本做编辑观察，输出 [YS_EDITOR] JSON。\n\n## 待观察文本\n\n$text';
  return <ChatMessage>[
    ChatMessage(role: 'system', content: kEditorObservationSkillContent),
    ...extraSystemMessages,
    ChatMessage(role: 'user', content: userPrompt),
  ];
}

/// 流式结束收尾：解析 + 硬限制校验 + 组装结果（R-019 拆出）。
EditorStreamResult _finalizeEditorResult(String fullContent) {
  final parsed = parseEditorObservation(fullContent);
  final displayContent = parsed.displayContent;
  if (parsed.observation == null) {
    return EditorStreamResult(
      displayContent: displayContent,
      observation: null,
    );
  }
  // parser 已做 schema 校验，service 只做硬限制校验
  final hardLimit = checkHardLimits(parsed.observation!);
  if (!hardLimit.passed) {
    return EditorStreamResult(
      displayContent: displayContent,
      observation: null,
    );
  }
  return EditorStreamResult(
    displayContent: displayContent,
    observation: parsed.observation,
  );
}

/// 流式累积器：拦截 [YS_EDITOR] 标记，转发标记前自然语言（R-019 拆出）。
/// 状态集中在类内，避免闭包跨回调共享（与 chat-service 拦截模式一致）。
class _EditorStreamAccumulator {
  final void Function(String) onStream;
  final List<ChatMessage> messages;
  String fullContent = '';
  bool inEditorBlock = false;
  int displayLength = 0; // 已转发给 onStream 的字符数
  _EditorStreamAccumulator(this.onStream, {required this.messages});

  void add(String content) {
    fullContent += content;
    if (inEditorBlock) return;
    final markerIndex = fullContent.indexOf(kEditorStart);
    if (markerIndex != -1) {
      final newDisplay = fullContent.substring(displayLength, markerIndex);
      if (newDisplay.isNotEmpty) onStream(newDisplay);
      displayLength = markerIndex;
      inEditorBlock = true;
      return;
    }
    final pendingLen = getEditorPendingMarkerPrefix(fullContent);
    final safeEnd = pendingLen > 0
        ? fullContent.length - pendingLen
        : fullContent.length;
    if (safeEnd > displayLength) {
      final newDisplay = fullContent.substring(displayLength, safeEnd);
      if (newDisplay.isNotEmpty) onStream(newDisplay);
      displayLength = safeEnd;
    }
  }
}
