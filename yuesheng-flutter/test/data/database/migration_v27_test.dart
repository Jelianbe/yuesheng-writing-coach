// ─────────────────────────────────────────────────────────────
// migration_v27_test — ADR-C78 批次1 v26 → v27 迁移路径测试
//
// 模拟真实升级：用 sqlite3 手工构造 v26 存量库文件（character_fact 无
// aliases/status，event_fact 无 stale/chapter_hash），user_version = 26，
// 再用 AppDatabase.forTesting 打开 → 触发 onUpgrade(26 → 27)。
//
// 覆盖：
//   1. 升级后 user_version = 27
//   2. 4 个新列全部补齐（每条 ALTER 带 PRAGMA table_info 幂等守卫）
//   3. 存量行取到正确默认值：aliases='[]'、status='active'、stale=0、
//      chapter_hash=null
//   4. 幂等：同一库文件重复打开不报错、不重复加列
//   5. 存量数据不丢（插入行仍在，断言 JSON 未被破坏）
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:writingcoach/data/database/database.dart';

var _dbSeq = 0;

/// 构造 v26 存量库文件（复刻 X-041a 迁移完成后的真实 schema）
String createV26LegacyDbFile() {
  final path =
      '${Directory.systemTemp.path}${Platform.pathSeparator}yuesheng_v27_migration_${_dbSeq++}.db';
  final db = sqlite3.sqlite3.open(path);
  db.execute('''
    CREATE TABLE character_fact (
      id                 TEXT NOT NULL,
      manuscript_id      TEXT NOT NULL,
      name               TEXT NOT NULL,
      first_seen_chapter INTEGER DEFAULT NULL,
      first_seen_at      INTEGER DEFAULT NULL,
      assertions         TEXT NOT NULL DEFAULT '[]',
      created_at         INTEGER NOT NULL DEFAULT 0,
      updated_at         INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (id)
    )
  ''');
  db.execute('''
    CREATE TABLE event_fact (
      id              TEXT NOT NULL,
      manuscript_id   TEXT NOT NULL,
      name            TEXT NOT NULL,
      chapter         INTEGER DEFAULT NULL,
      event_type      TEXT NOT NULL,
      cause_event_id  TEXT DEFAULT NULL,
      effect_event_id TEXT DEFAULT NULL,
      participants    TEXT NOT NULL DEFAULT '[]',
      description     TEXT NOT NULL DEFAULT '',
      created_at      INTEGER NOT NULL DEFAULT 0,
      updated_at      INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (id)
    )
  ''');
  db.execute('''
    INSERT INTO character_fact
      (id, manuscript_id, name, first_seen_chapter, assertions, created_at, updated_at)
    VALUES
      ('cf1', 'm1', '阿禾', 3, '[{"attribute":"独生子女状态","value":"独生子","chapter":3,"timestamp":1700000000}]', 100, 100)
  ''');
  db.execute('''
    INSERT INTO event_fact
      (id, manuscript_id, name, chapter, event_type, participants, description, created_at, updated_at)
    VALUES
      ('ef1', 'm1', '阿禾决定去金陵', 5, '决定', '["阿禾"]', '阿禾收拾行囊南下', 100, 100)
  ''');
  db.execute('PRAGMA user_version = 26');
  db.dispose();
  return path;
}

/// 查某表是否含指定列
Future<bool> _hasColumn(AppDatabase db, String table, String column) async {
  final rows = await db
      .customSelect(
        "SELECT name FROM pragma_table_info('$table') WHERE name='$column'",
      )
      .get();
  return rows.length == 1;
}

void main() {
  tearDown(() {
    for (final f in Directory.systemTemp.listSync().whereType<File>().where(
      (f) => f.path.contains('yuesheng_v27_migration_'),
    )) {
      f.deleteSync();
    }
  });

  test('#1 v26 → v27 升级：4 列补齐 + 存量行默认值正确 + 数据不丢', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase(File(createV26LegacyDbFile())),
    );
    addTearDown(db.close);

    // 1. user_version 升到 27
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), 27);

    // 2. 4 个新列全部存在
    expect(
      await _hasColumn(db, 'character_fact', 'aliases'),
      isTrue,
      reason: 'character_fact 缺少 aliases 列',
    );
    expect(
      await _hasColumn(db, 'character_fact', 'status'),
      isTrue,
      reason: 'character_fact 缺少 status 列',
    );
    expect(
      await _hasColumn(db, 'event_fact', 'stale'),
      isTrue,
      reason: 'event_fact 缺少 stale 列',
    );
    expect(
      await _hasColumn(db, 'event_fact', 'chapter_hash'),
      isTrue,
      reason: 'event_fact 缺少 chapter_hash 列',
    );

    // 3. 存量 character_fact 行：默认值 '[]' / 'active'，数据不丢
    final cf = await db
        .customSelect('SELECT * FROM character_fact WHERE id = \'cf1\'')
        .getSingle();
    expect(cf.read<String>('name'), '阿禾', reason: '存量人物数据丢失');
    expect(
      cf.read<String>('assertions'),
      contains('独生子女状态'),
      reason: '存量断言 JSON 被破坏',
    );
    expect(cf.read<String>('aliases'), '[]', reason: 'aliases 默认值错误');
    expect(cf.read<String>('status'), 'active', reason: 'status 默认值错误');

    // 4. 存量 event_fact 行：stale=0 / chapter_hash=null，数据不丢
    final ef = await db
        .customSelect('SELECT * FROM event_fact WHERE id = \'ef1\'')
        .getSingle();
    expect(ef.read<String>('name'), '阿禾决定去金陵', reason: '存量事件数据丢失');
    expect(ef.read<String>('description'), '阿禾收拾行囊南下');
    expect(ef.read<int>('stale'), 0, reason: 'stale 默认值错误');
    expect(
      ef.read<String?>('chapter_hash'),
      isNull,
      reason: 'chapter_hash 默认值应为 NULL',
    );
  });

  test('#2 幂等：v27 库重复打开不报错、不重复加列', () async {
    final path = createV26LegacyDbFile();

    final db1 = AppDatabase.forTesting(NativeDatabase(File(path)));
    await db1.customSelect('PRAGMA user_version').getSingle();
    await db1.close();

    // 第二次打开同一库（已是 v27），迁移不再触发，不应报 duplicate column
    final db2 = AppDatabase.forTesting(NativeDatabase(File(path)));
    addTearDown(db2.close);

    final version = await db2.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), 27);

    // 列数未因重复 ALTER 而膨胀
    final cfCols = await db2
        .customSelect(
          "SELECT COUNT(*) AS c FROM pragma_table_info('character_fact')",
        )
        .getSingle();
    expect(cfCols.read<int>('c'), 10, reason: 'character_fact 列被重复添加');
    final efCols = await db2
        .customSelect(
          "SELECT COUNT(*) AS c FROM pragma_table_info('event_fact')",
        )
        .getSingle();
    expect(efCols.read<int>('c'), 13, reason: 'event_fact 列被重复添加');

    // 存量行仍在
    final cf = await db2
        .customSelect('SELECT * FROM character_fact WHERE id = \'cf1\'')
        .getSingle();
    expect(cf.read<String>('status'), 'active');
    final ef = await db2
        .customSelect('SELECT * FROM event_fact WHERE id = \'ef1\'')
        .getSingle();
    expect(ef.read<int>('stale'), 0);
  });
}
