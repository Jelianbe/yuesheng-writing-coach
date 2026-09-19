// ─────────────────────────────────────────────────────────────
// llm_client_usage_sink_test — M 批：三条链路的用量采集
//
// 覆盖：
//   1. 非流式 chatCompletionWithMeta —— 顶层 usage 被采集（此前被整块丢弃）
//   2. 流式 streamChat —— usage 随**最后一个 chunk**下发（delta.content 为空串）
//      ，必须仍被采集（这正是原实现跳过该 chunk 的原因）
//   3. 端点未回 usage（非 DeepSeek provider）⇒ 零上报，不报错
//   4. sink 抛错 ⇒ 主流程不受影响（观测是旁路）
//   5. testLlmConnection 独立请求路径同样采集（口径零遗漏）
//   6. 缺省 sink ⇒ 上报到全局 kSharedLlmUsageMonitor
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/llm_config_storage.dart';
import 'package:writingcoach/services/llm_concurrency_gate.dart';
import 'package:writingcoach/services/llm_usage.dart';
import 'package:writingcoach/services/llm_usage_monitor.dart';

const _secureChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);
const _connChannel = MethodChannel('dev.fluttercommunity.plus/connectivity');

/// 记录请求体、按脚本返回响应的 Dio adapter（仿
/// llm_client_stream_fallback_test.dart 的 _SseScriptAdapter）。
class _ScriptAdapter implements HttpClientAdapter {
  final List<Object> script;
  final List<Map<String, dynamic>> requestBodies = [];
  int _cursor = 0;

  _ScriptAdapter(this.script);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestBodies.add(
      jsonDecode(options.data as String) as Map<String, dynamic>,
    );
    final item = script[_cursor++];
    if (item is Exception) throw item;
    return item as ResponseBody;
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _sse(String raw) => ResponseBody(
  Stream.value(Uint8List.fromList(utf8.encode(raw))),
  200,
  headers: {
    'content-type': ['text/event-stream'],
  },
);

ResponseBody _json(String raw) => ResponseBody(
  Stream.value(Uint8List.fromList(utf8.encode(raw))),
  200,
  headers: {
    'content-type': ['application/json'],
  },
);

/// 采集器：记录 (kind, usage) 序列
class _Sink {
  final List<(LlmUsageKind, LlmUsage)> received = [];

