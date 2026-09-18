// ─────────────────────────────────────────────────────────────
// pre_migrate 备份保留策略（**共享叶子模块**）
//
// 为什么单独一个文件：
//   本模块的两个消费方分别在**数据层与服层** ——
//     · `lib/data/database/database.dart` → `_preMigrateBackup`（迁移前备份的**唯一写入方**）
//     · `lib/services/database_backup_service.dart` → 保留策略的**既有归属**
//   若把实现放进 service 再由 `database.dart` 反向 import，会构成
//   `database.dart ↔ database_backup_service.dart` 的**文件级环** ⇒ 门禁 3（循环依赖）直接红。
//   ⇒ 本模块**不 import 任何项目内文件**（只依赖 `dart:io` / `package:path`），
//     两侧都依赖它，图上只多两条叶子边。
//
// 落盘形态（**不是** `.db` 单文件，是三件套）：
//   backup_<stamp>_pre_migrate_v<from>            ← 主库副本
//   backup_<stamp>_pre_migrate_v<from>-wal        ← WAL 副本
//   backup_<stamp>_pre_migrate_v<from>-shm        ← SHM 副本
//   ⇒ 「一套」= 同一次迁移前的这三件。
//
// ★ 为什么不能沿用按 `.db` 计数的旧清理：
//   `DatabaseBackupService.cleanupOldBackups` 过滤 `endsWith('.db')`，
//   而 pre_migrate 的文件名**没有 `.db` 扩展名**（后缀是 `-wal` / `-shm` 或什么都没有）
//   ⇒ 对它是**空操作**（一条都匹配不到）。这正是「备份目录无上限增长」的直接成因。
//   ⇒ 本模块按**前缀成套**归组，整**套**淘汰，**绝不删半套**（半套 = 不可用备份）。
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:path/path.dart' as p;

/// 默认保留套数（与既有 `DatabaseBackupService.defaultKeepCount = 10` 对齐）。
const int kDefaultKeepPreMigrateSets = 10;

/// 命名约定的唯一判据：`backup_<stamp>_pre_migrate_v<from>` 后可跟 `-wal` / `-shm`。
final RegExp _kPreMigrateName = RegExp(
  r'^backup_(\d+)_pre_migrate_v(\d+)(?:-(wal|shm))?$',
);

/// 尾缀（用于把三件套映射回同一个「套标识」）。
final RegExp _kSidecarSuffix = RegExp(r'-(?:wal|shm)$');

/// 纯函数：从文件名清单推出**应当删除**的文件名清单（升序）。
///
/// 判据：
/// 1. 按「套」归组（同一次迁移的三件套 = 同前缀）；
/// 2. 套按 stamp **降序**（新在前），保留最新 [keepSets] 套；
/// 3. 其余整**套**淘汰（绝不删半套）；
/// 4. ★ **不符合命名约定的文件一律不删** —— 不认识的东西不销毁（R1′ 精神）。
///    代价：无法识别的历史残留不会被清掉；这是有意换取「绝不误删」。
/// 5. [keepSets] 下限钳到 **1**：保留策略**不允许把备份清空**（传 0 不表示「全删」）。
List<String> selectPreMigrateFilesToDelete(
  List<String> fileNames, {
  int keepSets = kDefaultKeepPreMigrateSets,
}) {
  final effectiveKeep = keepSets < 1 ? 1 : keepSets;
  final sets = <String, List<String>>{};
  final stamps = <String, int>{};
  for (final name in fileNames) {
    final m = _kPreMigrateName.firstMatch(name);
    if (m == null) continue; // 不认识的命名 ⇒ 不参与保留计算
    final key = name.replaceFirst(_kSidecarSuffix, '');
    sets.putIfAbsent(key, () => <String>[]).add(name);
    stamps[key] = int.parse(m.group(1)!);
  }
  if (sets.length <= effectiveKeep) return const <String>[];

  final keys = sets.keys.toList()
    ..sort((a, b) => stamps[b]!.compareTo(stamps[a]!)); // 新 → 旧
  final doomed = <String>[];
  for (final key in keys.skip(effectiveKeep)) {
    doomed.addAll(sets[key]!);
  }
  return doomed..sort();
}

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
