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
    String? chapterHash,
  }) async {
    final now = nowSec();
    final encodedParticipants = stringifyJson(participants);
    await _db.transaction(() async {
      final existing = await _findEventByName(manuscriptId, name);
      if (existing == null) {
        await _insertEvent(
          manuscriptId: manuscriptId,
          name: name,
          chapter: chapter,
          eventType: eventType,
          causeEventId: causeEventId,
          effectEventId: effectEventId,
          participants: encodedParticipants,
          description: description,
          chapterHash: chapterHash,
          now: now,
        );
      } else {
        await _updateEvent(
          existing.id,
          name: name,
          chapter: chapter,
          eventType: eventType,
          causeEventId: causeEventId,
          effectEventId: effectEventId,
          participants: encodedParticipants,
          description: description,
          chapterHash: chapterHash,
          now: now,
        );
      }
    });
  }

  /// 按作品 + 名称查既有事件（UNIQUE(manuscript_id, name)）。
  ///
  /// R-019：由 [upsertEvent] 抽出（56 → 30 行）。
  Future<EventFact?> _findEventByName(String manuscriptId, String name) async {
    return (_db.select(_db.eventFacts)..where(
          (t) => t.manuscriptId.equals(manuscriptId) & t.name.equals(name),
        ))
        .getSingleOrNull();
  }

  /// 新建事件。R-019：由 [upsertEvent] 抽出。
  Future<void> _insertEvent({
    required String manuscriptId,
    required String name,
    required String eventType,
    required String participants, // 已序列化
    required String description,
    required int now,
    int? chapter,
    String? causeEventId,
    String? effectEventId,
    String? chapterHash,
  }) async {
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
            participants: Value(participants),
            description: Value(description),
            chapterHash: Value(chapterHash),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
  }

  /// 更新既有事件（不含 createdAt）。R-019：由 [upsertEvent] 抽出。
  Future<void> _updateEvent(
    String id, {
    required String name,
    required String eventType,
    required String participants, // 已序列化
    required String description,
    required int now,
    int? chapter,
    String? causeEventId,
    String? effectEventId,
    String? chapterHash,
  }) async {
    await (_db.update(_db.eventFacts)..where((t) => t.id.equals(id))).write(
      EventFactsCompanion(
        name: Value(name),
        chapter: Value(chapter),
        eventType: Value(eventType),
        causeEventId: Value(causeEventId),
        effectEventId: Value(effectEventId),
        participants: Value(participants),
        description: Value(description),
        // C78 批次2a：仅重诊路径（带指纹）才刷新指纹并归零 stale；其余调用点
        // 用 Value.absent() 保持原值不动，避免误清用户可见的 stale 状态。
        chapterHash: chapterHash == null
            ? const Value.absent()
            : Value(chapterHash),
        stale: chapterHash == null ? const Value.absent() : const Value(0),
        updatedAt: Value(now),
      ),
    );
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
