// ─────────────────────────────────────────────────────────────
// Editor Service
// 复刻 yuesheng-android/src/services/editor-service.ts
//
// 用 chatCompletion（非流式，ADR-C88）调 editor-observation skill，
// 一次性拿完整响应，parseEditorObservation + validateEditorOutput 完整校验，
// 拦截 [YS_EDITOR] 块（不转发给用户）。
//
// 失败处理（不 throw，取消除外）：
//   - API 错误 → 兜底文案 displayContent，observation = null
//   - 解析失败 → 去标记原文 displayContent，observation = null
//   - 校验失败 → 同解析失败
//   - 用户取消（DioExceptionType.cancel）→ 原样上抛（调用方优雅复位）
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
  // ADR-C88：快速观察改非流式（chatCompletion）。
  // 背景：editor-observation 请求首 token 即 [YS_EDITOR] JSON 块（无自然语言
  // 导语），DeepSeek 流式首字延迟在真机网络下不稳定，60s 首字超时命中导致
  // 「快速观察未生成有效结果」。非流式 60s 全响应超时更稳（分块诊断单块
  // 已实测可用），且 [YS_EDITOR] 块本就拦截不转发，流式展示无收益。
  // onStream 不再回调（签名保留兼容既有调用方）。
  try {
    final fullContent = await llmClient.chatCompletion(
      _buildEditorMessages(text, extraSystemMessages),
      cancelToken: cancelToken,
    );
    return _finalizeEditorResult(fullContent);
  } on DioException catch (e) {
    if (e.type == DioExceptionType.cancel) rethrow; // 用户取消向上传播
    return const EditorStreamResult(
      displayContent: '审稿通过，但生成编辑观察失败，请稍后重试',
      observation: null,
    );
  } catch (_) {
    // 其他异常 → 兜底文案，不抛出
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
