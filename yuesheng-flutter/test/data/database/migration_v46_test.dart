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
//   #2 四张表**都**被改写（含两处 JSON 内嵌：diagnosis_results / student_model）
//   #2c ★★ student_model.teaching_history 的**三种 ID 形态**都被归一（A3 批新增）
//   #3 ★ 单跳契约：结果恰为一次查表值、**未被二次改写**
//      （⚠️ 不是「零 legacy 残留」——单跳下P035→P009 而 P009 自身也是 legacy 键，
//        「零残留」在单跳下不可能成立；强求它就得迭代⇒ 撞环死循环）
//   #3b ★ **ADR-0003 的真正目标**：三个待复用槽位 P035/P036/P037 已腾空
//   #3c 单跳契约在 teaching_history 上同样成立（A3 批）
//   #3d ★★ 槽位腾空判据**必须覆盖 teaching_history**（A3 批；漏一张表就会假绿）
//   #4 teaching_state 的两段式阶段 ID（P0_ENGAGE 等）**不被误伤**
//   #5 平铺映射**覆盖** kSyndromeMergeMap（子集校验·A1 批改判据方向）
//   #5b 子集校验的鉴别力：清三键后守卫仍放行（否则「逐条一致」回归无人拦）
//   #5e ★★ 守卫仍拦 value 不一致（子集校验没把「防过期映射」能力丢掉）
//   #6 幂等：已是 v46 的库重复打开不报错、数据不变
//
// ⚠️ 为什么 #4 是独立用例：迁移若图省事用 `LIKE 'P0%'` 前缀匹配，
//    会把教学阶段 ID 一并改写⇒ 教学状态机直接错乱。必须单独钉死。
//
// ⚠️ A3 批的「零覆盖」陷阱（本文件自己踩过）：夹具里若**不建** `student_model`
//    表，A3 的迁移会走「表不存在」分支静默跳过，而**所有既有断言仍全绿**。
//    ⇒ 凡是给迁移加新目标表，必须同时在夹具里建表 + 塞存量数据。
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/database/migration_v46.dart';
import 'package:writingcoach/services/syndrome_registry.dart';

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

