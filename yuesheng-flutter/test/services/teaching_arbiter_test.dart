// ─────────────────────────────────────────────────────────────
// teaching_arbiter 单元测试 — D3 批落地（方案 X · 不闸门）
//
// 守「不触 R-027」边界：shouldTeach=false 时仍调 resolveTeachingFocus /
// buildTrainingInputForActiveSyndrome——注入路径输出不变。
//
// 覆盖路径：
//   1. 教路径：3 阀全调通 ⇒ activatedFocusId + trainingInput + shouldTeach=true
//   2. 不教路径（方案 X 守不闸门）：shouldTeach=false 但 activatedFocusId /
//      trainingInput 仍按各阀原判据计算
//   3. 调用顺序契约：arbitrationTrace 按阀1→阀2→阀3 顺序记录
//   4. activatedFocusId 为空 ⇒ trainingInput=null（与现行 message_injector 一致）
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/services/focus_resolver.dart';
import 'package:writingcoach/services/teaching_arbiter.dart';
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  late AppDatabase db;
  late SessionRepository sessionRepo;
  late StudentModelRepository studentModelRepo;
  late DiagnosisRepository diagnosisRepo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    studentModelRepo = StudentModelRepository(db);
    diagnosisRepo = DiagnosisRepository(db);
  });

  tearDown(() async => db.close());

  Future<String> seedSession() async => sessionRepo.createBlankSession();

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
    String syndromeId = 's1',
  }) async {
    await studentModelRepo.appendTeachingHistory(sessionId, {
      'type': 'training',
      'syndromeId': syndromeId,
      'result': result,
      'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
  }

  ResolveFocusInput buildFocusInput({
    List<ActiveProblemView> activeProblems = const [],
    String? aiSuggestedFocusId,
  }) {
    final problems = activeProblems
        .map(
          (p) => FocusProblem(
            syndromeId: p.syndromeId,
            syndromeName: p.syndromeName,
            severity: Severity.fromString(p.severity) ?? Severity.l2,
            confirmationStatus:
                ConfirmationStatus.fromString(p.confirmationStatus) ??
                ConfirmationStatus.suspected,
            status: 'active',
            confirmedAt: p.confirmedAt,
          ),
        )
        .toList();
    return ResolveFocusInput(
      problems: problems,
      aiSuggestedFocusId: aiSuggestedFocusId,
      userFocusOverride: null,
      subphase: null,
      focusHistory: const [],
    );
  }

  ActiveProblemView buildActiveProblem({
    String syndromeId = 's1',
    String syndromeName = '测试症候',
    String severity = 'L2',
    String confirmationStatus = 'confirmed',
  }) {
    return ActiveProblemView(
      syndromeId: syndromeId,
      syndromeName: syndromeName,
      severity: severity,
      confirmationStatus: confirmationStatus,
    );
  }

  Syndrome buildSyndrome({
    String syndromeId = 's1',
    String name = '测试症候',
    Severity severity = Severity.l2,
  }) {
    return Syndrome(
      syndromeId: syndromeId,
      name: name,
      severity: severity,
      evidence: const [],
      explanation: '',
    );
  }

  group('arbitrate — 教路径', () {
    test(
      '#1 3 阀全调通 ⇒ activatedFocusId + trainingInput + shouldTeach=true',
      () async {
        final sessionId = await seedSession();
        await appendDiagnosis(sessionId, maxSeverity: 'L3', timestamp: 1000);
        await appendDiagnosis(sessionId, maxSeverity: 'L2', timestamp: 2000);
        await appendTraining(sessionId);

        final activeProblem = buildActiveProblem(severity: 'L2');
        final input = ArbitrationInput(
          syndromes: [buildSyndrome(severity: Severity.l2)],
          focusInput: buildFocusInput(
            activeProblems: [activeProblem],
            aiSuggestedFocusId: 's1',
          ),
          studentModelRepo: studentModelRepo,
          sessionId: sessionId,
          activeProblems: [activeProblem],
          diagnosisRepo: diagnosisRepo,
        );

        final result = await arbitrate(input);

        expect(result.shouldTeach, isTrue);
        expect(result.focusOutput.activatedFocusId, 's1');
        expect(result.trainingInput, isNotNull);
      },
    );
  });

  group('arbitrate — 不教路径（方案 X · 守不闸门）', () {
    test(
      '#2 shouldTeach=false 但 activatedFocusId/trainingInput 仍按各阀原判据计算',
      () async {
        final sessionId = await seedSession();
        // 训练输入需 2+ 条诊断才能算出非 null trainingInput
        await appendDiagnosis(sessionId, maxSeverity: 'L1', timestamp: 1000);
        await appendDiagnosis(sessionId, maxSeverity: 'L1', timestamp: 2000);
        await appendTraining(sessionId);

        // 1 个 L1 症候 ⇒ shouldTriggerTeacherForDiagnosis=false
        // （无 L2/L3 且 syndromeCount < 3）
        final activeProblem = buildActiveProblem(severity: 'L1');
        final input = ArbitrationInput(
          syndromes: [buildSyndrome(severity: Severity.l1)],
          focusInput: buildFocusInput(
            activeProblems: [activeProblem],
            aiSuggestedFocusId: 's1',
          ),
          studentModelRepo: studentModelRepo,
          sessionId: sessionId,
          activeProblems: [activeProblem],
          diagnosisRepo: diagnosisRepo,
        );

        final result = await arbitrate(input);

        // shouldTeach 字段反映 shouldTriggerTeacherForDiagnosis 结果
        expect(result.shouldTeach, isFalse);
        // ★ 守「不触 R-027」边界：shouldTeach=false 时仍调 resolveTeachingFocus
        //   和 buildTrainingInputForActiveSyndrome——activatedFocusId 和
        //   trainingInput 仍按各阀原判据计算（注入路径输出不变）
        expect(result.focusOutput.activatedFocusId, 's1');
        expect(result.trainingInput, isNotNull);
      },
    );
  });

  group('arbitrate — 调用顺序契约', () {
    test('#3 arbitrationTrace 按阀1→阀2→阀3 顺序记录', () async {
      final sessionId = await seedSession();
      await appendDiagnosis(sessionId, maxSeverity: 'L2', timestamp: 1000);
      await appendDiagnosis(sessionId, maxSeverity: 'L1', timestamp: 2000);
      await appendTraining(sessionId);

      final activeProblem = buildActiveProblem(severity: 'L2');
      final input = ArbitrationInput(
        syndromes: [buildSyndrome(severity: Severity.l2)],
        focusInput: buildFocusInput(
          activeProblems: [activeProblem],
          aiSuggestedFocusId: 's1',
        ),
        studentModelRepo: studentModelRepo,
        sessionId: sessionId,
        activeProblems: [activeProblem],
        diagnosisRepo: diagnosisRepo,
      );

      final result = await arbitrate(input);

      // 3 条 trace，按阀1→阀2→阀3 顺序
      expect(result.arbitrationTrace.length, 3);
      expect(result.arbitrationTrace[0].contains('阀1'), isTrue);
      expect(result.arbitrationTrace[1].contains('阀2'), isTrue);
      expect(result.arbitrationTrace[2].contains('阀3'), isTrue);
    });
  });

  group('arbitrate — activatedFocusId 为空', () {
    test('#4 activatedFocusId 为空 ⇒ trainingInput=null（阀3 跳过）', () async {
      final sessionId = await seedSession();
      // 无 activeProblem + aiSuggestedFocusId=null + userFocusOverride=null
      // ⇒ resolveTeachingFocus 返回 activatedFocusId=null（fallback 失败）
      final input = ArbitrationInput(
        syndromes: const [],
        focusInput: buildFocusInput(
          activeProblems: const [],
          aiSuggestedFocusId: null,
        ),
        studentModelRepo: studentModelRepo,
        sessionId: sessionId,
        activeProblems: const [],
        diagnosisRepo: diagnosisRepo,
      );

      final result = await arbitrate(input);

      expect(result.focusOutput.activatedFocusId, isNull);
      expect(result.trainingInput, isNull);
      // 阀3 跳过 trace
      expect(result.arbitrationTrace.any((t) => t.contains('阀3 跳过')), isTrue);
    });
  });
}
