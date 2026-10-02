// ─────────────────────────────────────────────────────────────
// diagnosis_pending_growth_test — C126 消费方口径测试
//
// 锁定「计数排除未确认、明细保留记录」两条口径一致：
//   - growth.queryDiagnosisTotal 只数 status='confirmed'（pending/replaced 不计）
//   - progress.totalDiagnoses 只数 status='confirmed'
//   - progress.getDiagnosisHistory 历史列表仍返回全部行（含 pending/replaced）
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/database/utils.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/services/growth_service.dart';
import 'package:writingcoach/services/progress_service.dart';

void main() {
  late AppDatabase db;
  late String sessionId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionId = await SessionRepository(db).createBlankSession();
  });

  tearDown(() async => db.close());

  Future<void> insertRow(String status, int ts) async {
    await db
        .into(db.diagnosisResults)
        .insert(
          DiagnosisResultsCompanion.insert(
            id: generateUuid(),
            sessionId: sessionId,
            messageId: 'msg-${generateUuid()}',
            syndromes: Value(
              jsonEncode([
                {'syndrome_id': 'P005', 'severity': 'L2'},
              ]),
            ),
            suggestedActions: const Value('[]'),
            confidence: const Value(0.8),
            timestamp: Value(ts),
            createdAt: Value(ts),
            status: Value(status),
          ),
        );
  }

  test('growth.getGrowthOverview.totalDiagnoses 只数 confirmed', () async {
    await insertRow('confirmed', 1000);
    await insertRow('pending', 2000);
    await insertRow('replaced', 3000);

    final overview = await GrowthService(db).getGrowthOverview();
    expect(
      overview.totalDiagnoses,
      1,
      reason:
          'queryDiagnosisTotal 加 WHERE status=confirmed，pending/replaced 不计入',
    );
  });

  test('progress.totalDiagnoses 只数 confirmed，但历史列表保留全部行', () async {
    await insertRow('confirmed', 1000);
    await insertRow('pending', 2000);
    await insertRow('replaced', 3000);

    final summary = await ProgressService(db).getProgressSummary(sessionId);
    expect(summary.totalDiagnoses, 1, reason: '计数口径排除未确认结论');

    final history = await ProgressService(db).getDiagnosisHistory(sessionId);
    expect(history.length, 3, reason: '明细列表仍保留全部行（含 pending/replaced 逐条记录）');
  });
}
