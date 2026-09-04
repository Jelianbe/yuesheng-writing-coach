// ─────────────────────────────────────────────────────────────
// 学员画像 — 纯计算函数
// 复刻 yuesheng-android/src/services/student-profile-compute.ts
//
// 无 IO 依赖，便于单测。
// ─────────────────────────────────────────────────────────────

import 'package:writingcoach/config/shared_constants.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/types/teaching_types.dart';

/// 严重度 → 数值
int severityToNumber(Severity s) {
  switch (s) {
    case Severity.l3:
      return 3;
    case Severity.l2:
      return 2;
    case Severity.l1:
      return 1;
  }
}

Severity _severityFromString(String s) {
  return Severity.fromString(s) ?? Severity.l2;
}

/// 计算症候聚合 profile
///
/// 真源：student-profile-compute.ts computeSyndromeProfile
Map<String, SyndromeAggregation> computeSyndromeProfile(
  List<SyndromeFlatEntry> entries,
) {
  // 中间结构
  final grouped = <String, _SyndromeGroup>{};
  for (final e in entries) {
    final g = grouped.putIfAbsent(
      e.syndromeId,
      () => _SyndromeGroup(
        name: e.syndromeName,
        severities: <Severity>[],
        lastSeen: 0,
        sessionIds: <String>{},
      ),
    );
    g.severities.add(_severityFromString(e.severity));
    if (e.timestamp > g.lastSeen) g.lastSeen = e.timestamp;
    g.sessionIds.add(e.sessionId);
  }

  final result = <String, SyndromeAggregation>{};
  grouped.forEach((id, g) {
    final severityHistory = g.severities;
    final latestSeverity = severityHistory.isNotEmpty
        ? severityHistory.last
        : Severity.l2;
    final trend = computeTrend(severityHistory);
    final teachingState = inferTeachingState(
      severityHistory.length,
      severityHistory,
      trend,
      latestSeverity,
    );
    result[id] = SyndromeAggregation(
      syndromeId: id,
      syndromeName: g.name,
      occurrenceCount: severityHistory.length,
      severityHistory: severityHistory,
      latestSeverity: latestSeverity,
      trend: trend,
      lastSeenAt: g.lastSeen,
      sessionCount: g.sessionIds.length,
      teachingState: teachingState,
    );
  });
  return result;
}

/// 计算趋势
///
/// 真源：student-profile-compute.ts computeTrend
Trend computeTrend(List<Severity> history) {
  if (history.length < 2) return Trend.unknown;
  if (history.length < 4) return Trend.stable;

  final recent = history.sublist(history.length - 2);
  final earlier = history.sublist(history.length - 4, history.length - 2);
  final recentAvg =
      (severityToNumber(recent[0]) + severityToNumber(recent[1])) / 2;
  final earlierAvg =
      (severityToNumber(earlier[0]) + severityToNumber(earlier[1])) / 2;

  if (recentAvg < earlierAvg) return Trend.improving;
  if (recentAvg > earlierAvg) return Trend.worsening;
  return Trend.stable;
}

/// 推断教学状态（基线三态，mastered 由 training-evaluator 覆盖）
///
/// 真源：student-profile-compute.ts inferTeachingState
TeachingState inferTeachingState(
  int occurrenceCount,
  List<Severity> severityHistory,
  Trend trend,
  Severity latestSeverity,
) {
  if (occurrenceCount <= 2 && trend == Trend.unknown) {
    return TeachingState.identified;
  }

  // 最近 5 条
  final recent5 = severityHistory.length > 5
      ? severityHistory.sublist(severityHistory.length - 5)
      : severityHistory;
  if (recent5.length >= 3 &&
      recent5.every((s) => s == Severity.l1) &&
      trend == Trend.improving) {
    return TeachingState.consolidating;
  }

  if (trend == Trend.improving &&
      latestSeverity == Severity.l1 &&
      occurrenceCount >= 3) {
    return TeachingState.consolidating;
  }

  return TeachingState.inProgress;
}

/// 推断能力等级
///
/// 真源：student-profile-compute.ts inferProficiency
ProficiencyInference inferProficiency(List<Severity> history) {
  final total = history.length;
  if (total == 0) {
    return ProficiencyInference(
      level: ProficiencyLevel.beginner,
      confidence: 0,
    );
  }

  final l3Count = history.where((s) => s == Severity.l3).length;
  final l2Count = history.where((s) => s == Severity.l2).length;

  final beginner = _beginnerInference(l3Count, l2Count, total);
  if (beginner != null) return beginner;

  final advanced = _advancedInference(history);
  if (advanced != null) return advanced;

  return ProficiencyInference(
    level: ProficiencyLevel.intermediate,
    confidence: _intermediateConfidence(total),
  );
}

