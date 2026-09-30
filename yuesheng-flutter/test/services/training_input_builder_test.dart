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
import 'package:writingcoach/services/training_evaluator.dart';
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

  // ═════════════════════════════════════════════════════════════
  // ADR-C105 B5：派生字段的**直接**断言（不改实现，经输出 DTO 直锚）
  //
  // 立项依据（v3 更正后的实测）：`buildTrainingInputForActiveSyndrome` 的真实
  // 直接调用 = 5 处 / 1 文件（本文件 :76/:95/:109/:138/:156），但它们断言的
  // 只是 `teachingState` 与 `consecutiveFailures`。以下 helper **此前无任何
  // 直接断言**：`_resolvePreviousSeverity` / `_computeGapDays` /
  // `_computeDaysSinceLastObservation` / `_hasConfirmation` /
  // `_countConsecutiveLowSeverity` / `_isRelapseDetected` / `_loadTrainingFields`。
  // 它们的值全部经 `_assembleSummary` 落到输出 DTO ⇒ 可从 DTO 直锚，无需改实现。
  // ═════════════════════════════════════════════════════════════

  group('ADR-C105 B5 派生字段直接断言', () {
    /// 以「天」为单位构造时间戳（base 取大固定值，避免负数/溢出）
    int ts(int day) => 1000000 + day * 86400;

    Future<EvaluationSummaryInput> buildInput(
      String sessionId,
      Severity currentSeverity,
    ) async {
      final input = await buildTrainingInputForActiveSyndrome(
        studentModelRepo,
        sessionId,
        's1',
        ActiveProblemMeta(currentSeverity: currentSeverity),
      );
      if (input == null) {
        fail('前置不满足：诊断记录 < 2 条时返回 null（检查本用例的种子）');
      }
      return input;
    }

    test('★previousSeverity 取**倒数第二条**诊断（不是第一条/最旧条）', () async {
      final sessionId = await seedSession();
      // 时间正序：L1(day0) → L2(day10) → L1(day20) → L1(day30 最新)
      await appendDiagnosis(sessionId, maxSeverity: 'L1', timestamp: ts(0));
      await appendDiagnosis(sessionId, maxSeverity: 'L2', timestamp: ts(10));
      await appendDiagnosis(sessionId, maxSeverity: 'L1', timestamp: ts(20));
      await appendDiagnosis(sessionId, maxSeverity: 'L1', timestamp: ts(30));

      final input = await buildInput(sessionId, Severity.l1);
      expect(
        input.severityInput.previousSeverity,
        Severity.l1,
        reason:
            'previousSeverity = 倒序第 2 条（day20 的 L1）。'
            '若误取「倒序第 0 条」会得到同为 L1 而蒙混过关；'
            '若误取「最旧条」会得到 L1 也相同 ⇒ 本用例再叠一条对照（下一条用例用 L2 区分）',
      );
      expect(input.severityInput.occurrenceCount, 4);
    });

    test('★previousSeverity 与最新一条区分（倒数第二条 L2、最新 L1）', () async {
      final sessionId = await seedSession();
      // 正序：L1(day0) → L2(day10) → L1(day20 最新)
      await appendDiagnosis(sessionId, maxSeverity: 'L1', timestamp: ts(0));
      await appendDiagnosis(sessionId, maxSeverity: 'L2', timestamp: ts(10));
      await appendDiagnosis(sessionId, maxSeverity: 'L1', timestamp: ts(20));

      final input = await buildInput(sessionId, Severity.l1);
      expect(
        input.severityInput.previousSeverity,
        Severity.l2,
        reason:
            '倒序 = [L1(20), L2(10), L1(0)] ⇒ 第 2 条是 L2；'
            '若有人把它改成取最旧条（L1）或最新条（L1），本断言立即变红',
      );
    });

    test('★gapDays = 最近两次诊断的间隔（天，向下取整）', () async {
      final sessionId = await seedSession();
      await appendDiagnosis(sessionId, maxSeverity: 'L2', timestamp: ts(0));
      await appendDiagnosis(sessionId, maxSeverity: 'L1', timestamp: ts(20));
      await appendDiagnosis(sessionId, maxSeverity: 'L1', timestamp: ts(30));

      final input = await buildInput(sessionId, Severity.l1);
      expect(
        input.deteriorationInput.gapDays,
        10,
        reason: '(day30 − day20) = 10 天；若误取「最新 − 最旧」会得到 30',
      );
    });

    test('★consecutiveLowSeverity = 自最新往前数连续 L1 个数（遇非 L1 断）', () async {
      final sessionId = await seedSession();
      // 正序：L1(0) → L2(10) → L1(20) → L1(30)
      await appendDiagnosis(sessionId, maxSeverity: 'L1', timestamp: ts(0));
      await appendDiagnosis(sessionId, maxSeverity: 'L2', timestamp: ts(10));
      await appendDiagnosis(sessionId, maxSeverity: 'L1', timestamp: ts(20));
      await appendDiagnosis(sessionId, maxSeverity: 'L1', timestamp: ts(30));

      final input = await buildInput(sessionId, Severity.l1);
      expect(
        input.stateTransitionInput.consecutiveLowSeverity,
        2,
        reason: '倒序扫：L1、L1、遇 L2 停止 ⇒ 2；若把整个序列都数进来会得到 3',
      );
    });

    test('★relapseDetected 三态：L1→L2 真 / L1→L3 真 / L1→L1 假', () async {
      // 两条 L1 诊断 ⇒ 倒序第 2 条（=最旧）为 L1，即可作为「上次严重度」
      final sid = await seedSession();
      await appendDiagnosis(sid, maxSeverity: 'L1', timestamp: ts(0));
      await appendDiagnosis(sid, maxSeverity: 'L1', timestamp: ts(10));
      expect(
        (await buildInput(
          sid,
          Severity.l2,
        )).stateTransitionInput.relapseDetected,
        isTrue,
      );
      expect(
        (await buildInput(
          sid,
          Severity.l3,
        )).stateTransitionInput.relapseDetected,
        isTrue,
      );
      expect(
        (await buildInput(
          sid,
          Severity.l1,
        )).stateTransitionInput.relapseDetected,
        isFalse,
        reason: '当前仍 L1 ⇒ 不算复发（本三态是 ADR-C105 B5 要求的用例）',
      );
    });

    test('★wasResolvedToL1 需 confirmation 命中 confirmed+L1（错一个即假）', () async {
      final sessionId = await seedSession();
      await appendDiagnosis(sessionId, maxSeverity: 'L2', timestamp: ts(0));
      await appendDiagnosis(sessionId, maxSeverity: 'L1', timestamp: ts(10));

      Future<void> appendConfirmation({
        required String action,
        required String severity,
      }) => studentModelRepo.appendTeachingHistory(sessionId, {
        'type': 'confirmation',
        'syndromes': ['s1'],
        'action': action,
        'severity': severity,
        'timestamp': ts(11),
        'sessionId': sessionId,
      });

      // 未加确认记录 → false
      expect(
        (await buildInput(
          sessionId,
          Severity.l2,
        )).deteriorationInput.wasResolvedToL1,
        isFalse,
      );

      // 加一条 severity=L2 的确认 → 仍 false（严重度不匹配）
      await appendConfirmation(action: 'confirmed', severity: 'L2');
      expect(
        (await buildInput(
          sessionId,
          Severity.l2,
        )).deteriorationInput.wasResolvedToL1,
        isFalse,
        reason: 'confirmed 但 severity≠L1 ⇒ 不得算「已缓解到 L1」',
      );

      // 加一条 confirmed+L1 → true
      await appendConfirmation(action: 'confirmed', severity: 'L1');
      expect(
        (await buildInput(
          sessionId,
          Severity.l2,
        )).deteriorationInput.wasResolvedToL1,
        isTrue,
      );
    });

    test('★daysSinceLastObservation 取「训练/诊断」中更近者（非仅诊断）', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final sessionId = await seedSession();
      // 诊断在 10 天前；训练在 1 天前 ⇒ 最近观察应是训练
      await appendDiagnosis(
        sessionId,
        maxSeverity: 'L2',
        timestamp: now - 10 * 86400,
      );
      await appendDiagnosis(
        sessionId,
        maxSeverity: 'L1',
        timestamp: now - 9 * 86400,
      );
      await studentModelRepo.appendTeachingHistory(sessionId, {
        'type': 'training',
        'syndromeId': 's1',
        'result': 'passed',
        'timestamp': now - 1 * 86400,
        'sessionId': sessionId,
      });

      final input = await buildInput(sessionId, Severity.l1);
      expect(
        input.stateTransitionInput.daysSinceLastObservation,
        lessThan(5),
        reason:
            '最近观察 = 1 天前的训练。若实现漏掉训练分支、只看诊断，'
            '会得到 ~9~10 ⇒ 断言失败（本用例守护「训练也算观察」语义）',
      );

      // 对照组：移除训练（新建会话只留诊断）⇒ 应以诊断为准（≈9 天）
      final sid2 = await seedSession();
      await appendDiagnosis(
        sid2,
        maxSeverity: 'L2',
        timestamp: now - 10 * 86400,
      );
      await appendDiagnosis(
        sid2,
        maxSeverity: 'L1',
        timestamp: now - 9 * 86400,
      );
      final input2 = await buildInput(sid2, Severity.l1);
      expect(
        input2.stateTransitionInput.daysSinceLastObservation,
        greaterThanOrEqualTo(8),
        reason: '无训练时以最近诊断为准（≈9 天）',
      );
    });
  });
}
