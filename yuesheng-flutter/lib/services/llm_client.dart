// ─────────────────────────────────────────────────────────────
// LLM 客户端 — 复刻 yuesheng-android/src/services/llm-client.ts
// 用 Dio 实现 OpenAI 兼容协议：
//   - testLlmConnection: 测试连接（非流式，5 token，15s 超时）
//   - chatCompletion: 非流式对话（温度 0.3，4096 token，60s 超时）
//     chatCompletionWithMeta 同链路，另返回 finish_reason（截断检测）
//   - streamChat: 流式 SSE（温度 0.7，按 data: 行解析，[DONE] 结束）
// RN 用 XHR onprogress 实现 SSE；Flutter 用 Dio ResponseType.stream
// ─────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/reasoning_tier.dart';
import '../config/shared_constants.dart';
import 'llm_circuit_breaker.dart';
import 'llm_concurrency_gate.dart';
import 'llm_config_storage.dart';
import 'llm_error_codes.dart';
import 'llm_fallback.dart';
import 'llm_model_profile.dart';
import 'llm_retry.dart';
import 'llm_usage.dart';
import 'llm_usage_monitor.dart';
import 'network_check.dart';
import 'stream_guard.dart';

/// 聊天消息（OpenAI ChatMessage 格式）
class ChatMessage {
  final String role; // 'user' | 'assistant' | 'system'
  final String content;
  const ChatMessage({required this.role, required this.content});

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

/// 流式响应回调的单帧
class LlmStreamResponse {
  final String content;
  final bool isDone;
  const LlmStreamResponse({required this.content, required this.isDone});
}

/// 非流式响应完整结果（ADR-C88 观测增强）。
///
/// 除正文外一并带回 `finish_reason`：仅凭正文无法区分「模型没输出」与
/// 「输出被 max_tokens 截断」，二者在快速观察链路上的归因与处置不同
/// （前者查 prompt/解析，后者查输出预算）。
class ChatCompletionResult {
  /// 消息正文（可能为空串）
  final String content;

  /// OpenAI 兼容协议的结束原因：stop / length / tool_calls / content_filter…
  /// 端点未返回时为 null。
  final String? finishReason;

  const ChatCompletionResult({required this.content, this.finishReason});

  /// `finish_reason == 'length'` → 命中 max_tokens 上限，内容不完整。
  bool get isTruncated => finishReason == 'length';
}

/// 截断续接提示（批次B）：指示模型从断点继续、不重复、不加说明。
const String _kContinuePrompt =
    '输出被长度限制截断。请直接从断点继续输出剩余部分，'
    '不要重复上述已生成内容，不要加任何说明文字。';

/// 用户主动取消请求时抛出（区别于普通异常，调用方据此做优雅复位而非报错）
class LlmRequestCancelledException implements Exception {
  @override
  String toString() => '请求已取消';
}

/// 对流式解码后的字符串流套一层「两段式空闲超时」守卫。
///
/// 实现见 [guardStream]（services/stream_guard.dart），抽为独立可测模块：
/// - 首字符到达前：最长等待 [LlmConfig.streamConnectTimeoutMs]（连接/首字超时）；
/// - 首字符之后：任意相邻 chunk 间隔超过 [LlmConfig.streamIdleTimeoutMs] 视为断流。
/// 触发后抛出 [TimeoutException]，由 streamChat 调用方转 onError → UI 复位，
/// 避免 `await for` 因网络静默断流而永久阻塞、发送与识别全程卡死。

/// 测试连接结果
class TestConnectionResult {
  final bool success;
  final String message;
  final int? latencyMs;
  const TestConnectionResult({
    required this.success,
    required this.message,
    this.latencyMs,
  });
}

/// LLM 客户端（依赖 LlmConfigStorage + Dio）
class LlmClient {
  final LlmConfigStorage _configStorage;
  final Dio _dio;

  /// 多账号配置加载器（ADR-C91 批次 D-1）：null 时回退旧单键读取。
  /// 生产组装注入「默认账号优先 → 旧三键兼容迁移」；测试默认不传保持旧行为。
  final Future<LlmConfigValues?> Function()? _configLoader;

  /// 熔断器（入档批次）：连续失败开路 → 快速失败，冷却自动恢复
  final LlmCircuitBreaker _breaker;

  /// 在途请求并发闸门（入档批次）：真实请求互斥，防并发风暴
  final LlmConcurrencyGate _gate;

  /// 用量上报出口（M 批）：缺省交全局累计器（仿 [_gate] 的 kSharedLlmGate
  /// 写法），测试可注入独立实例隔离累计状态。
  final LlmUsageSink _usageSink;

  /// 当前在途调用的业务上下文（TH 九批）。
  ///
  /// **为何用实例字段而非逐层传参**：[streamChat] 与 [chatCompletionWithMeta]
  /// 共用同一 [_gate]（两入口都 enter/exit）⇒ 同一实例内真实请求天然串行，
  /// 字段无串扰；而逐层穿透会触及 `_consumeSseStream`（R-019 实测 50 行、
  /// 零余量），其调用行被 dart format 拆行即越界。字段由两入口在 enter 后
  /// 设置、finally 清理；免费测试模式不走此路径 ⇒ 保持 null。
  LlmCallContext? _activeCallContext;

  /// 待消费的一次性链路标记（见 [markCallContext]）。
  LlmCallContext? _pendingCallContext;

