// ─────────────────────────────────────────────────────────────
// display_types — 展示层类型（评估报告 / 学生画像）
// 真源：yuesheng-android/src/types/display.ts
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'teaching_types.dart';
import '../services/decode_guard.dart';

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

  /// E-1（复诊）：该症候在用户历史上的出现次数（跨会话，含本次）。
  /// 默认 1 表示「仅本次出现过」——旧数据反序列化后即为此值。
  final int occurrences;

  /// E-1（复诊）：历史「再犯」次数（好转后再次出现）。
  final int recurrences;

  /// E-1（复诊）：上一次出现时的严重度；无历史基准（仅出现一次）为 null。
  final Severity? previousSeverity;

  const SyndromeEvaluationDetail({
    required this.syndromeId,
    required this.syndromeName,
    required this.currentSeverity,
    required this.teachingState,
    required this.passCount,
    required this.totalCount,
    required this.trend,
    this.occurrences = 1,
    this.recurrences = 0,
    this.previousSeverity,
  });

  /// 是否为「复诊」（同一症候此前出现过）。
  ///
  /// UI 侧据此决定是否渲染复诊叙事 —— 只有出现过 ≥2 次才有对比意义。
  bool get isRecurrence => occurrences >= 2;

  /// 批次4-M3：序列化为 JSON（用于持久化到 app_state）
  Map<String, dynamic> toJson() => {
    'syndromeId': syndromeId,
    'syndromeName': syndromeName,
    'currentSeverity': currentSeverity.value,
    'teachingState': teachingState.value,
    'passCount': passCount,
    'totalCount': totalCount,
    'trend': trend.value,
    'occurrences': occurrences,
    'recurrences': recurrences,
    'previousSeverity': previousSeverity?.value,
  };

  /// 批次4-M3：从 JSON 反序列化
  ///
  /// E-1 向后兼容：`occurrences` / `recurrences` / `previousSeverity` 缺失时
  /// 回退为 1 / 0 / null（即「非复诊」），保证已落库的旧报告仍可解析。
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
      occurrences: (json['occurrences'] as num?)?.toInt() ?? 1,
      recurrences: (json['recurrences'] as num?)?.toInt() ?? 0,
      previousSeverity: Severity.fromString(
        json['previousSeverity'] as String?,
      ),
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
    } catch (e, st) {
      logDecodeFailure(field: 'evaluationData', error: e, stack: st);
      return null;
    }
  }
}
