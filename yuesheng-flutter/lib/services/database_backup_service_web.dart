// ─────────────────────────────────────────────────────────────
// DatabaseBackupService — **web 侧 stub**（T-20261031-03 §九 #3 · 编译期门控）
//
// ★ 为什么本服务需要 web stub：
//   `lib/services/database_backup_service.dart`（io 侧实现）整份依赖平台 io 库
//   （File / Directory / NativeDatabase / path_provider）⇒ 一旦被 web 可达代码
//   引用，web 编译期直接红。本 stub 提供**同名同签名的公开 API**，全部方法抛
//   `UnsupportedError`（**不静默成功**）。
//
// ★ io 侧实现**原地保留**（未搬文件、未改一行）：
//   `lib/services/database_backup_service.dart` 的实现体是 315 行的类，
//   搬到新路径会变成「新增 > 300 行的文件」⇒ 撞 R-019 **文件级棘轮**（容差 0）；
//   而 §九 #3 明令「休眠逻辑本体不动」⇒ 不做真分解、也不重生成基线。
//   ⇒ 本 stub 是「未来接线」的契约：**接线时必须条件导入本 stub**，
//     不得让 web 可达代码直接引用 io 侧文件。
//
// ★ 当前该服务**生产零入口**（providers / features / main 三处查找零命中，
//   仅 `test/services/database_backup_service_test.dart` 引用）⇒ web 构建
//   本就不可达该文件 ⇒ 本 stub 的**构建期收益为零**，它是**接线期的护栏**。
// ─────────────────────────────────────────────────────────────

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
  });

  /// web 侧没有可备份的本地库文件 ⇒ 构造参数只做签名对齐，不落任何状态。
  final AppDatabase database;

  /// 备份保留份数（与 io 侧 `DatabaseBackupService.defaultKeepCount` 对齐）。
  static const int defaultKeepCount = 10;

  /// web 首发不支持备份与恢复（浏览器无本地库文件 ⇒ 恢复语义不成立）。
  Future<String> createBackup({BackupType type = BackupType.manual}) async {
    throw UnsupportedError('web 平台无本地数据库文件：备份功能不可用');
  }

  /// web 首发不支持备份与恢复（浏览器无本地库文件 ⇒ 恢复语义不成立）。
  Future<void> restoreBackup(
    String backupPath, {
    Future<void> Function()? onReopen,
  }) async {
    throw UnsupportedError('web 平台无本地数据库文件：恢复功能不可用');
  }

  /// web 首发不支持备份清理（无备份目录可清）。
  Future<void> cleanupOldBackups({
    int keep = defaultKeepCount,
    BackupType? type,
  }) async {
    throw UnsupportedError('web 平台无本地数据库文件：备份清理不可用');
  }

  /// web 首发不支持备份历史（无本地库文件 ⇒ 无备份记录可列）。
  Future<List<BackupHistoryRow>> listBackups() async {
    throw UnsupportedError('web 平台无本地数据库文件：备份历史不可用');
  }
}
