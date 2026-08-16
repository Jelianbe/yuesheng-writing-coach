// ─────────────────────────────────────────────────────────────
// Editor Observation Repository
// 复刻 yuesheng-android/src/db/dao/editor-observation-dao.ts
//
// INSERT OR REPLACE：UNIQUE(session_id, message_id) 已由表 schema 保证。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/database/utils.dart';
import 'package:writingcoach/services/editor_validator.dart';

/// 新增 Editor Observation 入参
/// 真源：editor-observation-dao.ts insertEditorObservation params
class InsertEditorObservationParams {
  final String sessionId;
  final String messageId;
  final EditorResult editorResult;
  final bool teacherTriggered;
  final int pronouncedCount;
  final int againstCount;
  final String? targetRefType; // 'manuscript' | 'chapter' | null
  final String? targetRefId;

  const InsertEditorObservationParams({
    required this.sessionId,
    required this.messageId,
    required this.editorResult,
    required this.teacherTriggered,
    required this.pronouncedCount,
    required this.againstCount,
    this.targetRefType,
    this.targetRefId,
  });
}

class EditorObservationRepository {
  final AppDatabase _db;
  EditorObservationRepository(this._db);

  /// 新增编辑观察（INSERT OR REPLACE）
  ///
  /// 真源：editor-observation-dao.ts insertEditorObservation
  Future<String> insertEditorObservation(
    InsertEditorObservationParams params,
  ) async {
    final id = generateUuid();
    final now = nowSec();

    await _db
        .into(_db.editorObservations)
        .insertOnConflictUpdate(
          EditorObservationsCompanion.insert(
            id: id,
            sessionId: params.sessionId,
            messageId: params.messageId,
            possibleIntent: params.editorResult.possibleIntent,
            intentConfidence: params.editorResult.intentConfidence,
            observations: jsonEncode(
              _serializeObservations(params.editorResult.observations),
            ),
            overallImpression: params.editorResult.overallImpression,
            strengths: Value(jsonEncode(params.editorResult.strengths)),
            teacherTriggered: Value(params.teacherTriggered ? 1 : 0),
            pronouncedCount: Value(params.pronouncedCount),
            againstCount: Value(params.againstCount),
            targetRefType: params.targetRefType == null
                ? const Value.absent()
                : Value(params.targetRefType),
            targetRefId: params.targetRefId == null
                ? const Value.absent()
                : Value(params.targetRefId),
            timestamp: Value(now),
            createdAt: Value(now),
          ),
        );

    return id;
  }

  /// 获取 session 最近 N 条 observation（默认 20）
  Future<List<EditorObservationRow>> getRecentObservations(
    String sessionId, {
    int limit = 20,
  }) async {
    return (_db.select(_db.editorObservations)
          ..where((t) => t.sessionId.equals(sessionId))
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.timestamp, mode: OrderingMode.desc),
          ])
          ..limit(limit))
        .get();
  }

  /// 统计 session 的 observation 总数
  /// 真源：editor-observation-dao.ts countObservations
  Future<int> countObservations(String sessionId) async {
    final query = _db.selectOnly(_db.editorObservations)
      ..addColumns([_db.editorObservations.id.count()])
      ..where(_db.editorObservations.sessionId.equals(sessionId));
    final row = await query.getSingle();
    return row.read(_db.editorObservations.id.count()) ?? 0;
  }

  /// 统计 session 中教师触发的 observation 数（teacher_triggered=1）
  /// 真源：editor-observation-dao.ts countTriggeredObservations
  Future<int> countTriggeredObservations(String sessionId) async {
    final query = _db.selectOnly(_db.editorObservations)
      ..addColumns([_db.editorObservations.id.count()])
      ..where(
        _db.editorObservations.sessionId.equals(sessionId) &
            _db.editorObservations.teacherTriggered.equals(1),
      );
    final row = await query.getSingle();
    return row.read(_db.editorObservations.id.count()) ?? 0;
  }

  /// 获取 session 全部 observation（时间正序，审计用）
  Future<List<EditorObservationRow>> getAllObservations(
    String sessionId,
  ) async {
    return (_db.select(_db.editorObservations)
          ..where((t) => t.sessionId.equals(sessionId))
          ..orderBy([(t) => OrderingTerm(expression: t.timestamp)]))
        .get();
  }

  /// 根据 message_id 获取单条 observation
  Future<EditorObservationRow?> getObservationByMessage(
    String messageId,
  ) async {
    return (_db.select(_db.editorObservations)
          ..where((t) => t.messageId.equals(messageId))
          ..limit(1))
        .getSingleOrNull();
  }
}

List<Map<String, dynamic>> _serializeObservations(
  List<EditorObservation> observations,
) {
  return observations
      .map(
        (o) => {
          'dimension': o.dimension,
          'dimension_name': o.dimensionName,
          'phenomenon': o.phenomenon,
          'evidence': o.evidence,
          'reader_impact': o.readerImpact,
          'observation_visibility': o.observationVisibility,
          'intent_alignment': o.intentAlignment,
        },
      )
      .toList();
}
