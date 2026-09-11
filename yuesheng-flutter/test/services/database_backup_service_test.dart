// ─────────────────────────────────────────────────────────────
// DatabaseBackupService 测试（v29 备份与恢复）
//
// 覆盖：
//   1. createBackup：备份文件生成 + backup_history success 记录
//   2. restoreBackup：文件还原 + 残留 WAL/SHM 清理 + restored 标记
//   3. cleanupOldBackups：只保留最近 N 份（默认 10）
//   4. listBackups：按创建时间倒序
//   5. 备份目录按类型分目录（manual/pre_migrate/auto）
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/services/database_backup_service.dart';

void main() {
  late Directory tempDir;
  late String dbPath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('db_backup_test_');
    dbPath = p.join(tempDir.path, 'test.db');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  AppDatabase openDb() =>
      AppDatabase.forTesting(NativeDatabase(File(dbPath)));

  DatabaseBackupService service(AppDatabase db) => DatabaseBackupService(
        database: db,
        backupRootOverride: tempDir.path,
        dbPathOverride: dbPath,
      );

  test('createBackup 生成备份文件 + backup_history success 记录', () async {
    final db = openDb();
    addTearDown(db.close);
    final s = service(db);

    final backupPath = await s.createBackup(type: BackupType.manual);

    expect(File(backupPath).existsSync(), true, reason: '备份文件应存在');
    expect(p.basename(backupPath), contains('manual'));
    expect(File(backupPath).lengthSync(), greaterThan(0));

    final records = await s.listBackups();
    expect(records.length, 1);
    expect(records.first.status, 'success');
    expect(records.first.type, 'manual');
    expect(records.first.filePath, backupPath);
  });

  test('restoreBackup 还原文件内容 + 清理残留 WAL/SHM', () async {
    final db = openDb();
    final s = service(db);
    final backupPath = await s.createBackup();
    final backupBytes = File(backupPath).readAsBytesSync();
    await db.close();

    // 模拟主库被破坏 + 存在残留 WAL/SHM
    File(dbPath).writeAsBytesSync(List.filled(64, 1));
    File('$dbPath-wal').writeAsStringSync('stale-wal');
    File('$dbPath-shm').writeAsStringSync('stale-shm');

    await s.restoreBackup(backupPath);

    // 主库字节与备份完全一致（不再是破坏内容）
    final restored = File(dbPath).readAsBytesSync();
    expect(restored, backupBytes);
    expect(File('$dbPath-wal').existsSync(), false, reason: '残留 WAL 应清理');
    expect(File('$dbPath-shm').existsSync(), false, reason: '残留 SHM 应清理');
  });

  test('cleanupOldBackups 只保留最近 N 份（默认 10）', () async {
    final db = openDb();
    addTearDown(db.close);
    final s = service(db);
    final dir = Directory(p.join(tempDir.path, 'backups', 'manual'));
    await dir.create(recursive: true);
    // 造 13 份假备份（文件名带递增时间戳，越新字典序越大）
    for (var i = 0; i < 13; i++) {
      File(p.join(dir.path, 'backup_${2026000000000 + i}_manual.db'))
          .writeAsStringSync('x');
    }
    // 先创建一份真实备份触发 cleanup（校验只删假备份不动新备份）
    final realPath = await s.createBackup(type: BackupType.manual);

    final remaining = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.db'))
        .toList();
    expect(remaining.length, 10, reason: '应只保留最近 10 份');
    expect(
      remaining.any((f) => f.path == realPath),
      true,
      reason: '最新备份不应被清理',
    );
  });

  test('listBackups 按创建时间倒序', () async {
    final db = openDb();
    addTearDown(db.close);
    final s = service(db);

    final first = await s.createBackup(type: BackupType.manual);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final second = await s.createBackup(type: BackupType.auto);

    final records = await s.listBackups();
    expect(records.length, 2);
    expect(records.first.filePath, second, reason: '最新的应在最前');
    expect(records.last.filePath, first);
  });

  test('备份按类型分目录（manual / auto / pre_migrate）', () async {
    final db = openDb();
    addTearDown(db.close);
    final s = service(db);

    final manual = await s.createBackup(type: BackupType.manual);
    final auto = await s.createBackup(type: BackupType.auto);
    final pre = await s.createBackup(type: BackupType.preMigrate);

    expect(p.dirname(manual), p.join(tempDir.path, 'backups', 'manual'));
    expect(p.dirname(auto), p.join(tempDir.path, 'backups', 'auto'));
    expect(p.dirname(pre), p.join(tempDir.path, 'backups', 'pre_migrate'));
  });
}
