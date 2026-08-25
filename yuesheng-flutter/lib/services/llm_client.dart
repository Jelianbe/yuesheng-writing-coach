// ─────────────────────────────────────────────────────────────
// LLM 客户端 — 复刻 yuesheng-android/src/services/llm-client.ts
// 用 Dio 实现 OpenAI 兼容协议：
//   - testLlmConnection: 测试连接（非流式，5 token，15s 超时）
//   - chatCompletion: 非流式对话（温度 0.3，4096 token，60s 超时）
//   - streamChat: 流式 SSE（温度 0.7，按 data: 行解析，[DONE] 结束）
// RN 用 XHR onprogress 实现 SSE；Flutter 用 Dio ResponseType.stream
// ─────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/shared_constants.dart';
import 'llm_config_storage.dart';
import 'llm_fallback.dart';
import 'llm_retry.dart';
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

  LlmClient([LlmConfigStorage? configStorage, Dio? dio])
    : _configStorage = configStorage ?? LlmConfigStorage(),
      _dio = dio ?? Dio();

  /// 测试 LLM API 连通性
  Future<TestConnectionResult> testLlmConnection({
    LlmConfigValues? config,
  }) async {
    final cfg = config ?? await _configStorage.getLlmConfig();
    if (cfg == null) {
      return const TestConnectionResult(
        success: false,
        message: 'API 配置未设置，请先填写并保存',
      );
    }

    if (!await checkNetwork()) {
      return const TestConnectionResult(success: false, message: '设备网络不可用');
    }

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
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${cfg.apiKey}',
          },
          sendTimeout: Duration(milliseconds: LlmConfig.testTimeoutMs),
          receiveTimeout: Duration(milliseconds: LlmConfig.testTimeoutMs),
        ),
      );

      final latencyMs = DateTime.now().difference(startTime).inMilliseconds;
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
      final latencyMs = DateTime.now().difference(startTime).inMilliseconds;
      String errorMsg = 'HTTP ${e.response?.statusCode ?? 0}';
      final data = e.response?.data;
      if (data is String && data.isNotEmpty) {
        try {
          final errJson = jsonDecode(data) as Map<String, dynamic>;
          final msg = errJson['error']?['message'];
          if (msg != null) errorMsg += ': $msg';
        } catch (_) {
          errorMsg +=
              ': ${data.substring(0, data.length > LlmConfig.errorPreviewLength ? LlmConfig.errorPreviewLength : data.length)}';
        }
      } else if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        errorMsg = '请求超时（15秒无响应）';
      } else if (e.type == DioExceptionType.connectionError) {
        errorMsg = '网络请求失败（无法连接到服务器，检查 URL 或网络）';
      }
      return TestConnectionResult(
        success: false,
        message: errorMsg,
        latencyMs: latencyMs,
      );
    } catch (_) {
      return TestConnectionResult(success: false, message: '未知错误');
    }
  }

  /// 非流式对话（chatCompletion）
  ///
  /// B1-2/B1-1：可重试错误（超时/连接/5xx/429）指数退避重试；
  /// 配置了备选端点（yuesheng_api_fallbacks）时按序轮换。
  Future<String> chatCompletion(List<ChatMessage> messages) async {
    final cfg = await _configStorage.getLlmConfig();
    if (cfg == null) throw Exception('API 配置未设置');

    if (!await checkNetwork()) throw Exception('网络不可用');

    final fallbacks = parseFallbacks(await _configStorage.getLlmFallbacksRaw());
    final endpoints = expandEndpoints(
      cfg,
      fallbacks,
      LlmRetryPolicy.standard.maxAttempts,
    );

    try {
      return await executeWithRetry((attemptIndex) async {
        final c = endpoints[attemptIndex - 1];
        final response = await _dio.post<dynamic>(
          '${c.baseUrl}/chat/completions',
          data: jsonEncode({
            'model': c.model,
            'messages': messages.map((m) => m.toJson()).toList(),
            'stream': false,
            'temperature': LlmConfig.chatTemperature,
            'max_tokens': LlmConfig.chatMaxTokens,
          }),
          options: Options(
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${c.apiKey}',
            },
            sendTimeout: Duration(milliseconds: LlmConfig.chatTimeoutMs),
            receiveTimeout: Duration(milliseconds: LlmConfig.chatTimeoutMs),
          ),
        );

        final json = response.data is String
            ? jsonDecode(response.data as String) as Map<String, dynamic>
            : response.data as Map<String, dynamic>;
        final content = json['choices']?[0]?['message']?['content'] ?? '';
        return content as String;
      });
    } on DioException catch (e) {
      throw Exception(_buildDioError(e));
    }
  }

  /// 流式 SSE 对话（streamChat）
  ///
  /// [callback] 每收到一个增量 token 或 [DONE] 时回调。
  /// [cancelToken] 可用于取消请求。
  ///
  /// B1-2/B1-1：仅在「零 token」阶段失败才重试（建连超时/断流发生在
  /// 首个 token 前，重试安全）；一旦向 UI 输出过 token，后续失败直接
  /// 抛出——重试会导致同段回答重复输出。备选端点轮换同 chatCompletion。
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
  }) async {
    final cfg = await _configStorage.getLlmConfig();
    if (cfg == null) throw Exception('API 配置未设置');

    if (!await checkNetwork()) throw Exception('网络不可用');

    final fallbacks = parseFallbacks(await _configStorage.getLlmFallbacksRaw());
    final endpoints = expandEndpoints(
      cfg,
      fallbacks,
      LlmRetryPolicy.standard.maxAttempts,
    );

    try {
      await executeWithRetry((attemptIndex) async {
        final c = endpoints[attemptIndex - 1];
        final body = jsonEncode({
          'model': c.model,
          'messages': messages.map((m) => m.toJson()).toList(),
          'stream': true,
          'temperature': LlmConfig.streamTemperature,
        });

        // 批次55：TTFT（time-to-first-token）观测——请求发出到首个内容 token 到达。
        // 仅 debug 留痕不干预，建「流式首字延迟」基线（真实设备采集）。
        // B1：挪入重试闭包，每次尝试独立计时。
        final ttftWatch = Stopwatch()..start();
        var firstTokenLogged = false;

        // B1：本次尝试是否已向 UI 输出过 token（决定失败后能否安全重试）
        var hasEmittedToken = false;

        Response<ResponseBody> response;
        try {
          response = await _dio.post<ResponseBody>(
            '${c.baseUrl}/chat/completions',
            data: body,
            options: Options(
              responseType: ResponseType.stream,
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer ${c.apiKey}',
                'Accept': 'text/event-stream',
              },
              sendTimeout: const Duration(
                milliseconds: LlmConfig.streamTimeoutMs,
              ),
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

        final stream = response.data!.stream;
        String buffer = '';

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
                return;
              }

              try {
                final json = jsonDecode(data) as Map<String, dynamic>;
                final choices = json['choices'] as List<dynamic>?;
                if (choices != null && choices.isNotEmpty) {
                  final delta = choices[0]['delta'] as Map<String, dynamic>?;
                  final content = delta?['content'];
                  if (content is String && content.isNotEmpty) {
                    _logFirstToken(ttftWatch, firstTokenLogged);
                    firstTokenLogged = true;
                    hasEmittedToken = true;
                    callback(
                      LlmStreamResponse(content: content, isDone: false),
                    );
                  }
                }
              } catch (_) {
                // 忽略无法解析的行
                continue;
              }
            }
          }
        } catch (e) {
          // 已输出 token：重试会导致同段回答重复输出 → 语义性不可重试
          if (hasEmittedToken) throw LlmNonRetryableException(e);
          rethrow; // 零 token 阶段失败（断流/超时）→ 可安全重试
        }

        // 流正常结束但被取消：Dio 取消时底层流可能干净关闭而非抛错，
        // 此处补一道取消判定，确保统一走取消分支而非静默成功。
        if (cancelToken?.isCancelled ?? false) {
          throw LlmRequestCancelledException();
        }

        // 处理缓冲区中剩余的最后一块
        if (buffer.trim().startsWith('data: ')) {
          final data = buffer.trim().substring(6);
          if (data == '[DONE]') {
            callback(const LlmStreamResponse(content: '', isDone: true));
            return;
          }
          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final choices = json['choices'] as List<dynamic>?;
            if (choices != null && choices.isNotEmpty) {
              final delta = choices[0]['delta'] as Map<String, dynamic>?;
              final content = delta?['content'];
              if (content is String && content.isNotEmpty) {
                _logFirstToken(ttftWatch, firstTokenLogged);
                firstTokenLogged = true;
                hasEmittedToken = true;
                callback(LlmStreamResponse(content: content, isDone: false));
              }
            }
          } catch (_) {
            // 忽略
          }
        }
      });
    } on LlmNonRetryableException catch (wrapped) {
      // 解包：断流/超时等原始错误原样冒泡（调用方已有对应处理链路）
      throw wrapped.cause;
    } on DioException catch (e) {
      throw Exception(_buildDioError(e));
    }
  }

  /// 批次55：TTFT 首个 token 观测（仅 debug 留痕，不干预流式行为）。
  /// [alreadyLogged] 传值判定：首个内容 token 回调前为 false → 记录一次；
  /// 后续 token 传入 true → 跳过。
  void _logFirstToken(Stopwatch watch, bool alreadyLogged) {
    if (!kDebugMode || alreadyLogged) return;
    watch.stop();
    debugPrint('[批次55 TTFT] 首个 token 到达 ${watch.elapsedMilliseconds}ms（仅观测）');
  }

  String _buildDioError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      // 区分：流式 3 分钟兜底 vs 非流式 1 分钟兜底
      final t =
          e.requestOptions.receiveTimeout?.inMilliseconds ??
          LlmConfig.chatTimeoutMs;
      return '请求超时（${t ~/ 1000}秒无响应）';
    }
    if (e.type == DioExceptionType.connectionError) {
      return '网络请求失败';
    }
    final status = e.response?.statusCode ?? 0;
    String msg = 'HTTP $status';
    final data = e.response?.data;
    if (data is String && data.isNotEmpty) {
      final preview = data.length > LlmConfig.errorPreviewLengthLong
          ? data.substring(0, LlmConfig.errorPreviewLengthLong)
          : data;
      msg += ': $preview';
    }
    return msg;
  }
}
