// ─────────────────────────────────────────────────────────────
// DatabaseBackupService — 数据库备份与恢复（v29，外来设计文档 §二 适配）
//
// 适配要点：
//   - SQLite 在线备份不锁库：本项目用「WAL checkpoint(TRUNCATE) 合并 → 复制
//     主库单文件」实现，checkpoint 后单文件即完整一致快照；复制期间无并发写
//     （单用户桌面应用，备份触发时机可控：迁移前 / 用户主动触发）。
//   - backup_history 表记录每次备份（success/failed/restored），旧库（<v29）
//     无该表时记录自动跳过，备份文件本身不受影响。
//   - cleanupOldBackups 只保留最近 N 份（默认 10），防备份目录无限膨胀。
//   - restoreBackup 还原后删除残留 WAL/SHM：防旧 WAL 回放覆盖还原数据。
//     调用方必须先关闭数据库连接（本服务不负责重开连接）。
//
// ★ 调用方现状（2026-09-18 实测登记，**勿再当作「备份已在跑」的证据**）：
//   · **生产代码零实例化** —— `lib/` 内除本文件外无任何构造点（仅 `test/` 引用）。
//   · 迁移前备份的真实实现是 `database.dart::_preMigrateBackup`（**另一套**：
//     只做文件复制、不触碰 SQLite 状态，因它跑在 onUpgrade 事务里）。
//   · 因此 `createBackup` / `restoreBackup` / `listBackups` / `backup_history`
//     目前是**没有调用方的运维原语**（要有 UI 才能触达），而不是已生效的能力。
//   · **已接线的那一件是保留策略**：`cleanupOldBackups(type: preMigrate)`
//     委托给 `lib/data/database/backup_retention.dart`，并已由
//     `_preMigrateBackup` 在生产路径上真实调用（清偿「pre_migrate 目录无上限增长」）。
//   ※ 把它读到「看起来有备份能力」就等于 `DECISIONS §4-39` 那类**登记与事实脱节**。
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/database/backup_retention.dart';
import '../data/database/database.dart';

/// 备份类型（与 backup_history.type CHECK 一致）
enum BackupType {
  auto('auto'),
  manual('manual'),
  preMigrate('pre_migrate');

  const BackupType(this.dbName);

  /// 落库与目录名（preMigrate → pre_migrate，与 CHECK 约束一致）
  final String dbName;
}

/// 备份状态（与 backup_history.status CHECK 一致）
enum BackupStatus { success, failed, restored }

class DatabaseBackupService {
  DatabaseBackupService({
    required this.database,
    String? backupRootOverride,
    String? dbPathOverride,
  }) : _backupRootOverride = backupRootOverride,
       _dbPathOverride = dbPathOverride;

  final AppDatabase database;

  /// 测试注入：备份根目录覆盖（默认 <文档目录>/backups）
  final String? _backupRootOverride;

  /// 测试注入：数据库文件路径覆盖（默认 <文档目录>/yuesheng.db）
  final String? _dbPathOverride;

  /// 备份保留份数（外来设计 §二 cleanupOldBackups(10)）
  static const int defaultKeepCount = 10;

  /// 创建备份，返回备份文件绝对路径。
  /// 失败时抛异常，并尽量在 backup_history 留 failed 记录（表不存在则跳过）。
  Future<String> createBackup({BackupType type = BackupType.manual}) async {
    final dbPath = await _resolveDbPath();
    if (dbPath == null) {
      throw StateError('数据库文件不可用，无法备份');
    }
    final dir = await _backupDir(type);
    final stamp = _timestamp();
    final backupPath = p.join(dir.path, 'backup_${stamp}_${type.dbName}.db');
    try {
      // WAL 内容合并回主库：单文件快照完整
      await database.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
      await File(dbPath).copy(backupPath);
      final size = await File(backupPath).length();
      await _recordSafe(
        type: type,
        filePath: backupPath,
        fileSize: size,
        status: BackupStatus.success,
      );
      await cleanupOldBackups(keep: defaultKeepCount, type: type);
      return backupPath;
    } catch (e) {
      await _recordSafe(
        type: type,
        filePath: backupPath,
        fileSize: 0,
        status: BackupStatus.failed,
        error: '$e',
      );
      rethrow;
    }
  }

