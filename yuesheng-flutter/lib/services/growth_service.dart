// ─────────────────────────────────────────────────────────────
// growth_service — 用户级写作成长数据服务（跨会话全局聚合）
// 真源：yuesheng-android/src/services/growth-service.ts
//
// 职责（对齐 RN growth-detail 页面四数据源）：
//   - getGrowthOverview：成长总览（总字数/诊断次数/已解决/待改进/阶段/写作天数/首末写作）
//   - getAbilityScores：六大能力维度评分（0-100 + 趋势）
//   - getWritingCurve：最近 N 天写作曲线（每日字数 + 诊断次数）
//   - getSyndromeHistory：症候历史事件流（发现/解决时间线）
//
// 批次 51a：Flutter GrowthDetailPage 对齐 RN growth-detail.tsx 的数据层落地。
// 数据源均为现有 drift 表（chapters / diagnosis_results / active_problem /
// teaching_state），采用 customSelect 原生 SQL 复刻 RN SQL 语义。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:drift/drift.dart';

import '../data/database/database.dart';
import '../data/repositories/training_result_repository.dart';
import '../types/teaching_types.dart';

/// 成长数据服务（用户级，无 sessionId 维度）
class GrowthService {
  final AppDatabase _db;

  GrowthService(this._db);

  /// 六大能力维度（复刻 RN ABILITY_DIMENSIONS）
  static const List<({String key, String label, String description})>
  abilityDimensions = [
    (key: 'plot', label: '情节构建', description: '故事结构、节奏与冲突'),
    (key: 'character', label: '人物塑造', description: '角色立体度与动机'),
    (key: 'language', label: '语言表达', description: '用词、句式与节奏'),
    (key: 'logic', label: '逻辑连贯', description: '因果关系与衔接'),
    (key: 'emotion', label: '情感共鸣', description: '代入感与情绪传递'),
    (key: 'theme', label: '主题深度', description: '思想性与立意'),
  ];

  // ─────────────────────────────────────────────
  // 内部工具（复刻 RN classifyDimension / 评分公式）
  // ─────────────────────────────────────────────

  /// 症候名关键词归类到 6 大维度（复刻 RN classifyDimension）
  String _classifyDimension(String syndromeName) {
    if (RegExp(r'情节|结构|节奏|冲突|大纲').hasMatch(syndromeName)) return 'plot';
    if (RegExp(r'人物|角色|动机|心理').hasMatch(syndromeName)) return 'character';
    if (RegExp(r'语言|用词|句式|描写|文风').hasMatch(syndromeName)) {
      return 'language';
    }
    if (RegExp(r'逻辑|因果|衔接|跳跃').hasMatch(syndromeName)) return 'logic';
    if (RegExp(r'情感|情绪|代入|共鸣').hasMatch(syndromeName)) return 'emotion';
    if (RegExp(r'主题|立意|深度|思想').hasMatch(syndromeName)) return 'theme';
    // 默认归入语言表达
    return 'language';
  }

  /// 评分 + 趋势（复刻 RN 公式）
  AbilityScore _buildAbilityScore({
    required String dimension,
    required String description,
    required ({int detected, int resolved}) stats,
  }) {
    var score = 80 - stats.detected * 5 + stats.resolved * 3;
    score = score.clamp(30, 95);
    // 若无数据，给 70 分基线
    if (stats.detected == 0) score = 70;

    final Trend trend;
    if (stats.resolved > 0 && stats.resolved >= stats.detected * 0.5) {
      trend = Trend.improving;
    } else if (stats.detected > stats.resolved) {
      trend = Trend.worsening;
    } else {
      trend = Trend.stable;
    }

    return AbilityScore(
      dimension: dimension,
      score: score.round(),
      trend: trend,
      description: description,
    );
  }
}

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

    final trainingCount = await _countTrainingRecords();
    final diagTotal = totalDiagnoses?.read<int>('total') ?? 0;

    return _buildGrowthOverview(
      wordRow: wordRow,
      diagRow: diagRow,
      phaseRow: phaseRow,
      daysRow: daysRow,
      timeRow: timeRow,
      diagTotal: diagTotal,
      trainingCount: trainingCount,
    );
  }

  /// 训练次数（跨会话聚合 teaching_history type='training' 记录，批次61）。
  Future<int> _countTrainingRecords() async {
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
    return trainingCount;
  }

  /// 组装成长总览（R-019 拆出：getGrowthOverview）。
  GrowthOverview _buildGrowthOverview({
    required QueryRow? wordRow,
    required QueryRow? diagRow,
    required QueryRow? phaseRow,
    required QueryRow? daysRow,
    required QueryRow? timeRow,
    required int diagTotal,
    required int trainingCount,
  }) {
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

    final result = groups.entries
        .map((e) => _buildRecurrence(e.key, e.value))
        .toList();

    // 复发率降序，同率按出现次数降序（高频问题优先）
    result.sort((a, b) {
      final byRate = b.rate.compareTo(a.rate);
      if (byRate != 0) return byRate;
      return b.occurrences.compareTo(a.occurrences);
    });
    return result;
  }

  /// 统计单个症候的出现 / 好转 / 复发次数并算复发率。
  ///
  /// R-019：由 [getSyndromeRecurrences] 抽出（52 → 28 行）。
  SyndromeRecurrence _buildRecurrence(
    String syndromeId,
    List<({String name, String status, int createdAt})> records,
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
    );
  }

  /// X-041b：症候-训练通过率聚合（用户级全局，跨会话）
  ///
  /// 数据源 training_results 表（X-041a P0 持久化）。返回每个症候的
  /// passed/partial/failed 三态计数 + 通过率，按 total DESC 排序。
  ///
  /// UI 用途：成长详情页「训练通过率」区块，反映用户在各症候上的
  /// 练习投入量与掌握程度，作为长期进步曲线的补充维度。
  ///
  /// [days] 时间窗（默认近 30 天）；null 表示全量
  Future<List<SyndromeTrainingStats>> getSyndromeTrainingStats({
    int? days = 30,
  }) async {
    final repo = TrainingResultRepository(_db);
    if (days == null) {
      return repo.aggregateBySyndrome();
    }
    final since =
        DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch ~/
        1000;
    return repo.aggregateBySyndrome(sinceSec: since);
  }
}
