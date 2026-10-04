// ─────────────────────────────────────────────────────────────
// migration_v46_test — ADR-0003 阶段一前置：legacy 症候 ID 归一
//
// 背景：0.3.6 去重（e64096db）是**纯代码重编号、无数据迁移**，
//       库里残留旧 ID。ADR-0003 阶段一要复用 P035/P036/P037，
//       而这三个 ID 本身是 legacy 别名键 ⇒ 残留旧行会被新槽位静默误读。
//       v46 迁移在升级时把存量行按 `kSyndromeMergeMap` **单跳**改写。
//
// 覆盖（含四类「假绿」防线）：
//   #1 可达性：v45 存量库升级后 user_version = kSchemaHead
//   #2 三张表**都**被改写（含 diagnosis_results 的 JSON 内嵌 ID）
//   #3 ★ 单跳契约：结果恰为一次查表值、**未被二次改写**
//      （⚠️ 不是「零 legacy 残留」——单跳下P035→P009 而 P009 自身也是 legacy 键，
//        「零残留」在单跳下不可能成立；强求它就得迭代⇒ 撞环死循环）
//   #3b ★ **ADR-0003 的真正目标**：三个待复用槽位 P035/P036/P037 已腾空
//   #4 teaching_state 的两段式阶段 ID（P0_ENGAGE 等）**不被误伤**
//   #5 平铺映射与 kSyndromeMergeMap 逐条一致（防手抄漂移 → 静默数据损坏）
//   #6 幂等：已是 v46 的库重复打开不报错、数据不变
//
// ⚠️ 为什么 #4 是独立用例：迁移若图省事用 `LIKE 'P0%'` 前缀匹配，
//    会把教学阶段 ID 一并改写⇒ 教学状态机直接错乱。必须单独钉死。
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/database/migration_v46.dart';

import '../../test_support/schema_head.dart';

var _dbSeq = 0;

/// 生成一个**保证全新**的临时库路径。
///
/// ⚠️ 不能只用 `_dbSeq` 递增：它在每次 `flutter test` 进程启动时都从 0 重来，
/// 而 systemTemp 里的旧文件会跨轮次残留 ⇒ 第二次跑就撞
/// `table xxx already exists`（本批实测踩中，6 个用例全灭）。
/// 双保险 = 序号 + 进程启动微秒时间戳，且用前先删。
String _tempPath(String tag) {
  final path =
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'yuesheng_v46_${tag}_${_dbSeq++}_${DateTime.now().microsecondsSinceEpoch}.db';
  final f = File(path);
  if (f.existsSync()) f.deleteSync();
  return path;
}

