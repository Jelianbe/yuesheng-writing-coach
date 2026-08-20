// ─────────────────────────────────────────────────────────────
// growth_service 拆分：growth_service_stats.dart（R-019 ≤300 行）
// 成长统计 extension：getGrowthOverview/getWritingCurve/_formatUtcDate/getLatestStyleProfile。迁移自 growth_service.dart，行为零变更。
// ─────────────────────────────────────────────────────────────
part of 'growth_service.dart';
extension GrowthStatsExtension on GrowthService {
  /// 成长总览（复刻 RN getGrowthOverview）
  Future<GrowthOverview> getGrowthOverview() async {
    final wordRow = await (_db.customSelect(
      'SELECT COALESCE(SUM(word_count), 0) AS total FROM chapters',
    )).getSingleOrNull();

    final diagRow = await (_db.customSelect(
      'SELECT COUNT(*) AS total, '
      // COALESCE 兜底：空表时 SUM() 返回 NULL（对齐 RN `?? 0`）
      "COALESCE(SUM(CASE WHEN status = 'resolved' THEN 1 ELSE 0 END), 0) "
      'AS resolved, '
      "COALESCE(SUM(CASE WHEN status = 'active' THEN 1 ELSE 0 END), 0) "
      'AS active '
      'FROM active_problem',
    )).getSingleOrNull();

    final phaseRow = await (_db.customSelect(
      'SELECT current_phase AS phase FROM teaching_state '
      'ORDER BY updated_at DESC LIMIT 1',
    )).getSingleOrNull();

    final daysRow = await (_db.customSelect(
      "SELECT COUNT(DISTINCT strftime('%Y-%m-%d', updated_at, 'unixepoch')) "
      'AS days FROM chapters WHERE word_count > 0',
    )).getSingleOrNull();

    final timeRow = await (_db.customSelect(
      'SELECT MIN(updated_at) AS first, MAX(updated_at) AS last '
      'FROM chapters WHERE word_count > 0',
    )).getSingleOrNull();

    final totalDiagnoses = await (_db.customSelect(
      'SELECT COUNT(*) AS total FROM diagnosis_results',
    )).getSingleOrNull();

    // 批次61：训练次数（跨会话聚合 teaching_history type='training' 记录）
    final trainingRows = await (_db.select(_db.studentModels)).get();
    var trainingCount = 0;
    for (final m in trainingRows) {
      try {
        final decoded = jsonDecode(m.teachingHistory);
        if (decoded is List) {
          trainingCount += decoded
              .whereType<Map<String, dynamic>>()
              .where((r) => r['type'] == 'training')
              .length;
        }
      } catch (_) {
        // 单条历史解析失败不影响其余
      }
    }

    final diagTotal = totalDiagnoses?.read<int>('total') ?? 0;

    return GrowthOverview(
      totalWords: wordRow?.read<int>('total') ?? 0,
      totalDiagnoses: diagTotal,
      totalResolved: diagRow?.read<int>('resolved') ?? 0,
      totalActive: diagRow?.read<int>('active') ?? 0,
      currentPhase:
          TeachingPhase.fromString(phaseRow?.read<String?>('phase')) ??
          TeachingPhase.p0Engage,
      writingDays: daysRow?.read<int>('days') ?? 0,
      firstWritingAt: timeRow?.read<int?>('first'),
      lastWritingAt: timeRow?.read<int?>('last'),
      // AI 介入 = 诊断 + 训练（学员每次请求 AI 处理作品即一次介入）
      aiInterventions: diagTotal + trainingCount,
    );
  }

  /// 最近 N 天写作曲线（复刻 RN getWritingCurve）
  ///
  /// 按 UTC 日期聚合（对齐 RN toISOString().slice(0,10) 与 SQL unixepoch），
  /// 返回完整的最近 [days] 天序列，从旧到新（RN Array.from(map.values) 插入序）
  Future<List<WritingDataPoint>> getWritingCurve({int days = 14}) async {
    final nowUtc = DateTime.now().toUtc();
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final cutoff = nowSec - days * 86400;

    final chapterRows = await (_db.customSelect(
      "SELECT strftime('%Y-%m-%d', updated_at, 'unixepoch') AS date, "
      'updated_at AS ts, word_count AS words FROM chapters '
      'WHERE updated_at >= ? AND word_count > 0 ORDER BY updated_at ASC',
      variables: [Variable.withInt(cutoff)],
    )).get();

    final diagnosisRows = await (_db.customSelect(
      "SELECT strftime('%Y-%m-%d', timestamp, 'unixepoch') AS date, "
      'timestamp AS ts FROM diagnosis_results '
      'WHERE timestamp >= ? ORDER BY timestamp ASC',
      variables: [Variable.withInt(cutoff)],
    )).get();

    // 新用户无写作和诊断记录时返回空数组，触发 UI 空态引导文案
    if (chapterRows.isEmpty && diagnosisRows.isEmpty) return const [];

    // 初始化最近 days 天 UTC 日期序列（对齐 RN toISOString().slice(0,10)）
    final byDate = <String, WritingDataPoint>{};
    for (var i = days - 1; i >= 0; i--) {
      final d = nowUtc.subtract(Duration(days: i));
      final dateStr = _formatUtcDate(d);
      byDate[dateStr] = WritingDataPoint(
        date: dateStr,
        timestamp:
            DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ 1000,
        wordCount: 0,
        diagnosisCount: 0,
      );
    }

    for (final row in chapterRows) {
      final date = row.read<String>('date');
      final point = byDate[date];
      if (point != null) {
        byDate[date] = WritingDataPoint(
          date: point.date,
          timestamp: point.timestamp,
          wordCount: point.wordCount + row.read<int>('words'),
          diagnosisCount: point.diagnosisCount,
        );
      }
    }

    for (final row in diagnosisRows) {
      final date = row.read<String>('date');
      final point = byDate[date];
      if (point != null) {
        byDate[date] = WritingDataPoint(
          date: point.date,
          timestamp: point.timestamp,
          wordCount: point.wordCount,
          diagnosisCount: point.diagnosisCount + 1,
        );
      }
    }

    // 按插入顺序返回（旧 → 新），对齐 RN Array.from(byDate.values())
    return byDate.values.toList();
  }

  static String _formatUtcDate(DateTime utc) {
    return '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')}';
  }

  /// 获取最新写作风格画像（批次53c：跨会话取 updated_at 最新的一条）
  ///
  /// style_profile 存于 student_model（v13），本方法为成长页聚合入口。
  /// 无数据 / JSON 非法 → null（不抛出）。
  Future<WritingStyleProfile?> getLatestStyleProfile() async {
    final rows = await _db
        .customSelect(
          "SELECT style_profile FROM student_model "
          "WHERE style_profile IS NOT NULL AND style_profile != '' "
          'ORDER BY updated_at DESC, rowid DESC LIMIT 1',
        )
        .get();
    if (rows.isEmpty) return null;
    try {
      final decoded = rows.first.read<String>('style_profile');
      final map = (decoded.isEmpty)
          ? <String, dynamic>{}
          : (jsonDecode(decoded) as Map<String, dynamic>);
      return WritingStyleProfile.fromJson(map);
    } catch (_) {
      return null; // 非法 JSON → 忽略
    }
  }
}
