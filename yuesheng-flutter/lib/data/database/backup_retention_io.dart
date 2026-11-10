// ─────────────────────────────────────────────────────────────
// pre_migrate 备份保留策略 · **io 侧**（真实目录上执行淘汰）
//
// 本文件是 `dart:io` 的落点之一（另一处是 `database_io.dart`）；
// 平台无关的纯逻辑在 `backup_retention_core.dart`，门面在 `backup_retention.dart`。
//
// ★ 为什么单独一个文件（且本模块**不 import 任何项目内文件**）：
//   本模块的两个消费方分别在**数据层与服层** ——
//     · `lib/data/database/database.dart` → `_preMigrateBackup`（迁移前备份的**唯一写入方**）
//     · `lib/services/database_backup_service_io.dart` → 保留策略的**既有归属**
//   若把实现放进 service 再由 `database.dart` 反向 import，会构成
//   `database.dart ↔ database_backup_service.dart` 的**文件级环** ⇒ 门禁 3（循环依赖）直接红。
//   ⇒ 本模块**不 import 任何项目内文件**（只依赖 `dart:io` / `package:path`），
//     两侧都依赖它，图上只多两条叶子边。
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:path/path.dart' as p;

import 'backup_retention_core.dart';

export 'backup_retention_core.dart';

/// 在真实目录上执行保留策略；返回**被删除**的文件名清单。
///
/// [onError] 用于留痕：单个文件删除失败**不阻断**其余文件的清理，
/// 但**必须**被调用方记录（禁止空 catch，R-028）。
Future<List<String>> prunePreMigrateBackupSets(
  Directory dir, {
  int keepSets = kDefaultKeepPreMigrateSets,
  void Function(String name, Object error)? onError,
}) async {
  if (!await dir.exists()) return const <String>[];

  final names = <String>[];
  await for (final entity in dir.list()) {
    if (entity is File) names.add(p.basename(entity.path));
  }
  final doomed = selectPreMigrateFilesToDelete(names, keepSets: keepSets);
  final deleted = <String>[];
  for (final name in doomed) {
    try {
      await File(p.join(dir.path, name)).delete();
      deleted.add(name);
    } catch (e) {
      onError?.call(name, e);
    }
  }
  return deleted;
}
