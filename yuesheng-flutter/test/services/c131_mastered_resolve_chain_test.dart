// ─────────────────────────────────────────────────────────────
// C131 批「顺手清」：FSM 达标结算链（mastered→resolve）补测
//
// 依据：docs/2026-10-01-工作流链条审查报告.md §3.5 可测性表
//   「FSM 达标结算链（mastered→resolve）| 无覆盖 | —」
//
// 本文件补的断言缺口（不重复既有）：
//   1. DiagnosisService.checkAndResolveMastered（diagnosis_service.dart:191-201）
//      —— 此前零直接覆盖：active_problem.teaching_state='mastered' ⇒
//      checkAndResolveMastered 应解锁（status=resolved）并返回该 syndromeId；
//      非 mastered 的活跃症候不得被误解锁。
//   2. EvaluationService 软门控（evaluation_service.dart:431-441 带
//      trainingResultRepo 路径）——既有 evaluation_service_test.dart #6 传
//      null repo（门控整段跳过），本补测注入真实 TrainingResultRepository 并
//      落一条「无自评」训练结果行，如实断言：无证据 ⇒ 软门控放行（true），
//      mastered 迁移照常写回 teaching_state 并立即 resolve。
//
// 边界（R-010）：纯测试层新增，不改任何 lib/ 产品代码。
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/data/repositories/training_result_repository.dart';
import 'package:writingcoach/services/diagnosis_service.dart';
import 'package:writingcoach/services/evaluation_service.dart';
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  late AppDatabase db;
  late SessionRepository sessionRepo;
  late DiagnosisRepository diagnosisRepo;
  late StudentModelRepository studentModelRepo;
  late TrainingResultRepository trainingResultRepo;
  late DiagnosisService diagnosisService;
  late String sessionId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    diagnosisRepo = DiagnosisRepository(db);
    studentModelRepo = StudentModelRepository(db);
    trainingResultRepo = TrainingResultRepository(db);
    diagnosisService = DiagnosisService(
      diagnosisRepo: diagnosisRepo,
      studentModelRepo: studentModelRepo,
    );
    sessionId = await sessionRepo.createBlankSession();
  });

  tearDown(() async => db.close());

  /// 落一条诊断，产出活跃症候 s1（对齐 evaluation_service_test 夹具）。
  Future<void> seedActiveProblem({String syndromeId = 's1'}) async {
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
        syndromes: [
          {'syndrome_id': syndromeId, 'name': '叙事含糊', 'severity': 'L2'},
        ],
        suggestedActions: const [],
        confidence: 0.8,
      ),
    );
  }

  group('DiagnosisService.checkAndResolveMastered（v19 正向达标路径）', () {
    test('mastered 活跃症候 → 解锁 resolved 并返回 id；活跃列表不再含该症候', () async {
      await seedActiveProblem();
      // 模拟 FSM 已把 teaching_state 推进到 mastered
      await diagnosisRepo.updateTeachingState(sessionId, 's1', 'mastered');

      final resolvedIds = await diagnosisService.checkAndResolveMastered(
        sessionId,
      );

      expect(resolvedIds, contains('s1'));
      final active = await diagnosisRepo.listActiveProblems(sessionId);
      expect(
        active.any((p) => p.syndromeId == 's1'),
        isFalse,
        reason:
            'mastered 症候应被 resolveSyndromesBatch 置为 resolved，'
            '不再出现在 active 列表',
      );
    });

    test('非 mastered 活跃症候（in_progress）→ 不解锁、返回空', () async {
      await seedActiveProblem();
      await diagnosisRepo.updateTeachingState(sessionId, 's1', 'in_progress');

      final resolvedIds = await diagnosisService.checkAndResolveMastered(
        sessionId,
      );

      expect(resolvedIds, isEmpty);
      final active = await diagnosisRepo.listActiveProblems(sessionId);
      expect(
        active.any((p) => p.syndromeId == 's1'),
        isTrue,
        reason: '非 mastered 症候不得被正向解锁',
      );
    });

    test('混合：一条 mastered + 一条 in_progress → 仅解锁 mastered', () async {
      await seedActiveProblem(syndromeId: 's1');
      // s2 由第二条诊断落库
      final msgId2 = await sessionRepo.addMessage(
        sessionId,
        'assistant',
        '诊断内容2',
        messageType: 'diagnosis_result',
      );
      await diagnosisRepo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sessionId,
          messageId: msgId2,
          syndromes: [
            {'syndrome_id': 's2', 'name': '视角漂移', 'severity': 'L1'},
          ],
          suggestedActions: const [],
          confidence: 0.8,
        ),
      );
      await diagnosisRepo.updateTeachingState(sessionId, 's1', 'mastered');
      await diagnosisRepo.updateTeachingState(sessionId, 's2', 'consolidating');

      final resolvedIds = await diagnosisService.checkAndResolveMastered(
        sessionId,
      );

      expect(resolvedIds, ['s1']);
      final active = await diagnosisRepo.listActiveProblems(sessionId);
      expect(active.any((p) => p.syndromeId == 's1'), isFalse);
      expect(active.any((p) => p.syndromeId == 's2'), isTrue);
    });
  });

  group('EvaluationService 软门控：注入 TrainingResultRepository + 无自评行', () {
    test('无证据（selfAssessment=null）→ 门控放行，mastered 仍 resolve', () async {
      // 对齐 evaluation_service_test #6 的 mastered 触发夹具：
      // consolidating 起点 + L3→L2→L1→L1→L1 诊断史 + 5 次 passed 训练。
      await seedActiveProblem();
      await diagnosisRepo.updateTeachingState(sessionId, 's1', 'consolidating');
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
      for (int i = 0; i < 5; i++) {
        await studentModelRepo.appendTeachingHistory(sessionId, {
          'type': 'training',
          'syndromeId': 's1',
          'result': 'passed',
          'timestamp': now + i,
        });
      }

      // ★ 关键差异：落一条 training_results 行但 selfAssessment=null
      //   ⇒ masteryEvidenceSatisfiedFromRow 三列皆空 ⇒ 返回 true（放行）。
      await trainingResultRepo.insertTrainingResult(
        InsertTrainingResultParams(
          sessionId: sessionId,
          syndromeId: 's1',
          taskType: 'rewrite',
          userContent: '（学员练习内容）',
          result: 'passed',
          // selfAssessment 故意不传 → confidenceRating/explanationText/
          //   transferText 三列皆 null ⇒ 软门控「无证据放行」路径。
        ),
      );

      // 注入真实 TrainingResultRepository（#6 传 null，本补测走带 repo 路径）
      final service = EvaluationService(
        diagnosisRepo,
        studentModelRepo,
        trainingResultRepo,
      );

      final result = await service.computeRoundEvaluation(sessionId, 0);

      expect(result, isNotNull);
      expect(result!.syndromeDetails, isNotEmpty);
      final detail = result.syndromeDetails.firstWhere(
        (d) => d.syndromeId == 's1',
      );
      expect(
        detail.teachingState,
        TeachingState.mastered,
        reason: '无自评证据时软门控放行，mastered 应照常迁移',
      );
      final active = await diagnosisRepo.listActiveProblems(sessionId);
      expect(
        active.any((p) => p.syndromeId == 's1'),
        isFalse,
        reason: 'mastered 迁移应立即 resolve（status=resolved）',
      );
    });
  });
}
