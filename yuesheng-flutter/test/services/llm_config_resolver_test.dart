// ─────────────────────────────────────────────────────────────
// llm_config_resolver_test — 多账号配置解析（ADR-C91 批次 D-1）
//
// 覆盖：默认账号优先 / 旧单键兼容回退 / 惰性迁移（幂等）/
//       无账号无旧键 → null
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/ai_account_repository.dart';
import 'package:writingcoach/services/llm_config_resolver.dart';
import 'package:writingcoach/services/llm_config_storage.dart';

const _kStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

void _mockStorage(Map<String, String> store) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_kStorageChannel, (call) async {
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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late Map<String, String> storage;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    storage = {};
    _mockStorage(storage);
  });

  tearDown(() async => db.close());

  test('无账号无旧键 → null', () async {
    final cfg = await resolveLlmConfig(db);
    expect(cfg, isNull);
  });

  test('无账号但旧三键存在 → 回退旧配置 + 惰性迁移默认账号（幂等）', () async {
    storage['yuesheng_api_key'] = 'sk-legacy';
    storage['yuesheng_api_base_url'] = 'https://legacy.example.com';
    storage['yuesheng_api_model'] = 'legacy-model';

    final cfg = await resolveLlmConfig(db);
    expect(cfg, isNotNull);
    expect(cfg!.apiKey, 'sk-legacy');
    expect(cfg.baseUrl, 'https://legacy.example.com');
    expect(cfg.model, 'legacy-model');

    // 迁移：自动建默认账号（名称=旧 model），key 已落 key map
    final accounts = AIAccountRepository(db).listAccounts();
    expect((await accounts), hasLength(1));
    expect((await accounts).first.name, 'legacy-model');
    expect((await accounts).first.isDefault, isTrue);
    expect(
      await AIAccountRepository(db).getApiKey((await accounts).first.id),
      'sk-legacy',
    );

    // 幂等：再解析不重复建账号，且优先走账号
    await resolveLlmConfig(db);
    expect(await AIAccountRepository(db).listAccounts(), hasLength(1));
  });

  test('有默认账号 → 账号配置优先（旧键存在也不回退）', () async {
    // 先播种旧键（模拟迁移前残留）
    storage['yuesheng_api_key'] = 'sk-legacy';
    storage['yuesheng_api_base_url'] = 'https://legacy.example.com';
    storage['yuesheng_api_model'] = 'legacy-model';

    final repo = AIAccountRepository(db);
    await repo.createAccount(
      name: '账号一',
      baseUrl: 'https://account.example.com',
      model: 'account-model',
      apiKey: 'sk-account',
    );

    final cfg = await resolveLlmConfig(db);
    expect(cfg!.baseUrl, 'https://account.example.com');
    expect(cfg.model, 'account-model');
    expect(cfg.apiKey, 'sk-account');
  });

  test('账号存在但默认 key 缺失 → 回退旧键（可用性不塌）', () async {
    storage['yuesheng_api_key'] = 'sk-legacy';
    storage['yuesheng_api_base_url'] = 'https://legacy.example.com';
    storage['yuesheng_api_model'] = 'legacy-model';

    // 直插无 key 账号（key map 丢失场景）
    await db
        .into(db.aiAccounts)
        .insert(
          AiAccountsCompanion.insert(
            id: 'no-key-account',
            name: '无 Key',
            baseUrl: 'https://x.example.com',
            model: 'model-x',
          ),
        );

    final cfg = await resolveLlmConfig(db);
    expect(cfg, isNotNull);
    expect(cfg!.baseUrl, 'https://legacy.example.com');
  });
}
