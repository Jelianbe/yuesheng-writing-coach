// ─────────────────────────────────────────────────────────────
// BootstrapService 测试 — shouldShowQuestionnaire 判定链路
// 复刻 yuesheng-android/src/hooks/useBootstrap.test.ts（规划中）
//
// 覆盖路径（5 条，按判定顺序）：
//   1. 用户级 questionnaire_completed=true → 不弹
//   2. session 级 onboarding_data 有数据 → 不弹 + 迁移标记
//   3. 边界 A fallback：当前 session 无数据但其他 session 有 → 不弹 + 迁移标记
//   4. 全空（新用户）→ 弹问卷
//   5. sessionId=null → 弹问卷（fallback 仍生效）
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/app_state_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/services/bootstrap_service.dart';

void main() {
  late AppDatabase db;
  late BootstrapService service;
  late SessionRepository sessionRepo;
  late StudentModelRepository smRepo;
  late AppStateRepository appStateRepo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    smRepo = StudentModelRepository(db);
    appStateRepo = AppStateRepository(db);
    service = BootstrapService(
      appStateRepo: appStateRepo,
      studentModelRepo: smRepo,
    );
  });

  tearDown(() async => db.close());

  group('shouldShowQuestionnaire 判定链路', () {
    test('1. 用户级 questionnaire_completed=true → 返回 false（不弹）', () async {
      await appStateRepo.setQuestionnaireCompleted(true);

      final result = await service.shouldShowQuestionnaire('any-session-id');
      expect(result, false);
    });

    test('2. session 级 onboarding_data 有数据 → 返回 false + 迁移标记', () async {
      final sessionId = await sessionRepo.createBlankSession();
      await smRepo.updateOnboardingData(sessionId, {'level': 'beginner'});

      // 调用前 questionnaire_completed 应为 false
      expect(await appStateRepo.getQuestionnaireCompleted(), false);

      final result = await service.shouldShowQuestionnaire(sessionId);

      // 不弹
      expect(result, false);
      // 迁移标记已写入
      expect(await appStateRepo.getQuestionnaireCompleted(), true);
    });

    test('3. 边界 A fallback：其他 session 有数据 → 返回 false + 迁移标记', () async {
      // 模拟老用户场景：session A 有问卷，本次启动用 session B
      final sessionA = await sessionRepo.createBlankSession();
      final sessionB = await sessionRepo.createBlankSession();

      await smRepo.updateOnboardingData(sessionA, {'level': 'beginner'});

      // 调用前 questionnaire_completed 应为 false
      expect(await appStateRepo.getQuestionnaireCompleted(), false);

      // 用 sessionB 查询（sessionB 本身无 onboarding_data）
      final result = await service.shouldShowQuestionnaire(sessionB);

      // 不弹（fallback 命中 session A 的数据）
      expect(result, false);
      // 迁移标记已写入
      expect(await appStateRepo.getQuestionnaireCompleted(), true);
    });

    test('4. 全空（新用户）→ 返回 true（弹问卷）', () async {
      final sessionId = await sessionRepo.createBlankSession();

      // 调用前 questionnaire_completed 应为 false
      expect(await appStateRepo.getQuestionnaireCompleted(), false);

      final result = await service.shouldShowQuestionnaire(sessionId);

      // 弹问卷
      expect(result, true);
      // 不应写入迁移标记（确认仍是 false）
      expect(await appStateRepo.getQuestionnaireCompleted(), false);
    });

    test('5. sessionId=null → 返回 true（弹问卷）', () async {
      // 不创建任何 session，全表扫描应返回 false
      final result = await service.shouldShowQuestionnaire(null);
      expect(result, true);
    });

    test('迁移后第二次调用直接走用户级 → 返回 false', () async {
      final sessionId = await sessionRepo.createBlankSession();
      await smRepo.updateOnboardingData(sessionId, {'level': 'beginner'});

      // 第一次调用：触发迁移
      await service.shouldShowQuestionnaire(sessionId);

      // 第二次调用：应直接走用户级判定，不再查 session 级
      // 验证方式：即使删除 session 级数据，结果仍为 false
      await db.customStatement(
        "UPDATE student_model SET onboarding_data = NULL WHERE session_id = ?",
        [sessionId],
      );

      final result = await service.shouldShowQuestionnaire(sessionId);
      expect(result, false);
    });

    test('session 级 onboarding_data="" → 不算已填，走 fallback', () async {
      // 验证脏数据过滤：空串不应触发 session 级判定
      final sessionId = await sessionRepo.createBlankSession();
      await smRepo.appendTeachingHistory(sessionId, {'type': 'test'});
      await db.customStatement(
        "UPDATE student_model SET onboarding_data = '' WHERE session_id = ?",
        [sessionId],
      );

      // 空串应被过滤，全表扫描也返回 false（因为只有空串）
      final result = await service.shouldShowQuestionnaire(sessionId);
      expect(result, true);
    });

    test('session 级 onboarding_data="null" → 不算已填，走 fallback', () async {
      // 验证脏数据过滤：'null' 字面量不应触发 session 级判定
      final sessionId = await sessionRepo.createBlankSession();
      await smRepo.appendTeachingHistory(sessionId, {'type': 'test'});
      await db.customStatement(
        "UPDATE student_model SET onboarding_data = 'null' WHERE session_id = ?",
        [sessionId],
      );

      final result = await service.shouldShowQuestionnaire(sessionId);
      expect(result, true);
    });
  });
}
