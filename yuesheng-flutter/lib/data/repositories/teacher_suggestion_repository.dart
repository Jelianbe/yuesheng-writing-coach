// ─────────────────────────────────────────────────────────────
// Teacher Suggestion Repository
// 复刻 yuesheng-android/src/db/dao/teacher-suggestion-dao.ts
//
// FIFO 淘汰：同 session active 数 >= MAX_ACTIVE_PER_SESSION 时
// 最旧的自动 resolved，然后 INSERT 新条目（事务原子）。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/database/utils.dart';

const int _maxActivePerSession = 3;

/// 新增 Teacher Suggestion 入参
/// 真源：teacher-suggestion-dao.ts insertTeacherSuggestion params
class InsertTeacherSuggestionParams {
  final String sessionId;
  final String messageId;
  final String source; // 'editor' | 'diagnosis'
  final String teachingDecision; // 'guide' | 'train'
  final String? targetSyndromeId;
  final String? targetDimension;
  final String taskType; // 'rewrite' | 'analyze' | 'compare' | 'generate'
  final String taskDescription;
  final String difficulty; // 'easy' | 'medium' | 'hard'
  final List<String> evaluationCriteria;

  const InsertTeacherSuggestionParams({
    required this.sessionId,
    required this.messageId,
    required this.source,
    required this.teachingDecision,
    this.targetSyndromeId,
    this.targetDimension,
    required this.taskType,
    required this.taskDescription,
    required this.difficulty,
    required this.evaluationCriteria,
  });
}

class TeacherSuggestionRepository {
  final AppDatabase _db;
  TeacherSuggestionRepository(this._db);

  /// 新增 suggestion，触发 FIFO 淘汰。
  ///
  /// 真源：teacher-suggestion-dao.ts insertTeacherSuggestion
  Future<String> insertTeacherSuggestion(
    InsertTeacherSuggestionParams params,
  ) async {
    final id = generateUuid();
    final now = nowSec();

    await _db.transaction(() async {
      // FIFO 淘汰
      final activeCount =
          await (_db.selectOnly(_db.teacherSuggestions)
                ..addColumns([_db.teacherSuggestions.id.count()])
                ..where(
                  _db.teacherSuggestions.sessionId.equals(params.sessionId),
                )
                ..where(_db.teacherSuggestions.status.equals('active')))
              .map((row) => row.read(_db.teacherSuggestions.id.count()) ?? 0)
              .getSingle();

      if (activeCount >= _maxActivePerSession) {
        // 选最旧的一条 active（createdAt 升序）
        final oldestQuery = (_db.select(_db.teacherSuggestions)
          ..where((t) => t.sessionId.equals(params.sessionId))
          ..where((t) => t.status.equals('active'))
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt)])
          ..limit(1));
        final oldest = await oldestQuery.getSingleOrNull();
        if (oldest != null) {
          await (_db.update(
            _db.teacherSuggestions,
          )..where((t) => t.id.equals(oldest.id))).write(
            TeacherSuggestionsCompanion(
              status: const Value('resolved'),
              resolvedAt: Value(now),
            ),
          );
        }
      }

