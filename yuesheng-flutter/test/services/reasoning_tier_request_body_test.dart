// ─────────────────────────────────────────────────────────────
// reasoning_tier_request_body_test — 推理档位**真的进了请求体**吗？
//
// 为什么需要本文件（2026-09-19 `TH` 档位实验批 侦察所得）：
//   · `test/config/reasoning_tier_test.dart` 只断言「档位 → 补丁**映射**」这个
//     纯函数（`reasoningBodyPatchFor` 的返回值）；
//   · `test/providers/reasoning_tier_provider_test.dart` 只断言 provider ⇄ DB；
//   · 既有**请求体锚点**测试（`llm_client_stream_fallback_test.dart`）用的是
//     GLM / doubao / deepseek 空流兜底三条路径 —— 而档位补丁只在
//     `!profile.disableThinking` 分支里合并
//     （`lib/services/llm_client.dart:812-821` 与 `:846-854`）
//     ⇒ **那三条锚点恰好覆盖不到档位**。
//   ⇒ 缺口：**没有任何测试证明非标准档的键真的落进了最终请求体**。
//     本文件补这个缺口，两个 body 构建器（流式 / 非流式）各测一遍。
//
// 判别力（防「假绿」）：断言的是**最终 HTTP body 的键值**，不是映射函数的返回值
//   ⇒ 若有人把 `reasoningBodyPatchFor` 改成恒返回 `{}`、或把合并那两行删掉，
//     本文件转红；而只断言映射表的既有用例**不会**红。
//
// 真机侧的对应证据（同批，非本文件覆盖）：`deep` 档在同消息对照下把
//   `reasoning_tokens` 抬到 2.57×、`off` 档打到 0
//   ⇒ `.ai/reports/2026-09-19-TH档位实验.md` §3。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/config/reasoning_tier.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/llm_concurrency_gate.dart';
import 'package:writingcoach/services/llm_config_storage.dart';
import 'package:writingcoach/services/llm_usage.dart';

const _connChannel = MethodChannel('dev.fluttercommunity.plus/connectivity');
const _secureChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// 按脚本返回响应体、并记录每次请求体的 Dio adapter。
class _ScriptAdapter implements HttpClientAdapter {
  final List<ResponseBody> script;
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
    return script[_cursor++];
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

ResponseBody _jsonResp(Map<String, dynamic> payload) => ResponseBody.fromString(
  jsonEncode(payload),
  200,
  headers: {
    'content-type': ['application/json'],
  },
);

/// 正常内容流：一帧 content + [DONE]。
const _kContentStream =
    'data: {"choices":[{"delta":{"content":"你好呀"}}]}\n\n'
    'data: [DONE]\n\n';

/// 非流式最小可用响应（含 usage，使 `_reportUsage` 有据可读）。
Map<String, dynamic> _kChatResponse(String model) => {
  'model': model,
  'choices': [
    {
      'message': {'role': 'assistant', 'content': '你好呀'},
      'finish_reason': 'stop',
    },
  ],
  'usage': {'prompt_tokens': 11, 'completion_tokens': 7},
};

class _Sink {
  void call(LlmUsage usage, LlmUsageKind kind) {}
}

/// 装配：**档位经 config loader 下发**（生产同路径 —— `resolveLlmConfig(db)`
/// 读 `app_state.reasoning_tier` 后填入 `LlmConfigValues.reasoningTier`，
/// 见 `lib/services/llm_config_resolver.dart:25/34`）。
LlmClient _client(_ScriptAdapter adapter, String model, String? tier) {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_secureChannel, (call) async => null);
  // 网络预检（checkNetwork）platform channel mock：Wi-Fi 在线
  messenger.setMockMethodCallHandler(_connChannel, (call) async {
    if (call.method == 'check') return <String>['wifi'];
    return null;
  });
  return LlmClient(
    null,
    Dio()..httpClientAdapter = adapter,
    () async => LlmConfigValues(
      apiKey: 'k0',
      baseUrl: 'https://main/v1',
      model: model,
      reasoningTier: tier,
    ),
    null,
    LlmConcurrencyGate(),
    _Sink().call,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_connChannel, null);
    messenger.setMockMethodCallHandler(_secureChannel, null);
  });

  Future<Map<String, dynamic>> streamBody(String model, String? tier) async {
    final adapter = _ScriptAdapter([_sse(_kContentStream)]);
    await _client(
      adapter,
      model,
      tier,
    ).streamChat(const [ChatMessage(role: 'user', content: 'hi')], (_) {});
    expect(adapter.requestBodies, hasLength(1));
    return adapter.requestBodies.single;
  }

  Future<Map<String, dynamic>> chatBody(String model, String? tier) async {
    final adapter = _ScriptAdapter([_jsonResp(_kChatResponse(model))]);
    await _client(
      adapter,
      model,
      tier,
    ).chatCompletionWithMeta(const [ChatMessage(role: 'user', content: 'hi')]);
    expect(adapter.requestBodies, hasLength(1));
    return adapter.requestBodies.single;
  }

  group('流式请求体 · 档位补丁确实落盘（教学链路）', () {
    test('未设置档位 ⇒ 请求体无任何推理字段（零变更护栏）', () async {
      final body = await streamBody('deepseek-v4-flash', null);
      expect(body.containsKey('reasoning_effort'), isFalse);
      expect(body.containsKey('thinking'), isFalse);
    });

    test('标准档 ⇒ 与「未设置」一致：不产键', () async {
      final body = await streamBody('deepseek-v4-flash', reasoningTierStandard);
      expect(body.containsKey('reasoning_effort'), isFalse);
      expect(body.containsKey('thinking'), isFalse);
    });

    test('轻量档 ⇒ reasoning_effort: low', () async {
      final body = await streamBody('deepseek-v4-flash', reasoningTierLow);
      expect(body['reasoning_effort'], 'low');
    });

    test('深度档 ⇒ reasoning_effort: max', () async {
      final body = await streamBody('deepseek-v4-flash', reasoningTierDeep);
      expect(body['reasoning_effort'], 'max');
    });

    test('关闭思考档 ⇒ thinking: disabled，且不产 reasoning_effort', () async {
      final body = await streamBody('deepseek-v4-flash', reasoningTierOff);
      expect(body['thinking'], {'type': 'disabled'});
      expect(body.containsKey('reasoning_effort'), isFalse);
    });

    test('GLM thinking 系 ⇒ 画像兜底优先，档位被旁路（深度档也不产键）', () async {
      final body = await streamBody('glm-4.5', reasoningTierDeep);
      expect(body['thinking'], {'type': 'disabled'});
      expect(body.containsKey('reasoning_effort'), isFalse);
    });
  });

  group('非流式请求体 · 档位补丁确实落盘（提炼 / 观察链路）', () {
    test('未设置档位 ⇒ 无任何推理字段', () async {
      final body = await chatBody('deepseek-v4-flash', null);
      expect(body.containsKey('reasoning_effort'), isFalse);
      expect(body.containsKey('thinking'), isFalse);
    });

    test('深度档 ⇒ reasoning_effort: max', () async {
      final body = await chatBody('deepseek-v4-flash', reasoningTierDeep);
      expect(body['reasoning_effort'], 'max');
    });

    test('关闭思考档 ⇒ thinking: disabled', () async {
      final body = await chatBody('deepseek-v4-flash', reasoningTierOff);
      expect(body['thinking'], {'type': 'disabled'});
    });
  });
}
