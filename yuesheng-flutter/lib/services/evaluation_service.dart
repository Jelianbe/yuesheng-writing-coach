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

  /// 计算某轮评估数据（无诊断历史时返回 null）
  Future<EvaluationData?> computeRoundEvaluation(
    String sessionId,
    int round,
  ) async {
    try {
      final diagnoses = await _diagnosisRepo.listDiagnosisHistory(sessionId);
      if (diagnoses.isEmpty) return null;

      final activeProblems = await _diagnosisRepo.listActiveProblems(sessionId);
      final teachingHistory = await _studentModelRepo.getTeachingHistory(
        sessionId,
      );

      final diagnosisRecords = teachingHistory
          .where((r) => r['type'] == 'diagnosis')
          .toList();
      final confirmationRecords = teachingHistory
          .where((r) => r['type'] == 'confirmation')
          .toList();

      final trainingCount = diagnosisRecords.isEmpty
          ? 1
          : diagnosisRecords.length;

      // 达标数 = teaching_history 中 confirmed 的确认记录数
      final confirmedCount = confirmationRecords
          .where((r) => r['action'] == 'confirmed')
          .length;
      final disputedCount = confirmationRecords
          .where((r) => r['action'] == 'disputed')
          .length;
      final totalConfirms = confirmedCount + disputedCount;

      // 症候明细：优先用 training-evaluator 真实数据，失败走 fallback
      final syndromeDetails = <SyndromeEvaluationDetail>[];
      for (final problem in activeProblems) {
        final detail = await _buildSyndromeDetail(
          sessionId,
          problem,
          confirmationRecords,
          diagnosisRecords,
        );
        if (detail != null) syndromeDetails.add(detail);
      }

      // 达标率：优先聚合症候明细 passCount/totalCount
      final totalPass = syndromeDetails.fold<int>(
        0,
        (sum, s) => sum + s.passCount,
      );
      final totalAttempt = syndromeDetails.fold<int>(
        0,
        (sum, s) => sum + s.totalCount,
      );
      final double passRate;
      if (totalAttempt > 0) {
        passRate = totalPass / totalAttempt;
      } else if (totalConfirms > 0) {
        passRate = confirmedCount / totalConfirms;
      } else {
        passRate = 0.5;
      }

      // 趋势：优先从症候明细聚合
      final improvingCount = syndromeDetails
          .where((s) => s.trend == EvaluationTrend.improving)
          .length;
      final worseningCount = syndromeDetails
          .where((s) => s.trend == EvaluationTrend.worsening)
          .length;
      final EvaluationTrend trend;
      if (syndromeDetails.isNotEmpty) {
        trend = improvingCount > worseningCount
            ? EvaluationTrend.improving
            : worseningCount > improvingCount
            ? EvaluationTrend.worsening
            : EvaluationTrend.stable;
      } else {
        trend = classifyTrend(passRate, diagnoses);
      }

      // 严重度变化：round>0 且诊断 >= 2 条时比较最近两轮平均严重度
      int? severityDelta;
      if (round > 0 && diagnoses.length >= 2) {
        final prevSeverity = _getAverageSeverity(
          diagnoses.sublist(diagnoses.length - 2, diagnoses.length - 1),
        );
        final currSeverity = _getAverageSeverity(
          diagnoses.sublist(diagnoses.length - 1),
        );
        severityDelta = (currSeverity - prevSeverity).round();
      }

      final summaryText = _generateSummaryText(trend, passRate);

      return EvaluationData(
        round: round,
        trend: trend,
        trainingCount: trainingCount,
        passRate: passRate,
        severityDelta: severityDelta,
        summaryText: summaryText,
        syndromeDetails: syndromeDetails,
        generatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      // 评估失败不阻断主流程（静默，release 不暴露细节）
      return null;
    }
  }

  /// 构建单个症候的评估明细（training-evaluator 真实数据优先，fallback 独立计算）
  Future<SyndromeEvaluationDetail?> _buildSyndromeDetail(
    String sessionId,
    ActiveProblemView problem,
    List<Map<String, dynamic>> confirmationRecords,
    List<Map<String, dynamic>> diagnosisRecords,
  ) async {
    try {
      final trainingInput = await buildTrainingInputForActiveSyndrome(
        _studentModelRepo,
        sessionId,
        problem.syndromeId,
        ActiveProblemMeta(
          currentSeverity: Severity.fromString(problem.severity) ?? Severity.l2,
        ),
        // v19：传 DiagnosisRepo 让 training_input_builder 从 DB 读持久化起点
        diagnosisRepo: _diagnosisRepo,
      );
      if (trainingInput != null) {
        final startingTeachingState = trainingInput.teachingState;
        final summary = buildEvaluationSummary(
          problem.syndromeId,
          trainingInput,
        );
        // v19：FSM 输出持久化 — 若状态发生迁移，写回 active_problem.teaching_state
        // 实现「状态累积」：identified→in_progress→consolidating→mastered 单调前进
        if (summary.teachingState != startingTeachingState) {
          try {
            await _diagnosisRepo.updateTeachingState(
              sessionId,
              problem.syndromeId,
              summary.teachingState.value,
            );
            // v19 E3 正向达标路径：FSM 输出 mastered → 立即解锁（status=resolved）
            // 避免学员在评估面板看到「已掌握」后，症候仍在活跃列表停留到下次诊断。
            if (summary.teachingState == TeachingState.mastered) {
              try {
                await _diagnosisRepo.resolveSyndromesBatch(
                  sessionId,
                  [problem.syndromeId],
                );
              } catch (_) {
                // 解锁失败不阻断评估报告继续返回（下一次诊断提交时会重试）
              }
            }
          } catch (_) {
            // 持久化失败不阻断评估报告继续返回（容错降级）
          }
        }
        final passCount = trainingInput.passRateInput.passCount;
        final totalCount = trainingInput.passRateInput.totalCount < 1
            ? 1
            : trainingInput.passRateInput.totalCount;
        return SyndromeEvaluationDetail(
          syndromeId: problem.syndromeId,
          syndromeName: problem.syndromeName,
          currentSeverity: Severity.fromString(problem.severity) ?? Severity.l2,
          teachingState: summary.teachingState,
          passCount: passCount,
          totalCount: totalCount,
          trend: mapTrendJudgment(summary.trend),
        );
      }
    } catch (_) {
      // 失败走 fallback
    }

    // Fallback：基于 teaching_history 独立计算
    final syndromeConfirms = confirmationRecords.where((r) {
      final syndromes = r['syndromes'];
      return syndromes is List && syndromes.contains(problem.syndromeId);
    }).toList();
    final syndromeConfirmed = syndromeConfirms
        .where((r) => r['action'] == 'confirmed')
        .length;
    final syndromeDiagnosisCount = diagnosisRecords.where((r) {
      final syndromes = r['syndromes'];
      return syndromes is List && syndromes.contains(problem.syndromeId);
    }).length;
    final syndromePassCount = syndromeConfirmed;
    final syndromeTotalCount = syndromeDiagnosisCount < 1
        ? 1
        : syndromeDiagnosisCount;
    final passRate = syndromeTotalCount == 0
        ? 0
        : syndromePassCount / syndromeTotalCount;
    return SyndromeEvaluationDetail(
      syndromeId: problem.syndromeId,
      syndromeName: problem.syndromeName,
      currentSeverity: Severity.fromString(problem.severity) ?? Severity.l2,
      teachingState: TeachingState.identified,
      passCount: syndromePassCount,
      totalCount: syndromeTotalCount,
      trend: passRate >= EvaluationThresholds.passRateImproving
          ? EvaluationTrend.improving
          : passRate >= EvaluationThresholds.passRateWorsening
          ? EvaluationTrend.stable
          : EvaluationTrend.worsening,
    );
  }

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

  /// M4-C：阶段迁移达标率计算（只读，无副作用）
  ///
  /// 从 teaching_history 的 confirmation 记录聚合达标率：
  ///   passRate = confirmed / (confirmed + disputed)
  ///
  /// 无确认记录时返回 0.5（中性值——既不强制迁移也不标记退步）。
  /// 出错时同样返回 0.5，保证不阻断主流程。
  ///
  /// 与 [computeRoundEvaluation] 的区别：不构建症候明细、不触发 FSM 写回，
  /// 专供阶段迁移校验使用（所有活跃症候已 resolved 时，明细维度已无数据）。
  Future<double> computePassRateForPhaseMigration(String sessionId) async {
    try {
      final teachingHistory = await _studentModelRepo.getTeachingHistory(
        sessionId,
      );
      final confirmationRecords = teachingHistory
          .where((r) => r['type'] == 'confirmation')
          .toList();
      final confirmedCount = confirmationRecords
          .where((r) => r['action'] == 'confirmed')
          .length;
      final disputedCount = confirmationRecords
          .where((r) => r['action'] == 'disputed')
          .length;
      final totalConfirms = confirmedCount + disputedCount;
      // 批次4（4.2 L3）：最小样本量门槛——确认记录 <3 时不迁移。
      // 1 条 confirmed 即达标率 1.0 属小样本虚高，M4-A 自动迁移需足够样本支撑。
      if (totalConfirms < EvaluationThresholds.minPhaseMigrationSamples) {
        return 0.5; // 中性值 < phasePassRate(0.7)，自动迁移被拦截
      }
      if (totalConfirms > 0) {
        return confirmedCount / totalConfirms;
      }
      return 0.5;
    } catch (_) {
      return 0.5;
    }
  }

  String _generateSummaryText(EvaluationTrend trend, double passRate) {
    switch (trend) {
      case EvaluationTrend.improving:
        return '整体进步明显，继续保持';
      case EvaluationTrend.worsening:
        return '需要关注，建议调整训练策略';
      case EvaluationTrend.stable:
        return passRate >= EvaluationThresholds.stableSubdivide
            ? '表现稳定，持续练习'
            : '仍有提升空间，继续加油';
    }
  }
}
