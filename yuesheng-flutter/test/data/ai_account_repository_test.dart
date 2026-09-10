// ─────────────────────────────────────────────────────────────
// ai_account_repository_test — AIAccountRepository 单测（ADR-C91 批次 D-1）
//
// 覆盖：首建默认 / 设默认唯一 / key map 读写 / 更新 / 删除守卫 /
//       默认被删接管 / 损坏 key map 容错 / 配置组装
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/ai_account_repository.dart';

const _kStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// 以内存 map 替换 secure_storage platform channel
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
  late AIAccountRepository repo;
  late Map<String, String> storage;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = AIAccountRepository(db);
    storage = {};
    _mockStorage(storage);
  });

  tearDown(() async => db.close());

  group('createAccount', () {
    test('空库首建 → 自动默认 + key 写入 secure storage', () async {
      final acc = await repo.createAccount(
        name: '默认',
        baseUrl: 'https://api.deepseek.com',
        model: 'deepseek-v4-flash',
        apiKey: 'sk-test-1',
      );
      expect(acc.isDefault, isTrue);
      expect(await repo.getDefaultAccount(), isNotNull);
      expect((await repo.getDefaultAccount())!.id, acc.id);
      expect(await repo.getApiKey(acc.id), 'sk-test-1');
    });

    test('第二个账号不抢占默认', () async {
      final first = await repo.createAccount(
        name: 'A',
        baseUrl: 'https://a.example.com',
        model: 'model-a',
        apiKey: 'sk-a',
      );
      final second = await repo.createAccount(
        name: 'B',
        baseUrl: 'https://b.example.com',
        model: 'model-b',
        apiKey: 'sk-b',
      );
      expect(first.isDefault, isTrue);
      expect(second.isDefault, isFalse);
      expect((await repo.getDefaultAccount())!.id, first.id);
      // key 各自独立
      expect(await repo.getApiKey(second.id), 'sk-b');
    });

    test('isDefault=true 时清除其他默认（全局唯一）', () async {
      await repo.createAccount(
        name: 'A',
        baseUrl: 'https://a.example.com',
        model: 'model-a',
        apiKey: 'sk-a',
      );
      final b = await repo.createAccount(
        name: 'B',
        baseUrl: 'https://b.example.com',
        model: 'model-b',
        apiKey: 'sk-b',
        isDefault: true,
      );
      final accounts = await repo.listAccounts();
      expect(accounts.where((a) => a.isDefault).length, 1);
      expect((await repo.getDefaultAccount())!.id, b.id);
    });
  });

  group('setDefault', () {
    test('切换默认 → 全局唯一', () async {
      final a = await repo.createAccount(
        name: 'A',
        baseUrl: 'https://a.example.com',
        model: 'model-a',
        apiKey: 'sk-a',
      );
      final b = await repo.createAccount(
        name: 'B',
        baseUrl: 'https://b.example.com',
        model: 'model-b',
        apiKey: 'sk-b',
      );
      await repo.setDefault(b.id);
      final accounts = await repo.listAccounts();
      expect(accounts.where((x) => x.isDefault).length, 1);
      expect((await repo.getDefaultAccount())!.id, b.id);
      // DB 为准重查（非旧对象快照）
      expect(accounts.firstWhere((x) => x.id == a.id).isDefault, isFalse);
    });
  });

  group('getAccountConfig / getDefaultAccountConfig', () {
    test('key 存在 → 返回完整配置', () async {
      final acc = await repo.createAccount(
        name: '默认',
        baseUrl: 'https://api.deepseek.com',
        model: 'deepseek-v4-flash',
        apiKey: 'sk-test-1',
      );
      final cfg = await repo.getAccountConfig(acc.id);
      expect(cfg, isNotNull);
      expect(cfg!.baseUrl, 'https://api.deepseek.com');
      expect(cfg.model, 'deepseek-v4-flash');
      expect(cfg.apiKey, 'sk-test-1');

      final def = await repo.getDefaultAccountConfig();
      expect(def!.id, acc.id);
    });

    test('key 缺失 → 返回 null（配置不完整）', () async {
      // 直接插行（无 key）模拟 key map 丢失
      final id = 'orphan-account';
      await db
          .into(db.aiAccounts)
          .insert(
            AiAccountsCompanion.insert(
              id: id,
              name: '无 Key',
              baseUrl: 'https://x.example.com',
              model: 'model-x',
            ),
          );
      expect(await repo.getAccountConfig(id), isNull);
      expect(await repo.getDefaultAccountConfig(), isNull);
    });
  });

  group('updateAccount', () {
    test('更新元信息 + key（key 传值时覆盖）', () async {
      final acc = await repo.createAccount(
        name: '旧名',
        baseUrl: 'https://old.example.com',
        model: 'old-model',
        apiKey: 'sk-old',
      );
      await repo.updateAccount(
        id: acc.id,
        name: '新名',
        baseUrl: 'https://new.example.com',
        model: 'new-model',
        apiKey: 'sk-new',
      );
      final cfg = await repo.getAccountConfig(acc.id);
      expect(cfg!.name, '新名');
      expect(cfg.baseUrl, 'https://new.example.com');
      expect(cfg.model, 'new-model');
      expect(cfg.apiKey, 'sk-new');
    });

    test('apiKey 为 null → 不动 key', () async {
      final acc = await repo.createAccount(
        name: 'A',
        baseUrl: 'https://a.example.com',
        model: 'model-a',
        apiKey: 'sk-a',
      );
      await repo.updateAccount(
        id: acc.id,
        name: '改名',
        baseUrl: 'https://a.example.com',
        model: 'model-a',
      );
      expect(await repo.getApiKey(acc.id), 'sk-a');
    });
  });

  group('deleteAccount', () {
    test('删除最后一个 → LastAccountException', () async {
      final acc = await repo.createAccount(
        name: '唯一',
        baseUrl: 'https://a.example.com',
        model: 'model-a',
        apiKey: 'sk-a',
      );
      expect(
        () => repo.deleteAccount(acc.id),
        throwsA(isA<LastAccountException>()),
      );
      expect(await repo.listAccounts(), hasLength(1));
    });

    test('删除默认 → 首个剩余接管默认 + key 移除', () async {
      final a = await repo.createAccount(
        name: 'A',
        baseUrl: 'https://a.example.com',
        model: 'model-a',
        apiKey: 'sk-a',
      );
      final b = await repo.createAccount(
        name: 'B',
        baseUrl: 'https://b.example.com',
        model: 'model-b',
        apiKey: 'sk-b',
      );
      await repo.deleteAccount(a.id);
      final accounts = await repo.listAccounts();
      expect(accounts, hasLength(1));
      expect(accounts.first.id, b.id);
      expect(accounts.first.isDefault, isTrue);
      expect(await repo.getApiKey(a.id), isNull);
    });

    test('删除非默认 → 默认不变', () async {
      final a = await repo.createAccount(
        name: 'A',
        baseUrl: 'https://a.example.com',
        model: 'model-a',
        apiKey: 'sk-a',
      );
      final b = await repo.createAccount(
        name: 'B',
        baseUrl: 'https://b.example.com',
        model: 'model-b',
        apiKey: 'sk-b',
      );
      await repo.deleteAccount(b.id);
      expect((await repo.getDefaultAccount())!.id, a.id);
      expect(await repo.getApiKey(b.id), isNull);
    });
  });

  group('损坏 key map 容错（R-028）', () {
    test('非 JSON 内容 → 读回空 map，createAccount 不炸', () async {
      storage['yuesheng_ai_account_keys'] = '{{{not-json';
      final acc = await repo.createAccount(
        name: 'A',
        baseUrl: 'https://a.example.com',
        model: 'model-a',
        apiKey: 'sk-a',
      );
      expect(await repo.getApiKey(acc.id), 'sk-a');
    });
  });
}
