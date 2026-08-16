// ─────────────────────────────────────────────────────────────
// EventFactRepository — 事件知识 DAO（批次67 B62j / A6 第二迭代 F07）
// 作品级（manuscript_id 维度），TKG 事件节点（章节 + 因果边）
// ─────────────────────────────────────────────────────────────

import 'package:drift/drift.dart';

import '../database/database.dart';
import '../database/utils.dart';

class EventFactRepository {
  final AppDatabase _db;
  EventFactRepository(this._db);

  /// 写入/更新事件（同作品内按 name 唯一，UNIQUE(manuscript_id, name)）
  Future<void> upsertEvent({
    required String manuscriptId,
    required String name,
    required String eventType,
    int? chapter,
    String? causeEventId,
    String? effectEventId,
    List<String> participants = const [],
    String description = '',
  }) async {
    final now = nowSec();
    final encodedParticipants = stringifyJson(participants);
    await _db.transaction(() async {
      final existing =
          await (_db.select(_db.eventFacts)..where(
                (t) =>
                    t.manuscriptId.equals(manuscriptId) & t.name.equals(name),
              ))
              .getSingleOrNull();

      if (existing == null) {
        await _db
            .into(_db.eventFacts)
            .insert(
              EventFactsCompanion.insert(
                id: generateUuid(),
                manuscriptId: manuscriptId,
                name: name,
                chapter: Value(chapter),
                eventType: eventType,
                causeEventId: Value(causeEventId),
                effectEventId: Value(effectEventId),
                participants: Value(encodedParticipants),
                description: Value(description),
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );
      } else {
        await (_db.update(
          _db.eventFacts,
        )..where((t) => t.id.equals(existing.id))).write(
          EventFactsCompanion(
            name: Value(name),
            chapter: Value(chapter),
            eventType: Value(eventType),
            causeEventId: Value(causeEventId),
            effectEventId: Value(effectEventId),
            participants: Value(encodedParticipants),
            description: Value(description),
            updatedAt: Value(now),
          ),
        );
      }
    });
  }

  /// 列出作品下全部事件（按章节排序，null 排最后；同章节按名称）
  Future<List<EventFact>> listEvents(String manuscriptId) async {
    return (_db.select(_db.eventFacts)
          ..where((t) => t.manuscriptId.equals(manuscriptId))
          ..orderBy([
            (t) => OrderingTerm(
              expression: t.chapter,
              mode: OrderingMode.asc,
              nulls: NullsOrder.last,
            ),
            (t) => OrderingTerm(expression: t.name),
          ]))
        .get();
  }

  /// 获取单个事件
  Future<EventFact?> getEvent(String manuscriptId, String name) async {
    return (_db.select(_db.eventFacts)..where(
          (t) => t.manuscriptId.equals(manuscriptId) & t.name.equals(name),
        ))
        .getSingleOrNull();
  }

  /// 批次3-D4：仅更新事件的因果前驱 id（轻量更新，不触碰其他字段）
  Future<void> updateCauseEventId(String id, String? causeEventId) async {
    await (_db.update(_db.eventFacts)..where((t) => t.id.equals(id))).write(
      EventFactsCompanion(
        causeEventId: Value(causeEventId),
        updatedAt: Value(nowSec()),
      ),
    );
  }

  /// 解析事件参与人物列表（JSON 非法 / 脏条目 → 保守跳过，不抛出）
  static List<String> parseParticipants(String json) {
    return parseJsonStringList(json);
  }
}