/// l3 / l2 重度占比达标 → beginner；否则返回 null 交由后续档位判定。
///
/// 两条分支各自用自己的常量对（真源 student-profile-compute.ts 同构）。
ProficiencyInference? _beginnerInference(int l3Count, int l2Count, int total) {
  if (l3Count >= ProficiencyThresholds.beginnerL3CountThreshold) {
    return ProficiencyInference(
      level: ProficiencyLevel.beginner,
      confidence: _min(
        ProficiencyThresholds.maxBeginnerL3Confidence,
        ProficiencyThresholds.baseBeginnerL3Confidence + l3Count / total,
      ),
    );
  }
  if (l2Count >= ProficiencyThresholds.beginnerL2CountThreshold) {
    return ProficiencyInference(
      level: ProficiencyLevel.beginner,
      confidence: _min(
        ProficiencyThresholds.maxBeginnerL2Confidence,
        ProficiencyThresholds.baseBeginnerL2Confidence + l2Count / total,
      ),
    );
  }
  return null;
}

/// 近期窗口（长度 `advancedRecentWindow`）内全为 l1 且样本数达标 → advanced。
///
/// 样本不足窗口长度时取整条历史（不足 `advancedRecentMin` 会被判据挡下）。
ProficiencyInference? _advancedInference(List<Severity> history) {
  final windowSize = ProficiencyThresholds.advancedRecentWindow;
  final recent5 = history.length > windowSize
      ? history.sublist(history.length - windowSize)
      : history;
  if (recent5.length >= ProficiencyThresholds.advancedRecentMin &&
      recent5.every((s) => s == Severity.l1)) {
    return ProficiencyInference(
      level: ProficiencyLevel.advanced,
      confidence: ProficiencyThresholds.advancedConfidence,
    );
  }
  return null;
}

/// 未命中 beginner / advanced 时，按样本量分档给出 intermediate 置信度。
double _intermediateConfidence(int total) {
  if (total < ProficiencyThresholds.intermediateLowSampleThreshold) {
    return ProficiencyThresholds.lowSampleConfidence;
  }
  if (total < ProficiencyThresholds.intermediateMidSampleThreshold) {
    return ProficiencyThresholds.midSampleConfidence;
  }
  return ProficiencyThresholds.highSampleConfidence;
}

/// 症候优先级排序
///
/// 真源：student-profile-compute.ts prioritizeSyndromes
List<({String id, String name, double score})> prioritizeSyndromes(
  Map<String, SyndromeAggregation> profile,
) {
  final entries = profile.values.map((agg) {
    final severityWeight = severityToNumber(agg.latestSeverity);
    final frequencyWeight =
        agg.occurrenceCount * SyndromePriorityWeights.frequencyFactor;
    double trendWeight = 0;
    if (agg.trend == Trend.worsening) {
      trendWeight = SyndromePriorityWeights.trendWorsening;
    } else if (agg.trend == Trend.improving) {
      trendWeight = SyndromePriorityWeights.trendImproving;
    }

    double teachingStateWeight = 0;
    if (agg.teachingState == TeachingState.inProgress) {
      teachingStateWeight = SyndromePriorityWeights.stateInProgress;
    } else if (agg.teachingState == TeachingState.identified) {
      teachingStateWeight = SyndromePriorityWeights.stateIdentified;
    } else if (agg.teachingState == TeachingState.mastered) {
      teachingStateWeight = SyndromePriorityWeights.stateMastered;
    }

    final score =
        severityWeight * SyndromePriorityWeights.severityFactor +
        frequencyWeight +
        trendWeight +
        teachingStateWeight;
    return (id: agg.syndromeId, name: agg.syndromeName, score: score);
  }).toList();

  entries.sort((a, b) => b.score.compareTo(a.score));
  return entries;
}

/// 检测停滞
///
/// 真源：student-profile-compute.ts detectStagnation
StagnationResult detectStagnation(
  Map<String, SyndromeAggregation> profile,
  int totalSessions,
) {
  if (totalSessions < ProficiencyThresholds.stagnationMinSessions) {
    return const StagnationResult();
  }

  final totalDiagnoses = profile.values.fold<int>(
    0,
    (sum, agg) => sum + agg.occurrenceCount,
  );
  if (totalDiagnoses < ProficiencyThresholds.stagnationMinDiagnoses) {
    return const StagnationResult();
  }

  final hasImproving = profile.values.any(
    (agg) => agg.trend == Trend.improving,
  );
  if (hasImproving) return const StagnationResult();

  final allSeverities = profile.values
      .expand((agg) => agg.severityHistory)
      .map(severityToNumber)
      .toList();
  if (allSeverities.length <
      ProficiencyThresholds.stagnationMinSeverityHistory) {
    return const StagnationResult();
  }

  final recent2 = allSeverities.sublist(allSeverities.length - 2);
  final earlier2 = allSeverities.sublist(
    allSeverities.length - 4,
    allSeverities.length - 2,
  );
  final recentAvg = (recent2[0] + recent2[1]) / 2;
  final earlierAvg = (earlier2[0] + earlier2[1]) / 2;

  if (recentAvg >= earlierAvg) {
    return const StagnationResult(
      stagnated: true,
      reason: '连续 2 次对话无明显改善，建议调整教学方式',
    );
  }
  return const StagnationResult();
}

double _min(double a, double b) => a < b ? a : b;

class _SyndromeGroup {
  final String name;
  final List<Severity> severities;
  int lastSeen;
  final Set<String> sessionIds;
  _SyndromeGroup({
    required this.name,
    required this.severities,
    required this.lastSeen,
    required this.sessionIds,
  });
}