      // INSERT
      await _db
          .into(_db.teacherSuggestions)
          .insert(
            TeacherSuggestionsCompanion.insert(
              id: id,
              sessionId: params.sessionId,
              messageId: params.messageId,
              source: params.source,
              teachingDecision: params.teachingDecision,
              targetSyndromeId: params.targetSyndromeId == null
                  ? const Value.absent()
                  : Value(params.targetSyndromeId),
              targetDimension: params.targetDimension == null
                  ? const Value.absent()
                  : Value(params.targetDimension),
              taskType: params.taskType,
              taskDescription: params.taskDescription,
              difficulty: params.difficulty,
              evaluationCriteria: Value(jsonEncode(params.evaluationCriteria)),
              status: const Value('active'),
              createdAt: Value(now),
            ),
          );
    });

    return id;
  }

  /// 获取 session 所有 active suggestion（按 createdAt 倒序）
  Future<List<TeacherSuggestionRow>> getActiveSuggestions(
    String sessionId,
  ) async {
    return (_db.select(_db.teacherSuggestions)
          ..where((t) => t.sessionId.equals(sessionId))
          ..where((t) => t.status.equals('active'))
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
          ]))
        .get();
  }

  /// X-041d：按 syndromeId 查最近一条 suggestion（追溯训练来源）
  ///
  /// 用途：_handleTrainingResult 命中训练结果时，把触发当前训练轮
  /// 的建议 id + taskType 一并落到 training_results，补全追溯链。
  ///
  /// 取数规则（按 [createdAt] 倒序首条）：
  /// - status IN ('active','resolved')：覆盖未采纳 + 已采纳两种情况
  ///   （markAdopted/markResolved/markDismissed 都置 'resolved'，
  ///   仅靠 status 无法区分采纳/跳过；本查询只关心"是否曾经作为
  ///   该症候的训练触发建议"，故两者都纳入候选）
  /// - 无匹配返回 null（自主训练场景，suggestionId 留空）
  ///
  /// 注意：跨会话不查（训练轮只在本 session 内追溯触发建议）
  Future<TeacherSuggestionRow?> getLatestActiveBySyndrome(
    String sessionId,
    String syndromeId,
  ) async {
    final stmt = _db.select(_db.teacherSuggestions)
      ..where((t) => t.sessionId.equals(sessionId))
      ..where((t) => t.targetSyndromeId.equals(syndromeId))
      ..where((t) => t.status.isIn(const ['active', 'resolved']))
      ..orderBy([
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ])
      ..limit(1);
    return stmt.getSingleOrNull();
  }

  /// 标记 suggestion 已解决（D6：卡片「跳过此建议」按钮）
  ///
  /// 真源：teacher-suggestion-dao.ts markResolved
  /// 批次62：保留（FIFO/历史语义）；卡片跳过改用 [markDismissed]
  Future<void> markResolved(String suggestionId) async {
    await (_db.update(
      _db.teacherSuggestions,
    )..where((t) => t.id.equals(suggestionId))).write(
      TeacherSuggestionsCompanion(
        status: const Value('resolved'),
        resolvedAt: Value(nowSec()),
      ),
    );
  }

  /// 批次62：标记已采纳（卡片「开始练习」）。
  ///
  /// 置 resolved + adoptedAt，供 Just-in-Time 去重决策：
  /// 已采纳 → 冷却期后可触发新的/进阶反馈点。
  Future<void> markAdopted(String suggestionId) async {
    final now = nowSec();
    await (_db.update(
      _db.teacherSuggestions,
    )..where((t) => t.id.equals(suggestionId))).write(
      TeacherSuggestionsCompanion(
        status: const Value('resolved'),
        resolvedAt: Value(now),
        adoptedAt: Value(now),
      ),
    );
  }

  /// 批次62：标记已跳过（卡片「跳过此建议」）。
  ///
  /// 置 resolved + dismissedAt，语义 = 用户见过但未采纳，
  /// 去重窗口内不再触发同症候建议。
  Future<void> markDismissed(String suggestionId) async {
    final now = nowSec();
    await (_db.update(
      _db.teacherSuggestions,
    )..where((t) => t.id.equals(suggestionId))).write(
      TeacherSuggestionsCompanion(
        status: const Value('resolved'),
        resolvedAt: Value(now),
        dismissedAt: Value(now),
      ),
    );
  }

  /// 批次75：该建议是否已被用户跳过（卡片重建后按此持久态过滤）。
  ///
  /// 滚动回收重建卡片时「跳过」不能依赖局部 State——渲染前反查
  /// status='resolved' 且 dismissedAt 非空（markAdopted 只写 adoptedAt，
  /// 不影响本判定）。
  Future<bool> isDismissed(String suggestionId) async {
    if (suggestionId.isEmpty) return false;
    final row = await (_db.select(
      _db.teacherSuggestions,
    )..where((t) => t.id.equals(suggestionId))).getSingleOrNull();
    if (row == null) return false;
    return row.status == 'resolved' && row.dismissedAt != null;
  }

  /// 批次59/62：会话内同症候反馈去重（Just-in-Time 触发三问第 2 问）
  ///
  /// [recencyWindowSec] 窗口内该 session 最近一条同 [syndromeId] 建议：
  /// - 无记录 → false（可触发）
  /// - 有且未采纳（adoptedAt 为空，含已跳过/未处理）→ true（不触发——
  ///   用户已见过但未接受，不再骚扰）
  /// - 有且已采纳（adoptedAt 非空）→ 距采纳 < [adoptedWindowSec] → true
  ///   （冷却期）；≥ → false（可触发新的/进阶反馈点）
  ///
  /// syndromeId 为空（维度型建议）→ 不去重，返回 false。
  Future<bool> hasDuplicateSuggestion(
    String sessionId,
    String? syndromeId, {
    int recencyWindowSec = 3600,
    int adoptedWindowSec = 1800,
  }) async {
    if (syndromeId == null || syndromeId.isEmpty) return false;
    final now = nowSec();
    final cutoff = now - recencyWindowSec;
    final row =
        await (_db.select(_db.teacherSuggestions)
              ..where((t) => t.sessionId.equals(sessionId))
              ..where((t) => t.targetSyndromeId.equals(syndromeId))
              ..where((t) => t.createdAt.isBiggerThanValue(cutoff))
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.createdAt,
                  mode: OrderingMode.desc,
                ),
              ])
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return false;

    final adoptedAt = row.adoptedAt;
    if (adoptedAt == null) return true;
    return (now - adoptedAt) < adoptedWindowSec;
  }
}