  void call(LlmUsage usage, LlmUsageKind kind) {
    received.add((kind, usage));
  }
}

/// 抛错 sink：验证观测异常不阻断主流程
void _throwingSink(LlmUsage usage, LlmUsageKind kind) {
  throw StateError('观测出口故障（演练）');
}

const _kUsageJson =
    '{"prompt_tokens":120,"completion_tokens":8,"total_tokens":128,'
    '"prompt_cache_hit_tokens":64,"prompt_cache_miss_tokens":56,'
    '"completion_tokens_details":{"reasoning_tokens":3}}';

/// 流式：首帧正文 + **末帧 usage**（末帧 delta.content 为空串，
/// finish_reason 非空 —— 与 2026-09-14 真实端点抓包逐字同构）
const _kStreamWithUsage =
    'data: {"choices":[{"delta":{"content":"你好"}}]}\n\n'
    'data: {"model":"deepseek-flash","choices":[{"delta":{"content":""},'
    '"finish_reason":"stop"}],"usage":$_kUsageJson}\n\n'
    'data: [DONE]\n\n';

/// 流式：无 usage（非 DeepSeek provider 形态）
const _kStreamNoUsage =
    'data: {"choices":[{"delta":{"content":"你好"}}]}\n\n'
    'data: [DONE]\n\n';

LlmClient _client(_ScriptAdapter adapter, LlmUsageSink? sink, {String? tier}) {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_secureChannel, (call) async {
    final key = (call.arguments as Map?)?['key'] as String?;
    const store = <String, String>{
      'yuesheng_api_key': 'k0',
      'yuesheng_api_base_url': 'https://main/v1',
      'yuesheng_api_model': 'deepseek-chat',
    };
    return store[key];
  });
  messenger.setMockMethodCallHandler(_connChannel, (call) async {
    if (call.method == 'check') return <String>['wifi'];
    return null;
  });
  return LlmClient(
    LlmConfigStorage(const FlutterSecureStorage()),
    Dio()..httpClientAdapter = adapter,
    // TH-2：档位经 **config loader** 下发 —— 与生产同路径
    //（`resolveLlmConfig(db)` 读 `app_state.reasoning_tier` 后填入
    //  `LlmConfigValues.reasoningTier`，见 llm_config_resolver.dart:25/34）。
    // 传 null ⇒ 保持既有路径（旧单键存储不产档位 ⇒ 归一为 standard）。
    tier == null
        ? null
        : () async => LlmConfigValues(
            apiKey: 'k0',
            baseUrl: 'https://main/v1',
            model: 'deepseek-chat',
            reasoningTier: tier,
          ),
    null,
    LlmConcurrencyGate(),
    sink,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_secureChannel, null);
    messenger.setMockMethodCallHandler(_connChannel, null);
  });

  group('M 批 用量采集', () {
    test('非流式：顶层 usage 被采集并标注 chat', () async {
      final adapter = _ScriptAdapter([
        _json(
          '{"model":"deepseek-flash","choices":[{"message":{"role":"assistant",'
          '"content":"你好"},"finish_reason":"stop"}],"usage":$_kUsageJson}',
        ),
      ]);
      final sink = _Sink();
      final client = _client(adapter, sink.call);

      final r = await client.chatCompletionWithMeta([
        const ChatMessage(role: 'user', content: 'hi'),
      ]);

      expect(r.content, '你好');
      expect(sink.received, hasLength(1));
      final (kind, usage) = sink.received.single;
      expect(kind, LlmUsageKind.chat);
      expect(usage.promptTokens, 120);
      expect(usage.completionTokens, 8);
      expect(usage.cachedTokens, 64);
      expect(usage.reasoningTokens, 3);
      expect(usage.model, 'deepseek-flash');
      expect(usage.hitRate, closeTo(64 / 120, 1e-9));
    });

    test('流式：末帧空 content 携带的 usage 仍被采集并标注 stream', () async {
      final adapter = _ScriptAdapter([_sse(_kStreamWithUsage)]);
      final sink = _Sink();
      final client = _client(adapter, sink.call);

      final tokens = <String>[];
      await client.streamChat(
        [const ChatMessage(role: 'user', content: 'hi')],
        (r) {
          if (!r.isDone && r.content.isNotEmpty) tokens.add(r.content);
        },
      );

      expect(tokens, ['你好'], reason: '正文应正常投递（usage 采集不得干扰）');
      expect(sink.received, hasLength(1));
      final (kind, usage) = sink.received.single;
      expect(kind, LlmUsageKind.stream);
      expect(usage.promptTokens, 120);
      expect(usage.cachedTokens, 64);
    });

    test('端点未回 usage ⇒ 零上报且不报错', () async {
      final adapter = _ScriptAdapter([
        _sse(_kStreamNoUsage),
        _json(
          '{"choices":[{"message":{"role":"assistant","content":"你好"},'
          '"finish_reason":"stop"}]}',
        ),
      ]);
      final sink = _Sink();
      final client = _client(adapter, sink.call);

      await client.streamChat([
        const ChatMessage(role: 'user', content: 'hi'),
      ], (_) {});
      await client.chatCompletionWithMeta([
        const ChatMessage(role: 'user', content: 'hi'),
      ]);

      expect(sink.received, isEmpty);
    });

    test('sink 抛错 ⇒ 主流程不受影响（观测是旁路）', () async {
      final adapter = _ScriptAdapter([
        _json(
          '{"choices":[{"message":{"role":"assistant","content":"你好"},'
          '"finish_reason":"stop"}],"usage":$_kUsageJson}',
        ),
      ]);
      final client = _client(adapter, _throwingSink);

      final r = await client.chatCompletionWithMeta([
        const ChatMessage(role: 'user', content: 'hi'),
      ]);

      expect(r.content, '你好', reason: '观测出口故障不得吞掉正常响应');
      expect(r.finishReason, 'stop');
    });

    test('testLlmConnection 独立路径同样采集（口径零遗漏）', () async {
      final adapter = _ScriptAdapter([
        _json('{"model":"deepseek-flash","usage":$_kUsageJson,"choices":[]}'),
      ]);
      final sink = _Sink();
      final client = _client(adapter, sink.call);

      final r = await client.testLlmConnection();

      expect(r.success, isTrue);
      expect(sink.received, hasLength(1));
      expect(sink.received.single.$1, LlmUsageKind.chat);
      expect(sink.received.single.$2.promptTokens, 120);
    });

    test('缺省 sink ⇒ 上报到全局累计器', () async {
      final adapter = _ScriptAdapter([
        _json(
          '{"choices":[{"message":{"role":"assistant","content":"你好"},'
          '"finish_reason":"stop"}],"usage":$_kUsageJson}',
        ),
      ]);
      final before = kSharedLlmUsageMonitor.totals.promptTokens;
      final client = _client(adapter, null);

      await client.chatCompletionWithMeta([
        const ChatMessage(role: 'user', content: 'hi'),
      ]);

      expect(kSharedLlmUsageMonitor.totals.promptTokens, before + 120);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // TH 九批：业务链路标注（markCallContext）
  //
  // 为何是「前置标记 + 一次性消费」而非方法形参：给 streamChat /
  // chatCompletion / chatCompletionWithMeta 加可选具名参数会破坏全部
  // 测试 Fake 的 override 契约（实测 40+ 处 invalid_override）。
  // ─────────────────────────────────────────────────────────────
  group('TH 九批 链路标注', () {
    test('流式：标记 teacher ⇒ usage.context 带上 purpose 与耗时', () async {
      final adapter = _ScriptAdapter([_sse(_kStreamWithUsage)]);
      final sink = _Sink();
      final client = _client(adapter, sink.call);

      client.markCallContext(
        const LlmCallContext(purpose: LlmCallPurpose.teacher, sessionId: 's-1'),
      );
      await client.streamChat([
        const ChatMessage(role: 'user', content: 'hi'),
      ], (_) {});

      final usage = sink.received.single.$2;
      expect(usage.context?.purpose, LlmCallPurpose.teacher);
      expect(usage.context?.sessionId, 's-1');
      expect(
        usage.context?.latencyMs,
        isNotNull,
        reason: '流式 usage 随末帧下发 ⇒ 应带上全程耗时读数',
      );
    });

    test('非流式：标记 diagnosis ⇒ purpose=diagnosis', () async {
      final adapter = _ScriptAdapter([
        _json(
          '{"model":"deepseek-flash","choices":[{"message":{"role":"assistant",'
          '"content":"你好"},"finish_reason":"stop"}],"usage":$_kUsageJson}',
        ),
      ]);
      final sink = _Sink();
      final client = _client(adapter, sink.call);

      client.markCallContext(
        const LlmCallContext(purpose: LlmCallPurpose.diagnosis),
      );
      await client.chatCompletionWithMeta([
        const ChatMessage(role: 'user', content: 'hi'),
      ]);

      expect(
        sink.received.single.$2.context?.purpose,
        LlmCallPurpose.diagnosis,
      );
    });

    test('标记是一次性消费：第二次调用回落 unknown', () async {
      final adapter = _ScriptAdapter([
        _json(
          '{"choices":[{"message":{"role":"assistant","content":"a"},'
          '"finish_reason":"stop"}],"usage":$_kUsageJson}',
        ),
        _json(
          '{"choices":[{"message":{"role":"assistant","content":"b"},'
          '"finish_reason":"stop"}],"usage":$_kUsageJson}',
        ),
      ]);
      final sink = _Sink();
      final client = _client(adapter, sink.call);
      const msgs = [ChatMessage(role: 'user', content: 'hi')];

      client.markCallContext(
        const LlmCallContext(purpose: LlmCallPurpose.teacher),
      );
      await client.chatCompletionWithMeta(msgs);
      await client.chatCompletionWithMeta(msgs); // 无标记

      expect(sink.received, hasLength(2));
      expect(sink.received[0].$2.context?.purpose, LlmCallPurpose.teacher);
      expect(
        sink.received[1].$2.context,
        isNull,
        reason: '标记已消费 ⇒ 第二次不带 context（不残留错配）',
      );
    });

    test('未标记 ⇒ context 为 null（既有调用零标注）', () async {
      final adapter = _ScriptAdapter([
        _json(
          '{"choices":[{"message":{"role":"assistant","content":"a"},'
          '"finish_reason":"stop"}],"usage":$_kUsageJson}',
        ),
      ]);
      final sink = _Sink();
      final client = _client(adapter, sink.call);

      await client.chatCompletionWithMeta([
        const ChatMessage(role: 'user', content: 'hi'),
      ]);

      expect(sink.received.single.$2.context, isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // TH-2：档位入埋点（可事后回溯）
  //
  // 缺口（本组要堵的）：`test/config/reasoning_tier_test.dart` 只断言「档位 →
  // 补丁**映射**」这一纯函数；`test/services/reasoning_tier_request_body_test.dart`
  // 只断言档位**进了请求体**。**没有任何用例断言「档位进了埋点载荷」** ——
  // 而审计侧读的正是 `error_logs`。
  //
  // 鉴别力（为何走 LlmClient 而非直接调 withTier）：
  //   · 真实链路顺序 = **入口 withTier → usage 帧处 withLatency**。
  //     若 `withLatency` 丢掉档位，**只调 withTier 的用例照样绿**（假绿）；
  //     本组经 `streamChat` / `chatCompletionWithMeta` 走完整链路 ⇒ 必红。
  //   · `未设置档位 ⇒ standard` 一条同时锁住「归一」，防实现把 null 原样落库。
  // ─────────────────────────────────────────────────────────────
  group('TH-2 档位入埋点', () {
    test('流式 deep ⇒ 埋点带 deep，且与请求体同源（reasoning_effort=max）', () async {
      final adapter = _ScriptAdapter([_sse(_kStreamWithUsage)]);
      final sink = _Sink();
      final client = _client(adapter, sink.call, tier: 'deep');

      client.markCallContext(
        const LlmCallContext(purpose: LlmCallPurpose.mainChat),
      );
      await client.streamChat([
        const ChatMessage(role: 'user', content: 'hi'),
      ], (_) {});

      final ctx = sink.received.single.$2.context;
      expect(ctx?.reasoningTier, 'deep');
      expect(ctx?.latencyMs, isNotNull, reason: 'withLatency 不得把档位冲掉（两者必须共存）');
      expect(ctx?.purpose, LlmCallPurpose.mainChat);
      expect(
        adapter.requestBodies.single['reasoning_effort'],
        'max',
        reason: '埋点档位必须与请求体同源 —— 防「记 deep、发 standard」',
      );
    });

    test('非流式 low ⇒ 埋点带 low，请求体 reasoning_effort=low', () async {
      final adapter = _ScriptAdapter([
        _json(
          '{"model":"deepseek-flash","choices":[{"message":{"role":"assistant",'
          '"content":"你好"},"finish_reason":"stop"}],"usage":$_kUsageJson}',
        ),
      ]);
      final sink = _Sink();
      final client = _client(adapter, sink.call, tier: 'low');

      client.markCallContext(
        const LlmCallContext(purpose: LlmCallPurpose.diagnosis),
      );
      await client.chatCompletionWithMeta([
        const ChatMessage(role: 'user', content: 'hi'),
      ]);

      expect(sink.received.single.$2.context?.reasoningTier, 'low');
      expect(adapter.requestBodies.single['reasoning_effort'], 'low');
    });

    test('未设置档位 ⇒ 归一为 standard（键恒有值，不留 null 歧义）', () async {
      final adapter = _ScriptAdapter([
        _json(
          '{"choices":[{"message":{"role":"assistant","content":"a"},'
          '"finish_reason":"stop"}],"usage":$_kUsageJson}',
        ),
      ]);
      final sink = _Sink();
      final client = _client(adapter, sink.call); // tier 缺省

      client.markCallContext(
        const LlmCallContext(purpose: LlmCallPurpose.mainChat),
      );
      await client.chatCompletionWithMeta([
        const ChatMessage(role: 'user', content: 'hi'),
      ]);

      expect(sink.received.single.$2.context?.reasoningTier, 'standard');
      expect(
        adapter.requestBodies.single.containsKey('reasoning_effort'),
        isFalse,
        reason: 'standard 不产请求体键（既有锚点不变）',
      );
    });

    test('off 档 ⇒ 埋点带 off（不是 null，也不是 standard）', () async {
      final adapter = _ScriptAdapter([
        _json(
          '{"choices":[{"message":{"role":"assistant","content":"a"},'
          '"finish_reason":"stop"}],"usage":$_kUsageJson}',
        ),
      ]);
      final sink = _Sink();
      final client = _client(adapter, sink.call, tier: 'off');

      client.markCallContext(
        const LlmCallContext(purpose: LlmCallPurpose.mainChat),
      );
      await client.chatCompletionWithMeta([
        const ChatMessage(role: 'user', content: 'hi'),
      ]);

      expect(sink.received.single.$2.context?.reasoningTier, 'off');
      expect(adapter.requestBodies.single['thinking'], {'type': 'disabled'});
    });
  });
}
