// ─────────────────────────────────────────────────────────────
// growth_service 拆分：growth_service_dto.dart（R-019 ≤300 行）
// DTO：GrowthOverview/AbilityScore/WritingDataPoint/SyndromeHistoryEvent/SyndromeRecurrence。迁移自 growth_service.dart，行为零变更。
// ─────────────────────────────────────────────────────────────
part of 'growth_service.dart';

/// 成长总览（复刻 RN GrowthOverview）
class GrowthOverview {
  final int totalWords;
  final int totalDiagnoses;
  final int totalResolved;
  final int totalActive;
  final TeachingPhase currentPhase;
  final int writingDays;
  final int? firstWritingAt;
  final int? lastWritingAt;

  /// 批次61：AI 介入次数 = 诊断次数 + 训练次数（依赖度信号——学员独立后应下降）
  final int aiInterventions;

  const GrowthOverview({
    required this.totalWords,
    required this.totalDiagnoses,
    required this.totalResolved,
    required this.totalActive,
    required this.currentPhase,
    required this.writingDays,
    this.firstWritingAt,
    this.lastWritingAt,
    this.aiInterventions = 0,
  });
}

/// 能力维度评分（复刻 RN AbilityScore，score 0-100）
class AbilityScore {
  final String dimension;
  final int score;
  final Trend trend;
  final String description;

  const AbilityScore({
    required this.dimension,
    required this.score,
    required this.trend,
    required this.description,
  });
}

/// 写作曲线数据点（复刻 RN WritingDataPoint）
class WritingDataPoint {
  final String date; // YYYY-MM-DD（UTC，对齐 RN toISOString）
  final int timestamp;
  final int wordCount;
  final int diagnosisCount;

  const WritingDataPoint({
    required this.date,
    required this.timestamp,
    required this.wordCount,
    required this.diagnosisCount,
  });
}

/// 症候历史事件（复刻 RN SyndromeHistoryEvent）
class SyndromeHistoryEvent {
  final String syndromeId;
  final String syndromeName;
  final Severity severity;
  final String eventType; // 'detected' | 'resolved'
  final int timestamp;
  final String sessionId;

  const SyndromeHistoryEvent({
    required this.syndromeId,
    required this.syndromeName,
    required this.severity,
    required this.eventType,
    required this.timestamp,
    required this.sessionId,
  });
}

/// 同类症候复发统计（批次65 B62h）：同一种症候「出现→好转→再犯」聚合
class SyndromeRecurrence {
  final String syndromeId;
  final String syndromeName;

  /// 出现次数（跨会话 active_problem 记录数）
  final int occurrences;

  /// 好转次数（status = resolved）
  final int recovered;

  /// 再犯次数（好转后再次出现）
  final int recurrences;

  /// 复发率 = recurrences / max(occurrences - 1, 1)，0-1
  final double rate;

  const SyndromeRecurrence({
    required this.syndromeId,
    required this.syndromeName,
    required this.occurrences,
    required this.recovered,
    required this.recurrences,
    required this.rate,
  });
}
