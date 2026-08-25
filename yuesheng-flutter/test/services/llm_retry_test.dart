// ─────────────────────────────────────────────────────────────
// B1-1/B1-2 LLM 重试 + fallback 测试
//
// 覆盖三层：
//   A. 纯逻辑：退避序列 / 错误分类 / 执行器（executeWithRetry）
//   B. 纯逻辑：fallback 解析（parseFallbacks）与端点展开（expandEndpoints）
//   C. 集成：LlmClient.chatCompletion / streamChat 的重试与轮换语义
//      （method channel mock 替换 secure_storage 与 connectivity，
//       HttpClientAdapter 脚本化响应序列）
// ─────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/llm_config_storage.dart';
import 'package:writingcoach/services/llm_fallback.dart';
import 'package:writingcoach/services/llm_retry.dart';

const _secureChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _connChannel = MethodChannel('dev.fluttercommunity.plus/connectivity');

/// 以内存 map 替换 secure_storage / connectivity 两个 platform channel。
void _mockChannels(Map<String, String> store) {
  final messenger = TestDefaultBinaryMessengerBinding
      .instance
      .defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_secureChannel, (call) async {
    final key = (call.arguments as Map?)?['key'] as String?;
    switch (call.method) {
      case 'read':
        return store[key];
      case 'write':
        store[key!] = (call.arguments as Map)['value'] as String;
        return null;
      case 'delete':
        store.remove(key);
        return null;
      case 'containsKey':
        return store.containsKey(key);
      case 'readAll':
        return store;
    }
    return null;
  });
  messenger.setMockMethodCallHandler(_connChannel, (call) async {
    if (call.method == 'check') return <String>['wifi'];
    return null;
  });
}

/// 脚本化 Dio adapter：每次 fetch 依序弹出 [script] 一项。
/// 项为 ResponseBody → 正常返回；为 Exception → 抛出。
/// 记录每次请求的完整 URL 供轮换断言。
class _ScriptedAdapter implements HttpClientAdapter {
  final List<Object> script;
  final List<String> urls = [];
  int _cursor = 0;

