// ─────────────────────────────────────────────────────────────
// PilotMetricsRepository — 冷启动试点埋点（ADR-C121，v41）
//
// 追加式事件日志。ADR-C122 裁定：卡片墙整体退役（30 秒机制作废），
// card_wall_entered / micro_task_submitted **停写**；v41 表既有历史数据
// 保留（迁移兼容，只停写不删表）。app_opened 继续记录（通用启动埋点）。
//
// 事件类型（event_type）：
//   - card_wall_entered    学员打开卡片墙（ADR-C122 起停写，历史数据保留）
//   - micro_task_submitted 提交微任务产出（ADR-C122 起停写，历史数据保留）
//   - app_opened           每次冷启动（session_id 记 ''，用户级）
//
// 可诊断率不在此表：由 diagnosis_results（message_id/session_id 维度）
// 按「提交消息 → 诊断落库」关联计算（复用既有诊断链路，见 chat_service
// _applyDiagnosisInjection → _runDiagnosisFlow）。
//
// ⚠️ 试点专用表，正式设计批评估后决定去留；本批不承诺长期保留。
// ─────────────────────────────────────────────────────────────

import 'package:drift/drift.dart';

import '../database/database.dart';
import '../database/utils.dart';
import 'repository_write_guard.dart';

/// 试点事件类型常量（单一真源；消费方不得裸写字符串）
class PilotEventTypes {
  static const String cardWallEntered = 'card_wall_entered';
  static const String microTaskSubmitted = 'micro_task_submitted';
  static const String appOpened = 'app_opened';
  const PilotEventTypes._();
}

/// 微任务提交 payload 规约（ADR-C122 起停写，仅历史数据 decode/读数用）
class PilotSubmitPayload {
  /// 微任务卡 id（历史数据）
  final String card;

  /// 提交文本字数（历史数据）
  final int chars;

  const PilotSubmitPayload({required this.card, required this.chars});

  String encode() => '{"card":"$card","chars":$chars}';

  static PilotSubmitPayload decode(String raw) {
    final card = raw.contains('"card":')
        ? raw.split('"card":"').last.split('"').first
        : '';
    final charsRaw = raw.contains('"chars":')
        ? raw.split('"chars":').last.split(RegExp(r'[},]')).first
        : '';
    return PilotSubmitPayload(card: card, chars: int.tryParse(charsRaw) ?? 0);
  }
}

class PilotMetricsRepository {
  final AppDatabase _db;
  PilotMetricsRepository(this._db);

  /// 记录一条试点事件（追加式，写失败留痕后原样抛出，由调用方降级）。
  Future<void> recordEvent({
    required String sessionId,
    required String eventType,
    String payload = '',
  }) => guardRepoWrite('pilot_metrics', 'recordEvent', () async {
    await _db
        .into(_db.pilotMetricEvents)
        .insert(
          PilotMetricEventsCompanion.insert(
            id: generateUuid(),
            sessionId: sessionId,
            eventType: eventType,
            payload: Value(payload),
          ),
        );
  });

  /// 按会话查询全部事件（时间升序，验收读数用）。
  Future<List<PilotMetricEvent>> listBySession(String sessionId) =>
      (_db.select(_db.pilotMetricEvents)
            ..where((t) => t.sessionId.equals(sessionId))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();

  /// 按事件类型查询（跨会话，验收读数用）。
  Future<List<PilotMetricEvent>> listByType(String eventType) =>
      (_db.select(_db.pilotMetricEvents)
            ..where((t) => t.eventType.equals(eventType))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();

  /// 指定会话、指定事件类型的条数（验收读数用）。
  Future<int> countByType(String sessionId, String eventType) async {
    final rows =
        await (_db.select(_db.pilotMetricEvents)..where(
              (t) =>
                  t.sessionId.equals(sessionId) & t.eventType.equals(eventType),
            ))
            .get();
    return rows.length;
  }
}
