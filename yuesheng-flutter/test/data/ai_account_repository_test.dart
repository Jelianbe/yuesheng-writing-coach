// ─────────────────────────────────────────────────────────────
// ai_account_repository_test — AIAccountRepository 单测（ADR-C91 批次 D-1）
//
// 覆盖：首建默认 / 设默认唯一 / key map 读写 / 更新 / 删除守卫 /
//       默认被删接管 / 损坏 key map 容错 / 配置组装
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/ai_account_repository.dart';

const _kStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// secure storage 里 key map 的键名（与 AIAccountRepository 内部常量一致；
/// 该常量为private，此处按契约字面量对齐 —— 改仓储侧命名时本测试会红，属预期）。
const _kKeysMapKey = 'yuesheng_ai_account_keys';

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

  // ─────────────────────────────────────────────────────────────
  // 以下三组由变异测试（2026-10-04 B5 批）驱动补写。
  // 探测结论：10 个变异里这4 个**零红** ⇒ 修复前无任何用例能区分。
  //   M4 updateAccount 把`apiKey.isNotEmpty`判据去掉 → 零红
  //   M5 getDefaultAccount 回退取 accounts.last → 零红
  //   M8 getDefaultAccount 回退改成 return null  → 零红
  //   M9 getAccountConfig 只判 null 不判 isEmpty  → 零红
  // M5/M8 同一条「无 is_default 回退」分支；M9 与 M4 同一类「空串 vs null」判据。
  // ─────────────────────────────────────────────────────────────

  group('空串 apiKey 与 null 的区分（M4/M9的判据盲区）', () {
    // 插入时走 DB 直插：createAccount 不会写空串 key（无此分支），
    // 而 setDefault 可把is_default 清掉 ⇒ 便于同时构造回退场景。
    Future<String> insertOrphan({
      required String id,
      required String name,
      String key = '',
      int createdAt = 1767225600, // 2026-01-01T00:00:00Z 固定值，可比较先后
    }) async {
      await db
          .into(db.aiAccounts)
          .insert(
            AiAccountsCompanion.insert(
              id: id,
              name: name,
              baseUrl: 'https://$id.example.com',
              model: 'model-$id',
              isDefault: const Value(false),
              // ★ createdAt 是 int（unixepoch 秒），不是 DateTime
              createdAt: Value(createdAt),
            ),
          );
      storage[_kKeysMapKey] = jsonEncode({id: key});
      return id;
    }

    test('updateAccount 传空串 key → 保留原 key（不是清空）', () async {
      final acc = await repo.createAccount(
        name: 'A',
        baseUrl: 'https://a.example.com',
        model: 'model-a',
        apiKey: 'sk-original',
      );
      // ★ 传 '' 而非 null：实现的判据是 `apiKey != null && apiKey.isNotEmpty`，
      //   空串必须被当作「没传」⇒ 原key 保留。
      await repo.updateAccount(
        id: acc.id,
        name: '改名',
        baseUrl: 'https://a.example.com',
        model: 'model-a',
        apiKey: '',
      );
      expect(
        await repo.getApiKey(acc.id),
        'sk-original',
        reason: '空串 key 不该覆盖原key（否则用户误清一次就永久失去配置）',
      );
      // 元信息仍应更新（空串只影响 key，不影响其他字段）
      expect((await repo.getAccountConfig(acc.id))!.name, '改名');
    });

    test('getAccountConfig：key 为空串 → 视为配置不完整返回 null', () async {
      final id = await insertOrphan(id: 'emptykey', name: '空串key');
      // ★ 空串不是有效 key：getAccountConfig 必须判 isEmpty 才返回 null。
      //   只判 null 会让「配置不完整」的账号被当成可用 ⇒ B3 切模型会选到它。
      expect(await repo.getApiKey(id), '');
      expect(await repo.getAccountConfig(id), isNull);
    });
  });

  group('getDefaultAccount 无 is_default 时的回退分支（M5/M8的盲区）', () {
    test('全部账号 is_default=0 → 回退**首个**（非末个）', () async {
      // 直插三行、全is_default=0、createdAt 递增 ⇒ 「首个」有确定值。
      // ★ 这是变异 M5（first→last）的唯一判据点；也覆盖 M8（回退改 null）。
      for (var i = 1; i <= 3; i++) {
        await db
            .into(db.aiAccounts)
            .insert(
              AiAccountsCompanion.insert(
                id: 'acct$i',
                name: '账号$i',
                baseUrl: 'https://acct$i.example.com',
                model: 'm$i',
                isDefault: const Value(false),
                createdAt: Value(1767225600 + i), // 递增
              ),
            );
      }
      final def = await repo.getDefaultAccount();
      expect(def, isNotNull, reason: '无 is_default 时必须回退，不得返回 null');
      expect(def!.id, 'acct1', reason: '回退应取创建时间最小的首个，不是末个');
    });

    test('首个 is_default=0、次个 is_default=1 → 取后者（is_default 优先于顺序）', () async {
      // 正对照：证明上一例不是「总是取 acct1」，而是「按 is_default 优先、否则按创建序」。
      await db
          .into(db.aiAccounts)
          .insert(
            AiAccountsCompanion.insert(
              id: 'first-no-default',
              name: 'A',
              baseUrl: 'https://a.example.com',
              model: 'ma',
              isDefault: const Value(false),
              createdAt: const Value(1767225601),
            ),
          );
      await db
          .into(db.aiAccounts)
          .insert(
            AiAccountsCompanion.insert(
              id: 'second-is-default',
              name: 'B',
              baseUrl: 'https://b.example.com',
              model: 'mb',
              isDefault: const Value(true),
              createdAt: const Value(1767225602),
            ),
          );
      expect((await repo.getDefaultAccount())!.id, 'second-is-default');
    });
  });
}
