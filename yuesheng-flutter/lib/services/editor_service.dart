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
    final userPrompt =
        '请对以下小说文本做编辑观察，输出 [YS_EDITOR] JSON。\n\n## 待观察文本\n\n$text';
    final messages = <ChatMessage>[
      ChatMessage(role: 'system', content: kEditorObservationSkillContent),
      ...extraSystemMessages,
      ChatMessage(role: 'user', content: userPrompt),
    ];

    // 流式拦截：与 chat-service 中 [YS_DIAGNOSIS] 拦截模式一致
    String fullContent = '';
    bool inEditorBlock = false;
    int displayLength = 0; // 已转发给 onStream 的字符数

    await llmClient.streamChat(messages, (response) {
      if (response.isDone) return;
      if (response.content.isEmpty) return;

      fullContent += response.content;

      if (inEditorBlock) return;

      // 检测完整 [YS_EDITOR] 标记：转发标记前的部分，进入拦截状态
      final markerIndex = fullContent.indexOf(kEditorStart);
      if (markerIndex != -1) {
        final newDisplay = fullContent.substring(displayLength, markerIndex);
        if (newDisplay.isNotEmpty) onStream(newDisplay);
        displayLength = markerIndex;
        inEditorBlock = true;
        return;
      }

      // 检测尾部是否正在形成 [YS_EDITOR] 标记（防止跨 chunk 拆分误转发）
      final pendingLen = getEditorPendingMarkerPrefix(fullContent);
      final safeEnd = pendingLen > 0
          ? fullContent.length - pendingLen
          : fullContent.length;
      if (safeEnd > displayLength) {
        final newDisplay = fullContent.substring(displayLength, safeEnd);
        if (newDisplay.isNotEmpty) onStream(newDisplay);
        displayLength = safeEnd;
      }
    }, cancelToken: cancelToken);

    // 流式结束：分离 displayContent 和 observation
    final parsed = parseEditorObservation(fullContent);
    final displayContent = parsed.displayContent;

    if (parsed.observation == null) {
      return EditorStreamResult(
        displayContent: displayContent,
        observation: null,
      );
    }

    // 完整校验（schema + 硬限制——判决句检测）
    // parser 已做 schema 校验，service 只做硬限制校验
    // （修复 P0 bug：原代码传 EditorResult 给 validateEditorOutput，
    //  该函数期望原始 JSON Map，导致 schema 校验恒失败、所有合法输入返回 null）
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
  } catch (_) {
    // API 错误 → 返回兜底文案，不抛出
    return const EditorStreamResult(
      displayContent: '审稿通过，但生成编辑观察失败，请稍后重试',
      observation: null,
    );
  }
}
