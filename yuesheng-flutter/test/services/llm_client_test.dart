// ─────────────────────────────────────────────────────────────
// llm_client_test — LlmClient.testLlmConnection 前置守卫测试
//
// 覆盖（R-019 批次三补 + 批次A baseUrl 链路锚定）：
//   1. 配置缺失 → 返回「请先填写并保存」提示（mock secure storage 空）
//   2. 成功路径 → 请求 URL = '${cfg.baseUrl}/chat/completions'、
//      Authorization = 'Bearer <key>'、body.model = cfg.model（批次A 锚定）
//   3. 网络不可用 → 返回「设备网络不可用」
//   4. HTTP 500 → 返回 HTTP 500
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/llm_config_storage.dart';

const _kStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);
const _kConnChannel = MethodChannel('dev.fluttercommunity.plus/connectivity');

/// 以内存 map 替换 secure_storage / connectivity 两个 platform channel。
void _mockChannels(Map<String, String> store, {List<String> conn = const ['wifi']}) {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_kStorageChannel, (call) async {
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
  messenger.setMockMethodCallHandler(_kConnChannel, (call) async {
    if (call.method == 'check') return conn;
    return null;
  });
}

/// 记录请求 URL / Authorization / 请求体，返回固定 [status] 响应。
class _CapturingAdapter implements HttpClientAdapter {
  final int status;
  String? url;
  String? authorization;
  String? body;

  _CapturingAdapter({this.status = 200});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    url = options.uri.toString();
    authorization = (options.headers['Authorization'] ?? '').toString();
    if (options.data is String) body = options.data as String;
    return ResponseBody(
      Stream.value(Uint8List.fromList(utf8.encode(jsonEncode({'ok': true})))),
      status,
      headers: {'content-type': ['application/json']},
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 按序返回预设响应序列的 adapter，记录每次请求体（续接测试用）。
class _SequenceAdapter implements HttpClientAdapter {
  final List<({String content, String finishReason})> responses;
  final List<Map<String, dynamic>> requestBodies = [];
  int _cursor = 0;

  _SequenceAdapter(this.responses);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestBodies.add(jsonDecode(options.data as String) as Map<String, dynamic>);
    final r = responses[_cursor++];
    final data = {
      'choices': [
        {
          'message': {'role': 'assistant', 'content': r.content},
          'finish_reason': r.finishReason,
        },
      ],
    };
    return ResponseBody(
      Stream.value(Uint8List.fromList(utf8.encode(jsonEncode(data)))),
      200,
      headers: {'content-type': ['application/json']},
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // 空 secure storage：所有 read 返回 null → getLlmConfig 判空返回 null
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_kStorageChannel, (call) async => null);
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_kStorageChannel, null);
    messenger.setMockMethodCallHandler(_kConnChannel, null);
  });

  test('配置缺失 → 返回「请先填写并保存」', () async {
    final client = LlmClient(
      LlmConfigStorage(const FlutterSecureStorage()),
      Dio(),
    );
    final r = await client.testLlmConnection();
    expect(r.success, isFalse);
    expect(r.message, contains('API 配置未设置'));
  });

  test('成功路径 → 请求 URL 用配置 baseUrl，Authorization/body 正确（批次A 链路锚定）', () async {
    _mockChannels({
      'yuesheng_api_key': 'sk-custom-test',
      'yuesheng_api_base_url': 'https://api.custom.example.com',
      'yuesheng_api_model': 'custom-model',
    });
    final adapter = _CapturingAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final client = LlmClient(
      LlmConfigStorage(const FlutterSecureStorage()),
      dio,
    );

    final r = await client.testLlmConnection();

    expect(r.success, isTrue);
    // 核心锚点：请求必须打到「配置的 baseUrl + /chat/completions」，而非写死端点
    expect(adapter.url, 'https://api.custom.example.com/chat/completions');
    expect(adapter.authorization, 'Bearer sk-custom-test');
    final body = jsonDecode(adapter.body!) as Map<String, dynamic>;
    expect(body['model'], 'custom-model');
    expect(body['stream'], isFalse);
  });

  test('网络不可用 → 返回「设备网络不可用」且不发请求', () async {
    _mockChannels({
      'yuesheng_api_key': 'sk-custom-test',
      'yuesheng_api_base_url': 'https://api.custom.example.com',
      'yuesheng_api_model': 'custom-model',
    }, conn: <String>[]);
    final adapter = _CapturingAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final client = LlmClient(
      LlmConfigStorage(const FlutterSecureStorage()),
      dio,
    );

    final r = await client.testLlmConnection();

    expect(r.success, isFalse);
    expect(r.message, contains('设备网络不可用'));
    expect(adapter.url, isNull, reason: '网络预检失败时不应发出请求');
  });

  test('HTTP 500 → 返回 HTTP 500', () async {
    _mockChannels({
      'yuesheng_api_key': 'sk-custom-test',
      'yuesheng_api_base_url': 'https://api.custom.example.com',
      'yuesheng_api_model': 'custom-model',
    });
    final adapter = _CapturingAdapter(status: 500);
    final dio = Dio()..httpClientAdapter = adapter;
    final client = LlmClient(
      LlmConfigStorage(const FlutterSecureStorage()),
      dio,
    );

    final r = await client.testLlmConnection();

    expect(r.success, isFalse);
    expect(r.message, contains('HTTP 500'));
  });

  test('续接：截断后自动续接成功，拼接完整内容（批次B）', () async {
    _mockChannels({
      'yuesheng_api_key': 'sk-custom-test',
      'yuesheng_api_base_url': 'https://api.custom.example.com',
      'yuesheng_api_model': 'custom-model',
    });
    final adapter = _SequenceAdapter([
      (content: '第一段', finishReason: 'length'),
      (content: '第二段', finishReason: 'stop'),
    ]);
    final dio = Dio()..httpClientAdapter = adapter;
    final client = LlmClient(
      LlmConfigStorage(const FlutterSecureStorage()),
      dio,
    );

    final r = await client.chatCompletionWithContinuation(
      const [ChatMessage(role: 'user', content: 'hi')],
    );

    expect(r.content, '第一段第二段');
    expect(r.isTruncated, isFalse);
    expect(r.finishReason, 'stop');
    expect(adapter.requestBodies, hasLength(2));
    // 第二次请求必须把已生成内容作为 assistant 上下文 + 继续提示
    final secondMessages =
        adapter.requestBodies[1]['messages'] as List<dynamic>;
    expect(secondMessages, hasLength(3));
    expect(secondMessages[1]['role'], 'assistant');
    expect(secondMessages[1]['content'], '第一段');
    expect(secondMessages[2]['role'], 'user');
    expect(
      (secondMessages[2]['content'] as String),
      contains('继续'),
    );
  });

  test('续接：连续截断达到上限 → 返回拼接内容且仍标记截断（批次B）', () async {
    _mockChannels({
      'yuesheng_api_key': 'sk-custom-test',
      'yuesheng_api_base_url': 'https://api.custom.example.com',
      'yuesheng_api_model': 'custom-model',
    });
    final adapter = _SequenceAdapter([
      (content: 'A', finishReason: 'length'),
      (content: 'B', finishReason: 'length'),
      (content: 'C', finishReason: 'length'),
    ]);
    final dio = Dio()..httpClientAdapter = adapter;
    final client = LlmClient(
      LlmConfigStorage(const FlutterSecureStorage()),
      dio,
    );

    final r = await client.chatCompletionWithContinuation(
      const [ChatMessage(role: 'user', content: 'hi')],
      maxContinuations: 2,
    );

    expect(r.content, 'ABC');
    expect(r.isTruncated, isTrue);
    expect(r.finishReason, 'length');
    expect(adapter.requestBodies, hasLength(3));
  });

  test('续接：不截断时零额外请求（批次B）', () async {
    _mockChannels({
      'yuesheng_api_key': 'sk-custom-test',
      'yuesheng_api_base_url': 'https://api.custom.example.com',
      'yuesheng_api_model': 'custom-model',
    });
    final adapter = _SequenceAdapter([
      (content: '完整内容', finishReason: 'stop'),
    ]);
    final dio = Dio()..httpClientAdapter = adapter;
    final client = LlmClient(
      LlmConfigStorage(const FlutterSecureStorage()),
      dio,
    );

    final r = await client.chatCompletionWithContinuation(
      const [ChatMessage(role: 'user', content: 'hi')],
    );

    expect(r.content, '完整内容');
    expect(r.isTruncated, isFalse);
    expect(adapter.requestBodies, hasLength(1));
  });
}