  /// 从备份文件恢复。调用方须先 close 数据库连接；还原后清理残留
  /// WAL/SHM（防旧 WAL 回放覆盖还原数据）。
  /// 注意：连接已关闭，无法写入 restored 状态记录；restored 标记由
  /// 恢复流程重开连接后另行处理（本期不实现 UI，故不写状态）。
  Future<void> restoreBackup(String backupPath) async {
    final dbPath = await _resolveDbPath();
    if (dbPath == null) {
      throw StateError('数据库路径不可用，无法恢复');
    }
    if (!await File(backupPath).exists()) {
      throw FileSystemException('备份文件不存在', backupPath);
    }
    await File(backupPath).copy(dbPath);
    for (final suffix in const ['-wal', '-shm']) {
      final f = File(dbPath + suffix);
      if (await f.exists()) {
        await f.delete();
      }
    }
  }

  /// 清理旧备份：每种类型各保留最近 [keep] 份。
  /// 备份文件名带时间戳（毫秒），字典序倒序 = 新在前。
  ///
  /// ★ `preMigrate` **不走 `.db` 计数**：它的落盘形态是三件套
  /// （`backup_<stamp>_pre_migrate_v<from>` + `-wal` + `-shm`，**没有 `.db` 扩展名**）
  /// ⇒ 旧的 `endsWith('.db')` 过滤对它**一条都匹配不到**（空操作，这就是
  /// 「`backups/pre_migrate/` 无上限增长」的成因）。现委托给按「套」淘汰的共享模块，
  /// **绝不删半套**。
  Future<void> cleanupOldBackups({
    int keep = defaultKeepCount,
    BackupType? type,
  }) async {
    final types = type == null ? BackupType.values : <BackupType>[type];
    for (final t in types) {
      final dir = await _backupDir(t);
      if (!await dir.exists()) continue;
      if (t == BackupType.preMigrate) {
        await prunePreMigrateBackupSets(
          dir,
          keepSets: keep,
          onError: (name, e) =>
              debugPrint('[DB] pre_migrate 备份清理失败（已跳过）: $name $e'),
        );
        continue;
      }
      final files =
          await dir
                .list()
                .where((e) => e is File && e.path.endsWith('.db'))
                .cast<File>()
                .toList()
            ..sort((a, b) => b.path.compareTo(a.path));
      for (final f in files.skip(keep)) {
        await f.delete();
      }
    }
  }

  /// 备份历史记录（按创建时间倒序；同秒备份按 id 倒序，id 为微秒时间戳）
  Future<List<BackupHistoryRow>> listBackups() async {
    return (database.select(database.backupHistory)..orderBy([
          (t) => OrderingTerm.desc(t.createdAt),
          (t) => OrderingTerm.desc(t.id),
        ]))
        .get();
  }

  // ── 内部 ──

  Future<String?> _resolveDbPath() async {
    if (_dbPathOverride != null) return _dbPathOverride;
    try {
      final folder = await getApplicationDocumentsDirectory();
      return p.join(folder.path, 'yuesheng.db');
    } catch (_) {
      return null; // 测试环境无 path_provider 插件
    }
  }

  Future<Directory> _backupDir(BackupType type) async {
    final root =
        _backupRootOverride ?? (await getApplicationDocumentsDirectory()).path;
    final dir = Directory(p.join(root, 'backups', type.dbName));
    await dir.create(recursive: true);
    return dir;
  }

  String _timestamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}'
        '_${two(n.hour)}${two(n.minute)}${two(n.second)}'
        '_${n.millisecond.toString().padLeft(3, '0')}';
  }

  /// 写 backup_history 记录；旧库（<v29）无该表时静默跳过（备份文件仍有效）。
  Future<void> _recordSafe({
    required BackupType type,
    required String filePath,
    required int fileSize,
    required BackupStatus status,
    String error = '',
  }) async {
    try {
      await database
          .into(database.backupHistory)
          .insert(
            BackupHistoryCompanion.insert(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              type: type.dbName,
              filePath: filePath,
              fileSize: fileSize,
              status: status.name,
              errorMessage: Value(error),
            ),
          );
    } catch (e) {
      debugPrint('[DB] backup_history 记录跳过（表不存在或写入失败）: $e');
    }
  }
}
