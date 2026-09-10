// ─────────────────────────────────────────────────────────────
// AIAccountRepository — LLM 多账号（ADR-C91 批次 D-1）
//
// 元信息存 drift ai_accounts 表（v28）；api_key 存 flutter_secure_storage
// JSON map（account_id → api_key，R-029 密钥零 DB 面）。
// 账号 = 命名配置 {名称, baseUrl, model, apiKey}，全局唯一默认账号
//（应用层保证 is_default 至多一个，不依赖 DB UNIQUE）。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../database/database.dart';
import '../database/utils.dart';
import 'repository_write_guard.dart';

/// 删除最后一个账号时抛出（对齐外来 LAST_ACCOUNT 语义）
class LastAccountException implements Exception {
  @override
  String toString() => '至少保留一个账号';
}

/// LLM 多账号仓库
class AIAccountRepository {
  final AppDatabase _db;
  final FlutterSecureStorage _storage;

  /// secure storage 中的 key map 键（account_id → api_key JSON）
  static const String _kKeysMapKey = 'yuesheng_ai_account_keys';

  AIAccountRepository(this._db, [FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  // ───────────── 读 ─────────────

  /// 全部账号（按创建时间升序，首个 = 首建）
  Future<List<AiAccountRow>> listAccounts() async {
    final rows = await (_db.select(
      _db.aiAccounts,
    )..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).get();
    return rows;
  }

  /// 默认账号：is_default=1；无默认时回退首个启用账号（首建即默认）
  Future<AiAccountRow?> getDefaultAccount() async {
    final accounts = await listAccounts();
    if (accounts.isEmpty) return null;
    for (final a in accounts) {
      if (a.isDefault) return a;
    }
    return accounts.first;
  }

  /// 读取账号 api_key（secure storage map；缺失返回 null）
  Future<String?> getApiKey(String accountId) async {
    final map = await _readKeysMap();
    return map[accountId];
  }

  /// 读取账号完整配置（含 key；key 缺失返回 null —— 配置不完整）
  Future<LlmAccountConfig?> getAccountConfig(String accountId) async {
    final row = await (_db.select(
      _db.aiAccounts,
    )..where((t) => t.id.equals(accountId))).getSingleOrNull();
    if (row == null) return null;
    final key = await getApiKey(accountId);
    if (key == null || key.isEmpty) return null;
    return LlmAccountConfig(
      id: row.id,
      name: row.name,
      baseUrl: row.baseUrl,
      model: row.model,
      apiKey: key,
    );
  }

  /// 默认账号完整配置（无账号或 key 缺失返回 null）
  Future<LlmAccountConfig?> getDefaultAccountConfig() async {
    final account = await getDefaultAccount();
    if (account == null) return null;
    return getAccountConfig(account.id);
  }

  // ───────────── 写 ─────────────

  /// 新建账号。首个账号自动设为默认；[isDefault] 为 true 时清除其他默认。
  Future<AiAccountRow> createAccount({
    required String name,
    required String baseUrl,
    required String model,
    required String apiKey,
    bool isDefault = false,
  }) => guardRepoWrite('ai_account', 'createAccount', () async {
    final existing = await listAccounts();
    final id = generateUuid();
    final becomesDefault = isDefault || existing.isEmpty;
    if (becomesDefault && existing.isNotEmpty) {
      await _clearDefaultFlags();
    }
    await _writeKeysMap({...await _readKeysMap(), id: apiKey});
    await _db
        .into(_db.aiAccounts)
        .insert(
          AiAccountsCompanion.insert(
            id: id,
            name: name,
            baseUrl: baseUrl,
            model: model,
            isDefault: Value(becomesDefault),
          ),
        );
    return (_db.select(
      _db.aiAccounts,
    )..where((t) => t.id.equals(id))).getSingle();
  });

  /// 设默认（清除其他默认标记后置目标）
  Future<void> setDefault(String accountId) =>
      guardRepoWrite('ai_account', 'setDefault', () async {
        await _db.transaction(() async {
          await (_db.update(_db.aiAccounts)..where((t) => const Constant(true)))
              .write(AiAccountsCompanion(isDefault: const Value(false)));
          await (_db.update(_db.aiAccounts)
                ..where((t) => t.id.equals(accountId)))
              .write(AiAccountsCompanion(isDefault: const Value(true)));
        });
      });

  /// 更新账号元信息与（可选）api_key。key 为 null 时不动 key。
  Future<void> updateAccount({
    required String id,
    required String name,
    required String baseUrl,
    required String model,
    String? apiKey,
  }) => guardRepoWrite('ai_account', 'updateAccount', () async {
    if (apiKey != null && apiKey.isNotEmpty) {
      await _writeKeysMap({...await _readKeysMap(), id: apiKey});
    }
    await (_db.update(_db.aiAccounts)..where((t) => t.id.equals(id))).write(
      AiAccountsCompanion(
        name: Value(name),
        baseUrl: Value(baseUrl),
        model: Value(model),
      ),
    );
  });

  /// 删除账号：**至少保留一个**（最后账号拒绝删除）；默认被删 → 首个剩余接管。
  Future<void> deleteAccount(String accountId) =>
      guardRepoWrite('ai_account', 'deleteAccount', () async {
        final accounts = await listAccounts();
        if (accounts.length <= 1) throw LastAccountException();
        final target = accounts.firstWhere((a) => a.id == accountId);
        await _db.transaction(() async {
          await (_db.delete(
            _db.aiAccounts,
          )..where((t) => t.id.equals(accountId))).go();
          if (target.isDefault) {
            final rest = accounts.where((a) => a.id != accountId).toList();
            await (_db.update(_db.aiAccounts)
                  ..where((t) => t.id.equals(rest.first.id)))
                .write(AiAccountsCompanion(isDefault: const Value(true)));
          }
        });
        final map = await _readKeysMap();
        map.remove(accountId);
        await _writeKeysMap(map);
      });

  // ───────────── 内部 ─────────────

  /// 清除全部默认标记（createAccount 设默认前调用，事务外幂等）
  Future<void> _clearDefaultFlags() async {
    await (_db.update(_db.aiAccounts)..where((t) => const Constant(true)))
        .write(AiAccountsCompanion(isDefault: const Value(false)));
  }

  /// 读 key map（损坏 JSON → 空 map，R-028 容错不放大）
  Future<Map<String, String>> _readKeysMap() async {
    final raw = await _storage.read(key: _kKeysMapKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return {};
    }
  }

  /// 写 key map
  Future<void> _writeKeysMap(Map<String, String> map) async {
    await _storage.write(key: _kKeysMapKey, value: jsonEncode(map));
  }
}

/// 账号完整配置（含 key，供 LlmClient 使用）
class LlmAccountConfig {
  final String id;
  final String name;
  final String baseUrl;
  final String model;
  final String apiKey;

  const LlmAccountConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.model,
    required this.apiKey,
  });
}
