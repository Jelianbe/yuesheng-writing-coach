// ─────────────────────────────────────────────────────────────
// migration_v46_test — **v46 迁移已退役（2026-10-05 · 层 2 单轨收口批）**
//
// ── 本文件现在的身份 ──
//
//   它**不再测试 v46 迁移**，而是测试「v46 迁移**没有**被执行」这件事。
//   这是一次**断言方向的整体反转**，不是把断言改弱：
//
//     原方向：升级后 P035 被改写成 P009 ⇒ 期望为真
//     现方向：升级后 P035 **原样保留**   ⇒ 期望为真
//
//   ★ 反转后的用例是**退役决策的机器执行点**：若有人把 v46 调用点
//     加回 `database.dart` 的 `onUpgrade`，本文件会立刻变红。
//     换言之，这 12 条从「保护一个有害行为」变成了「挡住数据损坏复活」。
//
// ── 为什么必须反转（而不是删掉）──
//
//   0.3.6 去重（e64096db）是纯代码重编号、无数据迁移 ⇒ 库里残留旧 ID。
//   v46 迁移原本要按 `_legacyToCanonical` 把它们单跳改写。**但那份平铺表
//   含有 `P035→P009` / `P036→P004` / `P037→P026` 三条**，而这三个号
//   如今是**现行注册表实体**（撞文同质化症 / 细节失真症 / 故事核缺失症）。
//   ⇒ 执行 v46 会把存量库里**任何** `P035` 行改写成「对话疲劳症」——
//     改写后 ID 合法、有名字、能渲染 ⇒ **最隐蔽的数据损坏**。
//
//   v46 从未在任何装机包上跑过（实测 `git log 8a629c4e..HEAD -- pubspec.yaml`
//   零命中 ⇒ v46 提交晚于 0.4.1 版本 bump，当前 `0.4.1+2013` 包不含它），
//   加上本项目是单机离线 App、无对外接口、无审计义务 ⇒ 不做自动迁移，
//   用户侧处置为**手动重装**。完整论证见 `.ai/DECISIONS.md §4-167`。
//
// ── 当前覆盖清单（12 条）──
//
//   仍为真、原样保留（与「迁移是否跑」无关的独立性质）：
//     #1  可达性：v45 存量库升级后 user_version = kSchemaHead
//     #4  teaching_state 的两段式阶段 ID（P0_ENGAGE 等）不被误伤
//     #4b 升级只碰目标表，不越界碰 teaching_state
//     #6  幂等：重复打开数据不变
//     #7  四张目标表全不存在 → 升级不抛错（表存在守卫）
//
//   ★ 已反转为「原样保留」（退役决策的执行点）：
//     #2a  active_problem / training_results 的 legacy ID 原样保留
//     #2b  diagnosis_results 的 JSON 内嵌 ID 原样保留
//     #2c  student_model.teaching_history 的**三种 ID 形态**都原样保留
//          （★ 覆盖面不变：驼峰键 / confirmation 数组 / diagnosis 数组；
//            这三种形态若被漏改，症状与本用例完全相同 ⇒ 都绿）
//     #3   无任何改写发生（比原「单跳契约」更强：原版只查「没多跳」，
//          本版查「一个字节都没动」）
//     #3b  ★★ 三号**不被腾空** —— 它们如今是现行实体，槽位已被合法占用。
//          ← 这是本批最关键的一处方向修正：原用例把「三个待复用槽位已腾空」
//            当作期望行为，而达成它**只能**靠 v46 改写 ⇒ 原断言在保护
//            有害行为。
//     #3c / #3d  teaching_history 上同样无改写
//
//   已随归一一并退役（原对象已不存在）：
//     #5 / #5b / #5e —— 测的是 `findLegacyMapMismatches` 守卫与
//     `kSyndromeMergeMap` 的子集校验方向。守卫随迁移退役（迁移不执行 ⇒
//     「按过期映射改数据」不可能发生），merge map 已整张删除。
//     残留档表与退役档案的对齐改由 `syndrome_retirement_ledger_test.dart`
//     的 #8 / #6 / #13 承担（v46 留档表仍保留为**决策依据**，运行时零消费）。
//
// ── 两条不能丢的「假绿」防线（仍然成立）──
//
//   ⚠️ #4 的独立性：若将来有人再加 ID 改写逻辑并图省事用 `LIKE 'P0%'`
//      前缀匹配，会把教学阶段 ID 一并改写 ⇒ 教学状态机直接错乱。
//      必须单独钉死。
//   ⚠️ A3 批的「零覆盖」陷阱（本文件自己踩过）：夹具里若**不建**
//      `student_model` 表，改写逻辑会走「表不存在」分支静默跳过，
//      而**所有既有断言仍全绿**。
//      ⇒ 今后若再加 ID 改写逻辑，必须同时在夹具里建表 + 塞存量数据。
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:writingcoach/data/database/database.dart';

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

