// ─────────────────────────────────────────────────────────────
// ADR-C71 §5：onboarding 用户级回退读取 + 画像消费指令/认知风格去重
// ─────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/services/student_profile.dart';
import 'package:writingcoach/services/student_profile_format.dart';
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

  tearDown(() async {
    await db.close();
  });

  Map<String, dynamic> onboardingJson({
    bool skipped = false,
    List<String> focusAreas = const ['人物塑造'],
  }) => OnboardingData(
    proficiency: ProficiencyLevel.beginner,
    focusAreas: focusAreas,
    cognitiveStyle: CognitiveStyle.intuitive,
    writingGoal: '写完一个短篇',
    completedAt: 1000,
    skipped: skipped,
  ).toJson();

  group('buildStudentContext onboarding 用户级回退（ADR-C71）', () {
    test('本会话无问卷数据 → 回退取其他会话最新数据', () async {
      final sessionA = await sessionRepo.createBlankSession();
      await studentModelRepo.updateOnboardingData(sessionA, onboardingJson());
      final sessionB = await sessionRepo.createBlankSession();

      final result = await buildStudentContext(
        diagnosisRepo: diagnosisRepo,
        studentModelRepo: studentModelRepo,
        sessionRepo: sessionRepo,
        sessionId: sessionB,
      );

      expect(result.text, contains('【学员初始画像】'));
      expect(result.text, contains('关注领域：人物塑造'));
      // F2：消费指令随初始画像出现
      expect(result.text, contains('教学加权'));
    });

    test('来源问卷为 skipped → 不作为有效回退来源', () async {
      final sessionA = await sessionRepo.createBlankSession();
      await studentModelRepo.updateOnboardingData(
        sessionA,
        onboardingJson(skipped: true),
      );
      final sessionB = await sessionRepo.createBlankSession();

      final result = await buildStudentContext(
        diagnosisRepo: diagnosisRepo,
        studentModelRepo: studentModelRepo,
        sessionRepo: sessionRepo,
        sessionId: sessionB,
      );

      // 无诊断 + 无有效问卷 → 画像为空（与既有早退语义一致）
      expect(result.text, isEmpty);
    });

    test('本会话自有数据优先于其他会话的历史数据', () async {
      final sessionA = await sessionRepo.createBlankSession();
      await studentModelRepo.updateOnboardingData(
        sessionA,
        onboardingJson(focusAreas: ['情节设计']),
      );
      final sessionB = await sessionRepo.createBlankSession();
      await studentModelRepo.updateOnboardingData(
        sessionB,
        onboardingJson(focusAreas: ['文笔修辞']),
      );

      final result = await buildStudentContext(
        diagnosisRepo: diagnosisRepo,
        studentModelRepo: studentModelRepo,
        sessionRepo: sessionRepo,
        sessionId: sessionB,
      );

      expect(result.text, contains('关注领域：文笔修辞'));
      expect(result.text, isNot(contains('情节设计')));
    });
  });

  group('formatProfileText 消费指令与认知风格段（ADR-C71 §3.4）', () {
    test('onboarding 存在：有教学加权指令，无重复的认知风格段', () {
      final text = formatProfileText(
        StudentProfile(
          proficiency: ProficiencyLevel.beginner,
          confidence: 0.5,
          cognitiveStyle: CognitiveStyleInference(
            style: CognitiveStyle.intuitive,
            confidence: 0.5,
          ),
          syndromeProfile: const {},
          totalSessions: 1,
        ),
        null,
        null,
        OnboardingData(
          proficiency: ProficiencyLevel.beginner,
          focusAreas: const ['人物塑造'],
          cognitiveStyle: CognitiveStyle.intuitive,
          writingGoal: '写完一个短篇',
          completedAt: 1000,
        ),
      );

      expect(text, contains('教学加权'));
      expect(text, contains('一律以当轮为准'));
      expect(text, contains('学习偏好：'));
      // 与「学习偏好」同源同值的第二步认知风格段不再重复输出
      expect(text, isNot(contains('认知风格：')));
    });

    test('onboarding 缺失：认知风格来自推断时照常输出（依据为关键词推断）', () {
      final text = formatProfileText(
        StudentProfile(
          proficiency: ProficiencyLevel.elementary,
          confidence: 0.4,
          cognitiveStyle: CognitiveStyleInference(
            style: CognitiveStyle.analytical,
            confidence: 0.6,
          ),
          syndromeProfile: const {},
          totalSessions: 2,
        ),
        null,
        null,
        null,
      );

      expect(text, contains('认知风格：'));
      expect(text, contains('关键词使用频率推断'));
      expect(text, isNot(contains('教学加权')));
    });
  });
}