  /// 标注**紧随其后的一次** LLM 调用所属业务链路（TH 九批）。
  ///
  /// 调用点用法：`client.markCallContext(ctx); await client.streamChat(...);`
  ///
  /// **为何不用方法形参**：给 [streamChat] / [chatCompletion] /
  /// [chatCompletionWithMeta] 加可选具名参数，会强制**全部测试 Fake 类**
  /// 同步改造（Dart override 契约要求子类接受父类的全部具名参数）——
  /// 实测一次引入 40+ 处 `invalid_override`，波及 33 个测试文件。改用本
  /// 方法可**零改动既有 override**，也零改动请求体与返回值。
  ///
  /// 消费语义：在 [streamChat] / [chatCompletionWithMeta] 的**入口**取走
  /// 并清零（含免费测试模式的提前 return 分支）⇒ 不残留、不错配。
  void markCallContext(LlmCallContext? ctx) {
    _pendingCallContext = ctx;
  }

  /// 取走一次性标记（取后即清，防残留污染下一次调用）。
  LlmCallContext? _consumePendingContext() {
    final ctx = _pendingCallContext;
    _pendingCallContext = null;
    return ctx;
  }

  LlmClient([
    LlmConfigStorage? configStorage,
    Dio? dio,
    this._configLoader,
    LlmCircuitBreaker? circuitBreaker,
    LlmConcurrencyGate? gate,
    LlmUsageSink? usageSink,
  ]) : _configStorage = configStorage ?? LlmConfigStorage(),
       _dio = dio ?? Dio(),
       _breaker = circuitBreaker ?? LlmCircuitBreaker(),
       _gate = gate ?? kSharedLlmGate,
       _usageSink = usageSink ?? kSharedLlmUsageMonitor.record;

  /// 当前配置源：优先自定义 loader（多账号），否则旧单键存储
  Future<LlmConfigValues?> _loadConfig() {
    final loader = _configLoader;
    if (loader != null) return loader();
    return _configStorage.getLlmConfig();
  }

  /// 免费测试模式教学文案（批次 E-1，2026-09-10 用户决策）：
  /// 无次数限制、无开关——判定 = 未配置 API Key 自动启用；不伪造诊断，
  /// 固定文案由解析类调用方走各自现有失败兜底（editor 兜底 / 诊断失败卡）。
  static const String _kFreeTestReply =
      '（免费测试模式）我现在处于离线示例模式。配置 API Key 后，'
      '我就能为你做真实的写作诊断与编辑观察——去「设置」中填入即可。';

  static const _kConfigMissing = TestConnectionResult(
    success: false,
    message: 'API 配置未设置，当前为免费测试模式；填写并保存后可测试真实连接',
  );
  static const _kNetworkUnavailable = TestConnectionResult(
    success: false,
    message: '设备网络不可用',
  );

  /// 测试 LLM API 连通性
  Future<TestConnectionResult> testLlmConnection({
    LlmConfigValues? config,
  }) async {
    final cfg = config ?? await _loadConfig();
    if (cfg == null) return _kConfigMissing;

    if (!await checkNetwork()) return _kNetworkUnavailable;

    final url = '${cfg.baseUrl}/chat/completions';
    final startTime = DateTime.now();

    try {
      final response = await _dio.post<dynamic>(
        url,
        data: jsonEncode({
          'model': cfg.model,
          'messages': [const ChatMessage(role: 'user', content: 'hi').toJson()],
          'stream': false,
          'max_tokens': LlmConfig.testMaxTokens,
        }),
        options: _buildTestOptions(cfg),
      );

      final latencyMs = DateTime.now().difference(startTime).inMilliseconds;
      // M 批：连通性测试同样计费（5 token 级），为保持「用量口径零遗漏」
      // 一并采集；响应体非 JSON 对象时静默跳过。
      final body = _asJsonMap(response.data);
      if (body != null) {
        _reportUsage(body['usage'], LlmUsageKind.chat, model: body['model']);
      }
      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        return TestConnectionResult(
          success: true,
          message: '连接成功（${latencyMs}ms）',
          latencyMs: latencyMs,
        );
      }
      return TestConnectionResult(
        success: false,
        message: 'HTTP ${response.statusCode}',
        latencyMs: latencyMs,
      );
    } on DioException catch (e) {
      return _mapDioError(e, startTime);
    } catch (_) {
      return TestConnectionResult(success: false, message: '未知错误');
    }
  }

