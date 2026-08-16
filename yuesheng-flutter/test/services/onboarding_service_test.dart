// ─────────────────────────────────────────────────────────────
// OnboardingService 测试 — 三步状态迁移契约验证
// 复刻 yuesheng-android/src/services/onboarding-service.test.ts（规划中）
//
// 覆盖路径：
//   1. submitOnboarding 三步迁移（onboarding_data + beginner_level + questionnaire_completed）
//   2. proficiency → BeginnerLevel 映射（N0/N1/N2/N3 四级）
//   3. skipOnboarding 默认值（beginner + skipped=true）
//   4. 重复调用幂等性
//   5. onboarding_data 持久化正确性（toJson/tofromJson 往返）
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/app_state_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/services/onboarding_service.dart';
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  late AppDatabase db;
  late OnboardingService service;
  late SessionRepository sessionRepo;
  late StudentModelRepository smRepo;
  late TeachingStateRepository stateRepo;
  late AppStateRepository appStateRepo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    smRepo = StudentModelRepository(db);
    stateRepo = TeachingStateRepository(db);
    appStateRepo = AppStateRepository(db);
    service = OnboardingService(
      studentModelRepo: smRepo,
      stateRepo: stateRepo,
      appStateRepo: appStateRepo,
    );
  });

  tearDown(() async => db.close());

  OnboardingData makeData({
    ProficiencyLevel proficiency = ProficiencyLevel.elementary,
    List<String> focusAreas = const ['人物塑造', '情节设计'],
    CognitiveStyle cognitiveStyle = CognitiveStyle.mixed,
    bool skipped = false,
  }) {
    return OnboardingData(
      proficiency: proficiency,
      focusAreas: focusAreas,
      cognitiveStyle: cognitiveStyle,
      writingGoal: '',
      completedAt: 1700000000,
      skipped: skipped,
    );
  }

  group('submitOnboarding 三步状态迁移', () {
    test(
      'elementary → N1_ELEMENTS + onboarding_data + questionnaire_completed',
      () async {
        final sessionId = await sessionRepo.createBlankSession();

        await service.submitOnboarding(sessionId, makeData());

        // 1. onboarding_data 已写入
        final saved = await smRepo.getOnboardingData(sessionId);
        expect(saved, isNotNull);
        expect(saved!['proficiency'], 'elementary');
        expect(saved['focusAreas'], ['人物塑造', '情节设计']);
        expect(saved['cognitiveStyle'], 'mixed');
        expect(saved['skipped'], false);

        // 2. beginner_level 已映射并写入 teaching_state
        final ts = await stateRepo.getTeachingState(sessionId);
        expect(ts, isNotNull);
        expect(ts!.beginnerLevel, BeginnerLevel.n1Elements.value);

        // 3. questionnaire_completed 已标记
        expect(await appStateRepo.getQuestionnaireCompleted(), true);
      },
    );

    test('beginner → N0_ENGAGE 映射', () async {
      final sessionId = await sessionRepo.createBlankSession();
      await service.submitOnboarding(
        sessionId,
        makeData(proficiency: ProficiencyLevel.beginner),
      );

      final ts = await stateRepo.getTeachingState(sessionId);
      expect(ts!.beginnerLevel, BeginnerLevel.n0Engage.value);
    });

    test('intermediate → N2_SCENE 映射', () async {
      final sessionId = await sessionRepo.createBlankSession();
      await service.submitOnboarding(
        sessionId,
        makeData(proficiency: ProficiencyLevel.intermediate),
      );

      final ts = await stateRepo.getTeachingState(sessionId);
      expect(ts!.beginnerLevel, BeginnerLevel.n2Scene.value);
    });

    test('advanced → N3_DIAGNOSE 映射', () async {
      final sessionId = await sessionRepo.createBlankSession();
      await service.submitOnboarding(
        sessionId,
        makeData(proficiency: ProficiencyLevel.advanced),
      );

      final ts = await stateRepo.getTeachingState(sessionId);
      expect(ts!.beginnerLevel, BeginnerLevel.n3Diagnose.value);
    });
  });

  group('skipOnboarding 默认值', () {
    test('写入默认 beginner + skipped=true + 空数组', () async {
      final sessionId = await sessionRepo.createBlankSession();

      await service.skipOnboarding(sessionId);

      // onboarding_data
      final saved = await smRepo.getOnboardingData(sessionId);
      expect(saved, isNotNull);
      expect(saved!['proficiency'], 'beginner');
      expect(saved['focusAreas'], []);
      expect(saved['cognitiveStyle'], 'mixed');
      expect(saved['writingGoal'], '');
      expect(saved['skipped'], true);

      // beginner_level → N0_ENGAGE
      final ts = await stateRepo.getTeachingState(sessionId);
      expect(ts!.beginnerLevel, BeginnerLevel.n0Engage.value);

      // questionnaire_completed
      expect(await appStateRepo.getQuestionnaireCompleted(), true);
    });

    test('completedAt 为当前秒级时间戳', () async {
      final sessionId = await sessionRepo.createBlankSession();
      final startTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      await service.skipOnboarding(sessionId);

      final saved = await smRepo.getOnboardingData(sessionId);
      final completedAt = saved!['completedAt'] as int;
      expect(completedAt, greaterThanOrEqualTo(startTs));
      expect(completedAt, lessThan(startTs + 1000));
    });
  });

  group('幂等性', () {
    test('重复调用 submitOnboarding 不报错且状态一致', () async {
      final sessionId = await sessionRepo.createBlankSession();
      final data = makeData();

      await service.submitOnboarding(sessionId, data);
      await service.submitOnboarding(sessionId, data);

      // 最终状态应与第一次相同
      final ts = await stateRepo.getTeachingState(sessionId);
      expect(ts!.beginnerLevel, BeginnerLevel.n1Elements.value);
      expect(await appStateRepo.getQuestionnaireCompleted(), true);
    });

    test('先 submit 再 skip 不报错', () async {
      final sessionId = await sessionRepo.createBlankSession();

      await service.submitOnboarding(sessionId, makeData());
      await service.skipOnboarding(sessionId);

      final saved = await smRepo.getOnboardingData(sessionId);
      expect(saved!['skipped'], true);
      expect(saved['proficiency'], 'beginner');

      final ts = await stateRepo.getTeachingState(sessionId);
      expect(ts!.beginnerLevel, BeginnerLevel.n0Engage.value);
    });
  });

  group('onboarding_data 持久化往返', () {
    test('focusAreas 空数组能正确序列化/反序列化', () async {
      final sessionId = await sessionRepo.createBlankSession();
      await service.submitOnboarding(sessionId, makeData(focusAreas: []));

      final saved = await smRepo.getOnboardingData(sessionId);
      expect(saved!['focusAreas'], []);
    });

    test('全部 4 项 focusAreas 能正确持久化', () async {
      final sessionId = await sessionRepo.createBlankSession();
      await service.submitOnboarding(
        sessionId,
        makeData(focusAreas: ['人物塑造', '情节设计', '文笔修辞', '世界观构建']),
      );

      final saved = await smRepo.getOnboardingData(sessionId);
      expect(saved!['focusAreas'].length, 4);
    });
  });
}
