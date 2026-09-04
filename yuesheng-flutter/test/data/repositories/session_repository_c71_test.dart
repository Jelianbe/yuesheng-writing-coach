// ─────────────────────────────────────────────────────────────
// ADR-C71 §5：createBlankSession 跨会话继承 beginnerLevel
//
// 裁决：beginnerLevel 是用户级学习属性（N 系课程进度坐标），新建会话
// 继承全库最新非空值；phase/subphase 维持会话级（P0 起步）。
// ─────────────────────────────────────────────────────────────
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';

void main() {
  late AppDatabase db;
  late SessionRepository repo;
  late TeachingStateRepository stateRepo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = SessionRepository(db);
    stateRepo = TeachingStateRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('createBlankSession 继承 beginnerLevel（ADR-C71）', () {
    test('无任何历史 → 新会话 beginnerLevel 为 null', () async {
      final sessionId = await repo.createBlankSession();
      final ts = await stateRepo.getTeachingState(sessionId);
      expect(ts, isNotNull);
      expect(ts!.beginnerLevel, isNull);
      expect(ts.currentPhase, 'P0_ENGAGE');
    });

    test('有历史 → 新会话继承最新非空 beginnerLevel', () async {
      final oldSession = await repo.createBlankSession();
      await stateRepo.updateBeginnerLevel(oldSession, 'N1_ELEMENTS');

      final newSession = await repo.createBlankSession();
      final ts = await stateRepo.getTeachingState(newSession);
      expect(ts!.beginnerLevel, 'N1_ELEMENTS');
    });

    test('多条历史 → 按 updatedAt 最新值胜出', () async {
      final sessionA = await repo.createBlankSession();
      final sessionB = await repo.createBlankSession();
      // 直接写行并显式指定 updatedAt，规避同秒写入导致的排序歧义
      await (db.update(
        db.teachingState,
      )..where((t) => t.sessionId.equals(sessionA))).write(
        const TeachingStateCompanion(
          beginnerLevel: Value('N1_ELEMENTS'),
          updatedAt: Value(1000),
        ),
      );
      await (db.update(
        db.teachingState,
      )..where((t) => t.sessionId.equals(sessionB))).write(
        const TeachingStateCompanion(
          beginnerLevel: Value('N2_SCENE'),
          updatedAt: Value(2000),
        ),
      );

      final newSession = await repo.createBlankSession();
      final ts = await stateRepo.getTeachingState(newSession);
      expect(ts!.beginnerLevel, 'N2_SCENE');
    });

    test('phase 不继承：旧会话 P3 的新会话仍从 P0 起步（裁决：phase 会话级）', () async {
      final oldSession = await repo.createBlankSession();
      await stateRepo.updateBeginnerLevel(oldSession, 'N1_ELEMENTS');
      await (db.update(
        db.teachingState,
      )..where((t) => t.sessionId.equals(oldSession))).write(
        const TeachingStateCompanion(
          currentPhase: Value('P3_TRAINING'),
          updatedAt: Value(3000),
        ),
      );

      final newSession = await repo.createBlankSession();
      final ts = await stateRepo.getTeachingState(newSession);
      expect(ts!.currentPhase, 'P0_ENGAGE');
      expect(ts.beginnerLevel, 'N1_ELEMENTS');
    });
  });
}