  /// 构建测试连通性请求 options（R-019 拆出）。
  Options _buildTestOptions(LlmConfigValues cfg) {
    return Options(
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${cfg.apiKey}',
      },
      sendTimeout: Duration(milliseconds: LlmConfig.testTimeoutMs),
      receiveTimeout: Duration(milliseconds: LlmConfig.testTimeoutMs),
    );
  }

  /// Dio 异常 → 连通性错误文案（R-019 拆出；批次 3 统一走错误分类）。
  TestConnectionResult _mapDioError(DioException e, DateTime startTime) {
    final latencyMs = DateTime.now().difference(startTime).inMilliseconds;
    final kind = classifyLlmError(e);
    if (kind == LlmErrorKind.timeout) {
      return TestConnectionResult(
        success: false,
        message: llmErrorMessage(
          kind,
          timeoutSeconds: LlmConfig.testTimeoutMs ~/ 1000,
        ),
        latencyMs: latencyMs,
      );
    }
    if (kind == LlmErrorKind.network) {
      return TestConnectionResult(
        success: false,
        message: llmErrorMessage(kind),
        latencyMs: latencyMs,
      );
    }
    // 带状态码：优先取服务端 error.message 作 preview（测试连接场景更可读），
    // 解析失败回退原始响应体预览（脱敏）。
    String? preview;
    final data = e.response?.data;
    if (data is String && data.isNotEmpty) {
      try {
        final errJson = jsonDecode(data) as Map<String, dynamic>;
        final msg = errJson['error']?['message'];
        if (msg != null) preview = msg;
      } catch (_) {
        preview = data.length > LlmConfig.errorPreviewLength
            ? data.substring(0, LlmConfig.errorPreviewLength)
            : data;
      }
    }
    return TestConnectionResult(
      success: false,
      message: llmErrorMessage(
        kind,
        status: e.response?.statusCode ?? 0,
        preview: preview != null ? _redactAuth(preview) : null,
      ),
      latencyMs: latencyMs,
    );
  }

  /// 非流式对话（chatCompletion）
  ///
  /// B1-2/B1-1：可重试错误（超时/连接/5xx/429）指数退避重试；
  /// 配置了备选端点（yuesheng_api_fallbacks）时按序轮换。
  ///
  /// [maxTokens] 覆盖默认 completion 预算（ADR-C80 分块兜底重试用）；
  /// [extraBody] 合并进请求体（如 thinking 控制字段），不得含
  /// model / messages / stream / temperature / max_tokens——这些以本方法
  /// 参数与配置为准，传了会被静默覆盖。
  /// [cancelToken]（ADR-C88 快速观察非流式化）可用于取消请求；取消时
  /// 抛 DioExceptionType.cancel 原样上抛（不转 _buildDioError、不触发重试）。
  ///
  /// 只需要正文；需要 finish_reason（截断检测）或自定义重试策略的调用方
  /// 改用 [chatCompletionWithMeta]。
  Future<String> chatCompletion(
    List<ChatMessage> messages, {
    int? maxTokens,
    Map<String, dynamic>? extraBody,
    CancelToken? cancelToken,
  }) async {
    final result = await chatCompletionWithMeta(
      messages,
      maxTokens: maxTokens,
      extraBody: extraBody,
      cancelToken: cancelToken,
    );
    return result.content;
  }

  /// 非流式对话（含 finish_reason）——[chatCompletion] 的元数据版本。
  ///
  /// ADR-C88 观测增强：正文之外返回 finish_reason，供调用方判定
  /// 「内容被 max_tokens 截断」（见 [ChatCompletionResult.isTruncated]）。
  ///
  /// [retryPolicy] 可按场景收紧重试（快速观察用 2 次，见
  /// [LlmConfig.editorObservationMaxAttempts]）；端点轮换数随之取
  /// [LlmRetryPolicy.maxAttempts]。
  Future<ChatCompletionResult> chatCompletionWithMeta(
    List<ChatMessage> messages, {
    int? maxTokens,
    Map<String, dynamic>? extraBody,
    CancelToken? cancelToken,
    LlmRetryPolicy retryPolicy = LlmRetryPolicy.standard,
  }) async {
    // TH 九批：入口即消费一次性标记（免费模式提前 return 也不残留）。
    final callCtx = _consumePendingContext();
    final cfg = await _loadConfig();
    if (cfg == null) {
      // 批次 E-1 免费测试模式：未配置 API Key 自动启用（无开关、无次数限制），
      // 返回固定教学文案，不伪造诊断——解析类调用方走各自现有失败兜底。
      return ChatCompletionResult(content: _kFreeTestReply);
    }

    // 入档批次：在途请求并发闸门——真实请求互斥，异常/取消经 finally 必释放（免费模式本地模拟不占闸门）
    _gate.enter();
    // TH 九批：闸门内设置链路上下文（与 streamChat 同闸门 ⇒ 实例内互斥）。
    _activeCallContext = callCtx;
    try {
      final endpoints = await _prepareEndpoints(cfg, retryPolicy.maxAttempts);

      try {
        final result = await executeWithRetry(
          (attemptIndex) => _postChatCompletion(
            endpoints[attemptIndex - 1],
            messages,
            maxTokens: maxTokens,
            extraBody: extraBody,
            cancelToken: cancelToken,
          ),
          policy: retryPolicy,
        );
        _breaker.onSuccess();
        return result;
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) rethrow;
        if (LlmCircuitBreaker.shouldCount(e)) _breaker.onFailure();
        throw Exception(_buildDioError(e));
      }
    } finally {
      _activeCallContext = null;
      _gate.exit();
    }
  }

  /// 截断自动续接的非流式对话（批次B：防溢出）。
  ///
  /// [chatCompletionWithMeta] 的续接版本：响应命中 max_tokens 上限
  /// （finish_reason == 'length'）时，把已生成内容作为 assistant 上下文
  /// 追加进消息列表，指示模型从断点继续输出，最多续接 [maxContinuations]
  /// 轮（默认 3），返回拼接后的完整内容与最终 finish_reason。
  ///
  /// 适用：长结构化输出（诊断/编辑观察 JSON）单次 max_tokens 装不下、
  /// 但每轮又足够生成一段的场景。正常不截断时与 [chatCompletionWithMeta]
  /// 行为一致（零额外请求），截断时自动续接降低「内容崩溃」概率。
  Future<ChatCompletionResult> chatCompletionWithContinuation(
    List<ChatMessage> messages, {
    int? maxTokens,
    Map<String, dynamic>? extraBody,
    CancelToken? cancelToken,
    LlmRetryPolicy retryPolicy = LlmRetryPolicy.standard,
    int maxContinuations = 3,
  }) async {
    final chunks = <String>[];
    var current = List<ChatMessage>.from(messages);
    String? finishReason;
    for (var i = 0; i <= maxContinuations; i++) {
      final result = await chatCompletionWithMeta(
        current,
        maxTokens: maxTokens,
        extraBody: extraBody,
        cancelToken: cancelToken,
        retryPolicy: retryPolicy,
      );
      chunks.add(result.content);
      finishReason = result.finishReason;
      if (!result.isTruncated) break;
      current = [
        ...current,
        ChatMessage(role: 'assistant', content: result.content),
        const ChatMessage(role: 'user', content: _kContinuePrompt),
      ];
    }
    return ChatCompletionResult(
      content: chunks.join(),
      finishReason: finishReason,
    );
  }

  /// 单次非流式请求（R-019 拆出；含 finish_reason 读取）。
  Future<ChatCompletionResult> _postChatCompletion(
    LlmConfigValues c,
    List<ChatMessage> messages, {
    int? maxTokens,
    Map<String, dynamic>? extraBody,
    CancelToken? cancelToken,
  }) async {
    final watch = Stopwatch()..start(); // TH 九批：非流式全程耗时（埋点用）
    final response = await _dio.post<dynamic>(
      '${c.baseUrl}/chat/completions',
      data: _buildChatCompletionBody(
        c,
        messages,
        maxTokens: maxTokens,
        extraBody: extraBody,
      ),
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${c.apiKey}',
        },
        sendTimeout: Duration(milliseconds: LlmConfig.chatTimeoutMs),
        receiveTimeout: Duration(milliseconds: LlmConfig.chatTimeoutMs),
      ),
      cancelToken: cancelToken,
    );

    final json = response.data is String
        ? jsonDecode(response.data as String) as Map<String, dynamic>
        : response.data as Map<String, dynamic>;
    // M 批：非流式响应顶层 usage 此前被整块丢弃（只读 choices[0]），此处采集。
    _reportUsage(
      json['usage'],
      LlmUsageKind.chat,
      model: json['model'],
      latencyMs: watch.elapsedMilliseconds,
    );
    final choice = json['choices']?[0];
    return ChatCompletionResult(
      content: (choice?['message']?['content'] ?? '') as String,
      finishReason: choice?['finish_reason'] as String?,
    );
  }

  /// 流式 SSE 对话（streamChat）
  ///
  /// [callback] 每收到一个增量 token 或 [DONE] 时回调。
  /// [cancelToken] 可用于取消请求。
  ///
  /// B1-2/B1-1：仅在「零 token」阶段失败才重试（建连超时/断流发生在
  /// 首个 token 前，重试安全）；一旦向 UI 输出过 token，后续失败直接
  /// 抛出——重试会导致同段回答重复输出。备选端点轮换同 chatCompletion。
  ///
  /// ADR-C94：增可选 [extraBody]（合并进请求体；`model/messages/stream`
  /// 保留键防御性剥离，不得覆盖请求骨架；缺省时请求体逐字节不变）。
  /// deepseek 系「空流」（零 content token 且正常收尾）→ 分级降级：
  /// 尝试 2 注入 [LlmConfig.teachingStreamFallbackExtraBody] 兜底重试，
  /// 见 [_streamAttemptLoop]。
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
    Map<String, dynamic>? extraBody,
  }) async {
    // TH 九批：入口即消费一次性标记（免费模式提前 return 也不残留）。
    final callCtx = _consumePendingContext();
    final cfg = await _loadConfig();
    if (cfg == null) {
      // 批次 E-1 免费测试模式：模拟流式回调（教学文案分块推送 + DONE）。
      await _emitFreeTestStream(callback, cancelToken);
      return;
    }

    // 入档批次：在途请求并发闸门——真实请求互斥，异常/取消经 finally 必释放（免费模式本地模拟不占闸门）
    _gate.enter();
    // TH 九批：闸门内设置链路上下文（请求互斥 ⇒ 无串扰），finally 清理。
    _activeCallContext = callCtx;
    try {
      final endpoints = await _prepareEndpoints(
        cfg,
        LlmRetryPolicy.standard.maxAttempts,
      );

      try {
        await executeWithRetry((attemptIndex) async {
          await _streamAttemptLoop(
            endpoints[attemptIndex - 1],
            messages,
            callback,
            cancelToken,
            extraBody: extraBody,
          );
        });
        _breaker.onSuccess();
      } on LlmNonRetryableException catch (wrapped) {
        // 解包：断流/超时等原始错误原样冒泡（调用方已有对应处理链路）
        _reportStreamFailure(wrapped.cause);
        throw wrapped.cause;
      } on DioException catch (e) {
        if (LlmCircuitBreaker.shouldCount(e)) _breaker.onFailure();
        throw Exception(_buildDioError(e));
      }
    } finally {
      _activeCallContext = null;
      _gate.exit();
    }
  }

  /// 请求前置准备：熔断检查 + 网络检查 + 端点构建（R-019 拆出，两个入口共用）
  Future<List<LlmConfigValues>> _prepareEndpoints(
    LlmConfigValues cfg,
    int maxAttempts,
  ) async {
    if (_breaker.isOpen) throw LlmCircuitOpenException(_breaker.remaining);
    if (!await checkNetwork()) throw Exception('网络不可用');
    final fallbacks = parseFallbacks(await _configStorage.getLlmFallbacksRaw());
    return expandEndpoints(cfg, fallbacks, maxAttempts);
  }

  /// 流式失败上报熔断器（非 DioException 保守不计数；超时/可恢复 Dio 计数）
  void _reportStreamFailure(Object cause) {
    if (cause is DioException) {
      if (LlmCircuitBreaker.shouldCount(cause)) _breaker.onFailure();
      return;
    }
    if (cause is TimeoutException) {
      _breaker.onFailure();
    }
  }

  /// 免费测试模式模拟流式（批次 E-1）：教学文案分块推送 + DONE。
  /// 取消语义与真实流一致：cancelToken 已取消则提前抛 LlmRequestCancelledException。
  Future<void> _emitFreeTestStream(
    void Function(LlmStreamResponse response) callback,
    CancelToken? cancelToken,
  ) async {
    if (cancelToken?.isCancelled ?? false) throw LlmRequestCancelledException();
    const chunks = <String>[
      '（免费测试模式）我现在处于离线示例模式。',
      '配置 API Key 后，我就能为你做真实的写作诊断与编辑观察——',
      '去「设置」中填入即可。',
    ];
    for (final chunk in chunks) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (cancelToken?.isCancelled ?? false) {
        throw LlmRequestCancelledException();
      }
      callback(LlmStreamResponse(content: chunk, isDone: false));
    }
    callback(const LlmStreamResponse(content: '', isDone: true));
  }

  /// ADR-C94 §3.3 分级降级编排（R-019 拆出）。
  ///
  /// 尝试 1 用现参数原样（成功路径零行为变更）；判空判据（§3.4：`emitted ==
  /// false`——仅 content token 计数，reasoning_content 增量不计入——且本次尝试
  /// 干净结束，即未抛异常，**不再要求**必须达成 [DONE]，见 [_streamAttemptLoop]
  /// 内注释）成立、且模型属降级名单（`profile.fallbackDisableThinking`）→
  /// 尝试 2 注入兜底 extraBody；仍空 → 正常返回（不抛错），上层既有
  /// `onError('AI 返回为空')` 防线接住。
  ///
  /// **isDone 恰好一次契约**：isDone 帧经 [bufferedCallback] 缓存不立即投递，
  /// 降级发生则吞掉尝试 1 的 isDone，全程对调用方恰好投递一次（见
  /// [_flushIsDone]）。半输出（emitted == true）一律不降级——已向用户
  /// 投递内容，重发会复读，交上层既有错误语义处理。
  ///
  /// **降级判据（2026-09-15 EC 批放宽）**：零 content token 即可降级，
  /// **不再要求「正常收尾达成 [DONE]」**。依据：能走到判据处即本次尝试
  /// **未抛异常** —— 零 token 阶段的断流/超时已在 [_consumeSseStream] 内
  /// `rethrow`，由外层 `executeWithRetry` 接管 ⇒ 到达此处即「流干净结束」；
  /// 零投递 ⇒ 重发不复读。对全部 `done == true` 形态（含真实 API 的
  /// `finish_reason=length` 截断，探针实测 3/3 仍发 `[DONE]`）行为**逐路径等价**。
  Future<void> _streamAttemptLoop(
    LlmConfigValues c,
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback,
    CancelToken? cancelToken, {
    Map<String, dynamic>? extraBody,
  }) async {
    var isDoneSeen = false;
    void bufferedCallback(LlmStreamResponse response) {
      if (response.isDone) {
        isDoneSeen = true; // 缓存，不投递（降级时吞掉尝试 1 的 isDone）
        return;
      }
      callback(response);
    }

    final first = await _runStreamAttempt(
      c,
      messages,
      bufferedCallback,
      cancelToken,
      extraBody: extraBody,
    );
    // 判据见上方 doc：半输出不降级；零 content token 一律可降级（无论 [DONE]）。
    if (first.emitted) return _flushIsDone(callback, isDoneSeen);
    final profile = classifyLlmModel(c.model);
    if (!profile.fallbackDisableThinking) {
      return _flushIsDone(callback, isDoneSeen);
    }
    // ADR-C94：deepseek 系空流 → 尝试 2 注入 thinking disabled 兜底重试
    // （含 A-1b 五② 空流埋点，R-019 拆出）。
    await _runC94Fallback(
      c,
      messages,
      bufferedCallback,
      cancelToken,
      extraBody: extraBody,
    );
    return _flushIsDone(callback, isDoneSeen);
  }

  /// ADR-C94 兜底尝试 2（R-019 拆出）：deepseek 系空流降级重试。
  ///
  /// 语义同 [_streamAttemptLoop] doc：零 content token 一律可降级；尝试 2
  /// 注入 [LlmConfig.teachingStreamFallbackExtraBody]（合并参数见
  /// [_fallbackExtraBody]）。A-1b 五②：空流尝试端点不回 usage 帧 ⇒
  /// 正常流式埋点不可达，每次空流尝试补一条零 token 埋点（旁路）。
  Future<void> _runC94Fallback(
    LlmConfigValues c,
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback,
    CancelToken? cancelToken, {
    required Map<String, dynamic>? extraBody,
  }) async {
    _reportEmptyStreamAttempt(c.model);
    debugPrint(
      '[ADR-C94] streamChat 空流（零 content token）'
      '→ deepseek 系兜底重试 model=${c.model}（尝试 2 注入 thinking disabled）',
    );
    final second = await _runStreamAttempt(
      c,
      messages,
      callback,
      cancelToken,
      extraBody: _fallbackExtraBody(extraBody),
    );
    if (!second.emitted) {
      // 尝试 2 仍空：同样无 usage 帧，对称补埋点。
      _reportEmptyStreamAttempt(c.model);
    }
    debugPrint(
      second.emitted
          ? '[ADR-C94] 兜底尝试 2 救回（有内容输出）model=${c.model}'
          : '[ADR-C94] 兜底尝试 2 仍空，正常返回交上层防线 model=${c.model}',
    );
  }

  /// isDone 恰好一次契约的补投点（R-019 拆出）：仅当某次尝试达成过 [DONE]
  /// 时投递一次；降级后由最终尝试的 [DONE] 语义覆盖（缓存值同构）。
  void _flushIsDone(
    void Function(LlmStreamResponse response) callback,
    bool isDoneSeen,
  ) {
    if (isDoneSeen) {
      callback(const LlmStreamResponse(content: '', isDone: true));
    }
  }

  /// ADR-C94 尝试 2 的合并参数：兜底参数优先于调用方 extraBody（兜底是
  /// 纠偏动作，不得被调用方传参重新打开 thinking）；保留键剥离在
  /// [_buildStreamRequestBody] 处统一做。
  Map<String, dynamic> _fallbackExtraBody(
    Map<String, dynamic>? callerExtraBody,
  ) {
    return <String, dynamic>{
      ...?callerExtraBody,
      ...LlmConfig.teachingStreamFallbackExtraBody,
    };
  }

  /// 单次流式请求尝试（B1：仅零 token 阶段失败可安全重试，R-019 拆出）。
  /// ADR-C94：返回 `(emitted, done)`——emitted 仅由 content token 置位
  ///（`_handleSseData` 只认 `delta.content`，reasoning_content 增量不置位）；
  /// done = 该次尝试是否达成 [DONE]（正常收尾判据 b）。
  Future<({bool emitted, bool done})> _runStreamAttempt(
    LlmConfigValues c,
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback,
    CancelToken? cancelToken, {
    Map<String, dynamic>? extraBody,
  }) async {
    final body = _buildStreamRequestBody(c, messages, extraBody: extraBody);
    // 批次55：TTFT（time-to-first-token）观测——请求发出到首个内容 token 到达。
    // 仅 debug 留痕不干预，建「流式首字延迟」基线（真实设备采集）。
    // B1：挪入重试闭包，每次尝试独立计时。
    final ttftWatch = Stopwatch()..start();

    final response = await _postStreamRequest(c, body, cancelToken);
    final consumed = await _consumeSseStream(
      response.data!.stream,
      ttftWatch,
      callback,
    );
    if (consumed.done) return (emitted: consumed.emitted, done: true);

    // 流正常结束但被取消：Dio 取消时底层流可能干净关闭而非抛错，
    // 此处补一道取消判定，确保统一走取消分支而非静默成功。
    if (cancelToken?.isCancelled ?? false) {
      throw LlmRequestCancelledException();
    }

    // 处理缓冲区中剩余的最后一块（R-019 拆出）
    final trailing = _handleTrailingBuffer(
      consumed.buffer,
      ttftWatch,
      consumed.firstTokenLogged,
      callback,
    );
    // emitted 必须**累计**流内已投递的 token：流干净结束但未达成 [DONE] 时
    // 若只看 buffer 残片，已投递给用户的内容会被误判为零 token（原实现即
    // 如此，因下游 `done == false` 提前返回而不可达；空响应降级判据放宽后
    // 变为可达 ⇒ 会触发对半输出的重发复读）。此处取并集修正。
    return (emitted: consumed.emitted || trailing.emitted, done: trailing.done);
  }

  /// 消费 SSE 流（含断流语义重试判定，R-019 拆出）。
  Future<({String buffer, bool done, bool emitted, bool firstTokenLogged})>
  _consumeSseStream(
    Stream<List<int>> stream,
    Stopwatch ttftWatch,
    void Function(LlmStreamResponse response) callback,
  ) async {
    String buffer = '';
    var firstTokenLogged = false;
    var emitted = false;
    try {
      // 流内空闲超时守卫：防止网络静默断流导致 await for 永久阻塞（UI 卡死）。
      // 同时覆盖 Teacher/Editor/Progressive/Realtime 等所有走 streamChat 的链路。
      await for (final text in guardStream(
        stream.cast<List<int>>().transform(utf8.decoder),
      )) {
        buffer += text;
        final lines = buffer.split('\n');
        // 保留最后可能不完整的行
        buffer = lines.removeLast();
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty || !trimmed.startsWith('data: ')) continue;
          final data = trimmed.substring(6); // 'data: '.length == 6
          if (data == '[DONE]') {
            callback(const LlmStreamResponse(content: '', isDone: true));
            return (
              buffer: buffer,
              done: true,
              emitted: emitted,
              firstTokenLogged: firstTokenLogged,
            );
          }
          if (_handleSseData(data, ttftWatch, firstTokenLogged, callback)) {
            firstTokenLogged = true;
            emitted = true;
          }
        }
      }
    } catch (e) {
      // 已输出 token：重试会导致同段回答重复输出 → 语义性不可重试
      if (emitted) throw LlmNonRetryableException(e);
      rethrow; // 零 token 阶段失败（断流/超时）→ 可安全重试
    }
    return (
      buffer: buffer,
      done: false,
      emitted: emitted,
      firstTokenLogged: firstTokenLogged,
    );
  }

  /// 构建非流式请求体（R-019 拆出；ADR-C80 增 maxTokens / extraBody 覆盖；
  /// ADR-C83 增推理模型参数差异：o 系列禁 temperature、用 max_completion_tokens）。
  String _buildChatCompletionBody(
    LlmConfigValues c,
    List<ChatMessage> messages, {
    int? maxTokens,
    Map<String, dynamic>? extraBody,
  }) {
    final profile = classifyLlmModel(c.model);
    final body = <String, dynamic>{
      'model': c.model,
      'messages': messages.map((m) => m.toJson()).toList(),
      'stream': false,
    };
    if (profile.disableThinking) {
      // GLM thinking 系：显式关闭思考模式，防复杂 prompt 下退化乱码
      body['thinking'] = {'type': 'disabled'};
    } else {
      // 用户推理档位（真源 config/reasoning_tier.dart）：标准档 / 未设置
      // 不产任何键 ⇒ 请求体逐字节不变；仅对未强制关思考的模型生效
      //（GLM/doubao 画像为最小安全兜底，优先于档位）。
      final tierPatch = reasoningBodyPatchFor(c.reasoningTier);
      if (tierPatch.isNotEmpty) body.addAll(tierPatch);
    }
    if (profile.reasoningOnly) {
      body['max_completion_tokens'] = maxTokens ?? LlmConfig.chatMaxTokens;
    } else {
      body['temperature'] = LlmConfig.chatTemperature;
      body['max_tokens'] = maxTokens ?? LlmConfig.chatMaxTokens;
    }
    if (extraBody != null) body.addAll(extraBody);
    return jsonEncode(body);
  }

  /// 构建流式请求体（R-019 拆出；ADR-C83 增推理模型参数差异；
  /// ADR-C94 增 extraBody 合并——`addAll` 前防御性剥离 `model/messages/stream`
  /// 保留键，extraBody 不得覆盖请求骨架；extraBody 缺省时请求体逐字节不变）。
  String _buildStreamRequestBody(
    LlmConfigValues c,
    List<ChatMessage> messages, {
    Map<String, dynamic>? extraBody,
  }) {
    final profile = classifyLlmModel(c.model);
    final body = <String, dynamic>{
      'model': c.model,
      'messages': messages.map((m) => m.toJson()).toList(),
      'stream': true,
    };
    if (profile.disableThinking) {
      // GLM thinking 系：显式关闭思考模式，防复杂 prompt 下退化乱码
      body['thinking'] = {'type': 'disabled'};
    } else {
      // 用户推理档位（同 _buildChatCompletionBody）：标准档不产键 ⇒
      // 请求体逐字节不变，既有请求体锚点测试不受影响。
      final tierPatch = reasoningBodyPatchFor(c.reasoningTier);
      if (tierPatch.isNotEmpty) body.addAll(tierPatch);
    }
    if (profile.reasoningOnly) {
      body['max_completion_tokens'] = LlmConfig.chatMaxTokens;
    } else {
      body['temperature'] = LlmConfig.streamTemperature;
    }
    if (extraBody != null) {
      body.addAll(
        Map<String, dynamic>.from(extraBody)
          ..remove('model')
          ..remove('messages')
          ..remove('stream'),
      );
    }
    return jsonEncode(body);
  }

  /// 发起流式 POST（建连阶段取消单独分类，R-019 拆出）。
  Future<Response<ResponseBody>> _postStreamRequest(
    LlmConfigValues c,
    String body,
    CancelToken? cancelToken,
  ) async {
    try {
      return await _dio.post<ResponseBody>(
        '${c.baseUrl}/chat/completions',
        data: body,
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${c.apiKey}',
            'Accept': 'text/event-stream',
          },
          sendTimeout: const Duration(milliseconds: LlmConfig.streamTimeoutMs),
          receiveTimeout: const Duration(
            milliseconds: LlmConfig.streamTimeoutMs,
          ),
        ),
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        throw LlmRequestCancelledException();
      }
      rethrow; // 建连阶段失败（零 token）→ 交 executeWithRetry 分类
    }
  }

  /// 解析单条 SSE data（R-019 拆出）。返回是否已 emit token。
  bool _handleSseData(
    String data,
    Stopwatch ttftWatch,
    bool firstTokenLogged,
    void Function(LlmStreamResponse response) callback,
  ) {
    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      // M 批：流式 usage 随**最后一个 chunk**与 choices 同级下发（该 chunk 的
      // delta.content 为空串，include_usage 未设时 usage 仍返回）。必须先于
      // content 分支采集，否则会被「空 content」判定跳过。
      // TH 九批：ttftWatch 自请求发出前启动，而 usage 帧即末帧 ⇒ 其读数
      // 就是全程耗时（无需新增计时器）。
      _reportUsage(
        json['usage'],
        LlmUsageKind.stream,
        model: json['model'],
        latencyMs: ttftWatch.elapsedMilliseconds,
      );
      final choices = json['choices'] as List<dynamic>?;
      if (choices != null && choices.isNotEmpty) {
        final delta = choices[0]['delta'] as Map<String, dynamic>?;
        final content = delta?['content'];
        if (content is String && content.isNotEmpty) {
          _logFirstToken(ttftWatch, firstTokenLogged);
          callback(LlmStreamResponse(content: content, isDone: false));
          return true;
        }
      }
    } catch (_) {
      // 忽略无法解析的行
    }
    return false;
  }

  /// 处理缓冲区内剩余的最后一块（R-019 拆出）。
  ({bool done, bool emitted}) _handleTrailingBuffer(
    String buffer,
    Stopwatch ttftWatch,
    bool firstTokenLogged,
    void Function(LlmStreamResponse response) callback,
  ) {
    if (!buffer.trim().startsWith('data: ')) {
      return (done: false, emitted: false);
    }
    final data = buffer.trim().substring(6);
    if (data == '[DONE]') {
      callback(const LlmStreamResponse(content: '', isDone: true));
      return (done: true, emitted: false);
    }
    return (
      done: false,
      emitted: _handleSseData(data, ttftWatch, firstTokenLogged, callback),
    );
  }

  /// 批次55：TTFT 首个 token 观测（仅 debug 留痕，不干预流式行为）。
  /// [alreadyLogged] 传值判定：首个内容 token 回调前为 false → 记录一次；
  /// 后续 token 传入 true → 跳过。
  void _logFirstToken(Stopwatch watch, bool alreadyLogged) {
    if (!kDebugMode || alreadyLogged) return;
    watch.stop();
    debugPrint('[批次55 TTFT] 首个 token 到达 ${watch.elapsedMilliseconds}ms（仅观测）');
  }

  /// M 批：上报单次调用的 token 用量（三条链路共用出口）。
  ///
  /// 纪律（对齐 chat_service.dart _observeReplyLength）：观测是**旁路** ——
  /// 解析失败、sink 抛错都**不得阻断主流程**，也不改变任何既有返回值。
  /// [rawUsage] 为 null（端点未回 usage，如非 DeepSeek provider）时直接跳过。
  void _reportUsage(
    Object? rawUsage,
    LlmUsageKind kind, {
    Object? model,
    int? latencyMs,
  }) {
    if (rawUsage == null) return;
    try {
      final usage = LlmUsage.fromJson(
        rawUsage,
        model: model is String ? model : null,
      );
      // TH 九批：链路上下文取自入口设置的实例字段（见 [_activeCallContext]）。
      // ⚠️ testLlmConnection 不走闸门、且已到 R-019 上限（50 行），故不加
      // 标记 ⇒ 其记录恒为 unknown（本批诚实边界，见审计报告）。
      if (usage != null) {
        final ctx = _activeCallContext;
        _usageSink(usage.withContext(ctx?.withLatency(latencyMs)), kind);
      }
    } catch (_) {
      // 观测失败静默：绝不影响请求结果
    }
  }

  /// A-1b 五②：C94 空流尝试的**零 usage 埋点**（旁路，永不抛出）。
  ///
  /// 空流（零 content token 且收尾正常）时端点**不回落 usage 帧**，正常
  /// 流式埋点 [_reportUsage] 不可达 ⇒ llm_call 口径漏记该次调用。此处
  /// 构造零 token [LlmUsage] 补记：token 全 0 = 未知（不是真实用量），
  /// `purpose=streamEmptyFallback` 供审计侧计数；`reasoning_tokens=0`
  /// 与 A-1b 事后判据互证。任何异常静默吞掉，不得阻断主流程。
  void _reportEmptyStreamAttempt(String model) {
    try {
      final ctx = _activeCallContext;
      _usageSink(
        LlmUsage(
          promptTokens: 0,
          completionTokens: 0,
          cachedTokens: 0,
          reasoningTokens: 0,
          model: model,
          context: ctx == null
              ? const LlmCallContext(
                  purpose: LlmCallPurpose.streamEmptyFallback,
                )
              : LlmCallContext(
                  purpose: LlmCallPurpose.streamEmptyFallback,
                  sessionId: ctx.sessionId,
                ),
        ),
        LlmUsageKind.stream,
      );
    } catch (_) {
      // 观测失败静默：绝不影响请求结果
    }
  }

  /// 把响应体归一化为 JSON 对象（供 [_reportUsage] 取 `usage`）。
  ///
  /// Dio 只在对端返回 `application/json` 时才自动解析；实测既有链路里
  /// `response.data` 可能是**未解析的 String**（`_postChatCompletion` 亦
  /// 因此保留了 `data is String` 分支）⇒ 此处统一兜住，解析不出对象
  /// 一律返回 null（静默跳过，不影响主流程）。
  Map<String, dynamic>? _asJsonMap(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        return decoded is Map<String, dynamic> ? decoded : null;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  String _buildDioError(DioException e) {
    // 批次 3：统一走错误分类（llm_error_codes.dart）——401/403/429/超时/
    // 连接等给用户可操作文案，替代裸 "HTTP N"。
    final kind = classifyLlmError(e);
    if (kind == LlmErrorKind.timeout) {
      // 区分：流式 3 分钟兜底 vs 非流式 1 分钟兜底
      final t =
          e.requestOptions.receiveTimeout?.inMilliseconds ??
          LlmConfig.chatTimeoutMs;
      return llmErrorMessage(kind, timeoutSeconds: t ~/ 1000);
    }
    final status = e.response?.statusCode ?? 0;
    final data = e.response?.data;
    String? preview;
    if (data is String && data.isNotEmpty) {
      final raw = data.length > LlmConfig.errorPreviewLengthLong
          ? data.substring(0, LlmConfig.errorPreviewLengthLong)
          : data;
      // B22/R-029：防御性脱敏——OpenAI 错误响应通常不含 Authorization，
      // 但代理/网关可能 echo 请求头到错误响应体；此层作为防御纵深。
      preview = _redactAuth(raw);
    }
    return llmErrorMessage(kind, status: status, preview: preview);
  }

  /// R-029 安全：脱敏可能泄露的 Authorization / Bearer 凭证
  ///
  /// 覆盖两种形式：
  ///   1. `Bearer xxx`（OAuth 2.0 标准格式，含 JWT）
  ///   2. `Authorization: xxx` / `"Authorization":"xxx"`（头部键值形式）
  ///
  /// 不影响其他无关字段；保留请求头名以方便排查，仅屏蔽值。
  String _redactAuth(String text) {
    final bearerRe = RegExp(r'[Bb]earer\s+[A-Za-z0-9_\-\.]+');
    final headerRe = RegExp(
      r'''["']?Authorization["']?\s*[:=]\s*["']?[A-Za-z0-9_\-\.]+''',
      caseSensitive: false,
    );
    return text
        .replaceAll(bearerRe, 'Bearer ***')
        .replaceAll(headerRe, 'Authorization=***');
  }
}
