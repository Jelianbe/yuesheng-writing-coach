// ─────────────────────────────────────────────────────────────
// syndrome_recurrence — 同类症候复发聚合（跨会话，共享查询）
//
// E-1（复诊闭环显性化）：本文件由 growth_service 抽出，使
//   - GrowthService（成长详情页「同类症候复发率」）
//   - DiagnosisRepository（评估链路「复诊」叙事）
// 共用同一聚合实现，避免同一语义出现双实现。
//
// 语义（延续批次65 B62h，对齐 V1.0 原则4 / V1.1 建议6）：
//   数据源 active_problem：UNIQUE(session_id, syndrome_id) 保证同一会话内
//   同症候仅一条，跨会话多条构成「出现」序列。否定诊断（rejected）不参与。
//   按 created_at 时间序判定「再犯」：某条记录之前存在一条已好转（resolved）
//   记录，则该次出现计为一次复发。复发率 = 再犯 / max(出现-1, 1)。
// ─────────────────────────────────────────────────────────────

import 'package:drift/drift.dart' show Variable;

import '../data/database/database.dart';

/// 同类症候复发统计：同一种症候「出现→好转→再犯」聚合
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

  /// E-1：上一次出现时的严重度（L1/L2/L3）。
  ///
  /// 仅出现过一次（无历史基准）时为 null —— 调用方据此判断
  /// 「能否做上次/这次对比」，避免编造对比数据。
  final String? previousSeverity;

  const SyndromeRecurrence({
    required this.syndromeId,
    required this.syndromeName,
    required this.occurrences,
    required this.recovered,
    required this.recurrences,
    required this.rate,
    this.previousSeverity,
  });
}

/// 跨会话聚合同类症候复发率。
///
/// [sessionIds] 为 null 时聚合全库（原有语义，调用方不变）；给定集合时把
/// 范围收敛到该批会话（批次 A：书籍级成长叙事按作品取复发）。
///
/// 排序：复发率降序，同率按出现次数降序（高频问题优先）。
/// 无数据时返回空列表。
Future<List<SyndromeRecurrence>> querySyndromeRecurrences(
  AppDatabase db, {
  Set<String>? sessionIds,
}) async {
  // 空集短路：避免生成 `IN ()`（SQLite 语法错误）。
  if (sessionIds != null && sessionIds.isEmpty) return const [];
  // 绑定变量个数 = 传入的会话数（SQLite 默认上限 999）。单作品的会话数
  // 受章节数制约，远低于该上限，故不做分批。
  final scopeFilter = sessionIds == null
      ? ''
      : 'AND session_id IN (${List.filled(sessionIds.length, '?').join(',')}) ';
  final rows = await (db.customSelect(
    'SELECT syndrome_id, syndrome_name, severity, status, created_at '
    "FROM active_problem WHERE confirmation_status != 'rejected' "
    '$scopeFilter'
    'ORDER BY syndrome_id ASC, created_at ASC',
    variables: sessionIds == null
        ? const []
        : sessionIds.map((id) => Variable.withString(id)).toList(),
  )).get();

  // 按 syndrome_id 分组；行序已由 SQL 保证 created_at 升序，
  // 组内追加即得时间序（与抽出前逐字一致）。
  final groups =
      <String, List<({String name, String severity, String status})>>{};
  for (final row in rows) {
    final id = row.read<String>('syndrome_id');
    groups.putIfAbsent(id, () => []).add((
      name: row.read<String>('syndrome_name'),
      severity: row.read<String>('severity'),
      status: row.read<String>('status'),
    ));
  }

  final result = groups.entries
      .map((e) => _buildRecurrence(e.key, e.value))
      .toList();

  result.sort((a, b) {
    final byRate = b.rate.compareTo(a.rate);
    if (byRate != 0) return byRate;
    return b.occurrences.compareTo(a.occurrences);
  });
  return result;
}

/// 统计单个症候的出现 / 好转 / 复发次数并算复发率。
SyndromeRecurrence _buildRecurrence(
  String syndromeId,
  List<({String name, String severity, String status})> records,
) {
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
  return SyndromeRecurrence(
    syndromeId: syndromeId,
    syndromeName: records.first.name,
    occurrences: occurrences,
    recovered: recovered,
    recurrences: recurrences,
    rate: occurrences <= 1 ? 0 : recurrences / (occurrences - 1),
    // 末条为「本次」，倒数第二条即「上一次出现」；仅一次时不设基准
    previousSeverity: occurrences >= 2
        ? records[records.length - 2].severity
        : null,
  );
}
