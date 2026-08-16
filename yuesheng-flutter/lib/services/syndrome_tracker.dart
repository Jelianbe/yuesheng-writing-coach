// ─────────────────────────────────────────────────────────────
// syndrome_tracker — 症候跨轮次追踪（缺口清单 E 类，SyndromeDetailModal 数据源）
// 真源：yuesheng-android/src/services/syndrome-tracker.service.ts
//
// 从诊断历史（listDiagnosisHistory）聚合每个症候：
//   - occurrenceCount 出现次数 / firstSeen / lastSeen / currentSeverity
//   - recentPoints 最近 5 次诊断（severity + timestamp）
//   - trend 趋势（improving/stable/worsening）：前后半段平均严重度差分
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import '../data/repositories/diagnosis_repository.dart';

/// 单次诊断记录点（复刻 RN SyndromeTrendPoint）
class SyndromeTrendPoint {
  final int timestamp;
  final String severity; // L1 | L2 | L3
  final String diagnosisId;
  const SyndromeTrendPoint({
    required this.timestamp,
    required this.severity,
    required this.diagnosisId,
  });
}

/// 症候追踪聚合（复刻 RN SyndromeTracked）
class SyndromeTracked {
  final String syndromeId;
  final String name;
  final String currentSeverity;
  final int firstSeen;
  final int lastSeen;
  final int occurrenceCount;
  final String trend; // 'improving' | 'stable' | 'worsening'
  final List<SyndromeTrendPoint> recentPoints;

  const SyndromeTracked({
    required this.syndromeId,
    required this.name,
    required this.currentSeverity,
    required this.firstSeen,
    required this.lastSeen,
    required this.occurrenceCount,
    required this.trend,
    required this.recentPoints,
  });
}

const Map<String, int> _severityScore = {'L1': 1, 'L2': 2, 'L3': 3};

const Map<String, String> _trendLabel = {
  'improving': '好转',
  'stable': '稳定',
  'worsening': '加重',
};

const Map<String, String> _trendColor = {
  'improving': 'success', // 由 UI 层映射到主题色
  'stable': 'neutral',
  'worsening': 'danger',
};

/// 趋势文案（对齐 RN getTrendLabel）
String getTrendLabel(String trend) => _trendLabel[trend] ?? '稳定';

/// 趋势语义（对齐 RN getTrendColor，UI 层据此映射主题色）
String getTrendColor(String trend) => _trendColor[trend] ?? 'neutral';

class SyndromeTracker {
  final DiagnosisRepository _repo;
  SyndromeTracker(this._repo);

  /// 聚合会话内所有症候的跨轮次追踪（对齐 RN loadSyndromeTrends）
  Future<List<SyndromeTracked>> loadSyndromeTrends(String sessionId) async {
    final rows = await _repo.listDiagnosisHistory(sessionId);
    if (rows.isEmpty) return [];

    final map = <String, SyndromeTracked>{};

    // 诊断历史按 timestamp DESC；聚合时不依赖行序，逐条累加
    for (final row in rows) {
      final syndromes = _parseSyndromes(row.syndromes);
      for (final s in syndromes) {
        final id = s['syndrome_id'] as String? ?? '';
        if (id.isEmpty) continue;
        final point = SyndromeTrendPoint(
          timestamp: row.timestamp,
          severity: s['severity'] as String? ?? 'L2',
          diagnosisId: row.id,
        );

        final existing = map[id];
        if (existing == null) {
          map[id] = SyndromeTracked(
            syndromeId: id,
            name: s['name'] as String? ?? '',
            currentSeverity: point.severity,
            firstSeen: row.timestamp,
            lastSeen: row.timestamp,
            occurrenceCount: 1,
            trend: 'stable',
            recentPoints: [point],
          );
        } else {
          map[id] = SyndromeTracked(
            syndromeId: existing.syndromeId,
            name: existing.name,
            currentSeverity: row.timestamp > existing.lastSeen
                ? point.severity
                : existing.currentSeverity,
            firstSeen: row.timestamp < existing.firstSeen
                ? row.timestamp
                : existing.firstSeen,
            lastSeen: row.timestamp > existing.lastSeen
                ? row.timestamp
                : existing.lastSeen,
            occurrenceCount: existing.occurrenceCount + 1,
            trend: existing.trend,
            recentPoints: [...existing.recentPoints, point],
          );
        }
      }
    }

    final result = <SyndromeTracked>[];
    for (final t in map.values) {
      final points = [...t.recentPoints]
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      final recent = points.length > 5
          ? points.sublist(points.length - 5)
          : points;
      result.add(
        SyndromeTracked(
          syndromeId: t.syndromeId,
          name: t.name,
          currentSeverity: t.currentSeverity,
          firstSeen: t.firstSeen,
          lastSeen: t.lastSeen,
          occurrenceCount: t.occurrenceCount,
          trend: computeTrend(recent),
          recentPoints: recent,
        ),
      );
    }

    // 排序：当前严重度降序 → 出现次数降序（对齐 RN）
    result.sort((a, b) {
      final sevDiff =
          (_severityScore[b.currentSeverity] ?? 0) -
          (_severityScore[a.currentSeverity] ?? 0);
      if (sevDiff != 0) return sevDiff;
      return b.occurrenceCount - a.occurrenceCount;
    });
    return result;
  }

  /// 趋势计算：前后半段平均严重度差分（对齐 RN computeTrend）
  String computeTrend(List<SyndromeTrendPoint> points) {
    if (points.length < 2) return 'stable';
    final firstHalf = points.sublist(0, (points.length / 2).ceil());
    final secondHalf = points.sublist((points.length / 2).floor());
    final diff = _avgSeverity(secondHalf) - _avgSeverity(firstHalf);
    if (diff <= -0.3) return 'improving';
    if (diff >= 0.3) return 'worsening';
    return 'stable';
  }

  double _avgSeverity(List<SyndromeTrendPoint> points) {
    if (points.isEmpty) return 0;
    final sum = points.fold<int>(
      0,
      (acc, p) => acc + (_severityScore[p.severity] ?? 0),
    );
    return sum / points.length;
  }

  /// 解析 syndromes JSON（对齐诊断存储格式：List<{syndrome_id, name, severity, ...}>）
  List<Map<String, dynamic>> _parseSyndromes(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return const [];
      return decoded.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return const [];
    }
  }
}
