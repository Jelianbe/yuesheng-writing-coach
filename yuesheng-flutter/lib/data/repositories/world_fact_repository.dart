// ─────────────────────────────────────────────────────────────
// WorldFactRepository — 世界观设定 DAO（书籍级成长叙事 · 批次 E1）
//
// 作品级（manuscript_id 维度），与 character_fact_repository **同构**。
// 同构换来两样「白拿」：
//   ① [FactStaleService.mergeAssertions] 的 chapterHash 幽灵治理（C78 批次2a）
//   ② [CharacterAssertion] 断言数组形态（attribute / value / chapter / chapterHash）
//
// ★ 为什么复用 [CharacterAssertion] 而非新建 WorldAssertion：
//   该类型字段（attribute / value / chapter / timestamp / status / source /
//   evidence / chapterHash / stale / rejectReason）**无一带角色专属语义**——
//   它就是「带章节 + 时间双维度的属性断言」这一通用载体（types 文件头自述的
//   TKG 时间维度节点）。复用即白拿 stale / 合并 / 检测过滤三套已修好的机制；
//   新建类型会立刻要求把 FactStaleService 的静态方法全部泛化，在 schema 变更
//   风险已高的本批引入第二个重构面。若将来确需类型级区分，届时是一次纯机械抽取。
//
// ★ 世界观断言**不参与** F05 检测（由批次 E1 负向测试守护）：
//   detectCharacterConflicts 的输入是 characterName + 断言，世界观数据天然不在
//   其中；且判据本身不可复用（世界观是规则、天然带例外，见 tables.dart 本表注释），
//   故本文件**刻意不 import** conflict_detector——少一条依赖即少一条误接通道。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:drift/drift.dart';

import '../../services/fact_stale_service.dart';
import '../../types/character_types.dart';
import '../database/database.dart';
import '../database/utils.dart';
import 'repository_write_guard.dart';

/// `world_fact.status` 取值（tables.dart 本表注释明列 `active | archived`）。
/// 与 character_fact 的 `active | merged` 刻意不同：世界观无同名合并场景。
const String _kActiveStatus = 'active';

class WorldFactRepository {
  final AppDatabase _db;
  WorldFactRepository(this._db);

  /// 写入/更新世界观设定条目（同作品内按 name 唯一，UNIQUE(manuscript_id, name)）。
  ///
  /// 与 `CharacterFactRepository.upsertCharacter` 同构：assertions **增量合并**，
  /// 不覆盖历史断言；firstSeenChapter / firstSeenAt **仅 insert 时设置**，
  /// update 不覆盖（保留「首次提出」信息）。
  ///
  /// [chapterHash] + [chapterNo] 同时给出才启用 stale 机制（填指纹 / 标旧版 /
  /// 三元组合并全部委托 [FactStaleService.mergeAssertions]）；二者缺一即退化成
  /// 纯三元组去重——与 character 侧同一契约，保护未接线的调用点。
  Future<void> upsertWorld({
    required String manuscriptId,
    required String name,
    int? firstSeenChapter,
    int? firstSeenAt,
    List<CharacterAssertion> assertions = const [],
    String? chapterHash,
    int? chapterNo,
  }) => guardRepoWrite('world_fact', 'upsertWorld', () async {
    final now = nowSec();
    await _db.transaction(() async {
      final existing = await _findWorld(manuscriptId, name);
      if (existing == null) {
        await _insertWorld(
          manuscriptId: manuscriptId,
          name: name,
          firstSeenChapter: firstSeenChapter,
          firstSeenAt: firstSeenAt,
          assertions: assertions,
          chapterHash: chapterHash,
          chapterNo: chapterNo,
          now: now,
        );
      } else {
        await _updateWorld(
          existing.id,
          name: name,
          existingAssertions: parseAssertions(existing.assertions),
          assertions: assertions,
          chapterHash: chapterHash,
          chapterNo: chapterNo,
          now: now,
        );
      }
    });
  });

  /// 按作品 + 设定主题名查既有条目（UNIQUE(manuscript_id, name)）。
  /// R-019：由 [upsertWorld] 抽出（与 character_fact_repository 同构）。
  Future<WorldFact?> _findWorld(String manuscriptId, String name) async {
    return (_db.select(_db.worldFacts)..where(
          (t) => t.manuscriptId.equals(manuscriptId) & t.name.equals(name),
        ))
        .getSingleOrNull();
  }

