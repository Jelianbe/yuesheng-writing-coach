// ─────────────────────────────────────────────────────────────
// migration_v46.dart — ADR-0003 阶段一前置：legacy 症候 ID 归一
//
// ── 为什么需要它（背景）──
// 2026-09-29 的 0.3.6 去重做了一次**纯代码重编号**（`e64096db`）：
//   · 47 条旧注册表（P003–P049）→ 34 条新注册表（P001–P034）
//   · **无数据迁移**：老DB 行里存的仍是旧 ID
// 补救手段是 `kSyndromeMergeMap`（`syndrome_registry.dart:141`）：
//   读路径一律经 `effectiveSyndromeId` 做**单跳**归一。
//
// ── 为什么单跳不够 ──
// 读路径归一只保护「当次读出来用」。**落库的旧 ID 一直在库里**：
//   · `active_problems.syndrome_id`（`tables.dart:240`）
//   · `training_results.syndrome_id`（`tables.dart:728`）
//   · `diagnosis_results.syndromes`（`tables.dart:153`，JSON 内嵌）
//   · `student_model.teaching_history`（`tables.dart:298`，JSON 内嵌）
//     ⚠️ A3 批补的第四处。初版漏了它，而它正是 B1 批修的两处形态③ 的数据源
//     （`student_model_repository.dart:150` / `diagnosis_committer.dart:339`）。
//     **表名是 `student_model` 单数**，Dart 类名 `StudentModels` 是复数，两者不一致。
// 而 ADR-0003 阶段一要**复用 P035/P036/P037** 三个槽位。一旦复用，
// 库里残留的旧 P035 行会被新槽位**静默当成新症候**（ID 合法、有名字、能渲染
// ⇒ 表面上完全正常）。⇒ 必须在复用**之前**把存量行改写成归一目标。
//
// ── 语义：单跳，不迭代（重要）──
// `kSyndromeMergeMap` 的键与现行 ID **编号空间重叠**（50 个键里有 33 个是现行
// 活跃 ID），因此链上存在环（如 P003→P001→P002→P007→P005→P003）。
// **迭代归一会死循环**。现行契约是**单跳**（`effectiveSyndromeId` 的实现
// `kSyndromeMergeMap[id] ?? id`，`syndrome_registry.dart:198`），
// 测试 `#R8`（`syndrome_registry_test.dart:132`）也只断言单跳。
// 本migration 与之一致：**按 key 重写为 value，一次，不迭代**。
//
// ── 幂等性 ──
// 写后的值都是**活跃 ID**，可能同时又是别的 legacy 键（如 P009），
// 但本migration 只跑一次（由schemaVersion 46 门控），不做二次改写。
// 重复执行不幂等是**有意为之**——见上方「不迭代」。
//
// ── 陷阱：必须判表存在（本批踩中，42 个用例全灭）──
// 迁移测试的存量库是**手搓的最小 schema**：`migration_v39_test` 的 v38 库只有
// `manuscripts` / `event_fact` / `subplot_fact` 三张表，**根本没有**
// `active_problem` / `training_results` / `diagnosis_results`。
// 而 v39 测试文件头白纸黑字写着既有契约：
//   「#4 **最小 schema 库**（这两张表根本不存在）→ **不抛错**（判表存在，
//     同 v32/v38 范式）」。
// 本迁移初版对三张表**无条件 UPDATE** ⇒ 打在不存在的表上⇒ SQLite 抛
// `no such table: active_problem` ⇒ **从 v23 起 18 个 migration 测试文件的
// 42 个用例全灭**（2026-10-04 实测）。
// ⇒ 修法 = 复用项目既有 `AppDatabase.tableExists`（`database.dart:89`，
//   v16/v17/v32/v34/v38 各迁移块都这么写）。**不是**自己另写一套判据：
//   同一判据在两处各写一遍必然走偏。
//
// ── 陷阱：不可用 LIKE 'P0%' ──
// `teaching_state` 也存 `P`-开头 ID，但那是**两段式阶段 ID**
// （`P0_ENGAGE` / `P1_WORLD` / …，`tables.dart:198-208`，有 `check(isIn(...))` 白名单）。
// 本migration **不碰该表**，且所有匹配一律用**完整键 IN (...)** 精确列举，
// 杜绝前缀误伤。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:drift/drift.dart';

