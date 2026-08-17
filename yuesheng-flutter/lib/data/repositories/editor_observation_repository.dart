// ─────────────────────────────────────────────────────────────
// Editor Observation Repository
// 复刻 yuesheng-android/src/db/dao/editor-observation-dao.ts
//
// 幂等写入：UNIQUE(session_id, message_id) 冲突则更新（见 insertEditorObservation
// 内的原生 SQL，对齐 reference_repository 既有写法）。
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

  /// 新增/更新编辑观察（幂等：UNIQUE(session_id, message_id) 冲突则更新）
  ///
  /// 真源：editor-observation-dao.ts insertEditorObservation
  /// 说明：drift 的 insertOnConflictUpdate 默认以主键冲突为目标，而本表主键为随机
  /// uuid，无法吸收 (session_id, message_id) 的 UNIQUE 冲突，重复写入会抛 UNIQUE
  /// 异常被静默吞（B17）。故用原生 SQL 指定 UNIQUE 约束（对齐 reference_repository
  /// 既有写法），冲突时更新而非抛错。
  Future<String> insertEditorObservation(
    InsertEditorObservationParams params,
  ) async {
    final id = generateUuid();
    final now = nowSec();

    await _db.transaction(() async {
      await _db.customStatement(
        '''
        INSERT INTO editor_observation (
          id, session_id, message_id, possible_intent, intent_confidence,
          observations, overall_impression, strengths, teacher_triggered,
          pronounced_count, against_count, target_ref_type, target_ref_id,
          timestamp, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(session_id, message_id) DO UPDATE SET
          possible_intent = excluded.possible_intent,
          intent_confidence = excluded.intent_confidence,
          observations = excluded.observations,
          overall_impression = excluded.overall_impression,
          strengths = excluded.strengths,
          teacher_triggered = excluded.teacher_triggered,
          pronounced_count = excluded.pronounced_count,
          against_count = excluded.against_count,
          target_ref_type = excluded.target_ref_type,
          target_ref_id = excluded.target_ref_id,
          timestamp = excluded.timestamp
        ''',
        [
          id,
          params.sessionId,
          params.messageId,
          params.editorResult.possibleIntent,
          params.editorResult.intentConfidence,
          jsonEncode(_serializeObservations(params.editorResult.observations)),
          params.editorResult.overallImpression,
          jsonEncode(params.editorResult.strengths),
          params.teacherTriggered ? 1 : 0,
          params.pronouncedCount,
          params.againstCount,
          params.targetRefType,
          params.targetRefId,
          now,
          now,
        ],
      );
    });

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