/// v45 存量库：只建 v46 迁移要碰的三张表 + teaching_state（防误伤对照）。
///
/// 三张表的列按 `tables.dart` 的**全部非空列**给齐 —— 少一列就会在
/// INSERT 时报错，而报错会让「迁移前数据没写进去」这件事被误读成
/// 「迁移把数据删了」。
String createV45LegacyDbFile() {
  final path = _tempPath('v45');
  final db = sqlite3.sqlite3.open(path);
  db.execute('''
    CREATE TABLE active_problem (
      id TEXT PRIMARY KEY,
      session_id TEXT NOT NULL,
      syndrome_id TEXT NOT NULL,
      syndrome_name TEXT NOT NULL DEFAULT '',
      severity TEXT NOT NULL DEFAULT 'L2',
      status TEXT NOT NULL DEFAULT 'active',
      confirmation_status TEXT NOT NULL DEFAULT 'suspected',
      teaching_state TEXT,
      confirmed_at INTEGER,
      evidence_confidence REAL,
      created_at INTEGER NOT NULL DEFAULT 0,
      resolved_at INTEGER,
      updated_at INTEGER
    );
    CREATE TABLE training_results (
      id TEXT PRIMARY KEY,
      session_id TEXT NOT NULL,
      suggestion_id TEXT,
      syndrome_id TEXT NOT NULL,
      task_type TEXT NOT NULL,
      user_content TEXT NOT NULL,
      result TEXT,
      feedback_json TEXT,
      score REAL,
      confidence_rating INTEGER,
      explanation_text TEXT,
      transfer_text TEXT,
      user_rating TEXT,
      created_at INTEGER NOT NULL DEFAULT 0
    );
    CREATE TABLE diagnosis_results (
      id TEXT PRIMARY KEY,
      session_id TEXT NOT NULL,
      message_id TEXT NOT NULL,
      syndromes TEXT NOT NULL DEFAULT '[]',
      suggested_actions TEXT NOT NULL DEFAULT '[]',
      root_cause_analysis TEXT,
      next_focus TEXT,
      feedback_summary TEXT,
      confidence REAL NOT NULL DEFAULT 0.0,
      teaching_progress TEXT,
      target_ref_type TEXT,
      target_ref_id TEXT,
      timestamp INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL DEFAULT 0,
      current_teaching_focus_id TEXT,
      focus_reason TEXT,
      status TEXT NOT NULL DEFAULT 'confirmed'
    );
    CREATE TABLE teaching_state (
      id TEXT PRIMARY KEY,
      session_id TEXT NOT NULL UNIQUE,
      current_phase TEXT NOT NULL DEFAULT 'P0_ENGAGE',
      current_subphase TEXT,
      attitude_level TEXT,
      beginner_level TEXT,
      updated_at INTEGER NOT NULL DEFAULT 0
    );
    CREATE TABLE sessions (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL DEFAULT '',
      created_at INTEGER NOT NULL DEFAULT 0
    );
  ''');

  // ── 存量数据：三个legacy 键 + 一个现行 ID 作对照 ──
  db.execute("INSERT INTO sessions (id) VALUES ('s1')");

  // P035/P036/P037 是 ADR-0003 要复用的三个槽位 ⇒ 必须被改写
  db.execute(
    "INSERT INTO active_problem (id, session_id, syndrome_id, created_at) "
    "VALUES ('ap1', 's1', 'P035', 1)",
  );
  db.execute(
    "INSERT INTO active_problem (id, session_id, syndrome_id, created_at) "
    "VALUES ('ap2', 's1', 'P037', 1)",
  );
  db.execute(
    "INSERT INTO training_results (id, session_id, syndrome_id, task_type, "
    "user_content, created_at) VALUES ('tr1', 's1', 'P036', 'rewrite', 'x', 1)",
  );
  // 现行 ID 对照：P009 也是 legacy 键 ⇒ 单跳会被改写成 P007。
  // 这不是 bug 而是**单跳语义**（见 migration_v46.dart 文件头「不迭代」），
  // 本测试钉住这个行为以防将来被无意改成迭代。
  db.execute(
    "INSERT INTO training_results (id, session_id, syndrome_id, task_type, "
    "user_content, created_at) VALUES ('tr2', 's1', 'P009', 'rewrite', 'x', 1)",
  );

  // JSON 内嵌：一个 legacy + 一个现行
  db.execute(
    r"""INSERT INTO diagnosis_results (id, session_id, message_id, syndromes, created_at)
        VALUES ('dr1', 's1', 'm1',
        '[{"syndrome_id":"P035","name":"对话注水症","severity":"L2","evidence":[],"explanation":"x"}]',
        1)""",
  );
  db.execute(
    r"""INSERT INTO diagnosis_results (id, session_id, message_id, syndromes, created_at)
        VALUES ('dr2', 's1', 'm1',
        '[{"syndrome_id":"P001","name":"信息倾泻症","severity":"L2","evidence":[],"explanation":"x"}]',
        1)""",
  );

  // 防误伤对照：两段式教学阶段 ID（**不是**症候 ID）
  db.execute(
    "INSERT INTO teaching_state (id, session_id, current_phase, updated_at) "
    "VALUES ('ts1', 's1', 'P3_TRAINING', 1)",
  );

  db.execute('PRAGMA user_version = 45');
  db.dispose();
  return path;
}

Future<AppDatabase> _openUpgraded(String tag) async {
  final path = createV45LegacyDbFile();
  final db = AppDatabase.forTesting(NativeDatabase(File(path)));
  // 触发 onUpgrade
  await db.customSelect('PRAGMA user_version').getSingle();
  addTearDown(db.close);
  return db;
}

Future<List<String>> _column(AppDatabase db, String table, String col) async {
  final rows = await db.customSelect('SELECT $col AS v FROM $table').get();
  return rows.map((r) => r.read<String>('v')).toList();
}