/// 读某表某行的某列（**按行**判定用）。
///
/// ⚠️ 为什么需要它：判据「表里不得出现 P009」是**错的** ——
///   P009/P004/P026 本身都是现行注册表实体（实测 P009=对话疲劳症、
///   P004=节奏停滞、P026=心理内耗症），它们是 `_legacyToCanonical` 里
///   `P035→P009` 这类映射的**目标号**，完全合法。
///   ⇒ 判据只能按行：夹具塞进行 ap1(P035) 的那一行，其 syndrome_id
///      必须仍是 P035。
Future<String?> _cell(
  AppDatabase db,
  String table,
  String id,
  String col,
) async {
  final rows = await db
      .customSelect(
        'SELECT $col AS v FROM $table WHERE id = ?',
        variables: [Variable.withString(id)],
      )
      .get();
  if (rows.isEmpty) return null;
  return rows.single.read<String>('v');
}

/// 读 `student_model` 某行的 `teaching_history` 原文。
Future<String> _history(AppDatabase db, String id) async {
  final rows = await db
      .customSelect(
        'SELECT teaching_history FROM student_model WHERE id = ?',
        variables: [Variable.withString(id)],
      )
      .get();
  return rows.single.read<String>('teaching_history');
}

void main() {
  test('#1 可达性：v45 存量库升级后 user_version = kSchemaHead', () async {
    final db = await _openUpgraded('t1');
    final v = await db.customSelect('PRAGMA user_version').getSingle();
    expect(v.read<int>('user_version'), kSchemaHead);
  });

  test(
    '#2a ★★★ 反转：升级后 active_problem / training_results 的 legacy ID **原样保留**',
    () async {
      // 【2026-10-05 层 2 单轨收口批 · 断言方向已整体反转】
      //
      //   原用例（'#2a ... 的 legacy ID 被单跳改写'）断言
      //     P035 → P009、P037 → P026、P036 → P004、P009 → P007
      //   在 v46 迁移退役后**必然失败**（迁移不跑 ⇒ 数据原样）。
      //
      //   ★ 反转后的断言不是「把测试改绿」，而是**把测试指向当前正确行为**：
      //     库里那个 `P035` 应当**保持** `P035`（= 现行实体「撞文同质化症」），
      //     **不得**被改写成 `P009`（= 旧实体「对话注水症」的并入目标）。
      //
      //   这条用例现在的身份 = **v46 退役决策的机器执行点**：
      //     变异①：把 `onUpgrade` 里的 v46 调用点加回来 ⇒ 本用例红。
      //     变异②：任何形式的「按 `_legacyToCanonical` 平铺表改写存量行」
      //             ⇒ 本用例红。
      //   ⇒ 谁把数据损坏改回来，谁就被这条挡住。
      //
      //   ⚠️ 数据现状说明：装机会残留旧号行（如某行 `P035` 其实是退役前的
      //     「对话注水症」）。本项目对此的处置是**用户手动重装**（清库），
      //     **不做**自动迁移 —— 理由见 `database.dart` 的「v46 迁移退役说明」。
      //     本用例锁的是「App 侧不再动手」，不是「库里一定干净」。
      final db = await _openUpgraded('t2a');

      final ap = await _column(db, 'active_problem', 'syndrome_id');
      expect(ap, contains('P035'), reason: 'ap1 的 P035 应原样保留');
      expect(ap, contains('P037'), reason: 'ap2 的 P037 应原样保留');
      expect(
        ap,
        isNot(contains('P009')),
        reason:
            '★ 若 P035 变成 P009 ⇒ v46 迁移（或任何按平铺表改写的逻辑）'
            '又跑起来了 ⇒ 撞文同质化症的历史数据被静默改成对话疲劳症。'
            '这是本用例存在的**唯一**理由。',
      );
      expect(
        ap,
        isNot(contains('P026')),
        reason: '★ 若 P037 变成 P026 ⇒ 同上（故事核缺失症 → 心理内耗症）',
      );

      final tr = await _column(db, 'training_results', 'syndrome_id');
      expect(tr, contains('P036'), reason: 'tr1 的 P036 应原样保留');
      expect(tr, contains('P009'), reason: 'tr2 的 P009 应原样保留（它本就是现行 ID）');
      expect(
        tr,
        isNot(contains('P004')),
        reason: '★ 若 P036 变成 P004 ⇒ 同上（细节失真症 → 流水账叙述症）',
      );
      expect(
        tr,
        isNot(contains('P007')),
        reason: '★ 若 P009 变成 P007 ⇒ 单跳改写又跑起来了（P009 是真现行 ID）',
      );
    },
  );

  test('#2b ★★★ 反转：diagnosis_results 的 JSON 内嵌 ID **原样保留**', () async {
    // 【2026-10-05 层 2 单轨收口批 · 断言方向已反转，理由同 #2a】
    final db = await _openUpgraded('t2b');
    final rows = await db
        .customSelect("SELECT id, syndromes FROM diagnosis_results")
        .get();
    final byId = {
      for (final r in rows) r.read<String>('id'): r.read<String>('syndromes'),
    };

    expect(byId['dr1'], contains('"P035"'), reason: 'dr1 的 P035 应原样保留');
    expect(
      byId['dr1'],
      isNot(contains('"P009"')),
      reason: '★ 若 dr1 的 P035 变成 P009 ⇒ JSON 内嵌改写又跑起来了',
    );
    // name 字段是**历史快照**，任何情况下都不该被改（改了即篡改诊断记录）
    expect(
      byId['dr1'],
      contains('对话注水症'),
      reason: '⚠️ name 字段是历史快照，任何迁移都不得改它（改了即篡改诊断记录）',
    );

    expect(byId['dr2'], contains('"P001"'), reason: 'dr2 的 P001 应原样保留');
    expect(
      byId['dr2'],
      isNot(contains('"P002"')),
      reason: '★ 若 P001 变成 P002 ⇒ 改写又跑起来了（P001 是真现行 ID）',
    );
  });

  test('#3 ★★★ 反转：夹具各行的 syndrome_id 原样保留（按行判定，不按集合）', () async {
    // 【2026-10-05 层 2 单轨收口批 · 断言方向已反转】
    //
    //   原用例「单跳契约：结果等于 merge map 的一次查表值，未被二次改写」
    //   守的是「迁移按单跳语义改写、但不迭代」。迁移退役后，
    //   「单跳 / 不迭代」这个课题**整体消失**（没有改写，就无所谓跳几次）。
    //
    //   ⚠️ **判据方向的关键教训（本用例第二版才想对）**：
    //     第一版反转写成「表里不得出现 P009 / P004 / P026」——**这是错的**。
    //     实测这三个号**全都是现行注册表实体**：
    //       P004=节奏停滞 · P009=对话疲劳症 · P026=心理内耗症
    //     它们是 `_legacyToCanonical` 里 `P035→P009` 这类映射的**目标号**，
    //     本身完全合法；夹具 sm2 合法地塞了它们作对照行
    //     （原用例注释早就写过这条：「P004 本身也是 legacy 键，
    //     用它当『不会被改写』的对照是错的」——我第一版把这条忘了）。
    //     ⇒ **判据只能按行判定，不能按集合判定。**
    //
    //   本用例现在守的命题：升级路径对**每一行**都是恒等变换。
    //   比原版更强：原版只查「没多跳」，本版逐行查「一个字节都没动」。
    final db = await _openUpgraded('t3');

    // 按行判定：每行的 syndrome_id 必须仍是夹具塞进去的那个号
    expect(
      await _cell(db, 'active_problem', 'ap1', 'syndrome_id'),
      'P035',
      reason: '★ ap1 的 P035 若变成 P009 ⇒ 单跳改写复活（撞文同质化症→对话疲劳症）',
    );
    expect(
      await _cell(db, 'active_problem', 'ap2', 'syndrome_id'),
      'P037',
      reason: '★ ap2 的 P037 若变成 P026 ⇒ 单跳改写复活（故事核缺失症→心理内耗症）',
    );
    expect(
      await _cell(db, 'training_results', 'tr1', 'syndrome_id'),
      'P036',
      reason: '★ tr1 的 P036 若变成 P004 ⇒ 单跳改写复活（细节失真症→节奏停滞）',
    );
    expect(
      await _cell(db, 'training_results', 'tr2', 'syndrome_id'),
      'P009',
      reason: '★ tr2 的 P009 若变成 P007 ⇒ 改写复活（P009 本身是现行实体）',
    );

    // JSON 内嵌同理：dr1 的内嵌 ID 必须是 P035
    final json =
        (await db
                .customSelect(
                  "SELECT syndromes FROM diagnosis_results WHERE id='dr1'",
                )
                .get())
            .single
            .read<String>('syndromes');
    expect(json, contains('"P035"'), reason: 'dr1 内嵌 ID 应仍是 P035');
    expect(
      json,
      isNot(contains('"P009"')),
      reason: '★ dr1 内嵌出现 P009 ⇒ JSON 路径的改写复活',
    );
  });

  test('#3b ★★★ 反转：三号不被「腾空」——按行判定，槽位已被合法占用', () async {
    // 【2026-10-05 层 2 单轨收口批 · ★ 本用例方向必须反转 ★】
    //
    //   ⚠️ 本批**最关键**的一处测试方向修正。
    //
    //   原用例「ADR-0003 目标达成：三个待复用槽位已腾空」断言四张表里
    //   **都不存在** P035/P036/P037 的行，并把它当作**期望行为**。
    //   ★ 原断言在**保护一个有害行为**：要让 P035 在库里消失，
    //     唯一手段就是 v46 单跳改写；而它的实际后果是把「撞文同质化症」
    //     的历史数据改成「对话疲劳症」——改写后 ID 合法、有名字、能渲染
    //     ⇒ **最隐蔽的数据损坏**。
    //
    //   反转后守的命题：单轨下 `P035` 已是**现行注册表实体**，
    //   它的行**就该**留在库里，且不得被改成任何别的东西。
    //   ⇒ 本用例现在是**挡住 v46 复活的第一道门**。
    //
    //   ⚠️ 判据形态：按**行**判定（见 #3 的教训）——不能写
    //     「表里不得出现 P009/P004/P026」，因为它们**本身是现行实体**
    //     （实测 P009=对话疲劳症、P004=节奏停滞、P026=心理内耗症）。
    final db = await _openUpgraded('t3b');

    // ① 三号作为「现行实体」的行仍在（夹具塞的就是它们）
    expect(
      await _cell(db, 'active_problem', 'ap1', 'syndrome_id'),
      'P035',
      reason: 'ap1 的 P035 行应原样存在（P035 现为现行实体，不是待腾空槽位）',
    );
    expect(
      await _cell(db, 'active_problem', 'ap2', 'syndrome_id'),
      'P037',
      reason: 'ap2 的 P037 行应原样存在',
    );
    expect(
      await _cell(db, 'training_results', 'tr1', 'syndrome_id'),
      'P036',
      reason: 'tr1 的 P036 行应原样存在',
    );

    // ② ★ 反转的核心：夹具的 dr1 内嵌 ID 不得被改成旧映射的目标号
    final dr1 =
        (await db
                .customSelect(
                  "SELECT syndromes FROM diagnosis_results WHERE id='dr1'",
                )
                .get())
            .single
            .read<String>('syndromes');
    expect(dr1, contains('"P035"'), reason: 'dr1 内嵌 ID 应仍是 P035');
    expect(
      dr1,
      isNot(contains('"P009"')),
      reason: '★ dr1 内嵌出现 P009 ⇒ 撞文同质化症的历史数据被改写成对话疲劳症',
    );

    // ⚠️ teaching_history 这一格在原用例里是 A3 批的**唯一存在理由**
    //   （「漏一张表就会假绿」）。反转后**仍要查**，但按 sm1 行判定：
    //   sm1 的内嵌 ID 应仍是 P035 / P001，而不是变成 P009 / P002。
    final sm1 =
        (await db
                .customSelect(
                  "SELECT teaching_history FROM student_model WHERE id='sm1'",
                )
                .get())
            .single
            .read<String>('teaching_history');
    expect(sm1, contains('"P035"'), reason: 'sm1 内嵌 P035 应原样保留');
    expect(
      sm1,
      isNot(contains('"P009"')),
      reason: '★ sm1 出现 P009 ⇒ 驼峰键路径被改写（这条路径最易漏）',
    );
    expect(
      sm1,
      isNot(contains('"P002"')),
      reason: '★ sm1 出现 P002 ⇒ P001 被改写（P001 是真现行 ID）',
    );

    // 正对照：sm2 里合法塞了 P009 / P004 作为现行实体对照行，
    // 它们**必须仍在** —— 这一条同时钉住「判据按行不按集合」这件事本身：
    // 若有人把判据误写成「表里不得有 P009」，本对照会与他冲突。
    final sm2 =
        (await db
                .customSelect(
                  "SELECT teaching_history FROM student_model WHERE id='sm2'",
                )
                .get())
            .single
            .read<String>('teaching_history');
    expect(
      sm2,
      contains('"P009"'),
      reason:
          'sm2 的 P009 是**合法现行实体**（对话疲劳症）对照行，必须原样保留。'
          '本条是「判据按行不按集合」的正对照：若有人把判据写成'
          '「表里不得出现 P009」，本条与下面的禁改写断言会互相打架。',
    );
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

  test(
    '#2c ★★★ 反转：student_model.teaching_history 的三种 ID 形态都**原样保留**',
    () async {
      // 【2026-10-05 层 2 单轨收口批 · 断言方向已反转】
      //
      //   ⚠️ 本用例原版有一个极有价值的性质，**反转后必须保留**：
      //     它是唯一覆盖 teaching_history **三种 ID 形态**的用例 ——
      //       ① `syndromeId`（驼峰、字符串）—— type=='training'
      //       ② `syndromes`（数组）—— type=='confirmation'
      //       ③ `syndromes`（数组）—— type=='diagnosis'
      //     若这三条形态被漏改，症状与本用例**完全相同**（都绿）——
      //     这正是它存在的意义。反转只改断言方向，不动覆盖面。
      final db = await _openUpgraded('t2c');
      final rows = await db
          .customSelect('SELECT id, teaching_history FROM student_model')
          .get();
      final byId = {
        for (final r in rows)
          r.read<String>('id'): r.read<String>('teaching_history'),
      };

      // 形态①：驼峰 `syndromeId`（training 型）
      expect(byId['sm1'], contains('"P035"'), reason: '形态① sm1 的 P035 应原样保留');
      expect(byId['sm1'], contains('"P001"'), reason: '形态① sm1 的 P001 应原样保留');
      expect(
        byId['sm1'],
        isNot(contains('"P009"')),
        reason: '★ 形态① sm1 出现 P009 ⇒ 驼峰键被改写（这条路径最容易漏）',
      );
      expect(
        byId['sm1'],
        isNot(contains('"P002"')),
        reason: '★ 形态① sm1 出现 P002 ⇒ P001 被改写',
      );

      // 形态②：数组 `syndromes`（confirmation 型）
      expect(byId['sm2'], contains('"P037"'), reason: '形态② sm2 的 P037 应原样保留');
      expect(byId['sm2'], contains('"P009"'), reason: '形态② sm2 的 P009 应原样保留');
      expect(byId['sm2'], contains('"P004"'), reason: '形态② sm2 的 P004 应原样保留');
      expect(byId['sm2'], contains('"P034"'), reason: '形态② sm2 的 P034 应原样保留');
      expect(
        byId['sm2'],
        isNot(contains('"P026"')),
        reason: '★ 形态② sm2 出现 P026 ⇒ 数组元素被改写（P037→P026）',
      );
      expect(
        byId['sm2'],
        isNot(contains('"P007"')),
        reason: '★ 形态② sm2 出现 P007 ⇒ 数组元素被改写（P009→P007）',
      );
      expect(byId['sm2'], contains('123'), reason: '数组里的非字符串元素必须原样保留（鲁棒性）');

      // 形态③：数组 `syndromes`（diagnosis 型）
      expect(byId['sm3'], contains('"P035"'), reason: '形态③ sm3 的 P035 应原样保留');
      expect(byId['sm3'], contains('"P036"'), reason: '形态③ sm3 的 P036 应原样保留');
      expect(byId['sm3'], contains('"P001"'), reason: '形态③ sm3 的 P001 应原样保留');
      expect(
        byId['sm3'],
        isNot(contains('"P009"')),
        reason: '★ 形态③ sm3 出现 P009 ⇒ 数组元素被改写',
      );
      expect(
        byId['sm3'],
        isNot(contains('"P004"')),
        reason: '★ 形态③ sm3 出现 P004 ⇒ 数组元素被改写',
      );
      expect(
        byId['sm3'],
        isNot(contains('"P002"')),
        reason: '★ 形态③ sm3 出现 P002 ⇒ P001 被改写',
      );

      // 脏 JSON / 空数组：必须原样保留且**未阻断升级**
      expect(byId['sm4'], 'not-json-at-all', reason: '脏 JSON 行不得被改写');
      expect(byId['sm5'], '[]', reason: '空数组行不得被改写');
    },
  );

  test('#3c ★ 反转：teaching_history 上同样无改写发生', () async {
    // 【2026-10-05 层 2 单轨收口批 · 断言方向已反转】
    // 原用例名「单跳契约在 teaching_history 上同样成立」——
    // 「单跳契约」整体消失；现在查的是「无改写」。
    final db = await _openUpgraded('t3c');
    final rows = await db
        .customSelect(
          "SELECT teaching_history FROM student_model WHERE id='sm1'",
        )
        .get();
    final json = rows.single.read<String>('teaching_history');
    expect(json, contains('"P035"'));
    expect(
      json,
      isNot(contains('"P009"')),
      reason: '★ teaching_history 出现 P009 ⇒ 改写复活（P035→P009）',
    );
  });

  test('#3d ★★★ 反转：teaching_history 的三种 ID 形态均无改写（逐形态按行判定）', () async {
    // 【2026-10-05 层 2 单轨收口批 · 断言方向已反转，判据形态改为按行】
    //
    // ⚠️ 本用例原版是 A3 批的**存在理由**（「漏一张表就会假绿」）：
    //   v46 初版只查三张表 ⇒ student_model 里的旧行不被计入，
    //   于是「三张表都腾空」会绿、但第四张表仍存旧行。
    //   反转后**覆盖这一张表的必要性完全不变** ——
    //   漏查 student_model 同样会让本用例绿、而数据同样被损坏。
    //
    // ⚠️ 判据形态：原版写「行内不得包含 "P035"」（集合式），
    //   反转后改为**逐形态按行判定内嵌 ID 仍是原值**。
    //   不能写「行内不得含 P009」——sm2 合法含 P009（现行实体对照行）。
    final db = await _openUpgraded('t3d');

    // 形态①：驼峰 `syndromeId`（training 型）
    final sm1 = await _history(db, 'sm1');
    expect(sm1, contains('"P035"'), reason: '形态① P035 应原样保留');
    expect(
      sm1,
      isNot(contains('"P009"')),
      reason: '★ 形态① 出现 P009 ⇒ 驼峰键被改写（最易漏的一条路径）',
    );

    // 形态②：数组 `syndromes`（confirmation 型）
    final sm2 = await _history(db, 'sm2');
    expect(sm2, contains('"P037"'), reason: '形态② P037 应原样保留');
    expect(
      sm2,
      isNot(contains('"P026"')),
      reason: '★ 形态② 出现 P026 ⇒ P037 被改写成心理内耗症',
    );
    // P009 / P004 在 sm2 里是**合法现行实体对照行**，必须仍在
    expect(sm2, contains('"P009"'), reason: '形态② P009 是现行实体对照，应保留');
    expect(sm2, contains('"P004"'), reason: '形态② P004 是现行实体对照，应保留');
    expect(sm2, contains('"P034"'), reason: '形态② P034 应原样保留（防误伤对照）');
    expect(sm2, contains('123'), reason: '数组里的非字符串元素必须原样保留');

    // 形态③：数组 `syndromes`（diagnosis 型）
    final sm3 = await _history(db, 'sm3');
    expect(sm3, contains('"P035"'), reason: '形态③ P035 应原样保留');
    expect(sm3, contains('"P036"'), reason: '形态③ P036 应原样保留');
    expect(sm3, isNot(contains('"P009"')), reason: '★ 形态③ 出现 P009 ⇒ P035 被改写');
    expect(sm3, isNot(contains('"P004"')), reason: '★ 形态③ 出现 P004 ⇒ P036 被改写');
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
