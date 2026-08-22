// ─────────────────────────────────────────────────────────────
// growth_service 拆分：growth_service_ability.dart（R-019 ≤300 行）
// 能力评估 extension：getAbilityScores/getSyndromeHistory/getSyndromeRecurrences。迁移自 growth_service.dart，行为零变更。
// ─────────────────────────────────────────────────────────────
part of 'growth_service.dart';

extension GrowthAbilityExtension on GrowthService {
  /// 六大能力维度评分（复刻 RN getAbilityScores）
  ///
  /// 按症候名关键词归类到 6 大维度；评分公式：
  /// score = clamp(80 - 检测次数×5 + 已解决×3, 30, 95)；无数据维度给 70 基线
  Future<List<AbilityScore>> getAbilityScores() async {
    final rows = await (_db.customSelect(
      'SELECT syndrome_name, COUNT(*) AS total, '
      "SUM(CASE WHEN status = 'resolved' THEN 1 ELSE 0 END) AS resolved "
      "FROM active_problem WHERE syndrome_name != '' GROUP BY syndrome_name",
    )).get();

    // 新用户无诊断记录时返回空数组，触发 UI 空态引导文案
    if (rows.isEmpty) return const [];

    final dimensionMap = <String, ({int detected, int resolved})>{
      for (final dim in GrowthService.abilityDimensions)
        dim.key: (detected: 0, resolved: 0),
    };

    for (final row in rows) {
      final name = row.read<String>('syndrome_name');
      final total = row.read<int>('total');
      final resolved = row.read<int>('resolved');
      final dimKey = _classifyDimension(name);
      final current = dimensionMap[dimKey]!;
      dimensionMap[dimKey] = (
        detected: current.detected + total,
        resolved: current.resolved + resolved,
      );
    }

    return [
      for (final dim in GrowthService.abilityDimensions)
        _buildAbilityScore(
          dimension: dim.label,
          description: dim.description,
          stats: dimensionMap[dim.key]!,
        ),
    ];
  }

  /// 最近 N 天症候历史事件流（复刻 RN getSyndromeHistory）
  Future<List<SyndromeHistoryEvent>> getSyndromeHistory({int days = 30}) async {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final cutoff = nowSec - days * 86400;

    final detected = await (_db.customSelect(
      'SELECT syndrome_id, syndrome_name, severity, created_at AS ts, '
      'session_id FROM active_problem '
      'WHERE created_at >= ? ORDER BY created_at DESC',
      variables: [Variable.withInt(cutoff)],
    )).get();

    final resolved = await (_db.customSelect(
      'SELECT syndrome_id, syndrome_name, severity, resolved_at AS ts, '
      'session_id FROM active_problem '
      'WHERE resolved_at IS NOT NULL AND resolved_at >= ? '
      'ORDER BY resolved_at DESC',
      variables: [Variable.withInt(cutoff)],
    )).get();

    final events = <SyndromeHistoryEvent>[
      for (final row in detected)
        SyndromeHistoryEvent(
          syndromeId: row.read<String>('syndrome_id'),
          syndromeName: row.read<String>('syndrome_name'),
          severity:
              Severity.fromString(row.read<String>('severity')) ?? Severity.l2,
          eventType: 'detected',
          timestamp: row.read<int>('ts'),
          sessionId: row.read<String>('session_id'),
        ),
      for (final row in resolved)
        SyndromeHistoryEvent(
          syndromeId: row.read<String>('syndrome_id'),
          syndromeName: row.read<String>('syndrome_name'),
          severity:
              Severity.fromString(row.read<String>('severity')) ?? Severity.l2,
          eventType: 'resolved',
          timestamp: row.read<int>('ts'),
          sessionId: row.read<String>('session_id'),
        ),
    ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return events;
  }

  /// 同类症候复发率（批次65 B62h，对齐 V1.0 原则4 / V1.1 建议6）
  ///
  /// 数据源 active_problem：UNIQUE(session_id, syndrome_id) 保证同一会话内
  /// 同症候仅一条，跨会话多条构成「出现」序列。否定诊断（rejected）不参与。
  /// 按 created_at 时间序判定「再犯」：某条记录之前存在一条已好转（resolved）
  /// 记录，则该次出现计为一次复发。复发率 = 再犯 / max(出现-1, 1)。
  Future<List<SyndromeRecurrence>> getSyndromeRecurrences() async {
    final rows = await (_db.customSelect(
      'SELECT syndrome_id, syndrome_name, status, created_at FROM active_problem '
      "WHERE confirmation_status != 'rejected' "
      'ORDER BY syndrome_id ASC, created_at ASC',
    )).get();

    final groups =
        <String, List<({String name, String status, int createdAt})>>{};
    for (final row in rows) {
      final id = row.read<String>('syndrome_id');
      groups.putIfAbsent(id, () => []).add((
        name: row.read<String>('syndrome_name'),
        status: row.read<String>('status'),
        createdAt: row.read<int>('created_at'),
      ));
    }

    final result = <SyndromeRecurrence>[];
    for (final entry in groups.entries) {
      final records = entry.value;
      var recovered = 0;
      var recurrences = 0;
      var wasResolved = false;
      for (final rec in records) {
        // 之前一条已好转 → 本次出现计为复发（V1.0 原则4：同症候反复）
        if (wasResolved) recurrences++;
        final isResolved = rec.status == 'resolved';
        if (isResolved) recovered++;
        wasResolved = isResolved;
      }
      final occurrences = records.length;
      result.add(
        SyndromeRecurrence(
          syndromeId: entry.key,
          syndromeName: records.first.name,
          occurrences: occurrences,
          recovered: recovered,
          recurrences: recurrences,
          rate: occurrences <= 1 ? 0 : recurrences / (occurrences - 1),
        ),
      );
    }

    // 复发率降序，同率按出现次数降序（高频问题优先）
    result.sort((a, b) {
      final byRate = b.rate.compareTo(a.rate);
      if (byRate != 0) return byRate;
      return b.occurrences.compareTo(a.occurrences);
    });
    return result;
  }
}
