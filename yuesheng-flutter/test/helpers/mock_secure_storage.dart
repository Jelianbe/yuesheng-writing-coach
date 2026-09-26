// ─────────────────────────────────────────────────────────────
// mock_secure_storage — 测试共享的 flutter_secure_storage 通道替身
//
// 为什么必须存在：`testWidgets`（fakeAsync）环境下**未 mock 的
// flutter_secure_storage 平台通道调用会永久挂起**（.timeout 计时器也不推进）。
// 同源事故见 test/helpers/mock_last_session_storage.dart（批次 50）与
// 批次 1f4abb61（C2 引导接进发送入口后，24 例既有测试全部卡死在入口）。
//
// ⇒ 任何**会走到 LlmConfigStorage（读 API 配置）**的测试都必须先 install()。
//    已通过 `api_config_hint_seen=true` 短路的测试无需用本替身，但短路点一旦
//    被改动就会挂起，故两类测试都要留一条「曾拦截到真实通道」的正对照。
//
// 记录 reads 是为了提供**短路判据**：`reads.isEmpty` 可证明调用方在
// 触碰配置之前就已返回（见 api_config_nudge_test.dart #4）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// flutter_secure_storage 使用的平台通道名（多版本一致）
const MethodChannel kSecureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// API 配置三字段（键名与 lib/services/llm_config_storage.dart 一致）
const String kApiKeyPref = 'yuesheng_api_key';
const String kApiBaseUrlPref = 'yuesheng_api_base_url';
const String kApiModelPref = 'yuesheng_api_model';

/// 以内存 Map 替换 secure_storage 平台通道，并记录 read 调用。
class MockSecureStorage {
  final Map<String, String> store;

  /// 发生过的 read key 序列（短路判据用）
  final List<String> reads = [];

  MockSecureStorage([Map<String, String>? initial]) : store = initial ?? {};

  /// 预置「已配置」三字段，使 LlmConfigStorage.getLlmConfig() 非 null
  void seedConfigured({
    String apiKey = 'sk-test',
    String baseUrl = 'https://api.example.com',
    String model = 'test-model',
  }) {
    store
      ..[kApiKeyPref] = apiKey
      ..[kApiBaseUrlPref] = baseUrl
      ..[kApiModelPref] = model;
  }

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kSecureStorageChannel, (call) async {
          final key = (call.arguments as Map?)?['key'] as String?;
          switch (call.method) {
            case 'read':
              if (key != null) reads.add(key);
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
            default:
              return null;
          }
        });
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kSecureStorageChannel, null);
  }
}
