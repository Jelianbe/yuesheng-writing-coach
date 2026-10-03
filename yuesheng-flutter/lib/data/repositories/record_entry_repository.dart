// ─────────────────────────────────────────────────────────────
// RecordEntryRepository — 记录条目事件表数据访问（ADR-C143 批A/B，v44）
//
// 记录条目 = 提议式留痕：AI/作者显式提议 → pending → 作者裁决 kept/rejected。
// 复用 character_fact 既有 pending→kept/rejected 状态机（character_types）。
//
// R-009 / 摘录纪律（写死在本层）：
//   - excerpt 由调用方传入**原文整句/整段**，本层**原样落库**，
//     不做任何改写 / 缩写 / 提炼（本层无 LLM 调用、无文本变换）。
//   - 系统只补 created_at 时间戳 + message_id 来源指针，不打业务定性标签。
//   - 不替作者筛选「哪条值得记」：propose 由显式触发（作者喊「记一下」）调用，
//     本层不做自动检测。
//
// 本层不进诊断注入链（未确认记录 ≠ 教学诊断依据，ADR-C143 §1.6）。
// ─────────────────────────────────────────────────────────────

import 'package:drift/drift.dart';

import '../database/database.dart';
import '../database/utils.dart';
import 'repository_write_guard.dart';

/// 记录条目裁决态常量（单一真源；消费方不得裸写字符串）
class RecordEntryStatus {
  static const String pending = 'pending';
  static const String kept = 'kept';
  static const String rejected = 'rejected';
  const RecordEntryStatus._();

  static bool isValid(String v) => v == pending || v == kept || v == rejected;
}

class RecordEntryRepository {
  final AppDatabase _db;
  RecordEntryRepository(this._db);

  /// 提议一条 pending 记录条目。
  ///
  /// [excerpt] 必须是原文整句/整段**原样文本**——本方法**逐字落库**，
  /// 不调用 LLM、不做任何改写/缩写/提炼（摘录纪律）。[messageId] 为来源
  /// 消息指针（软引用，可空）；[excerpt] 是冗余快照（messages 级联删后仍可回溯）。
  Future<RecordEntry> proposePending({
    required String manuscriptId,
    String sessionId = '',
    String? messageId,
    required String excerpt,
  }) => guardRepoWrite('record_entry', 'proposePending', () async {
    final entry = RecordEntriesCompanion.insert(
      id: generateUuid(),
      manuscriptId: manuscriptId,
      sessionId: Value(sessionId),
      messageId: Value(messageId),
      excerpt: Value(excerpt),
      status: const Value(RecordEntryStatus.pending),
    );
    await _db.into(_db.recordEntries).insert(entry);
    return _requireById(entry.id.value);
  });

  /// 作者确认留档：pending → kept。
  Future<void> confirm(String id) => _decide(id, RecordEntryStatus.kept);

  /// 作者拒绝：pending → rejected。
  Future<void> reject(String id) => _decide(id, RecordEntryStatus.rejected);

  Future<void> _decide(
    String id,
    String status,
  ) => guardRepoWrite('record_entry', '_decide', () async {
    await (_db.update(_db.recordEntries)..where((t) => t.id.equals(id))).write(
      RecordEntriesCompanion(status: Value(status), decidedAt: Value(nowSec())),
    );
  });

  Future<RecordEntry> _requireById(String id) async {
    final row = await (_db.select(
      _db.recordEntries,
    )..where((t) => t.id.equals(id))).getSingle();
    return row;
  }

  Future<RecordEntry?> getById(String id) => (_db.select(
    _db.recordEntries,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  /// 待裁决列表（pending，按时间升序）——确认卡 UI 消费。
  Future<List<RecordEntry>> listPending(String manuscriptId) =>
      (_db.select(_db.recordEntries)
            ..where(
              (t) =>
                  t.manuscriptId.equals(manuscriptId) &
                  t.status.equals(RecordEntryStatus.pending),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();

  /// 某作品全部记录条目（按时间升序）。
  Future<List<RecordEntry>> listByManuscript(String manuscriptId) =>
      (_db.select(_db.recordEntries)
            ..where((t) => t.manuscriptId.equals(manuscriptId))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();
}
