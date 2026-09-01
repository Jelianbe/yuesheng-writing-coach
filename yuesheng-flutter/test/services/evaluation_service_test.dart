// ─────────────────────────────────────────────────────────────
// EvaluationService 单元测试 — 多轮评估计算
//
// 覆盖路径：
//   1. 无诊断历史 → 返回 null
//   2. 有诊断历史 → 返回 EvaluationData（round/trend/trainingCount/summaryText）
//   3. 症候明细：teachingState + passCount/totalCount（training-evaluator 真数据）
//   4. 达标率聚合：confirmed 确认记录提升 passRate
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/services/evaluation_service.dart';
import 'package:writingcoach/services/phase_transition.dart';
import 'package:writingcoach/types/display_types.dart';
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  late AppDatabase db;
  late SessionRepository sessionRepo;
  late DiagnosisRepository diagnosisRepo;
  late StudentModelRepository studentModelRepo;
  late EvaluationService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    diagnosisRepo = DiagnosisRepository(db);
    studentModelRepo = StudentModelRepository(db);
    service = EvaluationService(diagnosisRepo, studentModelRepo);
  });

  tearDown(() async => db.close());

  Future<String> seedSession() async {
    return sessionRepo.createBlankSession();
  }

  Future<void> seedDiagnosis(
    String sessionId, {
    List<Map<String, dynamic>>? syndromes,
  }) async {
    final msgId = await sessionRepo.addMessage(
      sessionId,
      'assistant',
      '诊断内容',
      messageType: 'diagnosis_result',
    );
    await diagnosisRepo.commitDiagnosis(
      DiagnosisInput(
        sessionId: sessionId,
        messageId: msgId,
        syndromes:
            syndromes ??
            [
              {'syndrome_id': 's1', 'name': '叙事含糊', 'severity': 'L2'},
            ],
        suggestedActions: const [],
        confidence: 0.8,
      ),
    );
  }

  group('EvaluationService.computeRoundEvaluation', () {
    test('#1 无诊断历史 → null', () async {
      final sessionId = await seedSession();

      final result = await service.computeRoundEvaluation(sessionId, 0);

      expect(result, isNull);
    });

    test('#2 有诊断历史 → 返回完整 EvaluationData', () async {
      final sessionId = await seedSession();
      await seedDiagnosis(sessionId);

      final result = await service.computeRoundEvaluation(sessionId, 0);

      expect(result, isNotNull);
      expect(result!.round, 0);
      expect(result.trend, isA<EvaluationTrend>());
      expect(result.trainingCount, greaterThanOrEqualTo(1));
      expect(result.summaryText, isNotEmpty);
      expect(result.generatedAt, greaterThan(0));
    });

    test(
      '#3 症候明细：teachingState + passCount/totalCount 来自 training-evaluator',
      () async {
        final sessionId = await seedSession();
        await seedDiagnosis(sessionId);

        final result = await service.computeRoundEvaluation(sessionId, 0);

        expect(result, isNotNull);
        expect(result!.syndromeDetails, isNotEmpty);
        final detail = result.syndromeDetails.first;
        expect(detail.syndromeId, 's1');
        expect(detail.syndromeName, '叙事含糊');
        expect(detail.teachingState, isA<TeachingState>());
        expect(detail.totalCount, greaterThanOrEqualTo(1));
      },
    );

    test('#4 confirmed 确认记录提升 passRate 聚合', () async {
      final sessionId = await seedSession();
      await seedDiagnosis(sessionId);
      // 确认记录：写入 teaching_history
      await studentModelRepo.appendTeachingHistory(sessionId, {
        'type': 'confirmation',
        'syndromes': ['s1'],
        'action': 'confirmed',
        'timestamp': 1700000001,
        'sessionId': sessionId,
      });

      final result = await service.computeRoundEvaluation(sessionId, 0);

      expect(result, isNotNull);
      expect(result!.passRate, greaterThanOrEqualTo(0));
      expect(result.passRate, lessThanOrEqualTo(1));
    });

    test('#5 诊断历史趋势改善 → 教学状态可达 consolidating（批次 44 FSM 起点真实化）', () async {
      final sessionId = await seedSession();
      // 诊断历史（teaching_history）：L3→L2→L1→L1，趋势改善
      // 需先 commitDiagnosis 建 active_problem，再补 teaching_history 供推断
      await seedDiagnosis(sessionId);
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      int ts = now - 4000;
      for (final maxSeverity in ['L3', 'L2', 'L1', 'L1']) {
        await studentModelRepo.appendTeachingHistory(sessionId, {
          'type': 'diagnosis',
          'syndromes': ['s1'],
          'maxSeverity': maxSeverity,
          'timestamp': ts,
          'sessionId': sessionId,
        });
        ts += 1000;
      }
      // 训练记录：trainingStarted = true
      await studentModelRepo.appendTeachingHistory(sessionId, {
        'type': 'training',
        'syndromeId': 's1',
        'result': 'passed',
        'timestamp': now,
      });

      final result = await service.computeRoundEvaluation(sessionId, 0);

      expect(result, isNotNull);
      expect(result!.syndromeDetails, isNotEmpty);
      final detail = result.syndromeDetails.firstWhere(
        (d) => d.syndromeId == 's1',
      );
      // 批次 44 修复：评估报告教学状态可达「趋稳中」（原先被硬编码 identified 阻断）
      expect(detail.teachingState, TeachingState.consolidating);
    });

    test('#6 consolidating→mastered 可达（非 FSRS 降级路径，FSRS 未启用）', () async {
      final sessionId = await seedSession();
      await seedDiagnosis(sessionId);
      // 设置教学状态为 consolidating（FSM 起点）
      await diagnosisRepo.updateTeachingState(sessionId, 's1', 'consolidating');
      // 诊断历史：L3→L2→L1→L1→L1（最近 3 次 L1 → consecutiveLowSeverity=3）
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      int ts = now - 5000;
      for (final maxSeverity in ['L3', 'L2', 'L1', 'L1', 'L1']) {
        await studentModelRepo.appendTeachingHistory(sessionId, {
          'type': 'diagnosis',
          'syndromes': ['s1'],
          'maxSeverity': maxSeverity,
          'timestamp': ts,
          'sessionId': sessionId,
        });
        ts += 1000;
      }
      // 训练记录：5 次 passed（consolidationObservations=5, consecutivePasses=5）
      for (int i = 0; i < 5; i++) {
        await studentModelRepo.appendTeachingHistory(sessionId, {
          'type': 'training',
          'syndromeId': 's1',
          'result': 'passed',
          'timestamp': now + i,
        });
      }

      final result = await service.computeRoundEvaluation(sessionId, 0);

      expect(result, isNotNull);
      expect(result!.syndromeDetails, isNotEmpty);
      final detail = result.syndromeDetails.firstWhere(
        (d) => d.syndromeId == 's1',
      );
      // FSRS 未启用，但非 FSRS 降级路径让 mastered 可达
      expect(detail.teachingState, TeachingState.mastered);
    });
  });

  group('nextPhase', () {
    test('P0→P1', () {
      expect(nextPhase(TeachingPhase.p0Engage), TeachingPhase.p1World);
    });
    test('P1→P2', () {
      expect(nextPhase(TeachingPhase.p1World), TeachingPhase.p2PracticeLoop);
    });
    test('P2→P3', () {
      expect(nextPhase(TeachingPhase.p2PracticeLoop), TeachingPhase.p3Training);
    });
    test('P3→P4', () {
      expect(nextPhase(TeachingPhase.p3Training), TeachingPhase.p4Review);
    });
    test('P4 无下一阶段 → null', () {
      expect(nextPhase(TeachingPhase.p4Review), isNull);
    });
  });

  // ── 批次5 M4-B：validatePhaseTransition 合法性校验 ──

  group('validatePhaseTransition（M4-B）', () {
    test('同阶段 → 合法（无迁移）', () {
      for (final p in TeachingPhase.values) {
        expect(validatePhaseTransition(p, p), isTrue);
      }
    });

    test('相邻递进 → 合法', () {
      expect(
        validatePhaseTransition(TeachingPhase.p0Engage, TeachingPhase.p1World),
        isTrue,
      );
      expect(
        validatePhaseTransition(
          TeachingPhase.p1World,
          TeachingPhase.p2PracticeLoop,
        ),
        isTrue,
      );
      expect(
        validatePhaseTransition(
          TeachingPhase.p2PracticeLoop,
          TeachingPhase.p3Training,
        ),
        isTrue,
      );
      expect(
        validatePhaseTransition(
          TeachingPhase.p3Training,
          TeachingPhase.p4Review,
        ),
        isTrue,
      );
    });

    test('P4→P2 回退 → 合法（下一训练周期）', () {
      expect(
        validatePhaseTransition(
          TeachingPhase.p4Review,
          TeachingPhase.p2PracticeLoop,
        ),
        isTrue,
      );
    });

    test('P4 唯一出口契约（C56/ADR-C54 §9.5 前提锁定）', () {
      // P4 无下一阶段——递进链终点，代码侧自动迁移在 P4 永不触发
      expect(
        nextPhase(TeachingPhase.p4Review),
        isNull,
        reason: 'P4 无下一阶段（phase_transition.dart）——P4 出口只能是 AI 填 P2',
      );
      // P4→P2 是 P4 的唯一出口（prompt 已按 ADR-C54 §9-D 显式指向 P2）
      expect(
        validatePhaseTransition(
          TeachingPhase.p4Review,
          TeachingPhase.p2PracticeLoop,
        ),
        isTrue,
        reason: 'P4→P2 是 P4 的唯一出口',
      );
    });

    test('跳级 → 非法', () {
      expect(
        validatePhaseTransition(
          TeachingPhase.p0Engage,
          TeachingPhase.p2PracticeLoop,
        ),
        isFalse,
      );
      expect(
        validatePhaseTransition(TeachingPhase.p0Engage, TeachingPhase.p4Review),
        isFalse,
      );
      expect(
        validatePhaseTransition(
          TeachingPhase.p1World,
          TeachingPhase.p3Training,
        ),
        isFalse,
      );
    });

    test('非法回退 → 非法（P2→P0、P3→P1 等）', () {
      expect(
        validatePhaseTransition(
          TeachingPhase.p2PracticeLoop,
          TeachingPhase.p0Engage,
        ),
        isFalse,
      );
      expect(
        validatePhaseTransition(
          TeachingPhase.p3Training,
          TeachingPhase.p1World,
        ),
        isFalse,
      );
      expect(
        validatePhaseTransition(TeachingPhase.p4Review, TeachingPhase.p0Engage),
        isFalse,
      );
    });
  });

  // ── 批次5 M4-C：computePassRateForPhaseMigration 达标率计算 ──

  group('computePassRateForPhaseMigration（M4-C）', () {
    test('无 confirmation 记录 → 中性值 0.5', () async {
      final sessionId = await seedSession();
      await seedDiagnosis(sessionId);

      final passRate = await service.computePassRateForPhaseMigration(
        sessionId,
      );

      expect(passRate, 0.5);
    });

    test('全部 confirmed → passRate = 1.0（≥ phasePassRate 允许迁移）', () async {
      final sessionId = await seedSession();
      await seedDiagnosis(sessionId);
      // 批次4（4.2 L3）：最小样本门槛 confirmed+disputed≥3，补足 3 条
      for (int i = 0; i < 3; i++) {
        await studentModelRepo.appendTeachingHistory(sessionId, {
          'type': 'confirmation',
          'syndromes': ['s1'],
          'action': 'confirmed',
          'timestamp': 1700000001 + i,
          'sessionId': sessionId,
        });
      }

      final passRate = await service.computePassRateForPhaseMigration(
        sessionId,
      );

      expect(passRate, 1.0);
      expect(
        passRate,
        greaterThanOrEqualTo(EvaluationThresholds.phasePassRate),
      );
    });

    test('全部 disputed → passRate = 0.0（< phaseFailRate 拦截迁移）', () async {
      final sessionId = await seedSession();
      await seedDiagnosis(sessionId);
      // 批次4（4.2 L3）：最小样本门槛 confirmed+disputed≥3，补足 3 条
      for (int i = 0; i < 3; i++) {
        await studentModelRepo.appendTeachingHistory(sessionId, {
          'type': 'confirmation',
          'syndromes': ['s1'],
          'action': 'disputed',
          'timestamp': 1700000001 + i,
          'sessionId': sessionId,
        });
      }

      final passRate = await service.computePassRateForPhaseMigration(
        sessionId,
      );

      expect(passRate, 0.0);
      expect(passRate, lessThan(EvaluationThresholds.phaseFailRate));
    });

    test('批次4（4.2 L3）：样本量 <3 时返回中性值 0.5（拦截 M4-A 自动迁移）', () async {
      final sessionId = await seedSession();
      await seedDiagnosis(sessionId);
      // 2 条 confirmed 达标率 1.0 属小样本虚高，应被最小样本门槛拦截
      await studentModelRepo.appendTeachingHistory(sessionId, {
        'type': 'confirmation',
        'syndromes': ['s1'],
        'action': 'confirmed',
        'timestamp': 1700000001,
        'sessionId': sessionId,
      });
      await studentModelRepo.appendTeachingHistory(sessionId, {
        'type': 'confirmation',
        'syndromes': ['s1'],
        'action': 'confirmed',
        'timestamp': 1700000002,
        'sessionId': sessionId,
      });

      final passRate = await service.computePassRateForPhaseMigration(
        sessionId,
      );

      expect(passRate, 0.5, reason: '<3 样本不得迁移');
      expect(passRate, lessThan(EvaluationThresholds.phasePassRate));
    });

    test('混合 confirmed/disputed → passRate = confirmed/total', () async {
      final sessionId = await seedSession();
      await seedDiagnosis(sessionId);
      // 3 confirmed + 1 disputed = 0.75
      for (int i = 0; i < 3; i++) {
        await studentModelRepo.appendTeachingHistory(sessionId, {
          'type': 'confirmation',
          'syndromes': ['s1'],
          'action': 'confirmed',
          'timestamp': 1700000001 + i,
          'sessionId': sessionId,
        });
      }
      await studentModelRepo.appendTeachingHistory(sessionId, {
        'type': 'confirmation',
        'syndromes': ['s1'],
        'action': 'disputed',
        'timestamp': 1700000010,
        'sessionId': sessionId,
      });

      final passRate = await service.computePassRateForPhaseMigration(
        sessionId,
      );

      expect(passRate, 0.75);
      expect(
        passRate,
        greaterThanOrEqualTo(EvaluationThresholds.phasePassRate),
      );
    });

    test('非 confirmation 类型的历史记录不计入', () async {
      final sessionId = await seedSession();
      await seedDiagnosis(sessionId);
      // diagnosis / training 记录不影响 passRate
      await studentModelRepo.appendTeachingHistory(sessionId, {
        'type': 'diagnosis',
        'syndromes': ['s1'],
        'timestamp': 1700000001,
        'sessionId': sessionId,
      });
      await studentModelRepo.appendTeachingHistory(sessionId, {
        'type': 'training',
        'syndromes': ['s1'],
        'result': 'passed',
        'timestamp': 1700000002,
        'sessionId': sessionId,
      });

      final passRate = await service.computePassRateForPhaseMigration(
        sessionId,
      );

      expect(passRate, 0.5, reason: '无 confirmation 记录 → 中性值');
    });
  });

  // ── A11 取数方向断言（宪法 §八 A11）：趋势方向与取数语义必须单测守护 ──
  // RN 教训：ORDER BY DESC 后 slice(-2,-1) 取最旧两条 → 趋势失真。
  // Flutter 用 listDiagnosisHistory(ASC) + sublist(len-2,len-1)/sublist(len-1)
  // 取「上一轮 / 当前轮」，必须钉死「列表末位 = 最新一轮」这一语义，
  // 否则顺序一翻、趋势就反。以下用例不依赖 slice 巧合，直接锁定方向。
  group('A11 取数方向断言：最新/最旧不靠 slice 巧合', () {
    DiagnosisRow _diag(String id, String severity) => DiagnosisRow(
      id: id,
      sessionId: 's',
      messageId: 'm$id',
      syndromes: '[{"severity":"$severity"}]',
      suggestedActions: '[]',
      confidence: 0.8,
      timestamp: 0,
      createdAt: 0,
    );

    test('ASC [旧L2→新L1] 趋势=improving（当前取最新一轮）', () {
      final list = [_diag('a', 'L2'), _diag('b', 'L1')];
      expect(service.classifyTrend(0.5, list), EvaluationTrend.improving);
    });

    test('ASC [旧L1→新L2] 趋势=worsening（当前取最新一轮）', () {
      final list = [_diag('a', 'L1'), _diag('b', 'L2')];
      expect(service.classifyTrend(0.5, list), EvaluationTrend.worsening);
    });

    test('方向反转保护：同一组严重度，逆序必得相反趋势', () {
      final asc = [_diag('a', 'L2'), _diag('b', 'L1')]; // 末位 L1 → 改善
      final desc = [_diag('b', 'L1'), _diag('a', 'L2')]; // 末位 L2 → 恶化
      final tAsc = service.classifyTrend(0.5, asc);
      final tDesc = service.classifyTrend(0.5, desc);
      expect(tAsc, EvaluationTrend.improving);
      expect(tDesc, EvaluationTrend.worsening);
      expect(tAsc, isNot(equals(tDesc)));
    });
  });
}
