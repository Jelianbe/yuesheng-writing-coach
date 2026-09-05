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

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/database/utils.dart';
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
    expect(list.map((r) => r.id).toList(), [id3, id2, id1], reason: '倒序：最新在前');
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
    final limited = await repo.queryBySyndrome('syn-limit-test', limit: 2);
    expect(limited.length, 2);
  });

  // ── X-041b 聚合查询 ───────────────────────────────────────────

  test('#8 aggregateBySyndrome 三态计数 + 通过率口径', () async {
    final s = await sessionRepo.createBlankSession(title: '会话G');
    // syn-A: 2 passed + 1 partial + 1 failed → 通过率 (2+0.5)/4=0.625
    await repo.insertTrainingResult(
      mkParams(sessionId: s, syndromeId: 'syn-A', result: 'passed'),
    );
    await repo.insertTrainingResult(
      mkParams(sessionId: s, syndromeId: 'syn-A', result: 'passed'),
    );
    await repo.insertTrainingResult(
      mkParams(sessionId: s, syndromeId: 'syn-A', result: 'partial'),
    );
    await repo.insertTrainingResult(
      mkParams(sessionId: s, syndromeId: 'syn-A', result: 'failed'),
    );
    // syn-B: 1 passed → 通过率 1.0
    await repo.insertTrainingResult(
      mkParams(sessionId: s, syndromeId: 'syn-B', result: 'passed'),
    );

    final stats = await repo.aggregateBySyndrome();
    expect(stats.length, 2);

    // 按 total DESC 排序：syn-A(4) 在前，syn-B(1) 在后
    expect(stats.first.syndromeId, 'syn-A');
    expect(stats.first.passed, 2);
    expect(stats.first.partial, 1);
    expect(stats.first.failed, 1);
    expect(stats.first.total, 4);
    expect(stats.first.passRate, closeTo(0.625, 1e-9));

    expect(stats.last.syndromeId, 'syn-B');
    expect(stats.last.passed, 1);
    expect(stats.last.partial, 0);
    expect(stats.last.failed, 0);
    expect(stats.last.passRate, 1.0);
  });

  test('#9 aggregateBySyndrome sinceSec 时间窗过滤', () async {
    final s = await sessionRepo.createBlankSession(title: '会话H');
    // 早期记录（t-100s）
    final old = nowSec() - 100;
    await repo.insertTrainingResult(
      mkParams(sessionId: s, syndromeId: 'syn-old', result: 'passed'),
    );
    // 手动改 created_at 模拟历史时间
    await (db.update(db.trainingResults)
          ..where((t) => t.syndromeId.equals('syn-old')))
        .write(TrainingResultsCompanion(createdAt: Value(old)));

    // 近期记录（默认 created_at=now）
    await repo.insertTrainingResult(
      mkParams(sessionId: s, syndromeId: 'syn-new', result: 'failed'),
    );

    // sinceSec = now-50：只剩 syn-new
    final recent = await repo.aggregateBySyndrome(sinceSec: nowSec() - 50);
    expect(recent.length, 1);
    expect(recent.first.syndromeId, 'syn-new');
    expect(recent.first.failed, 1);

    // 不加时间窗：两条都返回
    final all = await repo.aggregateBySyndrome();
    expect(all.length, 2);
  });

  test('#10 aggregateBySyndrome 空库 → 空列表', () async {
    final stats = await repo.aggregateBySyndrome();
    expect(stats, isEmpty);
  });

  test('#11 SyndromeTrainingStats 通过率口径边界', () {
    // 全 passed → 1.0
    const allPassed = SyndromeTrainingStats(
      syndromeId: 'x',
      passed: 5,
      partial: 0,
      failed: 0,
    );
    expect(allPassed.passRate, 1.0);

    // 全 failed → 0.0
    const allFailed = SyndromeTrainingStats(
      syndromeId: 'x',
      passed: 0,
      partial: 0,
      failed: 3,
    );
    expect(allFailed.passRate, 0.0);

    // 全 partial → 0.5
    const allPartial = SyndromeTrainingStats(
      syndromeId: 'x',
      passed: 0,
      partial: 4,
      failed: 0,
    );
    expect(allPartial.passRate, 0.5);

    // 零记录 → 0.0（避免除零）
    const empty = SyndromeTrainingStats(
      syndromeId: 'x',
      passed: 0,
      partial: 0,
      failed: 0,
    );
    expect(empty.passRate, 0.0);
  });
}
