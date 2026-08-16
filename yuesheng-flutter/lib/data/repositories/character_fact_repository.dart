// ─────────────────────────────────────────────────────────────
// CharacterFactRepository — 人物知识 DAO（批次66 B62i / A6 首步）
// 作品级（manuscript_id 维度），严格复刻 yuesheng schema 惯例
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:drift/drift.dart';

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
  Future<void> upsertCharacter({
    required String manuscriptId,
    required String name,
    int? firstSeenChapter,
    int? firstSeenAt,
    List<CharacterAssertion> assertions = const [],
  }) async {
    final now = nowSec();
    await _db.transaction(() async {
      final existing =
          await (_db.select(_db.characterFacts)..where(
                (t) =>
                    t.manuscriptId.equals(manuscriptId) & t.name.equals(name),
              ))
              .getSingleOrNull();

      if (existing == null) {
        final encoded = jsonEncode(assertions.map((a) => a.toJson()).toList());
        await _db
            .into(_db.characterFacts)
            .insert(
              CharacterFactsCompanion.insert(
                id: generateUuid(),
                manuscriptId: manuscriptId,
                name: name,
                firstSeenChapter: Value(firstSeenChapter),
                firstSeenAt: Value(firstSeenAt),
                assertions: Value(encoded),
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );
      } else {
        // 合并现有断言 + 新断言，按 (attribute, value, chapter) 三元组去重
        final existingAssertions = parseAssertions(existing.assertions);
        final merged = _mergeAssertions(existingAssertions, assertions);
        final encoded = jsonEncode(merged.map((a) => a.toJson()).toList());
        await (_db.update(
          _db.characterFacts,
        )..where((t) => t.id.equals(existing.id))).write(
          CharacterFactsCompanion(
            name: Value(name),
            // 不覆盖 firstSeenChapter / firstSeenAt，保留首次出场信息
            assertions: Value(encoded),
            updatedAt: Value(now),
          ),
        );
      }
    });
  }

  /// 合并断言列表：按 (attribute, value, chapter) 三元组去重。
  /// 同三元组的断言视为重复，保留先出现者（通常是历史断言，timestamp 更早）。
  static List<CharacterAssertion> _mergeAssertions(
    List<CharacterAssertion> existing,
    List<CharacterAssertion> additions,
  ) {
    final seen = <String>{};
    final result = <CharacterAssertion>[];
    for (final a in [...existing, ...additions]) {
      final key = '${a.attribute}\u0000${a.value}\u0000${a.chapter}';
      if (seen.add(key)) {
        result.add(a);
      }
    }
    return result;
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
  static List<CharacterAssertion> parseAssertions(String json) {
    if (json.isEmpty) return const [];
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return const [];
      final result = <CharacterAssertion>[];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          final assertion = CharacterAssertion.tryFromJson(item);
          if (assertion != null) result.add(assertion);
        }
      }
      return result;
    } catch (_) {
      return const [];
    }
  }
}
