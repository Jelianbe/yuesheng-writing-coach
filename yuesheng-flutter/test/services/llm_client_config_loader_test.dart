// ─────────────────────────────────────────────────────────────
// llm_client_config_loader_test — LlmClient configLoader 路由（ADR-C91 批次 D-1）
//
// 覆盖：configLoader 提供配置 → 三入口走 loader 配置；
//       configLoader 返回 null → 回退旧单键存储（测试零破坏基线）
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

void _mockChannels(
  Map<String, String> store, {
  List<String> conn = const ['wifi'],
}) {
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

class _CapturingAdapter implements HttpClientAdapter {
  String? url;
  String? authorization;
  String? body;

  _CapturingAdapter();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    url = options.uri.toString();
    authorization = (options.headers['Authorization'] ?? '').toString();
    if (options.data is String) body = options.data as String;
    final stream =
        options.data is String &&
            (jsonDecode(options.data as String) as Map)['stream'] == true
        ? _sseBody()
        : Stream.value(
            Uint8List.fromList(
              utf8.encode(
                jsonEncode({
                  'choices': [
                    {
                      'message': {
                        'role': 'assistant',
                        'content': 'loader 模型回复',
                      },
                      'finish_reason': 'stop',
                    },
                  ],
                }),
              ),
            ),
          );
    return ResponseBody(
      stream,
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  Stream<Uint8List> _sseBody() async* {
    yield Uint8List.fromList(
      utf8.encode(
        'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': 'loader 流式块'},
            },
          ],
        })}\n\n',
      ),
    );
    yield Uint8List.fromList(utf8.encode('data: [DONE]\n\n'));
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_kStorageChannel, null);
    messenger.setMockMethodCallHandler(_kConnChannel, null);
  });

  group('configLoader 提供配置 → 三入口走 loader（多账号路由）', () {
    test('chatCompletionWithMeta：请求 URL/Bearer/model 用 loader 配置', () async {
      _mockChannels({}); // 旧键空，证明不依赖旧存储
      final adapter = _CapturingAdapter();
      final client = LlmClient(
        LlmConfigStorage(const FlutterSecureStorage()),
        Dio()..httpClientAdapter = adapter,
        () async => const LlmConfigValues(
          apiKey: 'sk-loader',
          baseUrl: 'https://loader.example.com',
          model: 'loader-model',
        ),
      );

      final r = await client.chatCompletionWithMeta([
        ChatMessage(role: 'user', content: 'hi'),
      ]);

      expect(r.content, 'loader 模型回复');
      expect(
        adapter.url,
        'https://loader.example.com/chat/completions',
        reason: '多账号下必须打到 loader 提供的 baseUrl',
      );
      expect(adapter.authorization, 'Bearer sk-loader');
      final body = jsonDecode(adapter.body!) as Map<String, dynamic>;
      expect(body['model'], 'loader-model');
    });

    test('streamChat：分块内容走 loader 配置', () async {
      _mockChannels({});
      final adapter = _CapturingAdapter();
      final client = LlmClient(
        LlmConfigStorage(const FlutterSecureStorage()),
        Dio()..httpClientAdapter = adapter,
        () async => const LlmConfigValues(
          apiKey: 'sk-loader',
          baseUrl: 'https://loader.example.com',
          model: 'loader-model',
        ),
      );

      final chunks = <String>[];
      await client.streamChat([ChatMessage(role: 'user', content: 'hi')], (
        resp,
      ) {
        if (resp.content.isNotEmpty) chunks.add(resp.content);
      });

      expect(chunks, contains('loader 流式块'));
      expect(adapter.authorization, 'Bearer sk-loader');
    });

    test('testLlmConnection：用 loader 配置发起连通性测试', () async {
      _mockChannels({});
      final adapter = _CapturingAdapter();
      final client = LlmClient(
        LlmConfigStorage(const FlutterSecureStorage()),
        Dio()..httpClientAdapter = adapter,
        () async => const LlmConfigValues(
          apiKey: 'sk-loader',
          baseUrl: 'https://loader.example.com',
          model: 'loader-model',
        ),
      );

      final r = await client.testLlmConnection();

      expect(r.success, isTrue);
      expect(adapter.url, 'https://loader.example.com/chat/completions');
      expect(adapter.authorization, 'Bearer sk-loader');
    });
  });

  group('configLoader 返回 null → 无配置（免费模式）', () {
    test('chatCompletionWithMeta：loader null 时不再回退（回退是 resolver 职责）', () async {
      _mockChannels({
        'yuesheng_api_key': 'sk-legacy',
        'yuesheng_api_base_url': 'https://legacy.example.com',
        'yuesheng_api_model': 'legacy-model',
      });
      final adapter = _CapturingAdapter();
      final client = LlmClient(
        LlmConfigStorage(const FlutterSecureStorage()),
        Dio()..httpClientAdapter = adapter,
        () async => null, // 多账号路径：loader 是唯一配置源，null = 无配置
      );

      final r = await client.chatCompletionWithMeta([
        ChatMessage(role: 'user', content: 'hi'),
      ]);

      // 免费测试模式教学文案，不发请求
      expect(r.content, contains('免费测试模式'));
      expect(adapter.url, isNull, reason: '无配置时不应发出真实请求');
    });

    test('configLoader 未传（参数 null）→ 回退旧单键（批次 A 基线零破坏）', () async {
      _mockChannels({
        'yuesheng_api_key': 'sk-legacy',
        'yuesheng_api_base_url': 'https://legacy.example.com',
        'yuesheng_api_model': 'legacy-model',
      });
      final adapter = _CapturingAdapter();
      final client = LlmClient(
        LlmConfigStorage(const FlutterSecureStorage()),
        Dio()..httpClientAdapter = adapter,
      );

      final r = await client.chatCompletionWithMeta([
        ChatMessage(role: 'user', content: 'hi'),
      ]);

      expect(adapter.url, 'https://legacy.example.com/chat/completions');
      expect(adapter.authorization, 'Bearer sk-legacy');
      final body = jsonDecode(adapter.body!) as Map<String, dynamic>;
      expect(body['model'], 'legacy-model');
      expect(r.content, isNotEmpty);
    });
  });
}
