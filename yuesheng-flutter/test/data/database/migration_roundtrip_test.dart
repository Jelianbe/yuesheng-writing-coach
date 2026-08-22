// ─────────────────────────────────────────────────────────────
// migration_roundtrip_test — B30 v12 → v25 迁移往返测试
//
// 覆盖 migration_v23_test 之外的更早版本（v12）存量库升级路径：
// 手工用 sqlite3 构造 v12 存量库（重建 v12 真实 schema = 当前 v25 schema
// 减去 v13+ 引入的列/表），user_version = 12，预插存量数据，
// 再用 AppDatabase.forTesting 打开 → 触发 onUpgrade(12 → 25 全链路)。
//
// 断言：
//   1. 升级后 user_version = 25
//   2. 存量数据零丢失（manuscripts/chapters/sessions/messages/
//      student_model/teaching_state/active_problem/teacher_suggestion）
//   3. v13+ 增量列正确补齐（tags / references_json / style_profile /
//      style_fingerprint / volume_id / teaching_state / updated_at / adopted_at）
//   4. v16+ 新建表存在且可写（volumes / character_fact / outline_entity 等）
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:writingcoach/data/database/database.dart';

var _dbSeq = 0;

/// 构造 v12 存量库文件（手工重建 v12 真实 schema）。
///
/// v12 = 当前 v25 schema 减去以下 v13+ 引入的列/表：
///   - manuscripts.tags (v25)
///   - chapters.volume_id (v23) + status CHECK 不含 archived (v24)
///   - messages.references_json (v22)
///   - student_model.style_profile (v13) / style_fingerprint (v15)
///   - active_problem.teaching_state (v19) / updated_at (v20)
///   - teacher_suggestion.adopted_at / dismissed_at (v14)
///   - session_reference.ref_type CHECK 不含 'file' (v21)
///   - character_fact / event_fact / subplot_fact (v16/17)
///   - outline_entity / outline_impression (v18)
///   - volumes (v23)
String createV12LegacyDbFile() {
  final path =
      '${Directory.systemTemp.path}${Platform.pathSeparator}yuesheng_v12_migration_${_dbSeq++}.db';
  final db = sqlite3.sqlite3.open(path);

  db.execute('''
    CREATE TABLE manuscripts (
      id          TEXT PRIMARY KEY,
      title       TEXT NOT NULL DEFAULT '',
      description TEXT NOT NULL DEFAULT '',
      genre       TEXT NOT NULL DEFAULT '',
      language    TEXT NOT NULL DEFAULT '中文',
      status      TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active','archived')),
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
      status            TEXT NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','revising','complete')),
      last_diagnosed_at INTEGER DEFAULT NULL,
      created_at        INTEGER NOT NULL DEFAULT 0,
      updated_at        INTEGER NOT NULL DEFAULT 0
    )
  ''');
  db.execute('''
    CREATE TABLE sessions (
      id              TEXT PRIMARY KEY,
      title           TEXT NOT NULL DEFAULT '新建会话',
      preview         TEXT NOT NULL DEFAULT '',
      manuscript_id   TEXT DEFAULT NULL REFERENCES manuscripts(id) ON DELETE SET NULL,
      chapter_id      TEXT DEFAULT NULL REFERENCES chapters(id) ON DELETE SET NULL,
      diagnosis_summary TEXT NOT NULL DEFAULT '{}',
      created_at      INTEGER NOT NULL DEFAULT 0,
      updated_at      INTEGER NOT NULL DEFAULT 0
    )
  ''');
  db.execute('''
    CREATE TABLE messages (
      id          TEXT PRIMARY KEY,
      session_id  TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
      role        TEXT NOT NULL CHECK(role IN ('user','assistant','system')),
      content     TEXT NOT NULL DEFAULT '',
      timestamp   INTEGER NOT NULL DEFAULT 0,
      message_type TEXT NOT NULL DEFAULT 'chat'
    )
  ''');
  db.execute('''
    CREATE TABLE diagnosis_results (
      id                     TEXT PRIMARY KEY,
      session_id             TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
      message_id             TEXT NOT NULL,
      syndromes              TEXT NOT NULL DEFAULT '[]',
      suggested_actions      TEXT NOT NULL DEFAULT '[]',
      root_cause_analysis    TEXT DEFAULT NULL,
      next_focus             TEXT DEFAULT NULL,
      feedback_summary       TEXT DEFAULT NULL,
      confidence             REAL NOT NULL DEFAULT 0.0,
      teaching_progress      TEXT DEFAULT NULL,
      target_ref_type        TEXT DEFAULT NULL CHECK(target_ref_type IS NULL OR target_ref_type IN ('manuscript','chapter')),
      target_ref_id          TEXT DEFAULT NULL,
      timestamp              INTEGER NOT NULL DEFAULT 0,
      created_at             INTEGER NOT NULL DEFAULT 0,
      current_teaching_focus_id TEXT DEFAULT NULL,
      focus_reason           TEXT DEFAULT NULL
    )
  ''');
  db.execute('''
    CREATE TABLE teaching_state (
      id              TEXT PRIMARY KEY,
      session_id      TEXT NOT NULL UNIQUE REFERENCES sessions(id) ON DELETE CASCADE,
      current_phase   TEXT NOT NULL DEFAULT 'P0_ENGAGE' CHECK(current_phase IN ('P0_ENGAGE','P1_WORLD','P2_PRACTICE_LOOP','P3_TRAINING','P4_REVIEW')),
      current_subphase TEXT DEFAULT NULL,
      attitude_level  TEXT DEFAULT NULL,
      beginner_level  TEXT DEFAULT NULL CHECK(beginner_level IS NULL OR beginner_level IN ('N0_ENGAGE','N1_ELEMENTS','N2_SCENE','N3_DIAGNOSE','N4_INDEPENDENT')),
      updated_at      INTEGER NOT NULL DEFAULT 0
    )
  ''');
  db.execute('''
    CREATE TABLE active_problem (
      id                TEXT PRIMARY KEY,
      session_id        TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
      syndrome_id       TEXT NOT NULL,
      syndrome_name     TEXT NOT NULL DEFAULT '',
      severity          TEXT NOT NULL DEFAULT 'L2' CHECK(severity IN ('L1','L2','L3')),
      status            TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active','resolved')),
      confirmation_status TEXT NOT NULL DEFAULT 'suspected' CHECK(confirmation_status IN ('suspected','confirmed','rejected','ignored')),
      confirmed_at      INTEGER DEFAULT NULL,
      created_at        INTEGER NOT NULL DEFAULT 0,
      resolved_at       INTEGER DEFAULT NULL
    )
  ''');
  db.execute('''
    CREATE TABLE student_model (
      id                  TEXT PRIMARY KEY,
      session_id          TEXT DEFAULT NULL REFERENCES sessions(id) ON DELETE SET NULL,
      attitude_preference TEXT DEFAULT NULL,
      teaching_history    TEXT NOT NULL DEFAULT '[]',
      onboarding_data     TEXT DEFAULT NULL,
      created_at          INTEGER NOT NULL DEFAULT 0,
      updated_at          INTEGER NOT NULL DEFAULT 0
    )
  ''');
  db.execute('''
    CREATE TABLE session_reference (
      id            TEXT PRIMARY KEY,
      session_id    TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
      ref_type      TEXT NOT NULL CHECK(ref_type IN ('manuscript','chapter')),
      ref_id        TEXT NOT NULL,
      is_primary    INTEGER NOT NULL DEFAULT 0 CHECK(is_primary IN (0,1)),
      excerpt_range TEXT DEFAULT NULL,
      created_at    INTEGER NOT NULL DEFAULT 0
    )
  ''');
  db.execute('''
    CREATE TABLE teacher_suggestion (
      id                  TEXT PRIMARY KEY,
      session_id          TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
      message_id          TEXT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
      source              TEXT NOT NULL CHECK(source IN ('editor','diagnosis')),
      teaching_decision   TEXT NOT NULL CHECK(teaching_decision IN ('guide','train')),
      target_syndrome_id  TEXT DEFAULT NULL,
      target_dimension    TEXT DEFAULT NULL,
      task_type           TEXT NOT NULL CHECK(task_type IN ('rewrite','analyze','compare','generate')),
      task_description    TEXT NOT NULL,
      difficulty          TEXT NOT NULL CHECK(difficulty IN ('easy','medium','hard')),
      evaluation_criteria TEXT NOT NULL DEFAULT '[]',
      status              TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active','resolved')),
      created_at          INTEGER NOT NULL DEFAULT 0,
      resolved_at         INTEGER DEFAULT NULL
    )
  ''');

  // 预插存量数据（覆盖 7 张表的迁移链路断言）
  db.execute('''
    INSERT INTO manuscripts (id, title, description, genre, language, status, sort_order, created_at, updated_at)
    VALUES ('m1', '存量测试稿', '简介', 'fantasy', '中文', 'active', 0, 100, 100)
  ''');
  db.execute('''
    INSERT INTO chapters (id, manuscript_id, title, content, previous_content, word_count, sort_order, status, last_diagnosed_at, created_at, updated_at)
    VALUES ('c1', 'm1', '第一章', '存量正文', '旧稿', 4, 0, 'draft', 50, 100, 100)
  ''');
  db.execute('''
    INSERT INTO sessions (id, title, manuscript_id, created_at, updated_at)
    VALUES ('s1', '会话一', 'm1', 100, 100)
  ''');
  db.execute('''
    INSERT INTO messages (id, session_id, role, content, timestamp, message_type)
    VALUES ('msg1', 's1', 'user', '帮我看看这章', 100, 'chat')
  ''');
  db.execute('''
    INSERT INTO student_model (id, session_id, attitude_preference, teaching_history, onboarding_data, created_at, updated_at)
    VALUES ('sm1', 's1', '温和', '[]', NULL, 100, 100)
  ''');
  db.execute('''
    INSERT INTO teaching_state (id, session_id, current_phase, current_subphase, attitude_level, beginner_level, updated_at)
    VALUES ('ts1', 's1', 'P0_ENGAGE', NULL, 'doubao', 'N1_ELEMENTS', 100)
  ''');
  db.execute('''
    INSERT INTO active_problem (id, session_id, syndrome_id, syndrome_name, severity, status, confirmation_status, confirmed_at, created_at, resolved_at)
    VALUES ('ap1', 's1', 'P007', '句式单一', 'L2', 'active', 'suspected', NULL, 100, NULL)
  ''');
  db.execute('''
    INSERT INTO teacher_suggestion (id, session_id, message_id, source, teaching_decision, task_type, task_description, difficulty, status, created_at, resolved_at)
    VALUES ('tsg1', 's1', 'msg1', 'diagnosis', 'train', 'rewrite', '改写这段', 'easy', 'active', 100, NULL)
  ''');

  db.execute('PRAGMA user_version = 12');
  db.dispose();
  return path;
}

