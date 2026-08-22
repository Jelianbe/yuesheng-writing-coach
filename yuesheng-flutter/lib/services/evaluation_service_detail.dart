// ─────────────────────────────────────────────────────────────
// evaluation_service 拆分：evaluation_service_detail.dart（R-019 ≤300 行）
// 症候明细 extension：_buildSyndromeDetail。迁移自 evaluation_service.dart，行为零变更。
// ─────────────────────────────────────────────────────────────
part of 'evaluation_service.dart';

extension EvaluationDetailExtension on EvaluationService {
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
                await _diagnosisRepo.resolveSyndromesBatch(sessionId, [
                  problem.syndromeId,
                ]);
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
          trend: EvaluationService.mapTrendJudgment(summary.trend),
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
}
