// ─────────────────────────────────────────────────────────────
// OutlineRepository — 大纲实体/印象 DAO（批次72 大纲层）
// 作品级（manuscript_id 维度），AI 自主记忆沉淀的读写
// 保守策略：JSON 字段脏数据解析失败 → 返回空，绝不 throw
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/database.dart';
import '../database/utils.dart';

class OutlineRepository {
  final AppDatabase _db;
  OutlineRepository(this._db);

  /// 列出作品下全部实体（含 pending/active，按更新时间倒序）
  Future<List<OutlineEntity>> listEntities(String manuscriptId) {
    return (_db.select(_db.outlineEntities)
          ..where((t) => t.manuscriptId.equals(manuscriptId))
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
          ]))
        .get();
  }

  /// 按 id 取单个实体
  Future<OutlineEntity?> getEntityById(String id) {
    return (_db.select(
      _db.outlineEntities,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// 新建实体（默认 pending 态，待用户确认）
  Future<void> insertEntity({
    required String manuscriptId,
    required String entityType,
    required String entityKey,
    List<String> aliases = const [],
  }) async {
    final now = nowSec();
    await _db
        .into(_db.outlineEntities)
        .insert(
          OutlineEntitiesCompanion.insert(
            id: generateUuid(),
            manuscriptId: manuscriptId,
            entityType: entityType,
            entityKey: entityKey,
            aliases: Value(jsonEncode(aliases)),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
  }

  /// 追加实体别名（合并去重，防同实体别名散落）
  Future<void> mergeAliases(String entityId, List<String> newAliases) async {
    final entity = await getEntityById(entityId);
    if (entity == null || newAliases.isEmpty) return;
    final merged = {...parseAliases(entity.aliases), ...newAliases}.toList();
    await (_db.update(
      _db.outlineEntities,
    )..where((t) => t.id.equals(entityId))).write(
      OutlineEntitiesCompanion(
        aliases: Value(jsonEncode(merged)),
        updatedAt: Value(nowSec()),
      ),
    );
  }

  /// 列出实体下全部印象（按版本/时间正序）
  Future<List<OutlineImpression>> listImpressions(String entityId) {
    return (_db.select(_db.outlineImpressions)
          ..where((t) => t.entityId.equals(entityId))
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
        .get();
  }

  /// 按 id 取单个印象
  Future<OutlineImpression?> getImpressionById(String id) {
    return (_db.select(
      _db.outlineImpressions,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// 同实体下是否已有相同文本的印象（防重复入库）
  Future<bool> hasImpression(String entityId, String text) async {
    final existing =
        await (_db.select(_db.outlineImpressions)..where(
              (t) => t.entityId.equals(entityId) & t.impression.equals(text),
            ))
            .get();
    return existing.isNotEmpty;
  }

  /// 新增印象（默认 pending 态；conflictWith 由调用方校验后传入）
  Future<String> insertImpression({
    required String entityId,
    required String impression,
    String? sourceChapterId,
    int? sourceChapterNo,
    String? conflictWith,
  }) async {
    final id = generateUuid();
    await _db
        .into(_db.outlineImpressions)
        .insert(
          OutlineImpressionsCompanion.insert(
            id: id,
            entityId: entityId,
            impression: impression,
            sourceChapterId: Value(sourceChapterId),
            sourceChapterNo: Value(sourceChapterNo),
            conflictWith: Value(conflictWith),
            createdAt: Value(nowSec()),
          ),
        );
    return id;
  }

  /// 解析实体别名表（JSON 非法 → 空列表）
  static List<String> parseAliases(String json) {
    if (json.isEmpty) return const [];
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return const [];
      return decoded.whereType<String>().where((a) => a.isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }

  /// 确认实体（批次87-4 大纲抽屉快速确认）：仅 pending → active
  Future<void> approveEntity(String entityId) async {
    final entity = await getEntityById(entityId);
    if (entity == null || entity.status != 'pending') return;
    await (_db.update(
      _db.outlineEntities,
    )..where((t) => t.id.equals(entityId))).write(
      OutlineEntitiesCompanion(
        status: const Value('active'),
        updatedAt: Value(nowSec()),
      ),
    );
  }

  /// 确认印象（确认卡「接受」按钮）
  ///
  /// 事务内三动作（批次73）：
  ///   1. 若印象带 conflict_with → 被冲突的旧印象置 superseded（二选一）
  ///   2. 该印象置 active
  ///   3. 所属实体若 pending → active（用户已接受至少一条该实体认知）
  /// 批次5（5.2）：仅 pending 印象可被确认——已过期（cleanup 置 expired）
  /// 或已处理（active/rejected/superseded）的印象直接跳过，
  /// 防止陈旧确认卡上的印象覆盖当前 active 认知。
  Future<void> approveImpression(String impressionId) async {
    final imp = await getImpressionById(impressionId);
    if (imp == null || imp.status != 'pending') return;
    final now = nowSec();
    await _db.transaction(() async {
      if (imp.conflictWith != null) {
        await (_db.update(
          _db.outlineImpressions,
        )..where((t) => t.id.equals(imp.conflictWith!))).write(
          const OutlineImpressionsCompanion(status: Value('superseded')),
        );
      }
      await (_db.update(_db.outlineImpressions)
            ..where((t) => t.id.equals(impressionId)))
          .write(const OutlineImpressionsCompanion(status: Value('active')));
      final entity = await getEntityById(imp.entityId);
      if (entity != null && entity.status == 'pending') {
        await (_db.update(
          _db.outlineEntities,
        )..where((t) => t.id.equals(entity.id))).write(
          OutlineEntitiesCompanion(
            status: const Value('active'),
            updatedAt: Value(now),
          ),
        );
      }
    });
  }

  /// 拒绝印象（确认卡「拒绝」按钮）——冲突时拒绝即保留旧认知。
  /// 批次5（5.8）：批量冲突清理——被拒印象若带 conflict_with（指向旧印象 B），
  /// 同实体下其它 pending 且冲突指向同一 B 的印象一并拒绝，
  /// 避免同一冲突反复触发多张确认卡。
  Future<void> rejectImpression(String impressionId) async {
    final imp = await getImpressionById(impressionId);
    if (imp == null) return;
    await _db.transaction(() async {
      await (_db.update(_db.outlineImpressions)
            ..where((t) => t.id.equals(impressionId)))
          .write(const OutlineImpressionsCompanion(status: Value('rejected')));
      if (imp.conflictWith != null) {
        await (_db.update(_db.outlineImpressions)..where(
              (t) =>
                  t.entityId.equals(imp.entityId) &
                  t.status.equals('pending') &
                  t.conflictWith.equals(imp.conflictWith!),
            ))
            .write(
              const OutlineImpressionsCompanion(status: Value('rejected')),
            );
      }
    });
  }

  /// 批次5（5.2）：清理过期 pending 印象（防确认卡永居/陈旧覆盖）。
  ///
  /// 两维度清理，统一置 `expired` 态（区别于用户显式 rejected）：
  ///   1. 超过 [maxAgeDays]（默认 7 天）仍未确认的 pending 印象；
  ///   2. 所属作品已归档（manuscript.status='archived'）下的 pending 印象
  ///      （作品软删后不再需要确认卡）。
  /// 返回本次清理的印象数。
  Future<int> cleanupPendingImpressions({int maxAgeDays = 7}) async {
    final cutoff = nowSec() - maxAgeDays * 86400;
    var cleaned = 0;

    // 1. 超时未确认 → expired
    cleaned +=
        await (_db.update(_db.outlineImpressions)..where(
              (t) =>
                  t.status.equals('pending') &
                  t.createdAt.isSmallerThanValue(cutoff),
            ))
            .write(const OutlineImpressionsCompanion(status: Value('expired')));

    // 2. 归档作品下的 pending 印象 → expired（印象经实体挂作品）
    final archivedManuscripts = await (_db.select(
      _db.manuscripts,
    )..where((t) => t.status.equals('archived'))).get();
    if (archivedManuscripts.isNotEmpty) {
      final archivedIds = archivedManuscripts.map((m) => m.id).toList();
      final orphanEntities = await (_db.select(
        _db.outlineEntities,
      )..where((t) => t.manuscriptId.isIn(archivedIds))).get();
      final orphanEntityIds = orphanEntities.map((e) => e.id).toList();
      if (orphanEntityIds.isNotEmpty) {
        cleaned +=
            await (_db.update(_db.outlineImpressions)..where(
                  (t) =>
                      t.entityId.isIn(orphanEntityIds) &
                      t.status.equals('pending'),
                ))
                .write(
                  const OutlineImpressionsCompanion(status: Value('expired')),
                );
      }
    }

    return cleaned;
  }
}
