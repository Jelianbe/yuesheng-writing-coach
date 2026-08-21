// ─────────────────────────────────────────────────────────────
// evaluation_service 拆分：evaluation_service_passrate.dart（R-019 ≤300 行）
// 阶段迁移达标率 extension：computePassRateForPhaseMigration/_generateSummaryText。迁移自 evaluation_service.dart，行为零变更。
// ─────────────────────────────────────────────────────────────
part of 'evaluation_service.dart';
extension EvaluationPassRateExtension on EvaluationService {

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
