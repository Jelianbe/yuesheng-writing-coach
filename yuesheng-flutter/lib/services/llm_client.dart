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
import 'network_check.dart';

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
  Future<String> chatCompletion(List<ChatMessage> messages) async {
    final cfg = await _configStorage.getLlmConfig();
    if (cfg == null) throw Exception('API 配置未设置');

    if (!await checkNetwork()) throw Exception('网络不可用');

    final url = '${cfg.baseUrl}/chat/completions';
    try {
      final response = await _dio.post<dynamic>(
        url,
        data: jsonEncode({
          'model': cfg.model,
          'messages': messages.map((m) => m.toJson()).toList(),
          'stream': false,
          'temperature': LlmConfig.chatTemperature,
          'max_tokens': LlmConfig.chatMaxTokens,
        }),
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${cfg.apiKey}',
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
    } on DioException catch (e) {
      throw Exception(_buildDioError(e));
    }
  }

  /// 流式 SSE 对话（streamChat）
  ///
  /// [callback] 每收到一个增量 token 或 [DONE] 时回调。
  /// [cancelToken] 可用于取消请求。
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
  }) async {
    final cfg = await _configStorage.getLlmConfig();
    if (cfg == null) throw Exception('API 配置未设置');

    if (!await checkNetwork()) throw Exception('网络不可用');

    final url = '${cfg.baseUrl}/chat/completions';
    final body = jsonEncode({
      'model': cfg.model,
      'messages': messages.map((m) => m.toJson()).toList(),
      'stream': true,
      'temperature': LlmConfig.streamTemperature,
    });

    // 批次55：TTFT（time-to-first-token）观测——请求发出到首个内容 token 到达。
    // 仅 debug 留痕不干预，建「流式首字延迟」基线（真实设备采集）。
    final ttftWatch = Stopwatch()..start();
    var firstTokenLogged = false;

    Response<ResponseBody> response;
    try {
      response = await _dio.post<ResponseBody>(
        url,
        data: body,
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${cfg.apiKey}',
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
      throw Exception(_buildDioError(e));
    }

    final stream = response.data!.stream;
    String buffer = '';

    await for (final chunk in stream) {
      buffer += utf8.decode(chunk);

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
              callback(LlmStreamResponse(content: content, isDone: false));
            }
          }
        } catch (_) {
          // 忽略无法解析的行
          continue;
        }
      }
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
            callback(LlmStreamResponse(content: content, isDone: false));
          }
        }
      } catch (_) {
        // 忽略
      }
    }
  }

  /// 批次55：TTFT 首个 token 观测（仅 debug 留痕，不干预流式行为）。
  /// [alreadyLogged] 传值判定：首个内容 token 回调前为 false → 记录一次；
  /// 后续 token 传入 true → 跳过。
  void _logFirstToken(Stopwatch watch, bool alreadyLogged) {
    if (!kDebugMode || alreadyLogged) return;
    watch.stop();
    debugPrint(
      '[批次55 TTFT] 首个 token 到达 ${watch.elapsedMilliseconds}ms（仅观测）',
    );
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