import '../../services/syndrome_registry.dart';

/// 表名。权威来源 = 生成代码的 `static const String $name`（`database.g.dart`），
/// **不是** `tables.dart` 的类名——`ActiveProblems` 有
/// `@override String get tableName => 'active_problem'`（单数！`tables.dart:235`）。
/// 若按类名推蛇形写成 `active_problems`，UPDATE 会打在不存在的表上⇒
/// SQLite 不报错、`rowsAffected = 0` ⇒ **迁移静默失效**。
const _activeProblems = 'active_problem';
const _trainingResults = 'training_results';
const _diagnosisResults = 'diagnosis_results';

/// ⚠️ 表名是 **`student_model`（单数）**，不是 `student_models`。
/// 实测依据：`tables.dart:292` 的 `String get tableName => 'student_model'`；
/// Dart 类名 `StudentModels` 是复数，**与表名不一致** ⇒ 凭类名拼 SQL 会静默零命中。
const _studentModels = 'student_model';

/// 归一映射的**键清单**（按`kSyndromeMergeMap` 全量展开）。
///
/// 之所以不直接遍历 `kSyndromeMergeMap` 在运行时拼 SQL，是因为迁移必须
/// **可审计、可 diff**——把映射表平铺成SQL 字面量后，
/// 「改了哪条映射」在 git 里一眼可见。50 条不多，平铺成本可接受。
const Map<String, String> _legacyToCanonical = {
  'P001': 'P002',
  'P002': 'P007',
  'H001': 'P011',
  'H002': 'P011',
  'P003': 'P001',
  'P004': 'P002',
  'P005': 'P003',
  'P006': 'P004',
  'P007': 'P005',
  'P008': 'P006',
  'P009': 'P007',
  'P010': 'P008',
  'P011': 'P009',
  'P012': 'P010',
  'P013': 'P011',
  'P014': 'P012',
  'P015': 'P013',
  'P016': 'P014',
  'P018': 'P015',
  'P020': 'P016',
  'P021': 'P017',
  'P022': 'P018',
  'P026': 'P019',
  'P027': 'P020',
  'P028': 'P021',
  'P030': 'P022',
  'P031': 'P023',
  'P032': 'P024',
  'P037': 'P026',
  'P038': 'P027',
  'P040': 'P028',
  'P041': 'P029',
  'P042': 'P030',
  'P043': 'P031',
  'P046': 'P032',
  'P049': 'P033',
  'P017': 'P012',
  'P019': 'P001',
  'P023': 'P013',
  'P024': 'P019',
  'P025': 'P011',
  'P029': 'P005',
  'P033': 'P024',
  'P035': 'P009',
  'P036': 'P004',
  'P039': 'P007',
  'P044': 'P011',
  'P045': 'P007',
  'P047': 'P001',
  'P048': 'P018',
};

/// v46 使用的 legacy → 规范 ID 映射（供测试断言「迁移后无 legacy 残留」）。
Map<String, String> get legacyIdMigrationMap => _legacyToCanonical;

