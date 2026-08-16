// ─────────────────────────────────────────────────────────────
// 教学环境验证（live）— 真实 DeepSeek API 链路
//
// 真源：yuesheng-android 教学环境（DeepSeek 官方端点，OpenAI 兼容协议）
//   base_url = https://api.deepseek.com
//   model    = deepseek-v4-flash
//
// 运行方式（API key 只经环境变量传入，严禁写入源码）：
//   $env:DEEPSEEK_API_KEY="sk-xxx"
//   flutter test --tags live test/live_deepseek_env_test.dart
//
// 保护机制：
//   - 无 DEEPSEEK_API_KEY 时自动 markTestSkipped，不影响四闸全量跑
//   - @Tags(['live']) 标识，便于只跑真实链路
// ─────────────────────────────────────────────────────────────

@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/llm_config_storage.dart';

/// 官方 OpenAI 兼容端点（LlmClient 会拼接 /chat/completions）
const String _kBaseUrl = 'https://api.deepseek.com';

/// 用户指定的教学模型
const String _kModel = 'deepseek-v4-flash';

/// connectivity_plus 平台通道（checkNetwork 依赖）
const MethodChannel _kConnectivityChannel = MethodChannel(
  'dev.fluttercommunity.plus/connectivity',
);

/// flutter_secure_storage 平台通道（chatCompletion/streamChat 内部读配置）
const MethodChannel _kSecureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  LlmConfigValues? cfg;
  final bool hasKey = Platform.environment.containsKey('DEEPSEEK_API_KEY');

  setUpAll(() {
    // flutter_test binding 会把 HttpClient 全局替换为“永远返回 400”的 mock，
    // 必须恢复真实网络才能打真实链路。
    HttpOverrides.global = null;

    final key = Platform.environment['DEEPSEEK_API_KEY'];
    if (key != null && key.isNotEmpty) {
      cfg = LlmConfigValues(apiKey: key, baseUrl: _kBaseUrl, model: _kModel);
    }
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // 测试环境无宿主平台：mock connectivity，让 checkNetwork 返回“已联网”
    messenger.setMockMethodCallHandler(_kConnectivityChannel, (call) async {
      if (call.method == 'check') return <String>['wifi'];
      return null;
    });
    // chatCompletion / streamChat 从 secure storage 读配置，mock 其读写
    final storageValues = <String, String>{
      if (key != null && key.isNotEmpty) 'yuesheng_api_key': key,
      'yuesheng_api_base_url': _kBaseUrl,
      'yuesheng_api_model': _kModel,
    };
    messenger.setMockMethodCallHandler(_kSecureStorageChannel, (call) async {
      final args = (call.arguments as Map?) ?? const {};
      switch (call.method) {
        case 'read':
          return storageValues[args['key']];
        case 'write':
          storageValues[args['key'] as String] = args['value'] as String;
          return true;
        case 'delete':
          storageValues.remove(args['key']);
          return true;
      }
      return null;
    });
  });

  tearDownAll(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_kConnectivityChannel, null);
    messenger.setMockMethodCallHandler(_kSecureStorageChannel, null);
  });

  test(
    'testLlmConnection 非流式连通（5 token / 15s 超时）',
    () async {
      if (!hasKey) {
        markTestSkipped('未设置 DEEPSEEK_API_KEY，跳过真实链路');
        return;
      }
      final client = LlmClient();
      final r = await client.testLlmConnection(config: cfg);
      expect(r.success, isTrue, reason: '连接失败: ${r.message}');
      expect(r.latencyMs, isNotNull);
      // ignore: avoid_print
      print('[testLlmConnection] ${r.message}');
    },
    timeout: const Timeout(Duration(seconds: 40)),
  );

  test(
    'chatCompletion 非流式对话（温度 0.3 / 4096 token）',
    () async {
      if (!hasKey) {
        markTestSkipped('未设置 DEEPSEEK_API_KEY，跳过真实链路');
        return;
      }
      final client = LlmClient();
      final content = await client.chatCompletion([
        const ChatMessage(role: 'user', content: '请只回复四个字：链路通畅'),
      ]);
      expect(content, isNotEmpty);
      // ignore: avoid_print
      print('[chatCompletion] ${content.trim()}');
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  test(
    'streamChat 流式 SSE（温度 0.7，逐帧回调 + [DONE]）',
    () async {
      if (!hasKey) {
        markTestSkipped('未设置 DEEPSEEK_API_KEY，跳过真实链路');
        return;
      }
      final client = LlmClient();
      final sb = StringBuffer();
      var frameCount = 0;
      var done = false;
      await client.streamChat(
        [const ChatMessage(role: 'user', content: '请用一句话介绍你自己')],
        (r) {
          if (r.isDone) {
            done = true;
          } else if (r.content.isNotEmpty) {
            frameCount++;
            sb.write(r.content);
          }
        },
      );
      expect(done, isTrue, reason: '流式响应未收到 [DONE]');
      expect(frameCount, greaterThan(0), reason: '未收到任何增量帧');
      expect(sb.toString(), isNotEmpty);
      // ignore: avoid_print
      print('[streamChat] 帧数=$frameCount 内容=${sb.toString().trim()}');
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
