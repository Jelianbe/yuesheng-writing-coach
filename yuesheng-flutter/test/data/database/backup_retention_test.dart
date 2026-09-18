// ─────────────────────────────────────────────────────────────
// pre_migrate 备份保留策略测试
//
// 覆盖：
//   1. selectPreMigrateFilesToDelete：按「套」淘汰，**绝不删半套**
//   2. 边界：恰好 keepSets 套 ⇒ 不删；keepSets < 1 ⇒ 钳到 1（不允许清空备份）
//   3. ★ 不认识的文件名**一律不删**（不销毁不理解的东西）
//   4. prunePreMigrateBackupSets：真实目录落盘验证
//   5. ★ 接线契约（**源码级**）：`_preMigrateBackup` 必须调用保留策略，
//      且**先写新套再淘汰旧套**
//      —— 该路径在 `flutter test` 下**整体不执行**（`FLUTTER_TEST` 短路），
//        逻辑覆盖只能靠 1–4，而「调用点被悄悄摘掉」只能靠源码级断言拦住。
//        这是**有意的**：宁可留一条脆弱的契约，也不要一个没有护栏的死角。
//
// ⚠️ 未覆盖（诚实边界）：`prunePreMigrateBackupSets` 的 `onError`（逐文件删除失败留痕）
//    分支**没有自动化用例** —— 本机的文件系统无法稳定制造「列得到、删不掉」的条目
//    （把文件换成目录会让它在扫描阶段就被 `e is File` 过滤掉，根本不会进入删除面）。
//    该分支的价值在运行时留痕，不在断言。
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:writingcoach/data/database/backup_retention.dart';

/// 造一套（三件套，或 `full: false` 时只造主件）的文件名。
List<String> _set(int stamp, {int from = 29, bool full = true}) {
  final base = 'backup_${1700000000000 + stamp}_pre_migrate_v$from';
  return full ? <String>[base, '$base-wal', '$base-shm'] : <String>[base];
}

/// 删除清单的**返回序是升序**，比较前统一排序，避免用字面量顺序掩盖实现差异。
List<String> _sorted(List<String> xs) => xs..sort();

