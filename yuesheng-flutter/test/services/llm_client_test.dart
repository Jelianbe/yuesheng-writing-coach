// ─────────────────────────────────────────────────────────────
// llm_client_test — LlmClient.testLlmConnection 前置守卫测试
//
// 覆盖（R-019 批次三补）：
//   1. 配置缺失 → 返回「请先填写并保存」提示（mock secure storage 空）
//   2. 网络不可用 / 成功 / HTTP / Dio 错误映射 → 需 mock connectivity + Dio
//      adapter，记台账盲区
// ─────────────────────────────────────────────────────────────

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/llm_config_storage.dart';

const _kStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // 空 secure storage：所有 read 返回 null → getLlmConfig 判空返回 null
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_kStorageChannel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_kStorageChannel, null);
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
}
