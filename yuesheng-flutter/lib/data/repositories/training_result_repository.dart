// ─────────────────────────────────────────────────────────────
// Training Result Repository
// X-041a P0：训练结果持久化
//
// 真源：PracticeStore.trainingResult 当前仅存内存 state（重启即失）
// 本 repository 把训练尝试结果落到 training_results 表，补全持久化路径
//
// 设计意图：
// - 会话级查询：回看本会话内的所有练习尝试（queryBySession）
// - 症候级追溯：跨会话查某症候的练习历史，供复盘与画像演化（queryBySyndrome）
// - suggestion_id 软关联：删建议 SET NULL 保留训练历史
//
// P0 边界：仅持久化，不接管 PracticeStore 调用链（不破坏现有内存态逻辑）
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/database/utils.dart';

/// 新增 Training Result 入参
class InsertTrainingResultParams {
  final String sessionId;
  /// 关联建议（可空：无建议触发的自主训练）
  final String? suggestionId;
  final String syndromeId;
  /// 'rewrite' | 'analyze' | 'compare' | 'generate'
  final String taskType;
  /// 用户提交的练习内容
  final String userContent;
  /// 'passed' | 'partial' | 'failed'
  final String result;
  /// AI 评分反馈（nullable，Map → JSON string 落库）
  final Map<String, dynamic>? feedback;
  /// 0.0-1.0 评分（nullable）
  final double? score;

  const InsertTrainingResultParams({
    required this.sessionId,
    this.suggestionId,
    required this.syndromeId,
    required this.taskType,
    required this.userContent,
    required this.result,
    this.feedback,
    this.score,
  });
}

class TrainingResultRepository {
  final AppDatabase _db;
  TrainingResultRepository(this._db);

  /// 新增训练结果记录，返回 id
  ///
  /// 真源：PracticeStore.setTrainingResult 的持久化对应
  Future<String> insertTrainingResult(
    InsertTrainingResultParams params,
  ) async {
    final id = generateUuid();
    final now = nowSec();

    await _db.into(_db.trainingResults).insert(
      TrainingResultsCompanion.insert(
        id: id,
        sessionId: params.sessionId,
        suggestionId: params.suggestionId == null
            ? const Value.absent()
            : Value(params.suggestionId),
        syndromeId: params.syndromeId,
        taskType: params.taskType,
        userContent: params.userContent,
        result: params.result,
        feedbackJson: params.feedback == null
            ? const Value.absent()
            : Value(jsonEncode(params.feedback)),
        score: params.score == null
            ? const Value.absent()
            : Value(params.score),
        createdAt: Value(now),
      ),
    );

    return id;
  }

  /// 会话级查询：本会话所有训练结果，按 created_at 倒序
  ///
  /// 用于卡片回看、复盘面板按会话聚合
  Future<List<TrainingResultRow>> queryBySession(String sessionId) async {
    return (_db.select(_db.trainingResults)
          ..where((t) => t.sessionId.equals(sessionId))
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
          ]))
        .get();
  }

  /// 症候级追溯：跨会话查某症候的练习历史，按 created_at 倒序
  ///
  /// 用于画像演化追踪、长期进步曲线、症候复盘
  /// [limit] 默认 50，避免历史数据过多影响性能
  Future<List<TrainingResultRow>> queryBySyndrome(
    String syndromeId, {
    int limit = 50,
  }) async {
    return (_db.select(_db.trainingResults)
          ..where((t) => t.syndromeId.equals(syndromeId))
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
          ])
          ..limit(limit))
        .get();
  }

  /// 单条查询：按 id 精确定位（用于回写关联）
  Future<TrainingResultRow?> getById(String id) async {
    return (_db.select(_db.trainingResults)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }
}