void main() {
  group('selectPreMigrateFilesToDelete（纯函数）', () {
    test('12 套 / keep=10 ⇒ 只淘汰最旧 2 套的 6 个文件（整套，不留半套）', () {
      final names = <String>[for (var i = 0; i < 12; i++) ..._set(i)];

      final doomed = selectPreMigrateFilesToDelete(names, keepSets: 10);

      expect(doomed.length, 6, reason: '2 套 × 3 件');
      expect(doomed, _sorted(<String>[..._set(0), ..._set(1)]));
      expect(doomed.contains(_set(11).first), false, reason: '最新的必须保留');
      expect(doomed.contains(_set(2).first), false, reason: '第 3 新的是保留边界');
    });

    test('恰好等于 keepSets 套 ⇒ 一个都不删（边界，不允许误伤）', () {
      final names = <String>[for (var i = 0; i < 10; i++) ..._set(i)];

      expect(selectPreMigrateFilesToDelete(names, keepSets: 10), isEmpty);
    });

    test('keepSets < 1 被钳到 1：保留策略**不允许把备份清空**', () {
      final names = <String>[..._set(0), ..._set(1)];

      final doomed = selectPreMigrateFilesToDelete(names, keepSets: 0);

      expect(doomed, _sorted(_set(0)), reason: '只应删到剩最新 1 套');
      expect(doomed.any((n) => n.contains('1700000000001')), false);
    });

    test('不识别的命名一律不删（手工文件 / 别的类型 / 旧格式）', () {
      final names = <String>[
        ..._set(0),
        ..._set(1),
        'readme.txt',
        'backup_1700000000000_manual.db', // 别的类型：不归本策略管
        'backup_xx_pre_migrate_v29', // stamp 非数字 ⇒ 不符约定
        'backup_1700000000000_pre_migrate_v', // 缺 from ⇒ 不符约定
      ];

      final doomed = selectPreMigrateFilesToDelete(names, keepSets: 1);

      expect(doomed, _sorted(_set(0)));
      expect(
        doomed.contains('backup_1700000000000_manual.db'),
        false,
        reason: '不认识的命名绝不删',
      );
      expect(doomed.contains('readme.txt'), false);
    });

    test('半套（同一次迁移只落下一件）按 1 套计，不因缺件漏算', () {
      final names = <String>[..._set(0, full: false), ..._set(1), ..._set(2)];

      final doomed = selectPreMigrateFilesToDelete(names, keepSets: 2);

      expect(doomed, _set(0, full: false), reason: '最旧那「一套」（单件）被整体淘汰');
    });
  });

  group('prunePreMigrateBackupSets（真实目录）', () {
    late Directory tempDir;

    setUp(() => tempDir = Directory.systemTemp.createTempSync('pre_migrate_'));
    tearDown(() => tempDir.deleteSync(recursive: true));

    test('目录不存在 ⇒ 不抛异常、返回空（迁移路径要求失败不阻断）', () async {
      final missing = Directory(p.join(tempDir.path, 'nope'));

      expect(await prunePreMigrateBackupSets(missing, keepSets: 10), isEmpty);
    });

    test('落盘验证：5 套 / keep=2 ⇒ 只剩最新 2 套，每套三件齐全', () async {
      for (var i = 0; i < 5; i++) {
        for (final name in _set(i)) {
          File(p.join(tempDir.path, name)).writeAsStringSync('x');
        }
      }

      final deleted = await prunePreMigrateBackupSets(tempDir, keepSets: 2);

      expect(deleted.length, 9, reason: '3 套 × 3 件');
      final left =
          tempDir
              .listSync()
              .whereType<File>()
              .map((f) => p.basename(f.path))
              .toList()
            ..sort();
      expect(left.length, 6);
      expect(left, _sorted(<String>[..._set(3), ..._set(4)]));
    });

    test('空目录 / 只有不认识的命名 ⇒ 零删除、返回空', () async {
      File(p.join(tempDir.path, 'readme.txt')).writeAsStringSync('x');

      expect(await prunePreMigrateBackupSets(tempDir, keepSets: 1), isEmpty);
      expect(File(p.join(tempDir.path, 'readme.txt')).existsSync(), true);
    });
  });

  group('接线契约（源码级）', () {
    String readDatabaseSource() {
      for (final candidate in <String>[
        p.join('lib', 'data', 'database', 'database.dart'),
        p.join('..', 'lib', 'data', 'database', 'database.dart'),
      ]) {
        final f = File(candidate);
        if (f.existsSync()) return f.readAsStringSync();
      }
      // 宁可红，也不要静默跳过（护栏缺省必须是「拦下」）
      fail(
        '找不到 lib/data/database/database.dart（CWD=${Directory.current.path}）',
      );
    }

    test('_preMigrateBackup 内必须调用 prunePreMigrateBackupSets，且**在复制之后**', () {
      final src = readDatabaseSource();
      const marker = 'Future<void> _preMigrateBackup(int from) async {';
      final start = src.indexOf(marker);
      expect(start, greaterThan(-1), reason: '函数签名变了 ⇒ 本契约需同步更新');

      final body = src.substring(start, src.indexOf('\n  }', start));
      final pruneAt = body.indexOf('prunePreMigrateBackupSets(');
      final copyAt = body.indexOf('await src.copy(');

      expect(pruneAt, greaterThan(-1), reason: '保留策略的调用点被摘掉了');
      expect(copyAt, greaterThan(-1));
      expect(
        pruneAt,
        greaterThan(copyAt),
        reason: '必须**先写新套再淘汰旧套** —— 顺序反了会把刚写的套也纳入淘汰面',
      );
    });

    test('database.dart 仍导入共享叶子模块（且**不得**反向导入 service）', () {
      final src = readDatabaseSource();
      expect(src, contains("import 'backup_retention.dart';"));
      expect(
        src.contains('database_backup_service'),
        false,
        reason: '反向导入会构成文件级环 ⇒ 门禁 3 直接红（本模块就是为避开它才拆出来的）',
      );
    });
  });
}
