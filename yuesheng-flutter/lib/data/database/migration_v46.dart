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
// `kSyndromeMergeMap` 的键与现行 ID **编号空间重叠**（47 个键里有 33 个是现行
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

// ⚠️ 留档的**表名知识**（Dart 类名 ≠ 表名，这类坑的症状是**零命中而非报错**
//   ⇒ 易复发，删掉就等于把踩坑经验丢掉）：
//
//   | Dart 类 |真实表名 | 坑 |
//   |:--|:--|:--|
//   | `ActiveProblems` | `active_problem`（**单数**） | 按类名推蛇形写成
//     `active_problems` ⇒ UPDATE 打在不存在的表上 ⇒ SQLite 不报错、
//     `rowsAffected = 0` ⇒ **迁移静默失效**（依据 `tables.dart:235`）|
//   | `TrainingResults` | `training_results` | 复数，与类名一致，无坑 |
//   | `DiagnosisResults` | `diagnosis_results` | 复数，与类名一致，无坑 |
//   | `StudentModels` | `student_model`（**单数**） | ⚠️ Dart 类名是**复数**、
//     **与表名不一致** ⇒ 凭类名拼 SQL 会静默零命中（依据 `tables.dart:292`）|
//
//   ▸ 权威来源 = 生成代码的 `static const String $name`（`database.g.dart`），
//     **不是** `tables.dart` 的类名。若将来有工具要按表名操作症状数据，
//     以 `database.g.dart` 为准，不要照抄这张表（它只是留档）。

/// 归一映射的**键清单**（退役档案**全量 50 条**，含 recycled 3 条）。
///
/// 之所以不直接遍历 `kSyndromeMergeMap`（47 条）而在运行时拼 SQL：
/// ① **口径不同** —— 平铺表还必须含 recycled 3 条（槽位待复用为新症候，
///    不能留在读路径映射里），但存量库里确有这些旧号的历史行 ⇒ 必须归一；
/// ② 迁移必须**可审计、可 diff**——平铺成 SQL 字面量后，
///    「改了哪条映射」在 git 里一眼可见。50 条不多，平铺成本可接受。
///
/// ⚠️ 本段**由 `tool/gen_syndrome_retirement.py` 生成，请勿手改**。
/// 真源 = `lib/services/syndrome_retirement.dart`（退役档案）。
const Map<String, String> _legacyToCanonical = {
  // ⚠️ 本段由 tool/gen_syndrome_retirement.py 生成，请勿手改。
  // 真源 = lib/services/syndrome_retirement.dart（kSyndromeRetirement）
  // ⚠️ 本表仅供**历史留档** —— v46 迁移已退役、永不执行。
  // 全量 50 条，含 recycled 3 条 —— 而这 3 条正是v46 必须退役的原因：
  //   单跳语义会把存量库里任何 P035/P036/P037 行改写成旧实体，而那三个号
  //   如今已是现行实体（撞文同质化症 / 细节失真症 / 故事核缺失症）。
  'H001': 'P011',
  'H002': 'P011',
  'P001': 'P002',
  'P002': 'P007',
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
  'P039': 'P007',
  'P044': 'P011',
  'P045': 'P007',
  'P047': 'P001',
  'P048': 'P018',
  'P035': 'P009',
  'P036': 'P004',
  'P037': 'P026',
};

/// v46 使用的 legacy → 规范 ID 映射（供测试断言「迁移后无 legacy 残留」）。
Map<String, String> get legacyIdMigrationMap => _legacyToCanonical;

// ─────────────────────────────────────────────────────────────
// ★★ 以上是本文件保留下来的**全部**内容：平铺映射表 + 一个 getter。
//
// ── 为什么删掉守卫与迁移主体（2026-10-05 · 层 2 单轨收口批）──
//
// 1) **迁移主体 `migrateLegacySyndromeIds` 退役**：它在
//    `database.dart` 的 `onUpgrade` 调用点已删除，**永不执行**。
//    退役理由见 `database.dart` 里的「v46 迁移退役说明」整段注释，
//    决定性理由摘录：
//      · 本表**含 3 条 recycled**（`P035→P009` / `P036→P004` / `P037→P026`），
//        单跳语义下会把存量库里**任何** `P035` 行**一律**改写成 `P009`
//      · 而按单轨决策 `P035` 早已是**现行注册表实体**（撞文同质化症）
//        ⇒ 撞文同质化症的历史数据会被静默改成「对话疲劳症」
//        （ID 合法、有名字、能渲染 ⇒ 最隐蔽的一种数据损坏）
//
// 2) **守卫 `assertLegacyMapInSync` / `findLegacyMapMismatches` 一并退役**：
//    它们存在的唯一目的是「防忘了同步平铺映射 ⇒ 迁移按过期映射改数据」。
//    迁移不再执行 ⇒ 这类数据损坏**不可能发生** ⇒ 守卫失去对象。
//    另一层：它依赖的 `kSyndromeMergeMap`（读路径真源）**已整张删除**
//    （单轨收口批）⇒ 守卫的对照对象不复存在，保留它只会编译失败。
//
// ── 为什么保留这张表 ──
// 这是「0.3.6 纯代码重编号时，库里实际可能残留哪些旧号、并进了谁」的
// **唯一完整记录**。删掉它，这段知识就只能从 git 历史里考古。
// 退役档案（`lib/services/syndrome_retirement.dart`，50 条）记的是
// 「旧号 → 现行号」；而这张平铺表额外记了一件档案表达不了的事：
//**这三个 recycled 号当年是「槽位待复用」，而它们如今已经被真的复用了。**
//
// ⚠️ 本表由 `tool/gen_syndrome_retirement.py` 生成，请勿手改。
// ⚠️ 运行时**零消费**（除 `test/data/database/migration_v46_test.dart`
//    与 `test/services/syndrome_retirement_ledger_test.dart` 的档案断言）。
// ─────────────────────────────────────────────────────────────
