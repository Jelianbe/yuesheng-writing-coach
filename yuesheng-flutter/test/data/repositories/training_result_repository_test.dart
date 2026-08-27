// ─────────────────────────────────────────────────────────────
// training_result_repository_test — X-041a P0 训练结果持久化单元测试
//
// 覆盖：
//   1. insert → queryBySession 往返（含 feedback JSON、score 字段）
//   2. 多条记录 → queryBySession 按 createdAt DESC 排序
//   3. queryBySyndrome 跨会话追溯
//   4. suggestionId 可空（自主训练无建议触发）
//   5. getById 单条查询（含不存在场景）
//   6. score 可空往返
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/training_result_repository.dart';

void main() {
  late AppDatabase db;
  late TrainingResultRepository repo;
  late SessionRepository sessionRepo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = TrainingResultRepository(db);
    sessionRepo = SessionRepository(db);
  });

  tearDown(() async => db.close());

  /// 辅助：构造入参
  InsertTrainingResultParams mkParams({
    required String sessionId,
    String? suggestionId,
    String syndromeId = 'syn-emotion-tag',
    String taskType = 'rewrite',
    String userContent = '夜风吹过窗台，他抬起头。',
    String result = 'passed',
    Map<String, dynamic>? feedback,
    double? score,
  }) {
    return InsertTrainingResultParams(
      sessionId: sessionId,
      suggestionId: suggestionId,
      syndromeId: syndromeId,
      taskType: taskType,
      userContent: userContent,
      result: result,
      feedback: feedback,
      score: score,
    );
  }

  test('#1 insert → queryBySession 往返（feedback/score 字段）', () async {
    final sessionId = await sessionRepo.createBlankSession(title: '会话A');
    await repo.insertTrainingResult(
      mkParams(
        sessionId: sessionId,
        feedback: {'overall': 'good', 'issues': <String>[]},
        score: 0.85,
      ),
    );

    final list = await repo.queryBySession(sessionId);
    expect(list.length, 1);
    final row = list.first;
    expect(row.sessionId, sessionId);
    expect(row.suggestionId, isNull);
    expect(row.syndromeId, 'syn-emotion-tag');
    expect(row.taskType, 'rewrite');
    expect(row.userContent, '夜风吹过窗台，他抬起头。');
    expect(row.result, 'passed');
    expect(row.score, 0.85);
    // feedback JSON 字段往返
    expect(row.feedbackJson, isNotNull);
    expect(row.feedbackJson!.contains('overall'), isTrue);
    expect(row.feedbackJson!.contains('good'), isTrue);
  });

  test('#2 多条 → queryBySession 按 createdAt DESC', () async {
    final sessionId = await sessionRepo.createBlankSession(title: '会话B');
    // 顺序插入 3 条（createdAt 单调递增），期望倒序返回
    final id1 = await repo.insertTrainingResult(
      mkParams(sessionId: sessionId, userContent: '第一句'),
    );
    // 微小延时确保 nowSec 不同
    await Future<void>.delayed(const Duration(seconds: 1));
    final id2 = await repo.insertTrainingResult(
      mkParams(sessionId: sessionId, userContent: '第二句'),
    );
    await Future<void>.delayed(const Duration(seconds: 1));
    final id3 = await repo.insertTrainingResult(
      mkParams(sessionId: sessionId, userContent: '第三句'),
    );

    final list = await repo.queryBySession(sessionId);
    expect(list.length, 3);
    expect(list.map((r) => r.id).toList(), [id3, id2, id1],
        reason: '倒序：最新在前');
    expect(list.first.userContent, '第三句');
    expect(list.last.userContent, '第一句');
  });

  test('#3 queryBySyndrome 跨会话追溯', () async {
    final s1 = await sessionRepo.createBlankSession(title: '会话C1');
    final s2 = await sessionRepo.createBlankSession(title: '会话C2');
    await repo.insertTrainingResult(
      mkParams(sessionId: s1, syndromeId: 'syn-dialog-flat'),
    );
    await Future<void>.delayed(const Duration(seconds: 1));
    await repo.insertTrainingResult(
      mkParams(sessionId: s2, syndromeId: 'syn-dialog-flat'),
    );
    // 不相关症候不应被查出
    await repo.insertTrainingResult(
      mkParams(sessionId: s1, syndromeId: 'syn-other'),
    );

    final bySyndrome = await repo.queryBySyndrome('syn-dialog-flat');
    expect(bySyndrome.length, 2);
    expect(bySyndrome.every((r) => r.syndromeId == 'syn-dialog-flat'), isTrue);
    // 不同 session 的记录都返回
    expect(bySyndrome.map((r) => r.sessionId).toSet(), {s1, s2});
    // 倒序：s2 的记录在前
    expect(bySyndrome.first.sessionId, s2);
  });

  test('#4 suggestionId 可空（自主训练无建议触发）', () async {
    final sessionId = await sessionRepo.createBlankSession(title: '会话D');
    // suggestionId 为 null
    final id = await repo.insertTrainingResult(
      mkParams(sessionId: sessionId, suggestionId: null),
    );
    final row = await repo.getById(id);
    expect(row, isNotNull);
    expect(row!.suggestionId, isNull);
    // 提供具体 suggestionId（伪 id，不建立真实 FK 关系会因 FK 失败）
    // 此场景由 v26 schema SET NULL 保证：删建议不删训练历史
  });

  test('#5 getById 不存在 → null', () async {
    final row = await repo.getById('non-existent-id');
    expect(row, isNull);
  });

  test('#6 score 可空往返', () async {
    final sessionId = await sessionRepo.createBlankSession(title: '会话E');
    final id = await repo.insertTrainingResult(
      mkParams(sessionId: sessionId, score: null, result: 'partial'),
    );
    final row = await repo.getById(id);
    expect(row, isNotNull);
    expect(row!.score, isNull);
    expect(row.result, 'partial');
  });

  test('#7 queryBySyndrome limit 生效', () async {
    final s = await sessionRepo.createBlankSession(title: '会话F');
    for (var i = 0; i < 5; i++) {
      await repo.insertTrainingResult(
        mkParams(sessionId: s, syndromeId: 'syn-limit-test'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
    final limited = await repo.queryBySyndrome(
      'syn-limit-test',
      limit: 2,
    );
    expect(limited.length, 2);
  });
}
