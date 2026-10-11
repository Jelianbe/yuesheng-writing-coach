import 'package:drift/drift.dart';

import '../database/database.dart';

/// 对话思考题仓储（E-8）
///
/// 从 AI 教练对话中回收反思性问题，供成长页间隔重复回顾。
class ReflectionQuestionRepository {
  final AppDatabase _db;
  ReflectionQuestionRepository(this._db);

  /// 批量插入思考题（去重：同 messageId + question 不重复）
  Future<void> insertQuestions(
    List<ReflectionQuestionsCompanion> entries,
  ) async {
    for (final e in entries) {
      final exists =
          await (_db.select(_db.reflectionQuestions)..where(
                (t) =>
                    t.messageId.equals(e.messageId.value ?? '') &
                    t.question.equals(e.question.value),
              ))
              .getSingleOrNull();
      if (exists == null) {
        await _db.into(_db.reflectionQuestions).insert(e);
      }
    }
  }

  /// 列出待回顾的思考题（status=pending，按 nextReviewAt 升序）
  Future<List<ReflectionQuestion>> listPending({int limit = 20}) {
    return (_db.select(_db.reflectionQuestions)
          ..where((t) => t.status.equals('pending'))
          ..orderBy([(t) => OrderingTerm.asc(t.nextReviewAt)])
          ..limit(limit))
        .get();
  }

  /// 标记为已回顾（reviewCount+1，按间隔重复推延 nextReviewAt）
  Future<void> markReviewed(String id) async {
    final q = await (_db.select(
      _db.reflectionQuestions,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (q == null) return;
    final nextCount = q.reviewCount + 1;
    // 简化间隔重复：reviewCount 1→1天、2→3天、3→7天、4+→14天
    final days = switch (nextCount) {
      1 => 1,
      2 => 3,
      3 => 7,
      _ => 14,
    };
    final nextAt = DateTime.now().millisecondsSinceEpoch ~/ 1000 + days * 86400;
    await (_db.update(
      _db.reflectionQuestions,
    )..where((t) => t.id.equals(id))).write(
      ReflectionQuestionsCompanion(
        status: const Value('reviewed'),
        reviewCount: Value(nextCount),
        nextReviewAt: Value(nextAt),
      ),
    );
  }

  /// 忽略某条思考题
  Future<void> dismiss(String id) =>
      (_db.update(
        _db.reflectionQuestions,
      )..where((t) => t.id.equals(id))).write(
        const ReflectionQuestionsCompanion(status: Value('dismissed')),
      );
}