/// 校验 [_legacyToCanonical] **覆盖** `kSyndromeMergeMap` 且逐条 value 一致。
/// **返回不一致项**（空 = 一致）。
///
/// ## 为什么是「子集校验」而不是「逐条一致」（A1 批 · ADR-0003 阶段一）
///
/// 守卫的**本意**是「防忘了同步平铺映射 ⇒ migration 按过期映射改数据 ⇒ 静默数据损坏」。
/// 要防的只有一件事：**真源里有的键，平铺里缺了或值不一样**。
///
/// 而「两集合必须逐条一致」是**过严的约束**，它连带禁止了一个正当操作：
/// **清理历史遗留映射**。A2 批删掉 merge map 的 P035/P036/P037（三键即将被
/// ADR-0003 阶段一复用为新槽位），旧写法会报「条目数不一致：平铺 50 vs 真源 47」
/// + 三项「平铺里多出的键」⇒ `assertLegacyMapInSync()` 抛 `StateError`
/// **阻断所有用户升级** —— 为清理历史付出「全量用户打不开 App」的代价。
///
/// ## 两个集合各自的性质（这决定了正确形式）
///
/// | | [_legacyToCanonical]（平铺） | `kSyndromeMergeMap`（真源） |
/// |:--|:--|:--|
/// | 性质 | **一次性历史动作**：v46 出闸时按它改写存量行，改写完使命完成 | **长期读路径真源**：每次归一都读它 |
/// | 会不会长键 | 不会（存量只会越来越少） | 会（将来新增旧号归一时要加） |
/// | 该不该清 | **不该**（清了就永久漏归一那批存量数据） | 该清时随时可清 |
///
/// ⇒ 正确关系是**平铺 ⊇ 真源**（平铺可以多，真源不能多）。
/// 反过来写会让「平铺比真源干净」这种状态永远无法表达。
///
/// ⚠️ 这里**刻意不用 `assert`**：`assert` 在测试模式与发布模式下会被剥离，
/// 实测变异①（把 `P035→P009` 改错）时本函数**没有任何效果**——
/// 只有测试 `#5` 因为期望值写死才抓到。
/// 用返回值把不一致项**显式抛出去**，才能在生产升级路径上也真正生效。
List<String> findLegacyMapMismatches() {
  final bad = <String>[];
  // 反向检查：真源的每个键，平铺里必须存在且 value 相同。
  // ⚠️ 这里**只报「值不同」**；「键缺失」由下面的循环一并覆盖
  //（`mine == null != e.value` 必然成立），不必单列一条。
  for (final e in kSyndromeMergeMap.entries) {
    final mine = _legacyToCanonical[e.key];
    if (mine != e.value) {
      bad.add('${e.key}: 平铺=$mine vs 真源=${e.value}');
    }
  }
  return bad;
}

/// [_legacyToCanonical] 是手抄进 SQL 的平铺版，一旦有人改了
/// `kSyndromeMergeMap` 却忘了同步这里，migration 就会按过期映射改写数据
/// ⇒ **静默数据损坏**。故生产路径上也要硬失败（不靠 assert）。
///
/// 判据是**子集校验**（平铺 ⊇ 真源）—— 理由与允许的差异形态见
/// [findLegacyMapMismatches] 的文档注释。
/// 不一致则抛（阻断升级，绝不带着过期映射改数据）。
void assertLegacyMapInSync() {
  final bad = findLegacyMapMismatches();
  if (bad.isEmpty) return;
  throw StateError(
    'v46 迁移的平铺映射未覆盖 kSyndromeMergeMap，已阻断升级：\n'
    '  ${bad.join('\n  ')}\n'
    '请同步 lib/data/database/migration_v46.dart 的 _legacyToCanonical。',
  );
}

/// v46 迁移主体：把三张表的 legacy 症候 ID 按 merge map **单跳**重写。
///
/// 参数是 drift `Migrator`（`onUpgrade` 回调第一参），
/// 不用 `Executor`——后者是 drift **内部**类型（`src/runtime/api/db_base.dart`），
/// 依赖它等于依赖私有 API，drift 升级即可能断裂。
/// 也不直接用 `Migrator.runCustomStatement`——**它没有这个方法**
/// （`Migrator` 只暴露 create/alter/createAll 之类，见
/// `drift/src/runtime/query_builder/migration.dart`）⇒ 走
/// `m.database.customStatement`，那才是跑任意 SQL 的公开入口
/// （`database.dart` 的 v2–v45 全部迁移块都用它）。
Future<void> migrateLegacySyndromeIds(Migrator m) async {
  assertLegacyMapInSync();
  final db = m.database;

  // ── 两处普通列：同构，一条 helper 走两次 ──
  for (final table in const [_activeProblems, _trainingResults]) {
    if (!await _tableExists(db, table)) continue;
    await _rewritePlainColumn(db, table);
  }
  // ── 第三处：JSON 内嵌（diagnosis_results.syndromes）──
  if (await _tableExists(db, _diagnosisResults)) {
    await _migrateDiagnosisJson(db);
  }
  // ── 第四处：JSON 内嵌（student_model.teaching_history）· A3 批新增 ──
  if (await _tableExists(db, _studentModels)) {
    await _migrateTeachingHistoryJson(db);
  }
}

