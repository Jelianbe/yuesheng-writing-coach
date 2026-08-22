// ─────────────────────────────────────────────────────────────
// display_types — 展示层类型（评估报告 / 学生画像）
// 真源：yuesheng-android/src/types/display.ts
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'teaching_types.dart';

/// 评估趋势（UI 展示 3 值）
enum EvaluationTrend {
  improving('improving'),
  stable('stable'),
  worsening('worsening');

  final String value;
  const EvaluationTrend(this.value);

  static EvaluationTrend? fromString(String? s) {
    if (s == null) return null;
    for (final v in EvaluationTrend.values) {
      if (v.value == s) return v;
    }
    return null;
  }
}

/// 症候维度评估明细
class SyndromeEvaluationDetail {
  final String syndromeId;
  final String syndromeName;
  final Severity currentSeverity;
  final TeachingState teachingState;
  final int passCount;
  final int totalCount;
  final EvaluationTrend trend;

  const SyndromeEvaluationDetail({
    required this.syndromeId,
    required this.syndromeName,
    required this.currentSeverity,
    required this.teachingState,
    required this.passCount,
    required this.totalCount,
    required this.trend,
  });

  /// 批次4-M3：序列化为 JSON（用于持久化到 app_state）
  Map<String, dynamic> toJson() => {
    'syndromeId': syndromeId,
    'syndromeName': syndromeName,
    'currentSeverity': currentSeverity.value,
    'teachingState': teachingState.value,
    'passCount': passCount,
    'totalCount': totalCount,
    'trend': trend.value,
  };

  /// 批次4-M3：从 JSON 反序列化
  static SyndromeEvaluationDetail? fromJson(Map<String, dynamic> json) {
    final sev = Severity.fromString(json['currentSeverity'] as String?);
    final state = TeachingState.fromString(json['teachingState'] as String?);
    final trend = EvaluationTrend.fromString(json['trend'] as String?);
    if (sev == null || state == null || trend == null) return null;
    return SyndromeEvaluationDetail(
      syndromeId: json['syndromeId'] as String? ?? '',
      syndromeName: json['syndromeName'] as String? ?? '',
      currentSeverity: sev,
      teachingState: state,
      passCount: (json['passCount'] as num?)?.toInt() ?? 0,
      totalCount: (json['totalCount'] as num?)?.toInt() ?? 0,
      trend: trend,
    );
  }
}

/// 评估报告数据（一次训练反馈后生成）
class EvaluationData {
  /// 所属评估轮次
  final int round;

  /// 整体趋势
  final EvaluationTrend trend;

  /// 本轮有效练习次数
  final int trainingCount;

  /// 达标率 0~1
  final double passRate;

  /// 相对上一轮的整体严重度变化，例如 -1 / 0 / +1
  final int? severityDelta;

  /// 趋势说明文案
  final String summaryText;

  /// 症候维度明细
  final List<SyndromeEvaluationDetail> syndromeDetails;

  /// 报告生成时间
  final int generatedAt;

  const EvaluationData({
    required this.round,
    required this.trend,
    required this.trainingCount,
    required this.passRate,
    this.severityDelta,
    required this.summaryText,
    required this.syndromeDetails,
    required this.generatedAt,
  });

  /// 批次4-M3：序列化为 JSON 字符串（用于持久化到 app_state）
  String toJsonString() => jsonEncode({
    'round': round,
    'trend': trend.value,
    'trainingCount': trainingCount,
    'passRate': passRate,
    'severityDelta': severityDelta,
    'summaryText': summaryText,
    'syndromeDetails': syndromeDetails.map((d) => d.toJson()).toList(),
    'generatedAt': generatedAt,
  });

  /// 批次4-M3：从 JSON 字符串反序列化
  static EvaluationData? fromJsonString(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map<String, dynamic>) return null;
      final trend = EvaluationTrend.fromString(decoded['trend'] as String?);
      if (trend == null) return null;
      final detailsRaw = decoded['syndromeDetails'];
      final details = <SyndromeEvaluationDetail>[];
      if (detailsRaw is List) {
        for (final d in detailsRaw) {
          if (d is Map<String, dynamic>) {
            final detail = SyndromeEvaluationDetail.fromJson(d);
            if (detail != null) details.add(detail);
          }
        }
      }
      return EvaluationData(
        round: (decoded['round'] as num?)?.toInt() ?? 0,
        trend: trend,
        trainingCount: (decoded['trainingCount'] as num?)?.toInt() ?? 0,
        passRate: (decoded['passRate'] as num?)?.toDouble() ?? 0.0,
        severityDelta: decoded['severityDelta'] as int?,
        summaryText: decoded['summaryText'] as String? ?? '',
        syndromeDetails: details,
        generatedAt: (decoded['generatedAt'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}
