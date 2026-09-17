// ─────────────────────────────────────────────────────────────
// student_model_repository_test — 批1·N2：updateLatestTrainingRating
//
// 覆盖（含正负例对照）：
//   1. 命中最近一条 training 记录 → 写入 userRating 并返回 true
//   2. 末尾是非 training 记录（diagnosis）时仍取「最近一条 training」
//   3. syndromeId 不匹配 → false 且不写（防跨症候误写）
//   4. ★ 无 training 记录 → false，且**不新增记录**
//      （追加会在 teaching_history 里多出一条训练记录 ⇒ 污染
//       `_countTrailingPasses` 的「尾部连续 passed」计数）
//   5. 无 student_model 行 → false（不建行、不抛异常）
//   6. 重复回写 → 覆盖为最后一次值，记录数不增
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';

void main() {
  late AppDatabase db;
  late StudentModelRepository repo;
  late SessionRepository sessionRepo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = StudentModelRepository(db);
    sessionRepo = SessionRepository(db);
  });

  tearDown(() async => db.close());

  test('#1 命中最近一条 training 记录 → 写入 userRating（更早那条不动）', () async {
    final sid = await sessionRepo.createBlankSession(title: '会话N2-1');
    await repo.appendTeachingHistory(sid, {
      'type': 'training',
      'syndromeId': 'P001',
      'result': 'passed',
      'timestamp': 1000,
    });
    await repo.appendTeachingHistory(sid, {
      'type': 'training',
      'syndromeId': 'P001',
      'result': 'passed',
      'timestamp': 2000,
    });

    final ok = await repo.updateLatestTrainingRating(sid, rating: 'easy');

    expect(ok, isTrue);
    final history = await repo.getTeachingHistory(sid);
    expect(history.length, 2);
    expect(history[0].containsKey('userRating'), isFalse);
    expect(history[1]['userRating'], 'easy');
  });

  test('#2 末尾为非 training 记录时，仍取「最近一条 training」', () async {
    final sid = await sessionRepo.createBlankSession(title: '会话N2-2');
    await repo.appendTeachingHistory(sid, {
      'type': 'training',
      'syndromeId': 'P001',
      'result': 'passed',
    });
    await repo.appendTeachingHistory(sid, {
      'type': 'diagnosis',
      'syndromeId': 'P001',
    });

    final ok = await repo.updateLatestTrainingRating(sid, rating: 'hard');

    expect(ok, isTrue);
    final history = await repo.getTeachingHistory(sid);
    expect(history[0]['userRating'], 'hard');
    expect(history[1].containsKey('userRating'), isFalse);
  });

  test('#3 syndromeId 不匹配 → false 且不写（防跨症候误写）', () async {
    final sid = await sessionRepo.createBlankSession(title: '会话N2-3');
    await repo.appendTeachingHistory(sid, {
      'type': 'training',
      'syndromeId': 'P001',
      'result': 'passed',
    });

    final ok = await repo.updateLatestTrainingRating(
      sid,
      rating: 'good',
      syndromeId: 'P999',
    );

    expect(ok, isFalse);
    final history = await repo.getTeachingHistory(sid);
    expect(history.first.containsKey('userRating'), isFalse);
  });

  test('#4 ★ 无 training 记录 → false 且不新增记录', () async {
    final sid = await sessionRepo.createBlankSession(title: '会话N2-4');
    await repo.appendTeachingHistory(sid, {
      'type': 'diagnosis',
      'syndromeId': 'P001',
    });

    final ok = await repo.updateLatestTrainingRating(sid, rating: 'again');

    expect(ok, isFalse);
    final history = await repo.getTeachingHistory(sid);
    expect(history.length, 1); // 未被追加
  });

  test('#5 无 student_model 行 → false（不建行、不抛异常）', () async {
    final sid = await sessionRepo.createBlankSession(title: '会话N2-5');

    final ok = await repo.updateLatestTrainingRating(sid, rating: 'good');

    expect(ok, isFalse);
    expect(await repo.getTeachingHistory(sid), isEmpty);
  });

  test('#6 重复回写 → 覆盖为最后一次值，记录数不增', () async {
    final sid = await sessionRepo.createBlankSession(title: '会话N2-6');
    await repo.appendTeachingHistory(sid, {
      'type': 'training',
      'syndromeId': 'P001',
      'result': 'passed',
    });

    await repo.updateLatestTrainingRating(sid, rating: 'hard');
    await repo.updateLatestTrainingRating(sid, rating: 'easy');

    final history = await repo.getTeachingHistory(sid);
    expect(history.first['userRating'], 'easy');
    expect(history.length, 1);
  });
}