void main() {
  tearDown(() {
    for (final f in Directory.systemTemp.listSync().whereType<File>().where(
      (f) => f.path.contains('yuesheng_v12_migration_'),
    )) {
      f.deleteSync();
    }
  });

  test('#1 v12 → v25 升级：全链路迁移 + 存量数据零丢失', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase(File(createV12LegacyDbFile())),
    );
    addTearDown(db.close);

    // 1. user_version 升到 25
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), 25);

    // 2. manuscripts 存量保留 + tags 列补齐
    final m = await db
        .customSelect(
          "SELECT title, status, tags FROM manuscripts WHERE id = 'm1'",
        )
        .getSingle();
    expect(m.read<String>('title'), '存量测试稿');
    expect(m.read<String>('status'), 'active');
    expect(m.read<String>('tags'), '[]', reason: 'v25 新增 tags 默认空数组');

    // 3. chapters 存量保留 + volume_id 列补齐（默认未分卷）
    final c = await db
        .customSelect(
          "SELECT title, content, previous_content, volume_id FROM chapters WHERE id = 'c1'",
        )
        .getSingle();
    expect(c.read<String>('title'), '第一章');
    expect(c.read<String>('content'), '存量正文');
    expect(c.read<String?>('previous_content'), '旧稿');
    expect(
      c.read<String?>('volume_id'),
      isNull,
      reason: 'v23 新增 volume_id 默认 NULL',
    );

    // 4. messages 存量保留 + references_json 列补齐
    final msg = await db
        .customSelect(
          "SELECT content, message_type, references_json FROM messages WHERE id = 'msg1'",
        )
        .getSingle();
    expect(msg.read<String>('content'), '帮我看看这章');
    expect(msg.read<String>('message_type'), 'chat');
    expect(
      msg.read<String?>('references_json'),
      isNull,
      reason: 'v22 新增 references_json 默认 NULL',
    );

    // 5. student_model 存量保留 + style_profile/style_fingerprint 列补齐
    final sm = await db
        .customSelect(
          "SELECT attitude_preference, style_profile, style_fingerprint FROM student_model WHERE id = 'sm1'",
        )
        .getSingle();
    expect(sm.read<String?>('attitude_preference'), '温和');
    expect(
      sm.read<String?>('style_profile'),
      isNull,
      reason: 'v13 新增 style_profile 默认 NULL',
    );
    expect(
      sm.read<String?>('style_fingerprint'),
      isNull,
      reason: 'v15 新增 style_fingerprint 默认 NULL',
    );

    // 6. teaching_state 存量保留 + beginner_level 已在 v12 存在
    final ts = await db
        .customSelect(
          "SELECT current_phase, beginner_level FROM teaching_state WHERE id = 'ts1'",
        )
        .getSingle();
    expect(ts.read<String>('current_phase'), 'P0_ENGAGE');
    expect(ts.read<String?>('beginner_level'), 'N1_ELEMENTS');

    // 7. active_problem 存量保留 + teaching_state/updated_at 列补齐
    final ap = await db
        .customSelect(
          "SELECT syndrome_id, teaching_state, updated_at FROM active_problem WHERE id = 'ap1'",
        )
        .getSingle();
    expect(ap.read<String>('syndrome_id'), 'P007');
    expect(
      ap.read<String?>('teaching_state'),
      isNull,
      reason: 'v19 新增 teaching_state 默认 NULL',
    );
    expect(
      ap.read<int?>('updated_at'),
      isNull,
      reason: 'v20 新增 updated_at 默认 NULL',
    );

    // 8. teacher_suggestion 存量保留 + adopted_at/dismissed_at 列补齐
    final tsg = await db
        .customSelect(
          "SELECT task_type, adopted_at, dismissed_at FROM teacher_suggestion WHERE id = 'tsg1'",
        )
        .getSingle();
    expect(tsg.read<String>('task_type'), 'rewrite');
    expect(
      tsg.read<int?>('adopted_at'),
      isNull,
      reason: 'v14 新增 adopted_at 默认 NULL',
    );
    expect(
      tsg.read<int?>('dismissed_at'),
      isNull,
      reason: 'v14 新增 dismissed_at 默认 NULL',
    );
  });

  test('#2 v12 → v25：v16+ 新建表存在且可写', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase(File(createV12LegacyDbFile())),
    );
    addTearDown(db.close);

    // volumes（v23）可写可读
    await db.customStatement(
      "INSERT INTO volumes (id, manuscript_id, title) VALUES ('v1', 'm1', '第一卷')",
    );
    final volCount = await db
        .customSelect('SELECT COUNT(*) AS n FROM volumes')
        .getSingle();
    expect(volCount.read<int>('n'), 1);

    // character_fact / event_fact / subplot_fact（v16/v17）可写可读
    await db.customStatement(
      "INSERT INTO character_fact (id, manuscript_id, name) VALUES ('cf1', 'm1', '阿禾')",
    );
    await db.customStatement(
      "INSERT INTO event_fact (id, manuscript_id, name, event_type) VALUES ('ef1', 'm1', '阿禾去金陵', '转折')",
    );
    await db.customStatement(
      "INSERT INTO subplot_fact (id, manuscript_id, name) VALUES ('sf1', 'm1', '钥匙的秘密')",
    );
    final cf = await db
        .customSelect('SELECT COUNT(*) AS n FROM character_fact')
        .getSingle();
    final ef = await db
        .customSelect('SELECT COUNT(*) AS n FROM event_fact')
        .getSingle();
    final sf = await db
        .customSelect('SELECT COUNT(*) AS n FROM subplot_fact')
        .getSingle();
    expect(cf.read<int>('n'), 1);
    expect(ef.read<int>('n'), 1);
    expect(sf.read<int>('n'), 1);

    // outline_entity / outline_impression（v18）可写可读
    await db.customStatement(
      "INSERT INTO outline_entity (id, manuscript_id, entity_type, entity_key) VALUES ('oe1', 'm1', 'character', '王建国')",
    );
    final oe = await db
        .customSelect('SELECT COUNT(*) AS n FROM outline_entity')
        .getSingle();
    expect(oe.read<int>('n'), 1);

    // session_reference 经 v21 重建后支持 'file' 引用类型
    await db.customStatement(
      "INSERT INTO session_reference (id, session_id, ref_type, ref_id, is_primary) VALUES ('sr1', 's1', 'file', 'f1', 0)",
    );
    final sr = await db
        .customSelect("SELECT ref_type FROM session_reference WHERE id = 'sr1'")
        .getSingle();
    expect(sr.read<String>('ref_type'), 'file');
  });
}
