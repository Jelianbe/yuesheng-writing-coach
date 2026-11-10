// ─────────────────────────────────────────────────────────────
// pre_migrate 备份保留策略 · **纯逻辑部分**（平台无关，无 io 依赖）
//
// 为什么单独一个文件：
//   保留策略有两半 ——
//     · 「按套归组 → 淘汰清单」= **纯函数**（不碰文件系统）；
//     · 「在真实目录上执行淘汰」= **io 侧**（要 Directory / File）。
//   web 侧只需要前者（后者永远不执行：浏览器无文件系统）⇒ 把纯函数放在
//   本文件，io / web 两侧各自 import 它 ⇒ **不复制逻辑、不新增映射表**。
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
