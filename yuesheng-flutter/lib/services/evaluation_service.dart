// ─────────────────────────────────────────────────────────────
// EvaluationService — 多轮评估服务
// 真源：yuesheng-android/src/services/evaluation-service.ts
//
// 从诊断历史 + 训练历史 + training-evaluator 计算评估数据：
//   - trainingCount / passRate / trend / severityDelta
//   - 症候维度明细（真实 teachingState + passCount/totalCount）
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import '../data/database/database.dart';
import '../data/repositories/diagnosis_repository.dart';
import '../data/repositories/student_model_repository.dart';
import '../types/display_types.dart';
import '../types/teaching_types.dart';
import 'student_profile_compute.dart';
import 'training_evaluator.dart';
import 'training_input_builder.dart';

part 'evaluation_service_round.dart';
part 'evaluation_service_detail.dart';
part 'evaluation_service_passrate.dart';
/// 评估阈值（真源：shared-constants.ts EVALUATION_THRESHOLDS）
class EvaluationThresholds {
  static const double passRateImproving = 0.7;
  static const double passRateWorsening = 0.4;
  static const double phasePassRate = 0.7;
  static const double phaseFailRate = 0.4;
  static const double stableSubdivide = 0.5;

  /// 批次4（4.2 L3）：M4-A 自动迁移最小样本量——confirmed+disputed < 该值时禁止迁移
  static const int minPhaseMigrationSamples = 3;
}

/// 多轮评估服务
class EvaluationService {
  final DiagnosisRepository _diagnosisRepo;
  final StudentModelRepository _studentModelRepo;

  EvaluationService(this._diagnosisRepo, this._studentModelRepo);

  /// 将 training-evaluator 的 TrendJudgment（4 值）映射为 EvaluationTrend（3 值）
  /// 'insufficient_data' 映射为 'stable'（UI 不展示"数据不足"）
  static EvaluationTrend mapTrendJudgment(TrendJudgment judgment) {
    switch (judgment) {
      case TrendJudgment.improving:
        return EvaluationTrend.improving;
      case TrendJudgment.worsening:
        return EvaluationTrend.worsening;
      case TrendJudgment.stable:
      case TrendJudgment.insufficientData:
        return EvaluationTrend.stable;
    }
  }

  /// 分类整体趋势（无症候明细时兜底）
  EvaluationTrend classifyTrend(double passRate, List<DiagnosisRow> diagnoses) {
    if (passRate >= EvaluationThresholds.passRateImproving) {
      return EvaluationTrend.improving;
    }
    if (passRate < EvaluationThresholds.passRateWorsening) {
      return EvaluationTrend.worsening;
    }

    // 中等达标率：检查严重度变化趋势
    if (diagnoses.length >= 2) {
      final prevSeverity = _getAverageSeverity(
        diagnoses.sublist(diagnoses.length - 2, diagnoses.length - 1),
      );
      final currSeverity = _getAverageSeverity(
        diagnoses.sublist(diagnoses.length - 1),
      );
      if (currSeverity < prevSeverity) return EvaluationTrend.improving;
      if (currSeverity > prevSeverity) return EvaluationTrend.worsening;
    }

    return EvaluationTrend.stable;
  }

  /// 获取诊断列表的平均严重度（数值）
  double _getAverageSeverity(List<DiagnosisRow> diagnoses) {
    if (diagnoses.isEmpty) return 2;

    var totalSeverity = 0;
    var count = 0;
    for (final d in diagnoses) {
      try {
        final syndromes = jsonDecode(d.syndromes) as List<dynamic>;
        for (final s in syndromes) {
          final severity = (s as Map<String, dynamic>)['severity'] as String?;
          if (severity != null) {
            totalSeverity += severityToNumber(
              Severity.fromString(severity) ?? Severity.l2,
            );
            count++;
          }
        }
      } catch (_) {
        // 忽略解析错误
      }
    }

    return count > 0 ? totalSeverity / count : 2;
  }
}
