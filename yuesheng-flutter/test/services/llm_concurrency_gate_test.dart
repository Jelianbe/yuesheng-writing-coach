// ─────────────────────────────────────────────────────────────
// llm_concurrency_gate_test — 在途请求并发闸门测试
//
// 覆盖：
//   1. 闸门空闲时 enter 成功、isBusy=true
//   2. 在途时第二次 enter 抛 LlmInFlightException
//   3. exit 释放后再次 enter 成功
//   4. LlmClient 集成：在途时第二个请求快速失败（非流式）
//   5. LlmClient 集成：异常路径 finally 释放（闸门可再次使用）
//   6. LlmClient 集成：免费模式不占闸门
// ─────────────────────────────────────────────────────────────

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/llm_concurrency_gate.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/llm_config_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LlmConcurrencyGate 单元', () {
    test('空闲 enter 成功 → isBusy=true；exit 释放 → isBusy=false', () {
      final gate = LlmConcurrencyGate();
      expect(gate.isBusy, isFalse);
      gate.enter();
      expect(gate.isBusy, isTrue);
      gate.exit();
      expect(gate.isBusy, isFalse);
    });

    test('在途时第二次 enter 抛 LlmInFlightException', () {
      final gate = LlmConcurrencyGate();
      gate.enter();
      expect(() => gate.enter(), throwsA(isA<LlmInFlightException>()));
      gate.exit();
    });

    test('exit 幂等（未占用时静默）', () {
      final gate = LlmConcurrencyGate();
      gate.exit(); // 不抛
      expect(gate.isBusy, isFalse);
    });
  });

  group('LlmClient × 闸门集成', () {
    LlmClient buildClient(LlmConcurrencyGate gate) {
      return LlmClient(
        LlmConfigStorage(const FlutterSecureStorage()),
        Dio(),
        () async => const LlmConfigValues(
          apiKey: 'k',
          baseUrl: 'https://example.com',
          model: 'm',
        ),
        null,
        gate,
      );
    }

    test('在途时第二个非流式请求快速失败（LlmInFlightException）', () async {
      final gate = LlmConcurrencyGate();
      final client = buildClient(gate);
      gate.enter(); // 模拟已有请求在途

      await expectLater(
        () => client.chatCompletionWithMeta(
          const [ChatMessage(role: 'user', content: 'hi')],
        ),
        throwsA(isA<LlmInFlightException>()),
      );
      gate.exit();
    });

    test('异常路径 finally 释放：失败后闸门可再次使用', () async {
      final gate = LlmConcurrencyGate();
      final client = LlmClient(
        LlmConfigStorage(const FlutterSecureStorage()),
        Dio(BaseOptions(
          connectTimeout: const Duration(milliseconds: 1),
          receiveTimeout: const Duration(milliseconds: 1),
        )),
        () async => const LlmConfigValues(
          apiKey: 'k',
          baseUrl: 'https://10.255.255.1', // 不可达
          model: 'm',
        ),
        null,
        gate,
      );

      // 网络失败 → 异常
      await expectLater(
        () => client.chatCompletionWithMeta(
          const [ChatMessage(role: 'user', content: 'hi')],
        ),
        throwsA(isA<Exception>()),
      );
      // finally 已释放
      expect(gate.isBusy, isFalse);
    });

    test('免费模式（无配置）不占闸门', () async {
      final gate = LlmConcurrencyGate();
      final client = LlmClient(
        LlmConfigStorage(const FlutterSecureStorage()),
        Dio(),
        () async => null,
        null,
        gate,
      );
      final result = await client.chatCompletionWithMeta(
        const [ChatMessage(role: 'user', content: 'hi')],
      );
      expect(result.content, contains('免费测试模式'));
      expect(gate.isBusy, isFalse);
    });
  });
}
