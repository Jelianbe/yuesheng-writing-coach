// ─────────────────────────────────────────────────────────────
// SubplotFactRepository — 支线知识 DAO（批次67 B62j / A6 第二迭代 F11）
// 作品级（manuscript_id 维度），TKG 支线节点（引入/回收章节）
// ─────────────────────────────────────────────────────────────

import 'package:drift/drift.dart';

import '../database/database.dart';
import '../database/utils.dart';
import 'repository_write_guard.dart';

class SubplotFactRepository {
  final AppDatabase _db;
  SubplotFactRepository(this._db);

  /// 写入/更新支线（同作品内按 name 唯一，UNIQUE(manuscript_id, name)）
  ///
  /// N12-F3b：新增两个**身份键**参数（`ADR-C96`）。[introducedChapter] /
  /// [resolvedChapter] 保持 AI 原值不动（R1′），身份另存、与之并列。
  ///
  /// R-019：本函数原 49 行，加 4 个字段会顶破 50 行硬限 ⇒ 按兄弟仓储
  /// （`event_fact_repository.dart`）的既有形态拆出 `_findSubplotByName` /
  /// `_insertSubplot` / `_updateSubplot` 三个私有落库函数，**语义逐行不变**。
  Future<void> upsertSubplot({
    required String manuscriptId,
    required String name,
    int? introducedChapter,
    int? introducedChapterSortOrder,
    int? resolvedChapter,
    int? resolvedChapterSortOrder,
    int? resolvedAt,
    String description = '',
  }) => guardRepoWrite('subplot_fact', 'upsertSubplot', () async {
    final now = nowSec();
    await _db.transaction(() async {
      final existing = await _findSubplotByName(manuscriptId, name);
      if (existing == null) {
        await _insertSubplot(
          manuscriptId: manuscriptId,
          name: name,
          introducedChapter: introducedChapter,
          introducedChapterSortOrder: introducedChapterSortOrder,
          resolvedChapter: resolvedChapter,
          resolvedChapterSortOrder: resolvedChapterSortOrder,
          resolvedAt: resolvedAt,
          description: description,
          now: now,
        );
      } else {
        await _updateSubplot(
          existing.id,
          name: name,
          introducedChapter: introducedChapter,
          introducedChapterSortOrder: introducedChapterSortOrder,
          resolvedChapter: resolvedChapter,
          resolvedChapterSortOrder: resolvedChapterSortOrder,
          resolvedAt: resolvedAt,
          description: description,
          now: now,
        );
      }
    });
  });

  /// 按作品 + 名称查既有支线（UNIQUE(manuscript_id, name)）。
  Future<SubplotFact?> _findSubplotByName(
    String manuscriptId,
    String name,
  ) async {
    return (_db.select(_db.subplotFacts)..where(
          (t) => t.manuscriptId.equals(manuscriptId) & t.name.equals(name),
        ))
        .getSingleOrNull();
  }

  /// 新建支线。R-019：由 [upsertSubplot] 抽出（同 event_fact_repository 形态）。
  Future<void> _insertSubplot({
    required String manuscriptId,
    required String name,
    required String description,
    required int now,
    int? introducedChapter,
    int? introducedChapterSortOrder,
    int? resolvedChapter,
    int? resolvedChapterSortOrder,
    int? resolvedAt,
  }) => guardRepoWrite('subplot_fact', '_insertSubplot', () async {
    await _db
        .into(_db.subplotFacts)
        .insert(
          SubplotFactsCompanion.insert(
            id: generateUuid(),
            manuscriptId: manuscriptId,
            name: name,
            introducedChapter: Value(introducedChapter),
            introducedChapterSortOrder: Value(introducedChapterSortOrder),
            resolvedChapter: Value(resolvedChapter),
            resolvedChapterSortOrder: Value(resolvedChapterSortOrder),
            resolvedAt: Value(resolvedAt),
            description: Value(description),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
  });

  /// 更新既有支线（不含 createdAt）。R-019：由 [upsertSubplot] 抽出。
  Future<void> _updateSubplot(
    String id, {
    required String name,
    required String description,
    required int now,
    int? introducedChapter,
    int? introducedChapterSortOrder,
    int? resolvedChapter,
    int? resolvedChapterSortOrder,
    int? resolvedAt,
  }) => guardRepoWrite('subplot_fact', '_updateSubplot', () async {
    await (_db.update(_db.subplotFacts)..where((t) => t.id.equals(id))).write(
      SubplotFactsCompanion(
        name: Value(name),
        introducedChapter: Value(introducedChapter),
        introducedChapterSortOrder: Value(introducedChapterSortOrder),
        resolvedChapter: Value(resolvedChapter),
        resolvedChapterSortOrder: Value(resolvedChapterSortOrder),
        resolvedAt: Value(resolvedAt),
        description: Value(description),
        updatedAt: Value(now),
      ),
    );
  });

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
