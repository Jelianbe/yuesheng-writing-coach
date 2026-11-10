// ─────────────────────────────────────────────────────────────
// database_web — DB 打开 / WAL checkpoint / 迁移前备份的 **web 侧**
// （T-20261031-03 §九 #1 · 条件导入拆分的另一分支）
//
// 主文件用条件导入选边：
//   import 'database_io.dart' if (dart.library.js_interop) 'database_web.dart';
// ⇒ web 走本文件；native（移动端 / 桌面）走 `database_io.dart`。
//
// ★ 两侧语义逐条对照（支撑「移动端零行为变化」判据）：
//   1. 关闭前 WAL checkpoint：io 侧跑 `PRAGMA wal_checkpoint(TRUNCATE)`；
//      web 侧**不跑**（wasm SQLite 无 WAL 文件，跑了也无意义）。
//   2. 迁移前备份：io 侧在 `flutter test` 下短路，其余复制三件套；
//      web 侧**恒短路**（浏览器无文件系统 ⇒ 没有主库文件可备份）。
//   3. 数据库连接：io 侧 `NativeDatabase`（含 ABN-02 Windows release 回退）；
//      web 侧 `WasmDatabase`（drift 的 wasm 后端）。
//
// ⚠ **依赖 U4 资产**（`web/sqlite3.wasm` + `web/drift_worker.js`）：二者尚未落定
//   （`DECISIONS §4-458` A 点终值 CSP 串未定 + `web/` 部署配置未生成）⇒ 本文件
//   保证**编译期通过**，**运行期**要等 U4 资产与部署三件套就位。
// ─────────────────────────────────────────────────────────────

import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

/// 关闭前把 WAL 内容 checkpoint 回主库 —— web 侧**无 WAL 文件** ⇒ 跳过。
Future<void> walCheckpointBeforeClose(DatabaseConnectionUser db) async {
  // web：wasm SQLite 的持久化由 drift 自身负责，无 WAL sidecar 可 checkpoint。
}

/// 迁移前备份是否跳过 —— web 侧**恒跳过**（浏览器无文件系统）。
bool preMigrateBackupDisabled() => true;

/// 迁移前备份的目标（web 侧占位）：浏览器无文件系统 ⇒ 恒为空占位。
///
/// ★ 与 io 侧 `preMigrateBackupTarget()` **同名同形**（同名 + 同返回类型）——
///   主文件 `database.dart` 的 `_preMigrateBackup` 是**两侧共用**的代码，
///   若 web 侧缺这个函数，web 分支编译期直接红（`undefined_method`）。
///   实际路径上本函数**永不被调用**：`preMigrateBackupDisabled()` 恒 true
///   ⇒ `_preMigrateBackup` 第一行即 return。
Future<PreMigrateBackupTarget> preMigrateBackupTarget() async =>
    const PreMigrateBackupTarget();

/// web 侧的「备份目录」占位：浏览器无文件系统 ⇒ 路径为空、创建为空操作。
class WebBackupDir {
  const WebBackupDir();

  /// 空路径（占位；调用方在 web 上永远走不到落盘分支）。
  String get path => '';

  /// 空操作（web 无文件系统）。
  Future<void> create({bool recursive = false}) async {}
}

/// web 侧的「备份文件」占位：不存在、复制为空操作。
class WebBackupFile {
  const WebBackupFile();

  /// 恒 false（web 无文件）。
  Future<bool> exists() async => false;

  /// 空操作（web 无文件可复制）。
  Future<void> copy(String targetPath) async {}
}

/// 迁移前备份的目标（web 侧占位；`preMigrateBackupDisabled()` 先短路）。
class PreMigrateBackupTarget {
  const PreMigrateBackupTarget();

  /// 占位目录。
  WebBackupDir get dir => const WebBackupDir();

  /// 占位主库文件。
  WebBackupFile get dbFile => const WebBackupFile();

  /// 占位伴生文件。
  WebBackupFile sidecar(String suffix) => const WebBackupFile();
}

/// 数据库连接（web 侧）：drift 的 wasm 后端。
LazyDatabase openDatabaseConnection() {
  return LazyDatabase(() async {
    final result = await WasmDatabase.open(
      databaseName: 'yuesheng',
      // U4 资产：`web/sqlite3.wasm` 与 `web/drift_worker.js`（尚未落定）。
      sqlite3Uri: Uri.parse('sqlite3.wasm'),
      driftWorkerUri: Uri.parse('drift_worker.js'),
    );
    return result.resolvedExecutor;
  });
}
