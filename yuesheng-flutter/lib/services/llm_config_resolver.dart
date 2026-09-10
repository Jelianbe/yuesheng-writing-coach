// ─────────────────────────────────────────────────────────────
// LLM 配置解析器（ADR-C91 批次 D-1 多账号）
//
// 生产组装注入 LlmClient.configLoader：
//   默认账号优先 → 无可用账号配置时回退旧单键（兼容未迁移），
//   旧键存在且无账号 → 惰性迁移为「默认」账号（幂等，迁移失败不阻断）。
// 迁移失败回退旧配置继续可用（回退安全，旧三键保留不删）。
// ─────────────────────────────────────────────────────────────

import '../data/database/database.dart';
import '../data/repositories/ai_account_repository.dart';
import 'llm_config_storage.dart';

/// 解析当前 LLM 配置（多账号优先，旧单键兼容）。
///
/// [legacyStorage] 可注入（测试）；null 时用真实 secure storage。
Future<LlmConfigValues?> resolveLlmConfig(
  AppDatabase db, {
  LlmConfigStorage? legacyStorage,
}) async {
  final storage = legacyStorage ?? LlmConfigStorage();
  final repo = AIAccountRepository(db);

  // 1. 默认账号优先（含 key 完整才可用）
  final account = await repo.getDefaultAccountConfig();
  if (account != null) {
    return LlmConfigValues(
      apiKey: account.apiKey,
      baseUrl: account.baseUrl,
      model: account.model,
    );
  }

  // 2. 回退旧单键；若旧键存在且尚无账号 → 幂等迁移为默认账号
  final legacy = await storage.getLlmConfig();
  if (legacy == null) return null;
  final accounts = await repo.listAccounts();
  if (accounts.isEmpty) {
    try {
      await repo.createAccount(
        name: legacy.model,
        baseUrl: legacy.baseUrl,
        model: legacy.model,
        apiKey: legacy.apiKey,
        isDefault: true,
      );
    } catch (_) {
      // 迁移失败不阻断：本轮回退旧配置继续可用
    }
  }
  return legacy;
}
