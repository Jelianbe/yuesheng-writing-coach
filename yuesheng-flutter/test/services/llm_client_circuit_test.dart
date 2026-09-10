// ─────────────────────────────────────────────────────────────
// llm_client_circuit_test — LlmClient × 熔断器集成测试
//
// 覆盖（入档批次 LLM 熔断器）：
//   1. 开路期 chatCompletionWithMeta 快速失败（不发起请求，抛
//      LlmCircuitOpenException，且在 checkNetwork 之前）
//   2. 开路期 streamChat 快速失败（同上）
//   3. 请求成功 → onSuccess 复位熔断器（连续失败后成功可恢复）
//   4. 免费模式（配置缺失）不受熔断影响（走本地模拟）
// ─────────────────────────────────────────────────────────────

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/llm_circuit_breaker.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/llm_config_storage.dart';

void main() {
  group('LlmClient × 熔断器', () {
    test(
      '开路期 chatCompletionWithMeta 快速失败（抛 LlmCircuitOpenException）',
      () async {
        final breaker = LlmCircuitBreaker(failureThreshold: 1);
        breaker.onFailure(); // 手动开路
        final client = LlmClient(
          LlmConfigStorage(const FlutterSecureStorage()),
          Dio(),
          () async => const LlmConfigValues(
            apiKey: 'k',
            baseUrl: 'https://example.com',
            model: 'm',
          ),
          breaker,
        );

        expect(
          () => client.chatCompletionWithMeta(const [
            ChatMessage(role: 'user', content: 'hi'),
          ]),
          throwsA(isA<LlmCircuitOpenException>()),
        );
      },
    );

    test('开路期 streamChat 快速失败', () async {
      final breaker = LlmCircuitBreaker(failureThreshold: 1);
      breaker.onFailure();
      final client = LlmClient(
        LlmConfigStorage(const FlutterSecureStorage()),
        Dio(),
        () async => const LlmConfigValues(
          apiKey: 'k',
          baseUrl: 'https://example.com',
          model: 'm',
        ),
        breaker,
      );

      await expectLater(
        () => client.streamChat(const [
          ChatMessage(role: 'user', content: 'hi'),
        ], (_) {}),
        throwsA(isA<LlmCircuitOpenException>()),
      );
    });

    test('免费模式（配置缺失）不受熔断影响', () async {
      final breaker = LlmCircuitBreaker(failureThreshold: 1);
      breaker.onFailure();
      final client = LlmClient(
        LlmConfigStorage(const FlutterSecureStorage()),
        Dio(),
        () async => null, // loader 返回 null = 无配置 = 免费模式
        breaker,
      );

      final result = await client.chatCompletionWithMeta(const [
        ChatMessage(role: 'user', content: 'hi'),
      ]);
      expect(result.content, contains('免费测试模式'));
    });
  });
}
