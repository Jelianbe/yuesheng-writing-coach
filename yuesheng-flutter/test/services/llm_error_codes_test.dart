// ─────────────────────────────────────────────────────────────
// llm_error_codes_test — LLM 错误分类与用户可操作文案（批次 3）
//
// 覆盖：DioException → LlmErrorKind 全分类 + 各类文案映射。
// 纯函数，无需 channel mock。
// ─────────────────────────────────────────────────────────────

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/llm_error_codes.dart';

DioException _ex(DioExceptionType type, {int? status}) => DioException(
  requestOptions: RequestOptions(path: '/test'),
  type: type,
  response: status == null
      ? null
      : Response(requestOptions: RequestOptions(path: '/test'), statusCode: status),
);

void main() {
  group('classifyLlmError', () {
    test('超时三态 → timeout', () {
      for (final t in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.sendTimeout,
      ]) {
        expect(classifyLlmError(_ex(t)), LlmErrorKind.timeout);
      }
    });

    test('连接失败 → network', () {
      expect(
        classifyLlmError(_ex(DioExceptionType.connectionError)),
        LlmErrorKind.network,
      );
    });

    test('401/403 → unauthorized', () {
      expect(classifyLlmError(_ex(DioExceptionType.badResponse, status: 401)),
          LlmErrorKind.unauthorized);
      expect(classifyLlmError(_ex(DioExceptionType.badResponse, status: 403)),
          LlmErrorKind.unauthorized);
    });

    test('429 → rateLimited', () {
      expect(classifyLlmError(_ex(DioExceptionType.badResponse, status: 429)),
          LlmErrorKind.rateLimited);
    });

    test('5xx → server', () {
      for (final s in [500, 502, 503]) {
        expect(classifyLlmError(_ex(DioExceptionType.badResponse, status: s)),
            LlmErrorKind.server);
      }
    });

    test('400 → invalidRequest', () {
      expect(classifyLlmError(_ex(DioExceptionType.badResponse, status: 400)),
          LlmErrorKind.invalidRequest);
    });

    test('其他状态/无状态 → unknown', () {
      expect(classifyLlmError(_ex(DioExceptionType.badResponse, status: 404)),
          LlmErrorKind.unknown);
      expect(classifyLlmError(_ex(DioExceptionType.unknown)), LlmErrorKind.unknown);
    });
  });

  group('llmErrorMessage', () {
    test('timeout → 超时 + 重试引导 + 秒数', () {
      final msg = llmErrorMessage(LlmErrorKind.timeout, timeoutSeconds: 60);
      expect(msg, contains('请求超时'));
      expect(msg, contains('60秒'));
      expect(msg, contains('请稍后重试'));
    });

    test('network → 检查网络引导', () {
      expect(
        llmErrorMessage(LlmErrorKind.network),
        '网络连接失败，请检查网络后重试',
      );
    });

    test('unauthorized → 去设置检查 Key', () {
      final msg = llmErrorMessage(LlmErrorKind.unauthorized);
      expect(msg, contains('API Key 无效或已过期'));
      expect(msg, contains('设置'));
    });

    test('rateLimited → 稍后再试', () {
      expect(
        llmErrorMessage(LlmErrorKind.rateLimited),
        contains('请求过于频繁'),
      );
    });

    test('server → 含状态码 + 重试引导', () {
      final msg = llmErrorMessage(LlmErrorKind.server, status: 503);
      expect(msg, contains('HTTP 503'));
      expect(msg, contains('请稍后重试'));
    });

    test('invalidRequest → 检查模型配置', () {
      final msg = llmErrorMessage(LlmErrorKind.invalidRequest);
      expect(msg, contains('HTTP 400'));
      expect(msg, contains('模型'));
    });

    test('unknown 带 preview → HTTP N + 预览', () {
      final msg = llmErrorMessage(
        LlmErrorKind.unknown,
        status: 404,
        preview: 'Not Found',
      );
      expect(msg, 'HTTP 404: Not Found');
    });

    test('unknown 无 preview → 仅 HTTP N', () {
      expect(llmErrorMessage(LlmErrorKind.unknown, status: 404), 'HTTP 404');
    });
  });
}
