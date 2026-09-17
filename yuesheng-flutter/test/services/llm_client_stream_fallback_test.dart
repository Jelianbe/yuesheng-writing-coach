// ─────────────────────────────────────────────────────────────
// llm_client_stream_fallback_test — ADR-C94 S4a：deepseek 系流式分级降级
//
// 覆盖（架构 S1-T04 验收 + ADR-C94 §6 AC3/AC4）：
//   1. deepseek 空流（纯 reasoning_content + [DONE]）→ 尝试 2 注入
//      thinking disabled 兜底；尝试 1 请求体原参数（无 thinking 字段）
//   2. **纯推理流不被误判非空**（emitted 仅 content token 计数，
//      reasoning_content 增量不计入——§3.4 关键细节）
//   3. 尝试 2 仍空 → 正常返回（不抛错），isDone 恰好投递一次
//   4. 半输出（有 content token）不降级（单次请求）
//   5. 非 deepseek（GLM/doubao/通用）空流不降级，请求体逐字节不变（AC-3）
//   6. caller extraBody 合并：保留键剥离 + 兜底参数优先级（尝试 2 胜出）
//   7. A-1b 五②：空流尝试端点不回 usage 帧 ⇒ 补零 token 埋点
//      （purpose=streamEmptyFallback，每次空流尝试各一条；半输出 /
//      非 deepseek 不降级 ⇒ 无该埋点）
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/config/shared_constants.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/llm_config_storage.dart';
import 'package:writingcoach/services/llm_concurrency_gate.dart';
import 'package:writingcoach/services/llm_usage.dart';

const _secureChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);
const _connChannel = MethodChannel('dev.fluttercommunity.plus/connectivity');

/// 记录每次请求体并按脚本返回 SSE / 异常的 Dio adapter。
class _SseScriptAdapter implements HttpClientAdapter {
  /// 项为 ResponseBody → 正常返回；为 Exception → 抛出。
  final List<Object> script;
  final List<Map<String, dynamic>> requestBodies = [];
  int _cursor = 0;

  _SseScriptAdapter(this.script);

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

ResponseBody _sse(String raw) {
  return ResponseBody(
    Stream.value(Uint8List.fromList(utf8.encode(raw))),
    200,
    headers: {
      'content-type': ['text/event-stream'],
    },
  );
}

/// 纯推理流：只有 reasoning_content 增量 + [DONE]（零 content token）。
const _kPureReasoningStream =
    'data: {"choices":[{"delta":{"reasoning_content":"思考一"}}]}\n\n'
    'data: {"choices":[{"delta":{"reasoning_content":"思考二"}}]}\n\n'
    'data: [DONE]\n\n';

/// 正常内容流：一帧 content + [DONE]。
const _kContentStream =
    'data: {"choices":[{"delta":{"content":"你好呀"}}]}\n\n'
    'data: [DONE]\n\n';

/// 纯推理流（零 content token）但**无 [DONE]**——服务端 length 截断后直接
/// 关闭连接的收尾形态（reasoning 吃光 completion 预算时常见）。
const _kPureReasoningNoDoneStream =
    'data: {"choices":[{"delta":{"reasoning_content":"思考一"}}]}\n\n'
    'data: {"choices":[{"delta":{"reasoning_content":"思考二"}}]}\n\n';

/// 有 content token 但**无 [DONE]** 的流（半输出 + 干净结束）。
const _kContentNoDoneStream =
    'data: {"choices":[{"delta":{"content":"你好呀"}}]}\n\n';

/// 采集器：记录 (kind, usage) 序列（A-1b 五② 埋点断言用）。
class _Sink {
  final List<(LlmUsageKind, LlmUsage)> received = [];

  void call(LlmUsage usage, LlmUsageKind kind) {
    received.add((kind, usage));
  }
}

/// 回调采集器：分帧记录 content token 与 isDone 投递次数。
class _Collector {
  final List<String> tokens = [];
  int isDoneCount = 0;

