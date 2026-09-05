// ─────────────────────────────────────────────────────────────
// CharacterFactRepository — 人物知识 DAO（批次66 B62i / A6 首步）
// 作品级（manuscript_id 维度），严格复刻 yuesheng schema 惯例
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:drift/drift.dart';

import '../../services/fact_stale_service.dart';
import '../../types/character_types.dart';
import '../database/database.dart';
import '../database/utils.dart';

class CharacterFactRepository {
  final AppDatabase _db;
  CharacterFactRepository(this._db);

  /// 写入/更新人物（同作品内按 name 唯一，UNIQUE(manuscript_id, name)）
  ///
  /// 批次3-D2：assertions 增量合并，不覆盖历史断言。
  /// - insert：直接写入新断言
  /// - update：读取现有断言 → 与新断言按 (attribute, value, chapter) 去重合并 → 写回
  ///           firstSeenChapter / firstSeenAt 仅 insert 时设置，update 不覆盖
  ///
  /// C78 批次2a：[chapterHash] + [chapterNo] 同时给出才启用 stale 机制
  /// （填指纹 / 标旧版 / 三元组合并全部委托 [FactStaleService.mergeAssertions]）；
  /// 二者缺一即退化成批次3-D2 的纯三元组去重，保护未接线的调用点。
  Future<void> upsertCharacter({
    required String manuscriptId,
    required String name,
    int? firstSeenChapter,
    int? firstSeenAt,
    List<CharacterAssertion> assertions = const [],
    String? chapterHash,
    int? chapterNo,
  }) async {
    final now = nowSec();
    await _db.transaction(() async {
      final existing = await _findCharacter(manuscriptId, name);
      if (existing == null) {
        await _insertCharacter(
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
        await _updateCharacter(
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
  }

  /// 按作品 + 姓名查既有人物（UNIQUE(manuscript_id, name)）。
  /// R-019：由 [upsertCharacter] 抽出（与 event_fact_repository 同构）。
  Future<CharacterFact?> _findCharacter(
    String manuscriptId,
    String name,
  ) async {
    return (_db.select(_db.characterFacts)..where(
          (t) => t.manuscriptId.equals(manuscriptId) & t.name.equals(name),
        ))
        .getSingleOrNull();
  }

  /// 新建人物。R-019：由 [upsertCharacter] 抽出（C78 批次2a）。
  Future<void> _insertCharacter({
    required String manuscriptId,
    required String name,
    required List<CharacterAssertion> assertions,
    required int now,
    int? firstSeenChapter,
    int? firstSeenAt,
    String? chapterHash,
    int? chapterNo,
  }) async {
    final merged = FactStaleService.mergeAssertions(
      const [],
      assertions,
      chapterHash,
      chapterNo: chapterNo,
    );
    await _db
        .into(_db.characterFacts)
        .insert(
          CharacterFactsCompanion.insert(
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
  }

  /// 更新既有人物（不覆盖 firstSeenChapter / firstSeenAt，保留首次出场信息）。
  /// R-019：由 [upsertCharacter] 抽出（C78 批次2a）。
  Future<void> _updateCharacter(
    String id, {
    required String name,
    required List<CharacterAssertion> existingAssertions,
    required List<CharacterAssertion> assertions,
    required int now,
    String? chapterHash,
    int? chapterNo,
  }) async {
    final merged = FactStaleService.mergeAssertions(
      existingAssertions,
      assertions,
      chapterHash,
      chapterNo: chapterNo,
    );
    await (_db.update(_db.characterFacts)..where((t) => t.id.equals(id))).write(
      CharacterFactsCompanion(
        name: Value(name),
        assertions: Value(_encodeAssertions(merged)),
        updatedAt: Value(now),
      ),
    );
  }

  /// 断言列表 → JSON 字符串。
  /// 填指纹 / 标 stale / 三元组合并全部由 [FactStaleService] 负责，此处只管序列化。
  static String _encodeAssertions(List<CharacterAssertion> list) {
    return jsonEncode(list.map((a) => a.toJson()).toList());
  }

  /// 列出作品下全部人物（按姓名排序）
  Future<List<CharacterFact>> listCharacters(String manuscriptId) async {
    return (_db.select(_db.characterFacts)
          ..where((t) => t.manuscriptId.equals(manuscriptId))
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .get();
  }

  /// 获取单个人物
  Future<CharacterFact?> getCharacter(String manuscriptId, String name) async {
    return (_db.select(_db.characterFacts)..where(
          (t) => t.manuscriptId.equals(manuscriptId) & t.name.equals(name),
        ))
        .getSingleOrNull();
  }

  /// 解析人物的属性断言列表（JSON 非法 / 脏条目 → 保守跳过，不抛出）
  ///
  /// C78 批次2a：改走 [CharacterAssertion.fromDbJson]（原用 tryFromJson）。
  /// tryFromJson 是 **AI 协议** 解析入口，刻意不读 status / source /
  /// chapterHash / stale；但 DB 回读必须原样还原这些字段，否则 stale 标记
  /// 与用户裁决会在一次读写往返中丢失——批次1 遗留的潜伏缺陷。
  static List<CharacterAssertion> parseAssertions(String json) {
    return parseJsonList<CharacterAssertion>(
      json,
      const <CharacterAssertion>[],
      CharacterAssertion.fromDbJson,
    ).where((a) => a.attribute.isNotEmpty && a.value.isNotEmpty).toList();
  }
}