  _ScriptedAdapter(this.script);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    urls.add(options.uri.toString());
    final item = script[_cursor++];
    if (item is Exception) throw item;
    return item as ResponseBody;
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonBody(Object data, {int status = 200}) {
  return ResponseBody(
    Stream.value(Uint8List.fromList(utf8.encode(jsonEncode(data)))),
    status,
    headers: {
      'content-type': ['application/json'],
    },
  );
}

ResponseBody _sseBody(String raw) {
  return ResponseBody(
    Stream.value(Uint8List.fromList(utf8.encode(raw))),
    200,
    headers: {
      'content-type': ['text/event-stream'],
    },
  );
}

/// 生成「输出一帧后断流」的 SSE 流（模拟流中段静默断开）
Stream<Uint8List> _sseThenBreak(String firstFrame) async* {
  yield Uint8List.fromList(utf8.encode(firstFrame));
  throw TimeoutException('模型响应中断（模拟断流）');
}

DioException _dioErr(DioExceptionType type, {int? status}) {
  final ro = RequestOptions(path: '/chat/completions');
  if (status != null) {
    return DioException.badResponse(
      statusCode: status,
      requestOptions: ro,
      response: Response(requestOptions: ro, statusCode: status),
    );
  }
  return DioException(requestOptions: ro, type: type);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('A1. LlmRetryPolicy 退避序列', () {
    test('指数退避：500 → 1000 → 2000（jitter=0 确定性）', () {
      const p = LlmRetryPolicy(maxAttempts: 4, jitterMs: 0);
      expect(p.delayMsFor(1), 500);
      expect(p.delayMsFor(2), 1000);
      expect(p.delayMsFor(3), 2000);
    });

    test('maxDelayMs 封顶：500 → 800 → 800（cap=800）', () {
      const p = LlmRetryPolicy(maxAttempts: 3, maxDelayMs: 800, jitterMs: 0);
      expect(p.delayMsFor(1), 500);
      expect(p.delayMsFor(2), 800);
      expect(p.delayMsFor(3), 800);
    });

    test('抖动范围：jitter=100 → [capped, capped+100)', () {
      const p = LlmRetryPolicy(jitterMs: 100);
      final d = p.delayMsFor(1);
      expect(d, greaterThanOrEqualTo(500));
      expect(d, lessThan(600));
    });
  });

  group('A2. isRetryableDioError 错误分类', () {
    test('超时/连接错误 → 可重试', () {
      expect(isRetryableDioError(_dioErr(DioExceptionType.connectionTimeout)), isTrue);
      expect(isRetryableDioError(_dioErr(DioExceptionType.receiveTimeout)), isTrue);
      expect(isRetryableDioError(_dioErr(DioExceptionType.sendTimeout)), isTrue);
      expect(isRetryableDioError(_dioErr(DioExceptionType.connectionError)), isTrue);
    });

    test('5xx 与 429 → 可重试；4xx → 不可重试', () {
      expect(isRetryableDioError(_dioErr(DioExceptionType.badResponse, status: 500)), isTrue);
      expect(isRetryableDioError(_dioErr(DioExceptionType.badResponse, status: 503)), isTrue);
      expect(isRetryableDioError(_dioErr(DioExceptionType.badResponse, status: 429)), isTrue);
      expect(isRetryableDioError(_dioErr(DioExceptionType.badResponse, status: 400)), isFalse);
      expect(isRetryableDioError(_dioErr(DioExceptionType.badResponse, status: 401)), isFalse);
      expect(isRetryableDioError(_dioErr(DioExceptionType.badResponse, status: 403)), isFalse);
    });

    test('取消/未知/证书错误 → 不可重试', () {
      expect(isRetryableDioError(_dioErr(DioExceptionType.cancel)), isFalse);
      expect(isRetryableDioError(_dioErr(DioExceptionType.unknown)), isFalse);
      expect(isRetryableDioError(_dioErr(DioExceptionType.badCertificate)), isFalse);
    });
  });

  group('A3. executeWithRetry 执行器', () {
    test('首次成功：不重试、不退避', () async {
      final sleeps = <Duration>[];
      var calls = 0;
      final r = await executeWithRetry(
        (i) async {
          calls++;
          return 'ok';
        },
        sleep: (d) async => sleeps.add(d),
      );
      expect(r, 'ok');
      expect(calls, 1);
      expect(sleeps, isEmpty);
    });

    test('第 2 次成功：退避一次 [500ms]，attempt 序号 1→2', () async {
      final sleeps = <Duration>[];
      final seq = <int>[];
      final r = await executeWithRetry(
        (i) async {
          seq.add(i);
          if (i == 1) throw _dioErr(DioExceptionType.connectionTimeout);
          return 'recovered';
        },
        // 确定性退避（关闭抖动 + 标准 500/1000/2000），才能断言精确 Duration
        policy: const LlmRetryPolicy(jitterMs: 0),
        sleep: (d) async => sleeps.add(d),
      );
      expect(r, 'recovered');
      expect(seq, [1, 2]);
      expect(sleeps, [const Duration(milliseconds: 500)]);
    });

    test('全部耗尽：抛最后一次错误，attempt=maxAttempts，退避 N-1 次', () async {
      final sleeps = <Duration>[];
      var calls = 0;
      await expectLater(
        executeWithRetry(
          (i) async {
            calls++;
            throw _dioErr(DioExceptionType.receiveTimeout);
          },
          policy: const LlmRetryPolicy(jitterMs: 0),
          sleep: (d) async => sleeps.add(d),
        ),
        throwsA(isA<DioException>()),
      );
      expect(calls, 3);
      expect(sleeps.length, 2);
      expect(sleeps[0], const Duration(milliseconds: 500));
      expect(sleeps[1], const Duration(milliseconds: 1000));
    });

    test('4xx 不可重试：立即抛出，仅 1 次尝试', () async {
      var calls = 0;
      await expectLater(
        executeWithRetry(
          (i) async {
            calls++;
            throw _dioErr(DioExceptionType.badResponse, status: 401);
          },
          sleep: (_) async => fail('不应退避'),
        ),
        throwsA(isA<DioException>()),
      );
      expect(calls, 1);
    });

    test('LlmNonRetryableException：保持类型立即重抛', () async {
      var calls = 0;
      final marker = Exception('已输出 token 后失败');
      await expectLater(
        executeWithRetry(
          (i) async {
            calls++;
            throw LlmNonRetryableException(marker);
          },
          sleep: (_) async => fail('不应退避'),
        ),
        throwsA(isA<LlmNonRetryableException>()),
      );
      expect(calls, 1);
    });

    test('TimeoutException（零 token 断流）→ 可重试', () async {
      final sleeps = <Duration>[];
      var calls = 0;
      final r = await executeWithRetry(
        (i) async {
          calls++;
          if (i == 1) throw TimeoutException('首字超时');
          return 'ok';
        },
        sleep: (d) async => sleeps.add(d),
      );
      expect(r, 'ok');
      expect(calls, 2);
      expect(sleeps.length, 1);
    });

    test('非 Dio/非 Timeout 异常：不可重试直接抛', () async {
      var calls = 0;
      await expectLater(
        executeWithRetry(
          (i) async {
            calls++;
            throw StateError('业务错误');
          },
          sleep: (_) async => fail('不应退避'),
        ),
        throwsStateError,
      );
      expect(calls, 1);
    });

    test('onRetry 回调：收到下次序号/延迟/错误', () async {
      final logs = <(int, Duration, String)>[];
      await executeWithRetry(
        (i) async {
          if (i < 3) throw _dioErr(DioExceptionType.connectionError);
          return 'ok';
        },
        sleep: (_) async {},
        onRetry: (next, delay, e) => logs.add((next, delay, e.runtimeType.toString())),
      );
      expect(logs.length, 2);
      expect(logs[0].$1, 2);
      expect(logs[1].$1, 3);
    });
  });

  group('B1. parseFallbacks 解析容错', () {
    test('null / 空串 / 空白 → 空列表', () {
      expect(parseFallbacks(null), isEmpty);
      expect(parseFallbacks(''), isEmpty);
      expect(parseFallbacks('   '), isEmpty);
    });

    test('坏 JSON / 非数组 → 空列表（配置损坏不放大为崩溃）', () {
      expect(parseFallbacks('{bad json'), isEmpty);
      expect(parseFallbacks('{"a":1}'), isEmpty);
      expect(parseFallbacks('"str"'), isEmpty);
    });

    test('合法数组：完整条目解析、缺 baseUrl 条目跳过、字段可选', () {
      final r = parseFallbacks(
        '[{"baseUrl":"https://b1/v1","model":"m1","apiKey":"k1"},'
        '{"baseUrl":"https://b2/v1"},'
        '{"model":"孤儿"}]',
      );
      expect(r.length, 2);
      expect(r[0].baseUrl, 'https://b1/v1');
      expect(r[0].model, 'm1');
      expect(r[0].apiKey, 'k1');
      expect(r[1].baseUrl, 'https://b2/v1');
      expect(r[1].model, isNull);
      expect(r[1].apiKey, isNull);
    });
  });

  group('B2. expandEndpoints 端点展开', () {
    const primary = LlmConfigValues(
      apiKey: 'k0',
      baseUrl: 'https://main/v1',
      model: 'm0',
    );

    test('无 fallback：退化为纯同端点重试 [主,主,主]', () {
      final r = expandEndpoints(primary, const [], 3);
      expect(r.length, 3);
      expect(r.every((e) => e.baseUrl == 'https://main/v1'), isTrue);
    });

    test('2 个 fallback max=3：[主, 备1, 备2]', () {
      final r = expandEndpoints(primary, const [
        LlmFallbackEntry(baseUrl: 'https://b1/v1'),
        LlmFallbackEntry(baseUrl: 'https://b2/v1'),
      ], 3);
      expect(
        r.map((e) => e.baseUrl).toList(),
        ['https://main/v1', 'https://b1/v1', 'https://b2/v1'],
      );
    });

    test('1 个 fallback max=3：[主, 备1, 主]（额度回补主端点）', () {
      final r = expandEndpoints(primary, const [
        LlmFallbackEntry(baseUrl: 'https://b1/v1'),
      ], 3);
      expect(
        r.map((e) => e.baseUrl).toList(),
        ['https://main/v1', 'https://b1/v1', 'https://main/v1'],
      );
    });

    test('fallback 缺省字段继承主配置；显式字段覆盖', () {
      final r = expandEndpoints(primary, const [
        LlmFallbackEntry(baseUrl: 'https://b1/v1', model: 'm1'),
      ], 2);
      expect(r[1].model, 'm1'); // 显式覆盖
      expect(r[1].apiKey, 'k0'); // 继承主配置
    });
  });

  group('C. LlmClient 集成：chatCompletion', () {
    late Map<String, String> store;

    setUp(() {
      store = {
        'yuesheng_api_key': 'k0',
        'yuesheng_api_base_url': 'https://main/v1',
        'yuesheng_api_model': 'm0',
      };
      _mockChannels(store);
    });

    test('无 fallback：超时 2 次后第 3 次成功（URL 全打主端点）', () async {
      final adapter = _ScriptedAdapter([
        _dioErr(DioExceptionType.connectionTimeout),
        _dioErr(DioExceptionType.connectionTimeout),
        _jsonBody({
          'choices': [
            {'message': {'content': '最终回答'}},
          ],
        }),
      ]);
      final client = LlmClient(LlmConfigStorage(const FlutterSecureStorage()), Dio()..httpClientAdapter = adapter);

      final r = await client.chatCompletion([
        const ChatMessage(role: 'user', content: 'hi'),
      ]);
      expect(r, '最终回答');
      expect(adapter.urls.length, 3);
      expect(adapter.urls.every((u) => u.startsWith('https://main/v1')), isTrue);
    });

    test('fallback 轮换：主失败 → 备1 成功', () async {
      store['yuesheng_api_fallbacks'] =
          '[{"baseUrl":"https://backup/v1","model":"mb"}]';
      final adapter = _ScriptedAdapter([
        _dioErr(DioExceptionType.connectionError),
        _jsonBody({
          'choices': [
            {'message': {'content': '备家回答'}},
          ],
        }),
      ]);
      final client = LlmClient(LlmConfigStorage(const FlutterSecureStorage()), Dio()..httpClientAdapter = adapter);

      final r = await client.chatCompletion([
        const ChatMessage(role: 'user', content: 'hi'),
      ]);
      expect(r, '备家回答');
      expect(adapter.urls.length, 2);
      expect(adapter.urls[0].startsWith('https://main/v1'), isTrue);
      expect(adapter.urls[1].startsWith('https://backup/v1'), isTrue);
    });

    test('401 不可重试：转用户错误消息「HTTP 401」后抛出', () async {
      final adapter = _ScriptedAdapter([
        _dioErr(DioExceptionType.badResponse, status: 401),
      ]);
      final client = LlmClient(LlmConfigStorage(const FlutterSecureStorage()), Dio()..httpClientAdapter = adapter);

      await expectLater(
        client.chatCompletion([const ChatMessage(role: 'user', content: 'hi')]),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('HTTP 401'),
          ),
        ),
      );
      expect(adapter.urls.length, 1);
    });
  });

  group('C. LlmClient 集成：streamChat', () {
    late Map<String, String> store;

    setUp(() {
      store = {
        'yuesheng_api_key': 'k0',
        'yuesheng_api_base_url': 'https://main/v1',
        'yuesheng_api_model': 'm0',
      };
      _mockChannels(store);
    });

    test('零 token 建连失败 → 退避重试成功，token 正常输出', () async {
      final adapter = _ScriptedAdapter([
        _dioErr(DioExceptionType.connectionTimeout),
        _sseBody('data: {"choices":[{"delta":{"content":"你好"}}]}\n\ndata: [DONE]\n\n'),
      ]);
      final client = LlmClient(LlmConfigStorage(const FlutterSecureStorage()), Dio()..httpClientAdapter = adapter);

      final tokens = <String>[];
      await client.streamChat(
        [const ChatMessage(role: 'user', content: 'hi')],
        (resp) {
          if (!resp.isDone) tokens.add(resp.content);
        },
      );
      expect(tokens, ['你好']);
      expect(adapter.urls.length, 2);
    });

    test('已输出 token 后断流：不重试（单次请求），TimeoutException 冒泡', () async {
      final adapter = _ScriptedAdapter([
        ResponseBody(
          _sseThenBreak('data: {"choices":[{"delta":{"content":"部分"}}]}\n\n'),
          200,
          headers: {
            'content-type': ['text/event-stream'],
          },
        ),
        // 第二个脚本项存在但不应被消费——若被消费说明错误地重试了
        _sseBody('data: {"choices":[{"delta":{"content":"重复"}}]}\n\ndata: [DONE]\n\n'),
      ]);
      final client = LlmClient(LlmConfigStorage(const FlutterSecureStorage()), Dio()..httpClientAdapter = adapter);

      final tokens = <String>[];
      await expectLater(
        client.streamChat(
          [const ChatMessage(role: 'user', content: 'hi')],
          (resp) {
            if (!resp.isDone) tokens.add(resp.content);
          },
        ),
        throwsA(isA<TimeoutException>()),
      );
      // 核心安全断言：没有重复输出（重试被正确阻止）
      expect(tokens, ['部分']);
      expect(adapter.urls.length, 1);
    });

    test('取消：LlmRequestCancelledException 冒泡且不重试', () async {
      final adapter = _ScriptedAdapter([
        _dioErr(DioExceptionType.cancel),
        _sseBody('data: {"choices":[{"delta":{"content":"不应到达"}}]}\n\ndata: [DONE]\n\n'),
      ]);
      final client = LlmClient(LlmConfigStorage(const FlutterSecureStorage()), Dio()..httpClientAdapter = adapter);

      await expectLater(
        client.streamChat(
          [const ChatMessage(role: 'user', content: 'hi')],
          (_) {},
        ),
        throwsA(isA<LlmRequestCancelledException>()),
      );
      expect(adapter.urls.length, 1);
    });
  });
}
