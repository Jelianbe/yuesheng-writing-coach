// ─────────────────────────────────────────────────────────────
// live_usage_monitor_test — M 批：真实链路用量读数
//
// 定位：把 M 批的「尺子」**插到真实 DeepSeek 链路上**，产出第一份
// 真实 token 读数（此前全仓只有字符估算）。同一份 messages 连发两次，
// 第二次用于观察**自动上下文缓存**是否命中 —— 这是注入精细化专项
// 「省了多少」的直接证据来源。
//
// 运行方式（key 只经环境变量传入，严禁写入源码）：
//   $env:DEEPSEEK_API_KEY="sk-xxx"
//   flutter test --tags live test/live_usage_monitor_test.dart
//
// 无 DEEPSEEK_API_KEY 时自动 markTestSkipped，不影响全量跑。
// ─────────────────────────────────────────────────────────────

@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/llm_concurrency_gate.dart';
import 'package:writingcoach/services/llm_config_storage.dart';
import 'package:writingcoach/services/llm_usage_monitor.dart';

/// 官方 OpenAI 兼容端点（LlmClient 会拼接 /chat/completions）
const String _kBaseUrl = 'https://api.deepseek.com';

/// 与既有 live 套件一致的模型名
const String _kModel = 'deepseek-v4-flash';

const MethodChannel _kConnectivityChannel = MethodChannel(
  'dev.fluttercommunity.plus/connectivity',
);

/// flutter_secure_storage 平台通道（端点准备链路会读配置）
const MethodChannel _kSecureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// 模拟教学链路的长 system prompt（约 2,000 字符）：
/// 用于让「前缀缓存」有可能生效 —— 单次短 prompt 测不出缓存收益。
String _buildLongSystem() {
  final sb = StringBuffer('# SKILL: 用量观测探针\n\n');
  for (var i = 0; i < 40; i++) {
    sb.write(
      '第 ${i + 1} 条教学纪律：先判断学员所处环节，再决定回应方式。'
      '不替学员写句子、不替学员做决定，一次只抛一个可执行的点。\n',
    );
  }
  return sb.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final bool hasKey = Platform.environment.containsKey('DEEPSEEK_API_KEY');

  setUpAll(() {
    // flutter_test binding 会把 HttpClient 全局替换为「永远返回 400」的 mock，
    // 必须恢复真实网络才能打真实链路。
    HttpOverrides.global = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_kConnectivityChannel, (call) async {
      if (call.method == 'check') return <String>['wifi'];
      return null;
    });
    // 端点准备链路会经 secure storage 读配置（无宿主平台时抛
    // MissingPluginException），与 live_deepseek_env_test 一致地 mock 掉。
    final storage = <String, String>{
      'yuesheng_api_key': Platform.environment['DEEPSEEK_API_KEY'] ?? '',
      'yuesheng_api_base_url': _kBaseUrl,
      'yuesheng_api_model': _kModel,
    };
    messenger.setMockMethodCallHandler(_kSecureStorageChannel, (call) async {
      final args = (call.arguments as Map?) ?? const {};
      switch (call.method) {
        case 'read':
          return storage[args['key']];
        case 'write':
          storage[args['key'] as String] = args['value'] as String;
          return true;
        case 'delete':
          storage.remove(args['key']);
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

  test('真实链路用量读数（流式 + 非流式 + 缓存命中观察）', () async {
    if (!hasKey) {
      markTestSkipped('未设置 DEEPSEEK_API_KEY，跳过真实链路');
      return;
    }
    final key = Platform.environment['DEEPSEEK_API_KEY']!;
    final cfg = LlmConfigValues(
      apiKey: key,
      baseUrl: _kBaseUrl,
      model: _kModel,
    );
    final monitor = LlmUsageMonitor();
    final client = LlmClient(
      null,
      null,
      () async => cfg,
      null,
      LlmConcurrencyGate(),
      monitor.sink,
    );

    final messages = [
      ChatMessage(role: 'system', content: _buildLongSystem()),
      const ChatMessage(role: 'user', content: '只回复两个字：收到'),
    ];

    // ① 首次调用（预期缓存未命中）
    await client.chatCompletionWithMeta(messages);
    final afterFirst = monitor.totals;

    // ② 同前缀再调一次（观察自动上下文缓存是否命中）
    await client.streamChat(messages, (_) {});
    final afterSecond = monitor.totals;

    // ignore: avoid_print
    print('[M 批 真实读数] 第 1 次（非流式）: $afterFirst');
    // ignore: avoid_print
    print('[M 批 真实读数] 两次累计（第 2 次为流式）: $afterSecond');

    expect(afterSecond.calls, 2, reason: '两次调用都应被采集');
    expect(afterSecond.promptTokens, greaterThan(0), reason: '应读到真实输入 token');
    expect(
      afterSecond.completionTokens,
      greaterThan(0),
      reason: '应读到真实输出 token',
    );
    expect(
      afterSecond.hitRate,
      inInclusiveRange(0.0, 1.0),
      reason: '命中率须落在合法区间（尺子不得给出越界读数）',
    );
    expect(
      afterSecond.cachedTokens,
      greaterThanOrEqualTo(0),
      reason: '缓存读数不得为负',
    );
  }, timeout: const Timeout(Duration(seconds: 180)));
}
