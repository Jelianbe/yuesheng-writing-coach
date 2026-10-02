// ─────────────────────────────────────────────────────────────
// C123 任务3：beginner_level 双写仲裁单测
//
// 背景：onboarding_service（写点 A，显式学员采集）与 diagnosis_committer
// （写点 B，LLM 主链诊断推断）都写 teaching_state.beginner_level，此前无仲裁。
//
// 批准裁定：显式学员采集 > LLM 推断。LLM 仅在「尚未被显式采集」时回填；
// 显式采集后 LLM 不得覆盖（写点 A 保持无条件覆盖，写点 B 加读门）。
//
// 判据：用户级 questionnaire_completed；但 skipped=true 的 onboarding 也置该
// flag 并写 N0——skip 非显式等级采集，不能据此锁死。故门再用跨会话最新
// onboarding 数据的 skipped 标记排除 skip。
//
// Case A：先显式(N1) 后 LLM(N2) → 学员值保留 N1（LLM 被门丢弃）
// Case B：先 LLM(N2) 后显式(N1) → 学员值覆盖 N1（写点 A 无条件覆盖）
// Case C：未显式 + current NULL → LLM 正常回填（防回归，门开路径不回退）
// Case D：appStateRepo=null → 现状不锁（保护约 130 处既有构造点）
// Case E：skip → 写 N0 + questionnaire_completed=true，但 LLM(N1) 仍可回填
//         （skip ≠ 显式采集，不锁死 N0）
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/app_state_repository.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';
import 'package:writingcoach/services/diagnosis_committer.dart';
import 'package:writingcoach/services/onboarding_service.dart';
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  late AppDatabase db;
  late SessionRepository sessionRepo;
  late TeachingStateRepository stateRepo;
  late DiagnosisRepository diagnosisRepo;
  late StudentModelRepository studentModelRepo;
  late AppStateRepository appStateRepo;
  late OnboardingService onboarding;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    stateRepo = TeachingStateRepository(db);
    diagnosisRepo = DiagnosisRepository(db);
    studentModelRepo = StudentModelRepository(db);
    appStateRepo = AppStateRepository(db);
    onboarding = OnboardingService(
      studentModelRepo: studentModelRepo,
      stateRepo: stateRepo,
      appStateRepo: appStateRepo,
    );
  });

  tearDown(() async => db.close());

  DiagnosisCommitter buildCommitter({AppStateRepository? appStateRepo}) =>
      DiagnosisCommitter(
        sessionRepo: sessionRepo,
        stateRepo: stateRepo,
        diagnosisRepo: diagnosisRepo,
        studentModelRepo: studentModelRepo,
        referenceRepo: ReferenceRepository(db),
        chapterRepo: ChapterRepository(db),
        appStateRepo: appStateRepo,
      );

  /// 构造一条仅含 suggestedBeginnerLevel 的诊断（无 suggestedPhase）。
  ParsedDiagnosis diagSuggesting(BeginnerLevel level) => ParsedDiagnosis(
    syndromes: const [],
    suggestedActions: const [],
    confidence: 0.8,
    suggestedBeginnerLevel: level,
  );

  OnboardingData dataFor(ProficiencyLevel p) => OnboardingData(
    proficiency: p,
    focusAreas: const [],
    cognitiveStyle: CognitiveStyle.mixed,
    writingGoal: '',
    completedAt: 1700000000,
  );

  Future<String?> beginnerLevelOf(String sid) async =>
      (await stateRepo.getTeachingState(sid))?.beginnerLevel;

  test('Case A：先显式采集(N1) 后 LLM(N2) → 学员值保留 N1，不被覆盖', () async {
    final sid = await sessionRepo.createBlankSession();
    // 写点 A：显式 elementary → N1，并置 questionnaire_completed=true
    await onboarding.submitOnboarding(
      sid,
      dataFor(ProficiencyLevel.elementary),
    );
    expect(await beginnerLevelOf(sid), BeginnerLevel.n1Elements.value);

    // 写点 B：LLM 建议 N2（N1→N2 为合法 +1，resolver 本会接受）
    await buildCommitter(appStateRepo: appStateRepo).applyPhaseMigration(
      sessionId: sid,
      diagnosis: diagSuggesting(BeginnerLevel.n2Scene),
    );

    // 仲裁生效：显式采集后 LLM 不得覆盖 → 仍为 N1
    expect(await beginnerLevelOf(sid), BeginnerLevel.n1Elements.value);
  });

  test('Case B：先 LLM(N2) 后显式(N1) → 学员值覆盖 N1', () async {
    final sid = await sessionRepo.createBlankSession();
    // 先 LLM：未显式采集、current NULL → 门开，回填 N2
    await buildCommitter(appStateRepo: appStateRepo).applyPhaseMigration(
      sessionId: sid,
      diagnosis: diagSuggesting(BeginnerLevel.n2Scene),
    );
    expect(await beginnerLevelOf(sid), BeginnerLevel.n2Scene.value);

    // 写点 A：显式 elementary → N1（无条件覆盖，不走门）
    await onboarding.submitOnboarding(
      sid,
      dataFor(ProficiencyLevel.elementary),
    );
    expect(await beginnerLevelOf(sid), BeginnerLevel.n1Elements.value);
  });

  test('Case C：未显式 + current NULL → LLM 正常回填 N1（防回归）', () async {
    final sid = await sessionRepo.createBlankSession();
    await buildCommitter(appStateRepo: appStateRepo).applyPhaseMigration(
      sessionId: sid,
      diagnosis: diagSuggesting(BeginnerLevel.n1Elements),
    );

    expect(await beginnerLevelOf(sid), BeginnerLevel.n1Elements.value);
  });

  test('Case D：appStateRepo=null → 现状不锁，LLM 写生效', () async {
    final sid = await sessionRepo.createBlankSession();
    // 不传 appStateRepo（约 130 处既有构造点零改动路径）
    await buildCommitter().applyPhaseMigration(
      sessionId: sid,
      diagnosis: diagSuggesting(BeginnerLevel.n1Elements),
    );

    expect(await beginnerLevelOf(sid), BeginnerLevel.n1Elements.value);
  });

  test(
    'Case E：skip 写 N0 + questionnaire_completed=true，但 LLM(N1) 仍可回填',
    () async {
      final sid = await sessionRepo.createBlankSession();
      // 写点 A：skipped=true 的 onboarding → N0_ENGAGE，且 questionnaire_completed=true
      // （直接构造 skipped 数据喂 submitOnboarding；原 skipOnboarding 方法已删，产物等价）
      await onboarding.submitOnboarding(
        sid,
        OnboardingData(
          proficiency: ProficiencyLevel.beginner,
          focusAreas: const [],
          cognitiveStyle: CognitiveStyle.mixed,
          writingGoal: '',
          completedAt: 1700000000,
          skipped: true,
        ),
      );
      expect(await beginnerLevelOf(sid), BeginnerLevel.n0Engage.value);
      expect(await appStateRepo.getQuestionnaireCompleted(), isTrue);

      // 写点 B：LLM 建议 N1（N0→N1 合法 +1）。skip 非显式采集 → 不锁，应回填
      await buildCommitter(appStateRepo: appStateRepo).applyPhaseMigration(
        sessionId: sid,
        diagnosis: diagSuggesting(BeginnerLevel.n1Elements),
      );

      expect(await beginnerLevelOf(sid), BeginnerLevel.n1Elements.value);
    },
  );
}
