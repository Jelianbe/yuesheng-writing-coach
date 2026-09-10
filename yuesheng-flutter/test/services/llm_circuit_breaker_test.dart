import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/llm_circuit_breaker.dart';

void main() {
  group('LlmCircuitBreaker 状态机', () {
    test('初始 closed：isOpen=false，remaining=0', () {
      final breaker = LlmCircuitBreaker();
      expect(breaker.isOpen, isFalse);
      expect(breaker.remaining, Duration.zero);
    });

    test('连续失败达阈值 → 开路；未达阈值不打开', () {
      final breaker = LlmCircuitBreaker(failureThreshold: 3);
      breaker.onFailure();
      breaker.onFailure();
      expect(breaker.isOpen, isFalse);
      breaker.onFailure();
      expect(breaker.isOpen, isTrue);
      expect(breaker.remaining, greaterThan(Duration.zero));
    });

    test('冷却到期 → 自动复位 closed', () {
      final breaker = LlmCircuitBreaker(
        failureThreshold: 2,
        cooldown: const Duration(milliseconds: 50),
      );
      breaker.onFailure();
      breaker.onFailure();
      expect(breaker.isOpen, isTrue);
      // 手动推进时间：等待冷却期
      Future<void> wait() async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }

      return wait().then((_) {
        expect(breaker.isOpen, isFalse);
        expect(breaker.remaining, Duration.zero);
      });
    });

    test('onSuccess → 复位（失败计数清零，不再开路）', () {
      final breaker = LlmCircuitBreaker(failureThreshold: 3);
      breaker.onFailure();
      breaker.onFailure();
      breaker.onSuccess();
      breaker.onFailure();
      expect(breaker.isOpen, isFalse);
      breaker.onFailure();
      breaker.onFailure();
      expect(breaker.isOpen, isTrue);
    });

    test('开路期间继续失败不累计（等待冷却复位）', () {
      final breaker = LlmCircuitBreaker(
        failureThreshold: 2,
        cooldown: const Duration(milliseconds: 50),
      );
      breaker.onFailure();
      breaker.onFailure();
      expect(breaker.isOpen, isTrue);
      breaker.onFailure(); // 已开路，忽略
      breaker.onFailure(); // 已开路，忽略
      return Future<void>.delayed(const Duration(milliseconds: 80)).then((_) {
        expect(breaker.isOpen, isFalse);
        // 复位后从 0 重新计数
        breaker.onFailure();
        expect(breaker.isOpen, isFalse);
      });
    });
  });

  group('shouldCount（可恢复错误才计数）', () {
    test('timeout/network/rateLimited/server → true', () {
      for (final type in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.connectionError,
        DioExceptionType.badResponse,
      ]) {
        final e = DioException(
          requestOptions: RequestOptions(path: '/'),
          type: type,
          response: type == DioExceptionType.badResponse
              ? Response(
                  requestOptions: RequestOptions(path: '/'),
                  statusCode: 500,
                )
              : null,
        );
        expect(
          LlmCircuitBreaker.shouldCount(e),
          isTrue,
          reason: 'type=$type 应计数',
        );
      }
    });

    test('unauthorized（401/403）/invalidRequest（400）→ false', () {
      for (final status in [401, 403, 400]) {
        final e = DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/'),
            statusCode: status,
          ),
        );
        expect(
          LlmCircuitBreaker.shouldCount(e),
          isFalse,
          reason: 'status=$status 不应计数',
        );
      }
    });
  });

  group('LlmCircuitOpenException', () {
    test('toString 带剩余秒数', () {
      const e = LlmCircuitOpenException(Duration(seconds: 30));
      expect(e.toString(), contains('30'));
      expect(e.toString(), contains('熔断'));
    });
  });
}
