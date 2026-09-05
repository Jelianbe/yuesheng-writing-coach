// ─────────────────────────────────────────────────────────────
// migration_v23_test — 批次89 v22 → v23 迁移路径测试（v24 回收站 CHECK +
// v25 标签列一并迁移到 25）
//
// 模拟真实升级：用 sqlite3 手工构造 v22 存量库文件（manuscripts +
// chapters，无 volumes 表、chapters 无 volume_id），user_version = 22，
// 再用 AppDatabase.forTesting 打开 → 触发 onUpgrade(22 → … → 27)。
//
// 覆盖：
//   1. 升级后 user_version = 27
//   2. volumes 表已建（VolumeRepository 可写可读）
//   3. chapters 新增 volume_id 列，存量章节 volume_id 为 NULL（未分卷）
//   4. 存量章节数据完整保留
//   5. 幂等：升级后库二次打开不重复迁移、不报错
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/volume_repository.dart';

var _dbSeq = 0;

/// 构造 v22 存量库文件（复刻批次89 之前 chapters 的真实列）
String createV22LegacyDbFile() {
  final path =
      '${Directory.systemTemp.path}${Platform.pathSeparator}yuesheng_v22_migration_${_dbSeq++}.db';
  final db = sqlite3.sqlite3.open(path);
  db.execute('''
    CREATE TABLE manuscripts (
      id          TEXT PRIMARY KEY,
      title       TEXT NOT NULL DEFAULT '',
      description TEXT NOT NULL DEFAULT '',
      genre       TEXT NOT NULL DEFAULT '',
      language    TEXT NOT NULL DEFAULT '中文',
      status      TEXT NOT NULL DEFAULT 'draft',
      sort_order  INTEGER NOT NULL DEFAULT 0,
      created_at  INTEGER NOT NULL DEFAULT 0,
      updated_at  INTEGER NOT NULL DEFAULT 0
    )
  ''');
  db.execute('''
    CREATE TABLE chapters (
      id                TEXT PRIMARY KEY,
      manuscript_id     TEXT NOT NULL REFERENCES manuscripts(id) ON DELETE CASCADE,
      title             TEXT NOT NULL DEFAULT '',
      content           TEXT NOT NULL DEFAULT '',
      previous_content  TEXT DEFAULT NULL,
      word_count        INTEGER NOT NULL DEFAULT 0,
      sort_order        INTEGER NOT NULL DEFAULT 0,
      status            TEXT NOT NULL DEFAULT 'draft',
      last_diagnosed_at INTEGER DEFAULT NULL,
      created_at        INTEGER NOT NULL DEFAULT 0,
      updated_at        INTEGER NOT NULL DEFAULT 0
    )
  ''');
  db.execute('''
    INSERT INTO manuscripts (id, title, created_at, updated_at)
    VALUES ('m1', '存量测试稿', 100, 100)
  ''');
  db.execute('''
    INSERT INTO chapters (id, manuscript_id, title, content, word_count, sort_order, status, created_at, updated_at)
    VALUES ('c1', 'm1', '第一章', '存量正文', 4, 0, 'draft', 100, 100)
  ''');
  db.execute('PRAGMA user_version = 22');
  db.dispose();
  return path;
}

void main() {
  tearDown(() {
    // 清理测试生成的临时库文件
    for (final f in Directory.systemTemp.listSync().whereType<File>().where(
      (f) => f.path.contains('yuesheng_v22_migration_'),
    )) {
      f.deleteSync();
    }
  });

  test('#1 v22 → v25 升级：volumes 建表 + chapters.volume_id + 存量保留', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase(File(createV22LegacyDbFile())),
    );
    addTearDown(db.close);

    // 1. user_version 升到 27（v23 卷分组 + v24 回收站 CHECK + v25 标签列
    //    + v26 schema bump + v27 角色标签页列一并迁移）
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), 27);

    // 2. chapters 新增 volume_id，存量章节未分卷
    final chapter = await ChapterRepository(db).getChapter('c1');
    expect(chapter, isNotNull);
    expect(chapter!.title, '第一章', reason: '存量数据保留');
    expect(chapter.content, '存量正文');
    expect(chapter.volumeId, isNull, reason: '存量章节默认未分卷');

    // 3. volumes 表可写可读（VolumeRepository 正常工作）
    final repo = VolumeRepository(db);
    final volumeId = await repo.createVolume('m1', title: '第一卷');
    final volumes = await repo.listVolumes('m1');
    expect(volumes.length, 1);
    expect(volumes.first.id, volumeId);

    // 4. 章节可移入新卷
    await repo.setChapterVolume('c1', volumeId);
    expect((await ChapterRepository(db).getChapter('c1'))!.volumeId, volumeId);
  });

  test('#2 幂等：v23 库二次打开不重复迁移', () async {
    final path = createV22LegacyDbFile();

    final db1 = AppDatabase.forTesting(NativeDatabase(File(path)));
    await db1.customSelect('PRAGMA user_version').getSingle();
    await db1.close();

    // 第二次打开同一库（已是 v25），不应报「列已存在」类错误
    final db2 = AppDatabase.forTesting(NativeDatabase(File(path)));
    addTearDown(db2.close);
    final chapter = await ChapterRepository(db2).getChapter('c1');
    expect(chapter!.volumeId, isNull);
    final volumes = await VolumeRepository(db2).listVolumes('m1');
    expect(volumes, isEmpty);
  });
}
