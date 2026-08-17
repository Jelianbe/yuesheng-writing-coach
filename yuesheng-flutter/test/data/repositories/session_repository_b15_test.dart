// ─────────────────────────────────────────────────────────────
// session_repository_b15_test — B15 回归测试
//
// 场景：无消息的孤儿会话若已建立 student_model 行（切态度后），
// 清除缓存(deleteOrphanSessions) 必须成功且不抛 NOT NULL，
// 且 student_model 死数据行应被同步清理（同 deleteSession）。
// ─────────────────────────────────────────────────────────────

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';

void main() {
  late AppDatabase db;
  late SessionRepository sessionRepo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
  });

  tearDown(() async => db.close());

  test('B15 含 student_model 的孤儿会话清理不抛 NOT NULL 且清行', () async {
    // 1. 建一个无消息会话（createBlankSession 不建 studentModel）
    final sessionId = await sessionRepo.createBlankSession(title: 'orphan');

    // 2. 模拟"切态度"写入 student_model 行（无消息 → 孤儿）
    await db.into(db.studentModels).insert(
      StudentModelsCompanion.insert(
        id: 'sm-b15',
        sessionId: sessionId,
        attitudePreference: const Value('豆包'),
        teachingHistory: const Value('[]'),
        createdAt: Value(DateTime.now().millisecondsSinceEpoch),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );

    // 3. 清缓存：修复前此处抛
    //    NOT NULL constraint failed: student_model.session_id
    final deleted = await sessionRepo.deleteOrphanSessions();
    expect(deleted, 1);

    // 4. student_model 死数据行应被同步删（不再残留）
    final remaining = await (db.select(db.studentModels)
          ..where((t) => t.sessionId.equals(sessionId)))
        .get();
    expect(remaining, isEmpty);
  });
}