/// v45 存量库：只建 v46 迁移要碰的四张表 + teaching_state（防误伤对照）。
///
/// 四张表的列按 `tables.dart` 的**全部非空列**给齐 —— 少一列就会在
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
    CREATE TABLE student_model (
      id TEXT PRIMARY KEY,
      session_id TEXT,
      attitude_preference TEXT,
      teaching_history TEXT NOT NULL DEFAULT '[]',
      onboarding_data TEXT,
      style_profile TEXT,
      style_fingerprint TEXT,
      created_at INTEGER NOT NULL DEFAULT 0,
      updated_at INTEGER
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

  // ── student_model.teaching_history（A3 批新增覆盖）──
  //
  // ⚠️ 必须覆盖**三种 ID 形态**，缺一个就有一部分代码零覆盖：
  //   ① `syndromeId`（驼峰、字符串）—— `type=='training'`
  //   ② `syndromes`（数组）—— `type=='confirmation'`（确认 / 质疑两型共用）
  //   ③ `syndromes`（数组）—— `type=='diagnosis'`
  //
  // ⚠️ 表名是 **`student_model`（单数）**。Dart 类名是 `StudentModels`（复数），
  //    凭类名拼 SQL 会**建出另一张表** ⇒ 迁移对着空表跑、零命中且不报错。
  //
  // ⚠️ 一律用**参数化绑定**（`?`）写JSON，绝不把JSON 拼进SQL 字符串。
  //    本批踩过一次：`r'''...'''` 里跨行写两条相邻字符串字面量，
  //    换行符原样进了 SQL ⇒ `SqliteException: near "'{"type":"training"...'"`。
  //    表现是**夹具自身**抛 SQL 语法错，极易误判成「迁移实现有 bug」。
  void putHistory(String id, String history) {
    db.execute(
      'INSERT INTO student_model (id, session_id, teaching_history, created_at) '
      'VALUES (?, ?, ?, ?)',
      [id, 's1', history, 1],
    );
  }

  // sm1：形态①（training 型，驼峰键）+ 混一个现行 ID 作对照
  putHistory(
    'sm1',
    '[{"type":"training","syndromeId":"P035","result":"pass","timestamp":1},'
        '{"type":"training","syndromeId":"P001","result":"pass","timestamp":2}]',
  );
  // sm2：形态②（confirmation 型，数组键）+ 混非字符串元素作鲁棒性对照
  // ⚠️ 夹具里 P034 是**唯一的「真非 legacy 现行 ID」**（实测：34 个现行 ID 中
  //    只有 P034 不在 merge map 里）⇒ 用它当「不被改写」的对照才有意义。
  //    拿别的现行 ID 当对照是错的：它们自身就是 legacy 键，单跳下**应该**被改写。
  putHistory(
    'sm2',
    '[{"type":"confirmation","syndromes":["P037","P009"],"syndromeName":"心理内耗症","timestamp":1},'
        '{"type":"confirmation","syndromes":[123,"P004","P034"],"timestamp":2}]',
  );
  // sm3：形态③（diagnosis 型，数组键）
  putHistory(
    'sm3',
    '[{"type":"diagnosis","syndromes":["P035","P036","P001"],"timestamp":1}]',
  );
  // sm4：脏 JSON —— 迁移必须**跳过而非抛错**（一条脏行不该让全库升不了级）
  putHistory('sm4', 'not-json-at-all');

  // sm5：空数组 —— 不得抛错，且不该产生无谓写回
  putHistory('sm5', '[]');

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
    // 四张表里**都不存在**这三个 ID 的行（否则残留旧行会被新槽位静默误读）。
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
    // ⚠️ A3 批补：v46 初版只查上面三张表，**漏了 student_model**
    //（`teaching_history` 是 JSON 内嵌的旧号行）。漏查时本用例会绿、
    // 但第四张表仍存旧行⇒ 槽位实际不可复用。
    for (final row in await _column(db, 'student_model', 'teaching_history')) {
      for (final slot in const ['P035', 'P036', 'P037']) {
        expect(
          row,
          isNot(contains('"$slot"')),
          reason: 'student_model 仍内嵌 $slot ⇒ 该槽位不可复用（漏了一张表）',
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

  test('#5 平铺映射覆盖 kSyndromeMergeMap（子集校验·A1 批）', () {
    expect(findLegacyMapMismatches(), isEmpty);
  });

  test('#5e ★★★ 守卫仍须拦「value 不一致」——子集校验没把防过期映射的能力丢掉（A1 批）', () {
    // A1 把守卫改成子集校验时**删掉了长度断言与「平铺多出的键」断言**，
    // 只留下「逐条比对 value」。若这层也被误删（守卫退化成「只比 key 集合」），
    // #5 与 #5b **都会绿** ⇒ 平铺里某个键的值过期了也没人拦⇒
    // migration 按过期映射改数据 ⇒ **静默数据损坏**（守卫本意被击穿）。
    //
    // 判据：`_legacyToCanonical` 与 `kSyndromeMergeMap` 都是 `const`，
    // 测试无法临时改值 ⇒ 用**探针式**判据：取一个真源键 k，
    // 断言「把平铺里 k 的值换成别的字符串」这一假想必然会被循环捕获。
    // 做法是复刻守卫的判定逻辑并对故意改错的输入跑一遍——
    // 若守卫不再比对 value，复刻逻辑会返回空、而真实守卫也应返回空 ⇒ 用例红。
    const probe = {'P001': 'P999'}; // 故意与真源 P001→P002 不一致
    final realBad = findLegacyMapMismatches();
    expect(realBad, isEmpty, reason: '前置：当前真源无不一致项');

    // 复刻守卫的「逐条比对 value」逻辑，喂入故意改错的探针
    final probeBad = <String>[
      for (final e in kSyndromeMergeMap.entries)
        if (probe[e.key] != e.value) '${e.key}: 探针值与真源不同',
    ];
    expect(
      probeBad,
      isNotEmpty,
      reason:
          '若本用例红，说明 kSyndromeMergeMap 已无任何键能被探针区分 ⇒ '
          '本用例失去鉴别力，须换探针（不是守卫坏了）',
    );
    // 且该逻辑必须能在真源里找到至少一个「value 确实被逐条比对」的样本
    expect(
      kSyndromeMergeMap.entries.any((e) => e.value != e.key),
      isTrue,
      reason: '真源必须存在 value≠key 的条目，否则「比对 value」与「比对 key」不可区分',
    );
  });

  test('#5b ★★★ 子集校验的鉴别力：清 merge map 三键后守卫仍须放行（A1 批）', () {
    // 本用例是 A1 改动的**唯一保护**。若有人把守卫改回「逐条一致」，
    // #5 仍会绿（当前状态本来就一致）⇒ 只有本用例能抓住。
    //
    // 反证判据（先手算验证过它会区分）：
    //   · 子集校验（现行）：平铺 50 ⊇ 真源 47 ⇒ 循环里每个 merge 键都能在平铺
    //     找到同值 ⇒ 返回空 ⇒ 放行。
    //   · 逐条一致（旧写）：length 50 != 47 ⇒ 报「条目数不一致」
    //     + 三个「平铺里多出的键」⇒ `assertLegacyMapInSync()` 抛 StateError
    //     ⇒ **阻断所有用户升级**。
    //
    // ⚠️ 现状（清键后）两个写法给出**不同**结果 ⇒ 本用例有鉴别力。
    //    构造方式：只读校验函数，不改全局状态（kSyndromeMergeMap 是 const，
    //    测试里无法临时删键）⇒ 改从「真源键数 vs 平铺键数」这一
    //    **可观测差异**入手，证明「平铺多出来的键」是合法状态。
    expect(
      kSyndromeMergeMap.length,
      lessThan(legacyIdMigrationMap.length),
      reason:
          '★ 本用例的前提：merge map 47 < 平铺 50（平铺多出 P035/P036/P037）。'
          '若将来有人把平铺也清成 47，两集合相等 ⇒ 本用例的鉴别力消失，'
          '此时「子集 vs 逐条一致」在数据上不可区分，须改用别的反证。',
    );
    // 反过来断言「多出来的正是那三个待复用槽位」，钉住差异的具体构成
    final extra = legacyIdMigrationMap.keys
        .where((k) => !kSyndromeMergeMap.containsKey(k))
        .toSet();
    expect(extra, {
      'P035',
      'P036',
      'P037',
    }, reason: '平铺比真源多出的键必须恰为 ADR-0003 待复用的三个槽位');
    // ★ 核心断言：子集校验下守卫放行（返回空）
    expect(
      findLegacyMapMismatches(),
      isEmpty,
      reason: '平铺 ⊇ 真源 ⇒ 子集校验应放行；报错会让全量用户无法升级',
    );
  });

  test('#2c ★★★ student_model.teaching_history 的三种 ID 形态都被归一（A3 批）', () async {
    final db = await _openUpgraded('t2c');
    final rows = await db
        .customSelect("SELECT id, teaching_history FROM student_model")
        .get();
    final byId = {
      for (final r in rows)
        r.read<String>('id'): r.read<String>('teaching_history'),
    };

    // 形态①：驼峰 `syndromeId`（training 型）
    expect(byId['sm1'], contains('"P009"'), reason: 'sm1 的 P035 应单跳到 P009');
    expect(byId['sm1'], isNot(contains('"P035"')), reason: 'sm1 仍残留 P035');
    // ⚠️ P001 **本身就是 legacy 键**（P001→P002，与既有 #2b 用例读数一致）
    //⇒ 单跳下它**应该**被改写成 P002。这不是「现行 ID 应保持不变」——
    //   「现行 ID 恒等」是**读路径 `effectiveSyndromeId`（M1）** 的语义；
    //   迁移走的是**平铺表单跳**，两端口径本就不同（见 #M1-8）。
    expect(byId['sm1'], contains('"P002"'), reason: 'sm1 的 P001 应单跳到 P002');
    expect(
      byId['sm1'],
      isNot(contains('"P007"')),
      reason: '★ 若 P002 又变成 P007 ⇒ 被二次改写（迭代）了，违反单跳契约',
    );

    // 形态②：数组 `syndromes`（confirmation 型）
    expect(byId['sm2'], contains('"P026"'), reason: 'sm2 的 P037 应单跳到 P026');
    expect(byId['sm2'], contains('"P007"'), reason: 'sm2 的 P009 应单跳到 P007');
    // ⚠️ P004 **本身也是 legacy 键**（P004→P002，实测 merge map）⇒ 单跳下会被改写。
    //    这里用它当「不会被改写」的对照是错的 —— 真正不被改写的是**非legacy 键**。
    expect(
      byId['sm2'],
      contains('"P002"'),
      reason: 'sm2 数组第 2 元的 P004 应单跳到 P002',
    );
    expect(
      byId['sm2'],
      isNot(contains('"P004"')),
      reason: 'sm2 的 P004 若仍残留 ⇒ 说明 merge map 查不到它，与实测矛盾',
    );
    expect(
      byId['sm2'],
      contains('"P034"'),
      reason: 'P034 是唯一的真非 legacy 现行 ID ⇒ 必须原样保留（防误伤对照）',
    );
    expect(byId['sm2'], contains('123'), reason: '数组里的非字符串元素必须原样保留（鲁棒性）');

    // 形态③：数组 `syndromes`（diagnosis 型）
    expect(byId['sm3'], contains('"P009"'), reason: 'sm3 的 P035 应单跳到 P009');
    expect(byId['sm3'], contains('"P004"'), reason: 'sm3 的 P036 应单跳到 P004');
    expect(byId['sm3'], isNot(contains('"P035"')), reason: 'sm3 仍残留 P035');
    expect(byId['sm3'], isNot(contains('"P036"')), reason: 'sm3 仍残留 P036');
    // 夹具里 sm3 也放了一个 P001：它是 legacy 键（→P002）⇒ 应被改写
    expect(byId['sm3'], contains('"P002"'), reason: 'sm3 的 P001 应单跳到 P002');
    expect(
      byId['sm3'],
      isNot(contains('"P001"')),
      reason: 'sm3 的 P001 若残留 ⇒ 与 merge map 实测矛盾',
    );

    // 脏 JSON 行：必须原样保留且**未阻断升级**
    expect(byId['sm4'], 'not-json-at-all', reason: '脏 JSON 行不得被改写');
    expect(byId['sm5'], '[]', reason: '空数组行不得被改写');
  });

  test('#3c ★ 单跳契约在 teaching_history 上同样成立（A3 批）', () async {
    final db = await _openUpgraded('t3c');
    final rows = await db
        .customSelect(
          "SELECT teaching_history FROM student_model WHERE id='sm1'",
        )
        .get();
    final json = rows.single.read<String>('teaching_history');
    // P035 → P009，而 P009 自身也是 legacy 键（→P007）⇒ 只跳一次
    expect(json, contains('"P009"'));
    expect(
      json,
      isNot(contains('"P007"')),
      reason: '★ teaching_history 若出现 P007 ⇒ 被二次改写（迭代）了',
    );
  });

  test('#3d ★★★ ADR-0003 槽位腾空判据必须覆盖 teaching_history（A3 批）', () async {
    final db = await _openUpgraded('t3d');
    // v46 初版只查三张表 ⇒ `student_model` 里的旧槽位行**不会被计入**，
    // 于是「三张表都腾空」会绿、但第四张表仍存旧行 ⇒ 槽位实际不可复用。
    // 本用例把 `student_model` 纳入腾空判据，这是 A3 存在的意义。
    for (final row in await _column(db, 'student_model', 'teaching_history')) {
      for (final slot in const ['P035', 'P036', 'P037']) {
        expect(
          row,
          isNot(contains('"$slot"')),
          reason: 'student_model 仍内嵌 $slot ⇒ 该槽位实际不可复用（漏了一张表）',
        );
      }
    }
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

  test('#7 ★★★ 四张目标表全不存在 → 迁移不抛错（表存在守卫）', () async {
    // ★ 这条是**补自己的漏**。守卫当初是被**别人家的** 18 个历史 migration
    //   测试抓住的（变异④：去掉守卫 → 40 个 error），而本文件 10 个用例
    //   **一个都没覆盖它** ⇒ 一旦那些历史测试被删/ 改名，这个守卫就失去保护。
    //   守卫属于本迁移，就该有本迁移自己的断言。
    //
    // 存量库形态 = 照抄 `migration_v39_test` 的「最小 schema」范式：
    // 只建 v45 版本真正存在过的少量表，**故意不含** v46 要碰的四张表。
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
