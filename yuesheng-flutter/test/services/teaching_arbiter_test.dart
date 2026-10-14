// ─────────────────────────────────────────────────────────────
// teaching_arbiter 单元测试 — D3 批落地；H6 动作2（2026-10-14 舰长批准
// 启用）起阀 1 为真闸门。
//
// 闸门语义：shouldTeach=false ⇒ 跳过阀 2/阀 3（activatedFocusId=null、
// trainingInput=null）；shouldTeach=true ⇒ 行为与 D3 批完全一致。
//
// 覆盖路径：
//   1. 教路径：3 阀全调通 ⇒ activatedFocusId + trainingInput + shouldTeach=true
//   2. 闸门路径：shouldTeach=false ⇒ 阀 2/阀 3 不调用（占位 focusOutput）
//   3. 调用顺序契约：arbitrationTrace 按阀1→阀2→阀3 顺序记录
//   4. 空症候 ⇒ 闸门生效（阀 1 判据：无 L2/L3 且总数 <3）
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

  group('arbitrate — 闸门路径（H6 动作2 · 阀 1 真闸门）', () {
    test(
      '#2 shouldTeach=false ⇒ 阀2/阀3 不调用（activatedFocusId=null、trainingInput=null）',
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

        // 阀 1 判定
        expect(result.shouldTeach, isFalse);
        // ★ H6 动作2 闸门：不解析教学焦点、不构造训练输入。
        //   （旧行为「仍按各阀原判据计算」自 2026-10-14 起废止）
        expect(result.focusOutput.activatedFocusId, isNull);
        expect(result.trainingInput, isNull);
        // 占位输出标注闸门原因
        expect(result.focusOutput.reason, contains('阀1 闸门'));
        // trace 只有阀 1 + 闸门记录，无阀 2/阀 3 调用条目
        // （锚定调用签名而非「阀2」字样——闸门 trace 文案本身提及阀2/阀3）
        expect(
          result.arbitrationTrace.any(
            (t) => t.contains('阀2 resolveTeachingFocus'),
          ),
          isFalse,
        );
        expect(
          result.arbitrationTrace.any(
            (t) => t.contains('阀3 buildTrainingInput'),
          ),
          isFalse,
        );
        expect(
          result.arbitrationTrace.any((t) => t.contains('阀1 闸门生效')),
          isTrue,
        );
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

  group('arbitrate — 空症候（阀 1 判据不满足 ⇒ 闸门生效）', () {
    test('#4 空症候 ⇒ shouldTeach=false 走闸门（activatedFocusId=null）', () async {
      final sessionId = await seedSession();
      // 无 activeProblem + aiSuggestedFocusId=null + userFocusOverride=null
      // ⇒ 阀 1 判据不满足（0 条症候），闸门生效直接返回占位输出
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

      expect(result.shouldTeach, isFalse);
      expect(result.focusOutput.activatedFocusId, isNull);
      expect(result.trainingInput, isNull);
      // H6 动作2：闸门 trace（阀 2/阀 3 未调用，锚定调用签名）
      expect(result.arbitrationTrace.any((t) => t.contains('阀1 闸门生效')), isTrue);
      expect(
        result.arbitrationTrace.any((t) => t.contains('阀3 buildTrainingInput')),
        isFalse,
      );
    });
  });
}
