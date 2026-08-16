// ─────────────────────────────────────────────────────────────
// SubplotFactRepository — 支线知识 DAO（批次67 B62j / A6 第二迭代 F11）
// 作品级（manuscript_id 维度），TKG 支线节点（引入/回收章节）
// ─────────────────────────────────────────────────────────────

import 'package:drift/drift.dart';

import '../database/database.dart';
import '../database/utils.dart';

class SubplotFactRepository {
  final AppDatabase _db;
  SubplotFactRepository(this._db);

  /// 写入/更新支线（同作品内按 name 唯一，UNIQUE(manuscript_id, name)）
  Future<void> upsertSubplot({
    required String manuscriptId,
    required String name,
    int? introducedChapter,
    int? resolvedChapter,
    int? resolvedAt,
    String description = '',
  }) async {
    final now = nowSec();
    await _db.transaction(() async {
      final existing =
          await (_db.select(_db.subplotFacts)..where(
                (t) =>
                    t.manuscriptId.equals(manuscriptId) & t.name.equals(name),
              ))
              .getSingleOrNull();

      if (existing == null) {
        await _db
            .into(_db.subplotFacts)
            .insert(
              SubplotFactsCompanion.insert(
                id: generateUuid(),
                manuscriptId: manuscriptId,
                name: name,
                introducedChapter: Value(introducedChapter),
                resolvedChapter: Value(resolvedChapter),
                resolvedAt: Value(resolvedAt),
                description: Value(description),
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );
      } else {
        await (_db.update(
          _db.subplotFacts,
        )..where((t) => t.id.equals(existing.id))).write(
          SubplotFactsCompanion(
            name: Value(name),
            introducedChapter: Value(introducedChapter),
            resolvedChapter: Value(resolvedChapter),
            resolvedAt: Value(resolvedAt),
            description: Value(description),
            updatedAt: Value(now),
          ),
        );
      }
    });
  }

  /// 列出作品下全部支线（按引入章节排序，null 排最后；同章节按名称）
  Future<List<SubplotFact>> listSubplots(String manuscriptId) async {
    return (_db.select(_db.subplotFacts)
          ..where((t) => t.manuscriptId.equals(manuscriptId))
          ..orderBy([
            (t) => OrderingTerm(
              expression: t.introducedChapter,
              mode: OrderingMode.asc,
              nulls: NullsOrder.last,
            ),
            (t) => OrderingTerm(expression: t.name),
          ]))
        .get();
  }

  /// 获取单条支线
  Future<SubplotFact?> getSubplot(String manuscriptId, String name) async {
    return (_db.select(_db.subplotFacts)..where(
          (t) => t.manuscriptId.equals(manuscriptId) & t.name.equals(name),
        ))
        .getSingleOrNull();
  }
}