/// 目标表是否存在于当前库。
///
/// 判据与 `AppDatabase.tableExists`（`database.dart:89`）**逐字一致**
/// （`sqlite_master` + `type='table'`），但这里只能操作 `Migrator` 拿到的
/// `GeneratedDatabase`——`AppDatabase.tableExists` 是实例方法，
/// 迁移体内拿不到 `this`。故就地复刻，**并在上面的文件头注明这处必须与
/// `database.dart` 同步**。
///
/// ⚠️ 关于 `PRAGMA table_info`：**判表**与**判列**的失效方向相反，别混用。
/// `database.dart:80-83` 记载的坑是「**判列**」场景——`table_info` 对缺列表返回
/// 空集，会让「缺列」判定**恒为真** ⇒ 误 `ALTER`。
/// 而**判表**时，空集恰好=「表不存在」= 判对（变异⑤b 实测：换成
/// `PRAGMA table_info` 后测试仍全绿 ⇒ **等价变异**，非覆盖缺口）。
/// 本处仍用 `sqlite_master`，是为了与 `AppDatabase.tableExists` **逐字一致**——
/// 同一判据在两处各写一遍必然走偏，这是仓库既有的教训，不是风格洁癖。
Future<bool> _tableExists(GeneratedDatabase db, String table) async {
  final rows = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        variables: [Variable.withString(table)],
      )
      .get();
  return rows.isNotEmpty;
}

/// 按 [_legacyToCanonical] 逐键 UPDATE 某一列。
///
/// 逐键而非一条 `IN` + `CASE`：迁移量级是几十行，一次性 CASE 写起来长且难 diff；
/// 逐键 UPDATE 的 SQL 在 git 里可读，且天然幂等（值已是目标时不匹配）。
Future<void> _rewritePlainColumn(GeneratedDatabase db, String table) async {
  for (final entry in _legacyToCanonical.entries) {
    await db.customStatement(
      "UPDATE $table SET syndrome_id = '${entry.value}' "
      "WHERE syndrome_id = '${entry.key}'",
    );
  }
}

/// `diagnosis_results.syndromes` 是 JSON 数组字符串，须逐行解析 → 改 `syndrome_id` → 写回。
///
/// ⚠️ 跳过**解析失败**的行而非抛错：一条脏JSON 不应让整个迁移失败
/// （那会让 App 无法升级）。失败行原样保留，由`diagnosis_parser` 侧既有校验兜底。
Future<void> _migrateDiagnosisJson(GeneratedDatabase e) async {
  final rows = await e
      .customSelect("SELECT id, syndromes FROM $_diagnosisResults")
      .get();
  for (final row in rows) {
    final id = row.read<String>('id');
    final raw = row.read<String>('syndromes');
    List<dynamic>? decoded;
    try {
      final d = jsonDecode(raw);
      if (d is List) decoded = d;
    } on FormatException {
      continue;
    }
    if (decoded == null || decoded.isEmpty) continue;

    var changed = false;
    for (final item in decoded) {
      if (item is! Map) continue;
      final sid = item['syndrome_id'];
      if (sid is! String) continue;
      final to = _legacyToCanonical[sid];
      if (to != null && to != sid) {
        item['syndrome_id'] = to;
        changed = true;
      }
    }
    if (!changed) continue;
    await e.customStatement(
      "UPDATE $_diagnosisResults SET syndromes = ? WHERE id = ?",
      [jsonEncode(decoded), id],
    );
  }
}