  void call(LlmStreamResponse resp) {
    if (resp.isDone) {
      isDoneCount++;
    } else if (resp.content.isNotEmpty) {
      tokens.add(resp.content);
    }
  }
}

LlmClient _client(
  _SseScriptAdapter adapter,
  String model, {
  LlmUsageSink? sink,
}) {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_secureChannel, (call) async {
    final key = (call.arguments as Map?)?['key'] as String?;
    final store = <String, String>{
      'yuesheng_api_key': 'k0',
      'yuesheng_api_base_url': 'https://main/v1',
      'yuesheng_api_model': model,
    };
    return store[key];
  });
  // 网络预检（checkNetwork）platform channel mock：Wi-Fi 在线
  messenger.setMockMethodCallHandler(_connChannel, (call) async {
    if (call.method == 'check') return <String>['wifi'];
    return null;
  });
  return LlmClient(
    LlmConfigStorage(const FlutterSecureStorage()),
    Dio()..httpClientAdapter = adapter,
    null,
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

  group('ADR-C94 deepseek 空流分级降级', () {
    test('deepseek 空流 → 尝试 1 原参数、尝试 2 注入 thinking disabled，内容救回', () async {
      final adapter = _SseScriptAdapter([
        _sse(_kPureReasoningStream),
        _sse(_kContentStream),
      ]);
      final collector = _Collector();
      await _client(adapter, 'deepseek-v4-flash').streamChat(const [
        ChatMessage(role: 'user', content: 'hi'),
      ], collector.call);

      expect(adapter.requestBodies, hasLength(2));
      // 尝试 1：请求体原参数——无 thinking 字段、无 max_tokens（成功路径零变更）
      expect(adapter.requestBodies[0], {
        'model': 'deepseek-v4-flash',
        'messages': [
          {'role': 'user', 'content': 'hi'},
        ],
        'stream': true,
        'temperature': LlmConfig.streamTemperature,
      });
      // 尝试 2：仅追加兜底参数（C80 §1.2 探针唯一生效参数）
      expect(adapter.requestBodies[1]['thinking'], {'type': 'disabled'});
      // 内容由尝试 2 救回
      expect(collector.tokens, ['你好呀']);
      // isDone 恰好一次契约（尝试 1 的 isDone 被吞掉）
      expect(collector.isDoneCount, 1);
    });

    test('纯推理流（零 content token）不被误判非空——降级判据 emitted 仅计 content', () async {
      // 若 reasoning_content 增量计入 emitted，尝试 1 会被判非空 → 不降级
      // → 第二个脚本项不被消费。此处以「尝试 2 被触发」反证 emitted 语义。
      final adapter = _SseScriptAdapter([
        _sse(_kPureReasoningStream),
        _sse(_kContentStream),
      ]);
      final collector = _Collector();
      await _client(adapter, 'deepseek-chat').streamChat(const [
        ChatMessage(role: 'user', content: 'hi'),
      ], collector.call);
      expect(adapter.requestBodies, hasLength(2), reason: '纯推理流必须判空并触发尝试 2');
      expect(collector.tokens, ['你好呀']);
    });

    test('尝试 2 仍空 → 正常返回不抛错，恰好 2 次请求，isDone 恰好一次', () async {
      final adapter = _SseScriptAdapter([
        _sse(_kPureReasoningStream),
        _sse(_kPureReasoningStream),
      ]);
      final collector = _Collector();
      await _client(adapter, 'deepseek-reasoner').streamChat(const [
        ChatMessage(role: 'user', content: 'hi'),
      ], collector.call);
      expect(adapter.requestBodies, hasLength(2));
      expect(collector.tokens, isEmpty);
      expect(collector.isDoneCount, 1, reason: '两次尝试的 isDone 只投递一次');
    });

    test('半输出（有 content token）不降级——单次请求，isDone 恰好一次', () async {
      final adapter = _SseScriptAdapter([
        _sse(_kContentStream),
        // 第二个脚本项不应被消费
        _sse(_kContentStream),
      ]);
      final collector = _Collector();
      await _client(adapter, 'deepseek-v4-flash').streamChat(const [
        ChatMessage(role: 'user', content: 'hi'),
      ], collector.call);
      expect(adapter.requestBodies, hasLength(1));
      expect(collector.tokens, ['你好呀']);
      expect(collector.isDoneCount, 1);
    });
  });

  group('ADR-C94 AC3：非 deepseek 请求体逐字节不变、不降级', () {
    test('通用模型空流 → 不降级（单次请求），isDone 恰好一次', () async {
      final adapter = _SseScriptAdapter([
        _sse(_kPureReasoningStream),
        _sse(_kContentStream),
      ]);
      final collector = _Collector();
      await _client(adapter, 'some-generic-model').streamChat(const [
        ChatMessage(role: 'user', content: 'hi'),
      ], collector.call);
      expect(adapter.requestBodies, hasLength(1));
      expect(collector.tokens, isEmpty);
      expect(collector.isDoneCount, 1);
    });

    test('GLM thinking 系请求体锚点：既有 thinking disabled 行为不变、不重复降级', () async {
      final adapter = _SseScriptAdapter([_sse(_kContentStream)]);
      final collector = _Collector();
      await _client(adapter, 'glm-4.5').streamChat(const [
        ChatMessage(role: 'user', content: 'hi'),
      ], collector.call);
      expect(adapter.requestBodies, hasLength(1));
      expect(adapter.requestBodies[0], {
        'model': 'glm-4.5',
        'messages': [
          {'role': 'user', 'content': 'hi'},
        ],
        'stream': true,
        'thinking': {'type': 'disabled'},
        'temperature': LlmConfig.streamTemperature,
      });
      expect(collector.tokens, ['你好呀']);
    });

    test('doubao-seed 系请求体锚点：同 GLM 形态，兜底名单不命中（非 deepseek）', () async {
      final adapter = _SseScriptAdapter([_sse(_kContentStream)]);
      await _client(
        adapter,
        'doubao-seed-1.6',
      ).streamChat(const [ChatMessage(role: 'user', content: 'hi')], (_) {});
      expect(adapter.requestBodies, hasLength(1));
      expect(adapter.requestBodies[0]['model'], 'doubao-seed-1.6');
      expect(adapter.requestBodies[0]['thinking'], {'type': 'disabled'});
    });
  });

  group('ADR-C94 extraBody 合并纪律', () {
    test('caller extraBody：保留键剥离 + 尝试 2 兜底参数优先于 caller 传参', () async {
      final adapter = _SseScriptAdapter([
        _sse(_kPureReasoningStream),
        _sse(_kContentStream),
      ]);
      final collector = _Collector();
      await _client(adapter, 'deepseek-v4-flash').streamChat(
        const [ChatMessage(role: 'user', content: 'hi')],
        collector.call,
        extraBody: {
          'thinking': {'type': 'enabled'},
          'stream': false, // 保留键：必须被剥离
          'model': 'hacked', // 保留键：必须被剥离
          'custom_field': 'x',
        },
      );
      // 尝试 1：caller 的 thinking enabled 透传（custom_field 保留、保留键剥离）
      expect(adapter.requestBodies[0]['thinking'], {'type': 'enabled'});
      expect(adapter.requestBodies[0]['custom_field'], 'x');
      expect(
        adapter.requestBodies[0]['stream'],
        isTrue,
        reason: '保留键 stream 不得被 extraBody 覆盖',
      );
      expect(
        adapter.requestBodies[0]['model'],
        'deepseek-v4-flash',
        reason: '保留键 model 不得被 extraBody 覆盖',
      );
      // 尝试 2：兜底参数胜出（纠偏动作不得被 caller 重新打开 thinking）
      expect(adapter.requestBodies[1]['thinking'], {'type': 'disabled'});
      expect(adapter.requestBodies[1]['custom_field'], 'x');
      expect(collector.tokens, ['你好呀']);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 空内容缺陷补漏（2026-09-15）：
  // 降级判据原为「零 content token **且正常收尾达成 [DONE]**」，遗漏
  // 「服务端 length 截断后不发 [DONE] 即关闭连接」这一空响应形态
  //（reasoning 吃光 completion 预算时的常见收尾）。放宽后判据 =
  // 零 content token 且本次尝试未抛异常（= 流干净结束，无论 [DONE] 是否达成）。
  // 安全性依据：能走到降级分支说明未抛异常（零 token 阶段的断流/超时在
  // _consumeSseStream 内 rethrow，由外层 executeWithRetry 接管），且用户侧
  // 零内容 ⇒ 重发不复读。
  // ─────────────────────────────────────────────────────────────
  group('空响应降级判据放宽：零 token 且无 [DONE]（干净收尾）', () {
    test('deepseek 零 token + 无 [DONE] → 降级重试，内容由尝试 2 救回', () async {
      final adapter = _SseScriptAdapter([
        _sse(_kPureReasoningNoDoneStream), // 尝试 1：无 [DONE] 收尾
        _sse(_kContentStream), // 尝试 2：关思考后正常产出
      ]);
      final collector = _Collector();
      await _client(adapter, 'deepseek-v4-flash').streamChat(const [
        ChatMessage(role: 'user', content: 'hi'),
      ], collector.call);
      expect(
        adapter.requestBodies,
        hasLength(2),
        reason: '零 token 且无 [DONE] 的空响应必须触发降级（本批修复点）',
      );
      expect(adapter.requestBodies[1]['thinking'], {'type': 'disabled'});
      expect(collector.tokens, ['你好呀']);
      expect(collector.isDoneCount, 1);
    });

    test('deepseek 两次尝试均无 [DONE] → 2 次请求、不抛错、isDone 不投递', () async {
      final adapter = _SseScriptAdapter([
        _sse(_kPureReasoningNoDoneStream),
        _sse(_kPureReasoningNoDoneStream),
      ]);
      final collector = _Collector();
      await _client(adapter, 'deepseek-reasoner').streamChat(const [
        ChatMessage(role: 'user', content: 'hi'),
      ], collector.call);
      expect(adapter.requestBodies, hasLength(2));
      expect(collector.tokens, isEmpty);
      // 契约现状：两次尝试都未达成 [DONE] ⇒ 补投点不触发（与放宽前一致，
      // 非本批引入）。调用方需以「流结束」而非 isDone 帧作为终结信号。
      expect(collector.isDoneCount, 0);
    });

    test('非 deepseek 模型零 token + 无 [DONE] → 不降级（AC-3 守护）', () async {
      final adapter = _SseScriptAdapter([
        _sse(_kPureReasoningNoDoneStream),
        _sse(_kContentStream),
      ]);
      final collector = _Collector();
      await _client(adapter, 'some-generic-model').streamChat(const [
        ChatMessage(role: 'user', content: 'hi'),
      ], collector.call);
      expect(adapter.requestBodies, hasLength(1));
      expect(collector.tokens, isEmpty);
    });

    test('半输出 + 无 [DONE] → 不降级（已投递内容，重发会复读）', () async {
      final adapter = _SseScriptAdapter([
        _sse(_kContentNoDoneStream),
        _sse(_kContentStream), // 不应被消费
      ]);
      final collector = _Collector();
      await _client(adapter, 'deepseek-v4-flash').streamChat(const [
        ChatMessage(role: 'user', content: 'hi'),
      ], collector.call);
      expect(adapter.requestBodies, hasLength(1));
      expect(collector.tokens, ['你好呀']);
      expect(collector.isDoneCount, 0);
    });
  });
  group('A-1b 五②：C94 空流尝试补零 token 埋点', () {
    test('deepseek 双空流 → sink 收到 2 条 streamEmptyFallback（零 token）', () async {
      final adapter = _SseScriptAdapter([
        _sse(_kPureReasoningStream),
        _sse(_kPureReasoningStream),
      ]);
      final sink = _Sink();
      final collector = _Collector();
      await _client(adapter, 'deepseek-reasoner', sink: sink.call).streamChat(
        const [ChatMessage(role: 'user', content: 'hi')],
        collector.call,
      );
      expect(adapter.requestBodies, hasLength(2));
      expect(sink.received, hasLength(2), reason: '两次空流尝试各补一条埋点');
      for (final (kind, usage) in sink.received) {
        expect(kind, LlmUsageKind.stream);
        expect(usage.context?.purpose, LlmCallPurpose.streamEmptyFallback);
        expect(usage.promptTokens, 0);
        expect(usage.completionTokens, 0);
        expect(usage.reasoningTokens, 0);
      }
    });

    test('尝试 2 救回（有内容）→ 仅尝试 1 一条 streamEmptyFallback', () async {
      final adapter = _SseScriptAdapter([
        _sse(_kPureReasoningStream),
        _sse(_kContentStream),
      ]);
      final sink = _Sink();
      final collector = _Collector();
      await _client(adapter, 'deepseek-v4-flash', sink: sink.call).streamChat(
        const [ChatMessage(role: 'user', content: 'hi')],
        collector.call,
      );
      expect(adapter.requestBodies, hasLength(2));
      expect(
        sink.received,
        hasLength(1),
        reason: '尝试 2 有 content ⇒ 走正常流式埋点路径，不再补零 token',
      );
      expect(
        sink.received.single.$2.context?.purpose,
        LlmCallPurpose.streamEmptyFallback,
      );
    });

    test('半输出不降级 → 无 streamEmptyFallback 埋点', () async {
      final adapter = _SseScriptAdapter([_sse(_kContentStream)]);
      final sink = _Sink();
      final collector = _Collector();
      await _client(adapter, 'deepseek-v4-flash', sink: sink.call).streamChat(
        const [ChatMessage(role: 'user', content: 'hi')],
        collector.call,
      );
      expect(adapter.requestBodies, hasLength(1));
      expect(sink.received, isEmpty);
    });

    test('非 deepseek 空流不降级 → 无 streamEmptyFallback 埋点', () async {
      final adapter = _SseScriptAdapter([_sse(_kPureReasoningStream)]);
      final sink = _Sink();
      final collector = _Collector();
      await _client(adapter, 'some-generic-model', sink: sink.call).streamChat(
        const [ChatMessage(role: 'user', content: 'hi')],
        collector.call,
      );
      expect(adapter.requestBodies, hasLength(1));
      expect(sink.received, isEmpty);
    });
  });
}