  /// 新建设定条目。R-019：由 [upsertWorld] 抽出。
  Future<void> _insertWorld({
    required String manuscriptId,
    required String name,
    required List<CharacterAssertion> assertions,
    required int now,
    int? firstSeenChapter,
    int? firstSeenAt,
    String? chapterHash,
    int? chapterNo,
  }) => guardRepoWrite('world_fact', '_insertWorld', () async {
    final merged = FactStaleService.mergeAssertions(
      const [],
      assertions,
      chapterHash,
      chapterNo: chapterNo,
    );
    await _db
        .into(_db.worldFacts)
        .insert(
          WorldFactsCompanion.insert(
            id: generateUuid(),
            manuscriptId: manuscriptId,
            name: name,
            firstSeenChapter: Value(firstSeenChapter),
            firstSeenAt: Value(firstSeenAt),
            assertions: Value(_encodeAssertions(merged)),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
  });

  /// 更新既有条目（不覆盖 firstSeenChapter / firstSeenAt，保留首次提出信息）。
  /// R-019：由 [upsertWorld] 抽出。
  Future<void> _updateWorld(
    String id, {
    required String name,
    required List<CharacterAssertion> existingAssertions,
    required List<CharacterAssertion> assertions,
    required int now,
    String? chapterHash,
    int? chapterNo,
  }) => guardRepoWrite('world_fact', '_updateWorld', () async {
    final merged = FactStaleService.mergeAssertions(
      existingAssertions,
      assertions,
      chapterHash,
      chapterNo: chapterNo,
    );
    await (_db.update(_db.worldFacts)..where((t) => t.id.equals(id))).write(
      WorldFactsCompanion(
        name: Value(name),
        assertions: Value(_encodeAssertions(merged)),
        updatedAt: Value(now),
      ),
    );
  });

  /// 断言列表 → JSON 字符串。
  /// 填指纹 / 标 stale / 三元组合并全部由 [FactStaleService] 负责，此处只管序列化。
  static String _encodeAssertions(List<CharacterAssertion> list) {
    return jsonEncode(list.map((a) => a.toJson()).toList());
  }

  /// 列出作品下全部设定条目（按主题名排序）。
  ///
  /// [includeArchived] 默认 false——**默认排除 `status='archived'` 的归档行**，
  /// 与 `listCharacters` 默认排除 merged 同一取向（归档行不应出现在默认视图）。
  /// 注：drift 的 `where` 是 setter 不是追加，两次调用后者覆盖前者——过滤必须
  /// 写在**同一个表达式**里。
  Future<List<WorldFact>> listWorlds(
    String manuscriptId, {
    bool includeArchived = false,
  }) async {
    return (_db.select(_db.worldFacts)
          ..where(
            (t) => includeArchived
                ? t.manuscriptId.equals(manuscriptId)
                : t.manuscriptId.equals(manuscriptId) &
                      t.status.equals(_kActiveStatus),
          )
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .get();
  }

  /// 获取单个设定条目（按作品 + 主题名）
  Future<WorldFact?> getWorld(String manuscriptId, String name) async {
    return _findWorld(manuscriptId, name);
  }

  /// 按主键获取设定条目（详情页用：列表项携带的是 id）
  Future<WorldFact?> getWorldById(String id) async {
    return (_db.select(
      _db.worldFacts,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// 解析设定条目的断言列表（JSON 非法 / 脏条目 → 保守跳过，不抛出）
  ///
  /// 与 character 侧同走 [CharacterAssertion.fromDbJson]（DB 回读入口），
  /// 而非 tryFromJson（AI 协议入口）——后者刻意不读 status / source /
  /// chapterHash / stale，会让 stale 标记与用户裁决在读写往返中丢失。
  static List<CharacterAssertion> parseAssertions(String json) {
    return parseJsonList<CharacterAssertion>(
      json,
      const <CharacterAssertion>[],
      CharacterAssertion.fromDbJson,
    ).where((a) => a.attribute.isNotEmpty && a.value.isNotEmpty).toList();
  }
}