/// `student_model.teaching_history` 归一（A3 批 · ADR-0003 阶段一）。
///
/// ## 为什么必须补这一处（A3 批存在的唯一理由）
///
/// v46 初版只覆盖三张表（`active_problem` / `training_results` / `diagnosis_results`），
/// **漏了 `student_model`**（实测 `grep -c student_models migration_v46.dart` = 0）。
/// 而 `teaching_history` 正是 B1 批刚修的两处形态③ 的数据来源：
/// - `student_model_repository.dart:150`（写「最近一条 training 评分」）
/// - `diagnosis_committer.dart:339`（算「连续失败训练次数」，**直接驱动介入级别提升**）
///
/// ⇒ 不补这一处，ADR-0003 阶段一复用槽位后，这两条链路会读到旧号行。
/// **补的时机是现在**：v46 尚未出闸（实测 `git tag --contains 8a629c4e` 为空），
/// 现在补是一张表的工作量；出闸后再补就得写 v47 并再走一轮门禁。
///
/// ## ⚠️ 三种 ID 形态（照抄 `_migrateDiagnosisJson` 会静默漏掉两处）
///
/// `teaching_history` 的元素按 `type` 分三种，**ID 键名与类型都不同**：
///
/// | `type` | ID 键 | 形态 | 写入点（实测 4 处全覆盖）
/// |:--|:--|:--|:--|
/// | `training` | `syndromeId` | **字符串** | `diagnosis_flow_handler.dart:1350`
/// | `confirmation` | `syndromes` | **字符串数组** | `diagnosis_service.dart:232`（确认）
/// | `confirmation` | `syndromes` | **字符串数组** | `diagnosis_service.dart:258`（质疑）
/// | `diagnosis` | `syndromes` | **字符串数组** | `diagnosis_service.dart:388`
///
/// 对比：`diagnosis_results.syndromes` 用的是**蛇形 `syndrome_id`（字符串）**。
/// **键名不同（`syndromeId` vs `syndrome_id`）** ⇒ 照抄会**零命中且不报错**
/// ——迁移「成功」了但一条没改，是最坏的失败形态。
Future<void> _migrateTeachingHistoryJson(GeneratedDatabase e) async {
  final rows = await e
      .customSelect("SELECT id, teaching_history FROM $_studentModels")
      .get();
  for (final row in rows) {
    final id = row.read<String>('id');
    final raw = row.read<String>('teaching_history');
    List<dynamic>? decoded;
    try {
      final d = jsonDecode(raw);
      if (d is List) decoded = d;
    } on FormatException {
      continue;
    }
    if (decoded == null || decoded.isEmpty) continue;

    var changed = false;
    for (final item in decoded) {
      if (item is Map && _normalizeHistoryItem(item)) changed = true;
    }
    if (!changed) continue;
    await e.customStatement(
      "UPDATE $_studentModels SET teaching_history = ? WHERE id = ?",
      [jsonEncode(decoded), id],
    );
  }
}

/// 归一 `teaching_history` 的**单个元素**（原地改写），返回是否改动过。
///
/// 两种 ID 形态各占一段，**都必须覆盖** —— 漏掉任一段就是静默漏归一
/// （迁移「成功」了但那部分数据没改）。
bool _normalizeHistoryItem(Map<dynamic, dynamic> item) {
  var changed = false;
  // 形态①`type=='training'`：驼峰 `syndromeId`，字符串
  final single = item['syndromeId'];
  if (single is String) {
    final to = _legacyToCanonical[single];
    if (to != null && to != single) {
      item['syndromeId'] = to;
      changed = true;
    }
  }
  // 形态②/③`syndromes`：字符串数组（confirmation 与 diagnosis 两型共用）
  final many = item['syndromes'];
  if (many is List) {
    for (var i = 0; i < many.length; i++) {
      final s = many[i];
      if (s is! String) continue;
      final to = _legacyToCanonical[s];
      if (to != null && to != s) {
        many[i] = to;
        changed = true;
      }
    }
  }
  return changed;
}
