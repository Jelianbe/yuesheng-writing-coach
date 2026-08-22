// ─────────────────────────────────────────────────────────────
// evaluation_service 拆分：evaluation_service_round.dart（R-019 ≤300 行）
// 轮次评估 extension：computeRoundEvaluation。迁移自 evaluation_service.dart，行为零变更。
// ─────────────────────────────────────────────────────────────
part of 'evaluation_service.dart';

extension EvaluationRoundExtension on EvaluationService {
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
}
