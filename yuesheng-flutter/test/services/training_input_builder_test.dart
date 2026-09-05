// ─────────────────────────────────────────────────────────────
// TrainingInputBuilder 单元测试 — FSM 起点真实化（批次 44）
//
// 覆盖路径：
//   1. 诊断历史充足 + 趋势改善 → teachingState 起点 = consolidating
//      （修复：原硬编码 identified，FSM 永远到不了 consolidating）
//   2. 诊断历史少（<2）→ 返回 null（既有行为保持）
//   3. 多次诊断但未稳定改善 → 起点不越级（conservative，不误判 consolidating）
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/services/training_input_builder.dart';
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  late AppDatabase db;
  late SessionRepository sessionRepo;
  late StudentModelRepository studentModelRepo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    studentModelRepo = StudentModelRepository(db);
  });

  tearDown(() async => db.close());

  Future<String> seedSession() async {
    return sessionRepo.createBlankSession();
  }

  Future<void> appendDiagnosis(
    String sessionId, {
    required String maxSeverity,
    required int timestamp,
    String syndromeId = 's1',
  }) async {
    await studentModelRepo.appendTeachingHistory(sessionId, {
      'type': 'diagnosis',
      'syndromes': [syndromeId],
      'maxSeverity': maxSeverity,
      'timestamp': timestamp,
      'sessionId': sessionId,
    });
  }

  Future<void> appendTraining(
    String sessionId, {
    String result = 'passed',
  }) async {
    await studentModelRepo.appendTeachingHistory(sessionId, {
      'type': 'training',
      'syndromeId': 's1',
      'result': result,
      'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
  }

  group('buildTrainingInputForActiveSyndrome — FSM 起点', () {
    test(
      '#1 诊断充足 + 趋势改善（L3→L2→L1→L1）→ teachingState 起点 = consolidating',
      () async {
        final sessionId = await seedSession();
        // 时间正序：L3(最旧) → L2 → L1 → L1(最新)
        await appendDiagnosis(sessionId, maxSeverity: 'L3', timestamp: 1000);
        await appendDiagnosis(sessionId, maxSeverity: 'L2', timestamp: 2000);
        await appendDiagnosis(sessionId, maxSeverity: 'L1', timestamp: 3000);
        await appendDiagnosis(sessionId, maxSeverity: 'L1', timestamp: 4000);
        await appendTraining(sessionId);

        final input = await buildTrainingInputForActiveSyndrome(
          studentModelRepo,
          sessionId,
          's1',
          const ActiveProblemMeta(currentSeverity: Severity.l1),
        );

        expect(input, isNotNull);
        // 批次 44 修复核心：起点不再是硬编码 identified，
        // 而是按诊断历史推断出 consolidating（评估报告徽章可达「趋稳中」）
        expect(input!.teachingState, TeachingState.consolidating);
      },
    );

    test('#1b 恰好 2 条诊断（阈值边界）→ 非 null', () async {
      final sessionId = await seedSession();
      await appendDiagnosis(sessionId, maxSeverity: 'L2', timestamp: 1000);
      await appendDiagnosis(sessionId, maxSeverity: 'L1', timestamp: 2000);

      final input = await buildTrainingInputForActiveSyndrome(
        studentModelRepo,
        sessionId,
        's1',
        const ActiveProblemMeta(currentSeverity: Severity.l1),
      );

      expect(input, isNotNull);
    });

    test('#2 诊断历史不足（<2 条）→ null（既有行为保持）', () async {
      final sessionId = await seedSession();
      await appendDiagnosis(sessionId, maxSeverity: 'L2', timestamp: 1000);

      final input = await buildTrainingInputForActiveSyndrome(
        studentModelRepo,
        sessionId,
        's1',
        const ActiveProblemMeta(currentSeverity: Severity.l2),
      );

      expect(input, isNull);
    });

    test('#2b 训练尾部连续 failed → deteriorationInput 连续失败锚定', () async {
      final sessionId = await seedSession();
      await appendDiagnosis(sessionId, maxSeverity: 'L2', timestamp: 1000);
      await appendDiagnosis(sessionId, maxSeverity: 'L1', timestamp: 2000);
      await studentModelRepo.appendTeachingHistory(sessionId, {
        'type': 'training',
        'syndromeId': 's1',
        'result': 'failed',
        'timestamp': 3000,
        'sessionId': sessionId,
      });
      await studentModelRepo.appendTeachingHistory(sessionId, {
        'type': 'training',
        'syndromeId': 's1',
        'result': 'failed',
        'timestamp': 4000,
        'sessionId': sessionId,
      });

      final input = await buildTrainingInputForActiveSyndrome(
        studentModelRepo,
        sessionId,
        's1',
        const ActiveProblemMeta(currentSeverity: Severity.l1),
      );

      expect(input, isNotNull);
      expect(input!.deteriorationInput.consecutiveFailures, 2);
    });

    test('#3 多次诊断但未稳定改善（L1→L2→L1→L2 波动）→ 起点不越级到 consolidating', () async {
      final sessionId = await seedSession();
      await appendDiagnosis(sessionId, maxSeverity: 'L1', timestamp: 1000);
      await appendDiagnosis(sessionId, maxSeverity: 'L2', timestamp: 2000);
      await appendDiagnosis(sessionId, maxSeverity: 'L1', timestamp: 3000);
      await appendDiagnosis(sessionId, maxSeverity: 'L2', timestamp: 4000);

      final input = await buildTrainingInputForActiveSyndrome(
        studentModelRepo,
        sessionId,
        's1',
        const ActiveProblemMeta(currentSeverity: Severity.l2),
      );

      expect(input, isNotNull);
      // 波动无改善趋势 → 起点为 in_progress（保守，不误判 consolidating）
      expect(input!.teachingState, TeachingState.inProgress);
    });
  });

  group('computeTrainingPerformance（批次16 7.2 performance_gate）', () {
    Future<void> appendTrainingAt(
      String sessionId, {
      required String result,
      required int timestamp,
      String syndromeId = 's1',
    }) async {
      await studentModelRepo.appendTeachingHistory(sessionId, {
        'type': 'training',
        'syndromeId': syndromeId,
        'result': result,
        'timestamp': timestamp,
        'sessionId': sessionId,
      });
    }

    test('#P1 无训练记录 → null', () async {
      final sessionId = await seedSession();
      expect(
        await computeTrainingPerformance(studentModelRepo, sessionId, 's1'),
        isNull,
      );
    });

    test('#P2 混合结果 → passRate / 连续段计算正确', () async {
      final sessionId = await seedSession();
      // 时间正序：failed → passed → partial → passed（最新）
      await appendTrainingAt(sessionId, result: 'failed', timestamp: 1000);
      await appendTrainingAt(sessionId, result: 'passed', timestamp: 2000);
      await appendTrainingAt(sessionId, result: 'partial', timestamp: 3000);
      await appendTrainingAt(sessionId, result: 'passed', timestamp: 4000);

      final p = await computeTrainingPerformance(
        studentModelRepo,
        sessionId,
        's1',
      );
      expect(p, isNotNull);
      expect(p!.totalCount, 4);
      expect(p.passRate, 0.5); // 2 passed / 4
      expect(p.consecutivePasses, 1); // 最新为 passed，遇 partial 中断
      expect(p.consecutiveFails, 0); // 最新为 passed，不是 failed
    });

    test('#P3 连续未达标 → consecutiveFails 正确（partial 不计入）', () async {
      final sessionId = await seedSession();
      await appendTrainingAt(sessionId, result: 'partial', timestamp: 1000);
      await appendTrainingAt(sessionId, result: 'failed', timestamp: 2000);
      await appendTrainingAt(sessionId, result: 'failed', timestamp: 3000);

      final p = await computeTrainingPerformance(
        studentModelRepo,
        sessionId,
        's1',
      );
      expect(p, isNotNull);
      expect(p!.passRate, 0.0);
      expect(p.consecutiveFails, 2);
      expect(p.consecutivePasses, 0);
    });

    test('#P4 只统计目标症候，不串其他症候', () async {
      final sessionId = await seedSession();
      await appendTrainingAt(sessionId, result: 'passed', timestamp: 1000);
      await appendTrainingAt(
        sessionId,
        result: 'failed',
        timestamp: 2000,
        syndromeId: 's2',
      );

      final p = await computeTrainingPerformance(
        studentModelRepo,
        sessionId,
        's1',
      );
      expect(p, isNotNull);
      expect(p!.totalCount, 1);
      expect(p.passRate, 1.0);
      expect(p.consecutiveFails, 0);
    });
  });
}
