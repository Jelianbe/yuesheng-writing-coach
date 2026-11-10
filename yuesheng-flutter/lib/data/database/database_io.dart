// ─────────────────────────────────────────────────────────────
// database_io — DB 打开 / WAL checkpoint / 迁移前备份的 **io 侧**
// （T-20261031-03 §九 #1 · 条件导入拆分）
//
// 为什么独立文件：`dart:io` 的**唯一落点**必须与「无 io 依赖的主文件」分开，
// 否则 web 编译期就红。主文件用条件导入选边：
//   import 'database_io.dart' if (dart.library.js_interop) 'database_web.dart';
// ⇒ native（移动端 / 桌面）走本文件；web 走 `database_web.dart` 的 stub。
//
// ★ 移动端零行为变化：本文件的实现与拆分前 `database.dart` 的对应代码
//   **逐字等价**（含 ABN-02 Windows release 回退语义、迁移前备份三件套复制、
//   关闭前 WAL checkpoint）。拆分只搬位置，不改逻辑。
//
// ★ 本文件**不 import 任何项目内文件**（只依赖 drift / path / path_provider），
//   ⇒ 不会与 `database.dart` 形成文件级环（门禁 3 零新增）。
// ─────────────────────────────────────────────────────────────

import 'dart:developer';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 关闭前把 WAL 内容 checkpoint 回主库（TRUNCATE 截断 WAL），
/// 收尾持久化 + 防 WAL 文件异常增长；失败留痕不阻断关闭。
Future<void> walCheckpointBeforeClose(DatabaseConnectionUser db) async {
  try {
    await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
  } catch (e) {
    debugPrint('[DB] wal_checkpoint 失败: $e');
  }
}

/// 迁移前备份是否跳过：测试环境（`flutter test` 内存库，无真实文件且
/// path_provider 无 binding）直接跳过，不阻断任何迁移。
bool preMigrateBackupDisabled() =>
    Platform.environment['FLUTTER_TEST'] == 'true';

/// 迁移前备份的目标（备份目录 + 主库文件）。
///
/// 拆分前这两条路径是在 `_preMigrateBackup` 里就地算出来的；
/// 现在由本文件算好后交给主文件使用（**路径拼法逐字不变**）。
class PreMigrateBackupTarget {
  PreMigrateBackupTarget({required this.dir, required this.dbFile});

  /// 备份目录 `<文档目录>/backups/pre_migrate`。
  final Directory dir;

  /// 主库文件 `<文档目录>/yuesheng.db`。
  final File dbFile;

  /// 主库的伴生文件（`-wal` / `-shm`）。
  File sidecar(String suffix) => File(dbFile.path + suffix);
}

/// 组装迁移前备份的目标（备份目录 + 主库文件）。
Future<PreMigrateBackupTarget> preMigrateBackupTarget() async {
  final dbFolder = await getApplicationDocumentsDirectory();
  return PreMigrateBackupTarget(
    dir: Directory(p.join(dbFolder.path, 'backups', 'pre_migrate')),
    dbFile: File(p.join(dbFolder.path, 'yuesheng.db')),
  );
}

/// 数据库连接（拆分前是 `database.dart` 的 `_openConnection()`，逐字保留）。
LazyDatabase openDatabaseConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'yuesheng.db'));
    // ABN-02 FIX：Windows release 下 NativeDatabase.createInBackground() 会在
    // 后台 Isolate 线程中执行 DynamicLibrary.open(sqlite3.dll)，当 Windows
    // release build 打包的 DLL 搜索路径 / 用户权限不足时，Isolate 崩溃但错误
    // 被 LazyDatabase + runZonedGuarded 两级捕获并静默降级为"DB 未初始化"，
    // 后续任何 INSERT（如新建作品）都会以"创建失败，请稍后再试"告终。
    //
    // 修复策略：
    //   1) 默认退回到主线程同步 NativeDatabase(file)——Drift 的所有操作已经是
    //      async query executor 包装，实际 DB IO 不阻塞 Flutter UI（只跑 microtasks）。
    //   2) 初始化阶段显式 try-catch：如果 sqlite3.dll 无法加载 / 文件目录写不了，
    //      把详细错误打到 debugPrint 并 rethrow（阻止静默吞错误后下游报模糊失败）。
    //   3) 保留 createInBackground 为 future 可选开关（数据库 > 200MB / 移动端
    //      低端机场景后续可配置化，本次 R-010 最小化不新增配置项）。
    try {
      return NativeDatabase(file);
    } catch (e, s) {
      log(
        '[AppDatabase][FATAL] 打开数据库失败: path=${file.path}, error=$e',
        name: 'yuesheng.db',
        error: e,
        stackTrace: s,
      );
      rethrow;
    }
  });
}