void main() {
  test('#1 可达性：v45 存量库升级后 user_version = kSchemaHead', () async {
    final db = await _openUpgraded('t1');
    final v = await db.customSelect('PRAGMA user_version').getSingle();
    expect(v.read<int>('user_version'), kSchemaHead);
  });

  test('#2a active_problems / training_results 的 legacy ID 被单跳改写', () async {
    final db = await _openUpgraded('t2a');

    final ap = await _column(db, 'active_problem', 'syndrome_id');
    // P035 → P009（对话注水症 → 对话疲劳症）
    expect(ap, contains('P009'), reason: 'ap1 的 P035 未被改写');
    // P037 → P026（心理内耗症 → 心理内耗症，唯一语义真冲突槽位）
    expect(ap, contains('P026'), reason: 'ap2 的 P037 未被改写');

    final tr = await _column(db, 'training_results', 'syndrome_id');
    expect(tr, contains('P004'), reason: 'tr1 的 P036 未被改写成 P004');
    // 单跳语义：P009 是 legacy 键（P009→P007），故只跳一次到 P007
    expect(tr, contains('P007'), reason: 'tr2 的 P009 应单跳到 P007');
  });

  test('#2b diagnosis_results 的 JSON 内嵌 ID 也被改写', () async {
    final db = await _openUpgraded('t2b');
    final rows = await db
        .customSelect("SELECT id, syndromes FROM diagnosis_results")
        .get();
    final byId = {
      for (final r in rows) r.read<String>('id'): r.read<String>('syndromes'),
    };

    expect(byId['dr1'], contains('"P009"'), reason: 'dr1 的 P035 未被改写');
    expect(byId['dr1'], isNot(contains('"P035"')), reason: 'dr1 仍残留 P035');
    expect(
      byId['dr1'],
      contains('对话注水症'),
      reason: '⚠️ name 字段是**历史快照**、不是 ID，本迁移不改它（改了即篡改诊断记录）',
    );

    expect(byId['dr2'], contains('"P002"'), reason: 'dr2 的 P001 应单跳到 P002');
  });

  test('#3 ★ 单跳：结果等于 merge map 的一次查表值，未被二次改写', () async {
    final db = await _openUpgraded('t3');
    // ★ 单跳语义下，「迁移后查不出任何 legacy 键」**必然不成立**：
    //   P035 → P009，而 P009 自身也是 legacy 键（→ P007）。
    // 这不是缺陷，而是「不迭代」的直接后果（migration_v46.dart 文件头已明写
    // 「链上有环、迭代会死循环」）。若强求「零残留」就必须迭代 ⇒ 死循环。
    // 正确判据 = 结果恰为**一次**查表值，且**未**被二次改写。
    const m = {
      'P035': 'P009',
      'P037': 'P026',
      'P009': 'P007',
      'P036': 'P004',
      'P001': 'P002',
    };

    final ap = await _column(db, 'active_problem', 'syndrome_id');
    expect(ap, contains(m['P035']), reason: 'ap1 的 P035 应单跳到 P009');
    expect(ap, contains(m['P037']), reason: 'ap2 的 P037 应单跳到 P026');
    expect(
      ap,
      isNot(contains(m['P009'])),
      reason: '★ 若P035 变成 P007 ⇒ 被二次改写（迭代）了，违反单跳契约',
    );

    final tr = await _column(db, 'training_results', 'syndrome_id');
    expect(tr, contains(m['P036']), reason: 'tr1 的 P036 应单跳到 P004');
    expect(tr, contains(m['P009']), reason: 'tr2 的 P009 应单跳到 P007');

    // JSON 列同理：dr1 的 P035 → P009（而非 P007）
    final rows = await db
        .customSelect("SELECT syndromes FROM diagnosis_results WHERE id='dr1'")
        .get();
    final json = rows.single.read<String>('syndromes');
    expect(json, contains('"P009"'));
    expect(json, isNot(contains('"P007"')));
  });

  test('#3b ★ ADR-0003 目标达成：三个待复用槽位已腾空', () async {
    final db = await _openUpgraded('t3b');

    // ADR-0003 阶段一要复用 P035/P036/P037。判定「可复用」的唯一充分条件：
    // 三张表里**都不存在**这三个 ID 的行（否则残留旧行会被新槽位静默误读）。
    for (final row in await _column(db, 'active_problem', 'syndrome_id')) {
      expect(
        const {'P035', 'P036', 'P037'}.contains(row),
        isFalse,
        reason: 'active_problem 仍存 $row ⇒ 该槽位不可复用',
      );
    }
    for (final row in await _column(db, 'training_results', 'syndrome_id')) {
      expect(
        const {'P035', 'P036', 'P037'}.contains(row),
        isFalse,
        reason: 'training_results 仍存 $row ⇒ 该槽位不可复用',
      );
    }
    for (final row in await _column(db, 'diagnosis_results', 'syndromes')) {
      for (final slot in const ['P035', 'P036', 'P037']) {
        expect(
          row,
          isNot(contains('"$slot"')),
          reason: 'diagnosis_results 仍内嵌 $slot ⇒ 该槽位不可复用',
        );
      }
    }
  });

  test('#4 ★ teaching_state 的两段式阶段 ID 不被误伤', () async {
    final db = await _openUpgraded('t4');
    final phases = await _column(db, 'teaching_state', 'current_phase');
    expect(
      phases,
      contains('P3_TRAINING'),
      reason: 'P3_TRAINING 被误改 ⇒ 迁移用了 LIKE 前缀匹配而非精确列举',
    );
  });

  test('#4b ★★ 迁移只 UPDATE 目标两表，不越界碰teaching_state', () async {
    // ⚠️ #4 单独跑时**无论迁移怎么写都会绿**——迁移只 UPDATE
    //   `syndrome_id` 这一列，压根碰不到 `teaching_state.current_phase`
    //   ⇒ #4 是「无害但低鉴别力」。
    // 本用例把失败模式换成**真实可达**的那个：三张表循环里误把
    //   teaching_state 也列进来（写成 `SET current_phase = ...`
    //   或把它当 syndrome_id 列去 UPDATE）。
    //
    // ⛔ 曾经的错误前提：本用例原写成「LIKE 前缀匹配会误伤教学阶段 ID」。
    //   实测（变异②）：注入 LIKE 后**测试仍全绿**——因为
    //   `teaching_state.current_phase` 与 `syndrome_id` 是不同列，
    //   前缀匹配**够不着它**。⇒ 该失败模式在当前迁移形态下不可达，
    //   写进测试就是伪断言（比没有测试更坏：它给人「已覆盖」的错觉）。
    //   故改为下面这条真正可达的：越界写 teaching_state。
    final db = await _openUpgraded('t4b');

    // 教学表**只**应有它自己那1 行、且阶段 ID 原样
    final all = await db
        .customSelect('SELECT current_phase FROM teaching_state')
        .get();
    expect(all.length, 1);
    expect(all.single.read<String>('current_phase'), 'P3_TRAINING');

    // 全表扫一遍：迁移跑完后，任何表里都不该出现「阶段 ID 被当成症候 ID 改写」
    // 的痕迹——即 teaching_state 里不得出现任何 P0xx 三段式。
    for (final r
        in await db
            .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
            .get()) {
      final t = r.read<String>('name');
      if (t == 'teaching_state') {
        final v = await _column(db, t, 'current_phase');
        expect(
          v.every((s) => !RegExp(r'^P\d{3}$').hasMatch(s)),
          isTrue,
          reason: 'teaching_state.current_phase 出现了三段式症候 ID：$v',
        );
      }
    }
  });

  test('#5 平铺映射与 kSyndromeMergeMap 逐条一致（返回不一致项）', () {
    expect(findLegacyMapMismatches(), isEmpty);
  });

  test('#6 幂等：已是 v46 的库重复打开，数据不变', () async {
    final path = createV45LegacyDbFile();
    final db1 = AppDatabase.forTesting(NativeDatabase(File(path)));
    final after1 = await _column(db1, 'active_problem', 'syndrome_id');
    await db1.close();

    final db2 = AppDatabase.forTesting(NativeDatabase(File(path)));
    addTearDown(db2.close);
    final v = await db2.customSelect('PRAGMA user_version').getSingle();
    expect(v.read<int>('user_version'), kSchemaHead);

    final after2 = await _column(db2, 'active_problem', 'syndrome_id');
    expect(after2, after1, reason: '重复打开改动了数据 ⇒ 迁移非幂等');
  });

  test('#7 ★★★ 三张目标表全不存在 → 迁移不抛错（表存在守卫）', () async {
    // ★ 这条是**补自己的漏**。守卫当初是被**别人家的** 18 个历史 migration
    //   测试抓住的（变异④：去掉守卫 → 40 个 error），而本文件 10 个用例
    //   **一个都没覆盖它** ⇒ 一旦那些历史测试被删/ 改名，这个守卫就失去保护。
    //   守卫属于本迁移，就该有本迁移自己的断言。
    //
    // 存量库形态 = 照抄 `migration_v39_test` 的「最小 schema」范式：
    // 只建 v45 版本真正存在过的少量表，**故意不含** v46 要碰的三张表。
    final path = _tempPath('v45_min');
    final raw = sqlite3.sqlite3.open(path);
    raw.execute('''
    CREATE TABLE sessions (
      id TEXT PRIMARY KEY,
      user_id TEXT,
      started_at INTEGER NOT NULL DEFAULT 0,
      last_active_at INTEGER NOT NULL DEFAULT 0,
      pinned INTEGER NOT NULL DEFAULT 0
    );
    CREATE TABLE teaching_state (
      id TEXT PRIMARY KEY,
      session_id TEXT NOT NULL UNIQUE,
      current_phase TEXT NOT NULL DEFAULT 'P0_ENGAGE',
      current_subphase TEXT,
      attitude_level TEXT,
      beginner_level TEXT,
      updated_at INTEGER NOT NULL DEFAULT 0
    );
  ''');
    raw.execute('PRAGMA user_version = 45');
    raw.dispose();

    final db = AppDatabase.forTesting(NativeDatabase(File(path)));
    addTearDown(db.close);
    // 不抛错就是本用例的全部断言；再验版本推到位（否则每次打开都重跑升级）。
    final v = await db.customSelect('PRAGMA user_version').getSingle();
    expect(v.read<int>('user_version'), kSchemaHead);
  });
}
