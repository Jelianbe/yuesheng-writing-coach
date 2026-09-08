// ─────────────────────────────────────────────────────────────
// Editor Service
// 复刻 yuesheng-android/src/services/editor-service.ts
//
// 用 chatCompletionWithMeta（非流式，ADR-C88）调 editor-observation skill，
// 一次性拿完整响应，parseEditorObservation + validateEditorOutput 完整校验，
// 拦截 [YS_EDITOR] 块（不转发给用户）。
//
// 失败处理（不 throw，取消除外）：
//   - API 错误 → 兜底文案 displayContent，observation = null
//   - 解析失败 → 去标记原文 displayContent，observation = null
//   - 校验失败 → 同解析失败
//   - 用户取消（DioExceptionType.cancel）→ 原样上抛（调用方优雅复位）
//
// 失败留痕（ADR-C88 观测增强）：除用户取消外的失败路径统一经
// _logObserveFailure 落 error_logs，带 stage（api/parse/hardlimit）+
// contentLength + head160，真机失败可直接归因、不再靠猜。
// ─────────────────────────────────────────────────────────────

import 'package:dio/dio.dart';
import 'package:writingcoach/config/shared_constants.dart';
import 'package:writingcoach/services/agent_skills.dart';
import 'package:writingcoach/services/editor_parser.dart';
import 'package:writingcoach/services/editor_validator.dart';
import 'package:writingcoach/services/error_handler.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/llm_retry.dart';

/// 失败阶段（error_logs.context.stage）
const String _stageApi = 'api';
const String _stageParse = 'parse';
const String _stageHardLimit = 'hardlimit';

class EditorStreamResult {
  final String displayContent;
  final EditorResult? observation;

  /// 响应不完整（finish_reason='length' 或缺 [/YS_EDITOR]）→ true。
  ///
  /// 即便 observation 非空也只代表抢救出了一部分，调用方据此给
  /// 「内容被截断」文案，与「未生成有效结果」区分开。
  final bool truncated;

  const EditorStreamResult({
    required this.displayContent,
    this.observation,
    this.truncated = false,
  });
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
    final completion = await llmClient.chatCompletionWithMeta(
      _buildEditorMessages(text, extraSystemMessages),
      cancelToken: cancelToken,
      // ADR-C88：editor-observation 长 JSON 需更高输出预算（默认 4096
      // 可能截断 → 解析失败 →「快速观察未生成有效结果」）。
      maxTokens: LlmConfig.editorObservationMaxTokens,
      // ADR-C88 观测增强：快速观察是写作过程中的即时反馈，用户等待敏感，
      // 默认 3 次尝试最坏 ~180s；这里降为 [LlmConfig.editorObservationMaxAttempts]。
      retryPolicy: LlmRetryPolicy(
        maxAttempts: LlmConfig.editorObservationMaxAttempts,
      ),
    );
    return _finalizeEditorResult(completion);
  } on DioException catch (e) {
    if (e.type == DioExceptionType.cancel) rethrow; // 用户取消向上传播
    // F1：API/网络错误（原静默，仅一句兜底文案，error_logs 为零）
    _logObserveFailure(stage: _stageApi, reason: 'api_error', error: e);
    return const EditorStreamResult(
      displayContent: '审稿通过，但生成编辑观察失败，请稍后重试',
      observation: null,
    );
  } catch (e, stack) {
    // F1：其他异常（配置缺失/网络不可用/JSON 解码等）同样留痕，不抛出
    _logObserveFailure(
      stage: _stageApi,
      reason: 'unexpected_error',
      error: e,
      stack: stack,
    );
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

/// 收尾：解析 + 硬限制校验 + 组装结果（R-019 拆出）。
EditorStreamResult _finalizeEditorResult(ChatCompletionResult completion) {
  final raw = completion.content;
  final parsed = parseEditorObservation(raw);
  // 截断的两个信号任一命中即视为内容不完整：端点报 finish_reason='length'，
  // 或响应缺 [/YS_EDITOR] 结束标记（parser 已尝试截取到末尾抢救）。
  final truncated = parsed.truncated || completion.isTruncated;
  final observation = parsed.observation;

  if (observation == null) {
    // F2 根因在此：取不出 observation（无标记/截断/JSON 畸形/schema 不合）
    _logParseFailure(
      finishReason: completion.finishReason,
      raw: raw,
      truncated: truncated,
      failureReason: parsed.failureReason,
    );
    return EditorStreamResult(
      displayContent: parsed.displayContent,
      truncated: truncated,
    );
  }

  // parser 已做 schema 校验，service 只做硬限制校验
  final hardLimit = checkHardLimits(observation);
  if (!hardLimit.passed) {
    // F4：判决词拦截（原无任何文案、无任何留痕）
    _logHardLimitFailure(raw, truncated, hardLimit);
    return EditorStreamResult(
      displayContent: parsed.displayContent,
      truncated: truncated,
    );
  }

  if (truncated) {
    // 截断但抢救成功：内容可能不完整，留痕供阈值校准（observation 仍可用）
    _logObserveFailure(
      stage: _stageParse,
      reason: 'truncated_recovered',
      content: raw,
      truncated: true,
      finishReason: completion.finishReason,
    );
  }
  return EditorStreamResult(
    displayContent: parsed.displayContent,
    observation: observation,
    truncated: truncated,
  );
}

/// 取不出 observation 的留痕（R-019 拆出：_finalizeEditorResult）。
void _logParseFailure({
  required String raw,
  required bool truncated,
  required String? failureReason,
  String? finishReason,
}) {
  _logObserveFailure(
    stage: _stageParse,
    reason: failureReason ?? 'unknown',
    content: raw,
    truncated: truncated,
    finishReason: finishReason,
  );
}

/// 硬限制（判决词）拦截的留痕（R-019 拆出：_finalizeEditorResult）。
void _logHardLimitFailure(
  String raw,
  bool truncated,
  HardLimitResult hardLimit,
) {
  _logObserveFailure(
    stage: _stageHardLimit,
    reason: 'verdict_words',
    content: raw,
    truncated: truncated,
    category: 'validation',
    extra: {
      'violations': hardLimit.violations
          .map((v) => '${v.dimension}.${v.field}:${v.verdictWords.join('/')}')
          .toList(),
    },
  );
}

/// 快速观察失败统一留痕（ADR-C88 观测增强）。
///
/// [stage] api/parse/hardlimit；[reason] 具体原因（api_error / no_marker /
/// truncated / json_invalid / schema_invalid / verdict_words …）；
/// [content] 原始响应（只取长度与前 160 字符入 context，便于判断是否截断）。
/// 用户取消（F3）不调用本方法——取消是预期行为，记入会污染 error_logs。
void _logObserveFailure({
  required String stage,
  required String reason,
  String content = '',
  bool truncated = false,
  String level = 'warn',
  String category = 'api',
  String? finishReason,
  Object? error,
  StackTrace? stack,
  Map<String, dynamic>? extra,
}) {
  ErrorHandler.instance.captureError(
    level: level,
    category: category,
    message: '快速观察失败 stage=$stage reason=$reason',
    context: {
      'stage': stage,
      'reason': reason,
      'contentLength': content.length,
      'head160': content.length > 160 ? content.substring(0, 160) : content,
      'truncated': truncated,
      'finishReason': ?finishReason,
      'error': ?error?.toString(),
      ...?extra,
    },
    stack: stack?.toString(),
  );
}
