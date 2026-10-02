// ─────────────────────────────────────────────────────────────
// EditDiffEventRepository — 写作修改事件埋点（ADR-C132 批1 地基，v43）
//
// 追加式事件日志（与 pilot_metric_event 同范式），供北极星「漏斗底端」
// 分析：反馈后用户是否在教练指认的位置做了修改（位置级 diff）。
//
// 事件类型（event_type）：
//   - diff       位置级 diff：章节保存时自动捕获（saveChapterContent 接线）
//   - anchor_ack 指认事件：用户确认教练指认的片段位置（UI 接线批 3）
//   - completion 成稿事件：章节被标记完成（UI 接线批 3）
//
// 埋点先行纪律（变体池验收⑤）：A/B 前必须有位置级 diff，无埋点不谈 A/B。
// ─────────────────────────────────────────────────────────────

import 'package:drift/drift.dart';

import '../database/database.dart';
import '../database/utils.dart';
import 'repository_write_guard.dart';

/// 写作修改事件类型常量（单一真源；消费方不得裸写字符串）
class EditDiffEventTypes {
  static const String diff = 'diff';
  static const String anchorAck = 'anchor_ack';
  static const String completion = 'completion';
  const EditDiffEventTypes._();
}

/// 位置级 diff 事件入参（记录一次「反馈后修改」）。
class EditDiffInput {
  final String sessionId;
  final String chapterId;
  final String? messageId;
  final int anchorStart;
  final int anchorEnd;
  final String beforeText;
  final String afterText;
  final int diffSegments;

  const EditDiffInput({
    required this.sessionId,
    required this.chapterId,
    this.messageId,
    required this.anchorStart,
    required this.anchorEnd,
    required this.beforeText,
    required this.afterText,
    required this.diffSegments,
  });

  String encodePayload() => '{"diff_segments":$diffSegments}';

  static EditDiffInput decodePayload(
    String raw, {
    required String sessionId,
    required String chapterId,
    String? messageId,
    required int anchorStart,
    required int anchorEnd,
    required String beforeText,
    required String afterText,
  }) {
    var segments = 1;
    if (raw.contains('"diff_segments":')) {
      final v = raw.split('"diff_segments":').last.split(RegExp(r'[},]')).first;
      segments = int.tryParse(v) ?? 1;
    }
    return EditDiffInput(
      sessionId: sessionId,
      chapterId: chapterId,
      messageId: messageId,
      anchorStart: anchorStart,
      anchorEnd: anchorEnd,
      beforeText: beforeText,
      afterText: afterText,
      diffSegments: segments,
    );
  }
}

class EditDiffEventRepository {
  final AppDatabase _db;
  EditDiffEventRepository(this._db);

  /// 记录一条位置级 diff 事件（章节保存自动捕获）。
  Future<void> recordDiff(EditDiffInput input) =>
      guardRepoWrite('edit_diff_event', 'recordDiff', () async {
        await _db
            .into(_db.editDiffEvents)
            .insert(
              EditDiffEventsCompanion.insert(
                id: generateUuid(),
                sessionId: Value(input.sessionId),
                chapterId: input.chapterId,
                messageId: Value(input.messageId),
                eventType: EditDiffEventTypes.diff,
                anchorStart: Value(input.anchorStart),
                anchorEnd: Value(input.anchorEnd),
                beforeText: Value(input.beforeText),
                afterText: Value(input.afterText),
                payload: Value(input.encodePayload()),
              ),
            );
      });

  /// 记录一条指认事件（用户确认教练指认的片段，UI 接线批 3）。
  ///
  /// [anchorStart]/[anchorEnd] 可空（表 schema nullable）：诊断证据通常
  /// 只有「段落位置 + 原文摘录」，无字符级偏移——精确位置由 diff 事件承载，
  /// 指认事件记录「确认了哪个片段」（anchorText 必填）。
  Future<void> recordAnchorAcknowledged({
    required String sessionId,
    required String chapterId,
    String? messageId,
    int? anchorStart,
    int? anchorEnd,
    required String anchorText,
  }) => guardRepoWrite('edit_diff_event', 'recordAnchorAcknowledged', () async {
    await _db
        .into(_db.editDiffEvents)
        .insert(
          EditDiffEventsCompanion.insert(
            id: generateUuid(),
            sessionId: Value(sessionId),
            chapterId: chapterId,
            messageId: Value(messageId),
            eventType: EditDiffEventTypes.anchorAck,
            anchorStart: Value(anchorStart),
            anchorEnd: Value(anchorEnd),
            afterText: Value(anchorText),
          ),
        );
  });

  /// 记录一条成稿事件（章节被标记完成，UI 接线批 3）。
  Future<void> recordCompletion({
    required String sessionId,
    required String chapterId,
  }) => guardRepoWrite('edit_diff_event', 'recordCompletion', () async {
    await _db
        .into(_db.editDiffEvents)
        .insert(
          EditDiffEventsCompanion.insert(
            id: generateUuid(),
            sessionId: Value(sessionId),
            chapterId: chapterId,
            eventType: EditDiffEventTypes.completion,
          ),
        );
  });

  /// 按章节查询事件（时间升序，北极星读数用）。
  Future<List<EditDiffEvent>> listByChapter(String chapterId) =>
      (_db.select(_db.editDiffEvents)
            ..where((t) => t.chapterId.equals(chapterId))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();

  /// 按会话查询事件（时间升序）。
  Future<List<EditDiffEvent>> listBySession(String sessionId) =>
      (_db.select(_db.editDiffEvents)
            ..where((t) => t.sessionId.equals(sessionId))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();

  /// 按事件类型查询（跨会话）。
  Future<List<EditDiffEvent>> listByType(String eventType) =>
      (_db.select(_db.editDiffEvents)
            ..where((t) => t.eventType.equals(eventType))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();
}
