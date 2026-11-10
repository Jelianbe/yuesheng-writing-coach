// ─────────────────────────────────────────────────────────────
// pre_migrate 备份保留策略 · **web 侧**（浏览器无文件系统 ⇒ 永不执行）
//
// 平台门面见 `backup_retention.dart`。
//
// web 侧语义：
//   · 纯函数（按套淘汰清单）来自 `backup_retention_core.dart`，**逻辑与 io 侧同源**
//     （不复制、不分叉）；
//   · 「在真实目录上执行淘汰」在浏览器**没有对应物**（无文件系统）⇒ 抛
//     `UnsupportedError`（**不静默返回空**：返回空会让调用方以为「清理过、没东西可删」，
//     把「平台不支持」伪装成「已清理」）。
//   · 实际路径上本函数**永不被调用**：迁移前备份在 web 侧整体短路
//     （见 `database_web.dart` 的 `preMigrateBackupDisabled()`）。
// ─────────────────────────────────────────────────────────────

import 'backup_retention_core.dart';

export 'backup_retention_core.dart';

/// web 侧无文件系统 ⇒ 不支持在真实目录上执行保留策略。
Future<List<String>> prunePreMigrateBackupSets(
  Object dir, {
  int keepSets = kDefaultKeepPreMigrateSets,
  void Function(String name, Object error)? onError,
}) async {
  throw UnsupportedError('web 平台无文件系统：pre_migrate 备份保留策略不可执行');
}
