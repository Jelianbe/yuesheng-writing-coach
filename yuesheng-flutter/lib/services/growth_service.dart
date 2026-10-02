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
import 'decode_guard.dart';
import 'syndrome_recurrence.dart';

// E-1：SyndromeRecurrence 已迁至 syndrome_recurrence.dart（与评估链路共用聚合实现）。
// re-export 保持既有消费方（growth_providers / growth_detail_widgets /
// growth_detail_sections）的 import 路径不变。
export 'syndrome_recurrence.dart' show SyndromeRecurrence;

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

  /// P2-10：零基础 N 系坐标（teaching_state 最新行；无记录为 null）
  final BeginnerLevel? currentBeginnerLevel;
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
    this.currentBeginnerLevel,
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
  final String date; // YYYY-MM-DD（本地自然日，B1：与用户本地日历对齐）
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

/// R-019 真分解（ADR-C112 ③）：成长总览的 6 段**只读查询**聚合为独立类。
///
/// 刻意**不含** B1 的本地自然日去重 —— 该逻辑依赖
/// `GrowthStatsExtension._localDateStr`（extension static，跨类型不可见），
/// 故由调用方拿到时间戳后完成，保证「SQL 文本」与「去重语义」两处都不变。
/// 6 段 SQL **逐字符**搬移，执行顺序由调用方保持（虽无依赖，保持以杜绝时序差异）。
class _GrowthOverviewQuery {
  _GrowthOverviewQuery(this._db);

  final AppDatabase _db;

  Future<QueryRow?> queryTotalWords() {
    return (_db.customSelect(
      'SELECT COALESCE(SUM(word_count), 0) AS total FROM chapters',
    )).getSingleOrNull();
  }

  Future<QueryRow?> queryDiagnosisStats() {
    return (_db.customSelect(
      'SELECT COUNT(*) AS total, '
      // COALESCE 兜底：空表时 SUM() 返回 NULL（对齐 RN `?? 0`）
      "COALESCE(SUM(CASE WHEN status = 'resolved' THEN 1 ELSE 0 END), 0) "
      'AS resolved, '
      "COALESCE(SUM(CASE WHEN status = 'active' THEN 1 ELSE 0 END), 0) "
      'AS active '
      'FROM active_problem',
    )).getSingleOrNull();
  }

  Future<QueryRow?> queryTeachingPhase() {
    return (_db.customSelect(
      'SELECT current_phase AS phase, beginner_level AS beginner '
      'FROM teaching_state '
      'ORDER BY updated_at DESC LIMIT 1',
    )).getSingleOrNull();
  }

  /// 返回全部 `updated_at`（秒）。B1：本地自然日去重在**调用方**完成 ——
  /// 本工程 sqlite 的 strftime('localtime') 不可用（恒返回 NULL），故取出
  /// 全部时刻后在 Dart 侧按本地 y/m/d 去重计数，避免 UTC+8 用户本地
  /// 00:00–08:00 的记录被并到前一个 UTC 日导致少算。
  Future<List<int>> queryWritingDays() async {
    final rows = await (_db.customSelect(
      'SELECT updated_at FROM chapters WHERE word_count > 0',
    )).get();
    return [for (final r in rows) r.read<int>('updated_at')];
  }

  Future<QueryRow?> queryChapterTimeRange() {
    return (_db.customSelect(
      'SELECT MIN(updated_at) AS first, MAX(updated_at) AS last '
      'FROM chapters WHERE word_count > 0',
    )).getSingleOrNull();
  }

  Future<QueryRow?> queryDiagnosisTotal() {
    // C126：只数 status='confirmed'（权威正式诊断）；pending/replaced 未确认不计入
    // 「诊断次数 / AI 介入次数」——不把教学轮反问结论当已确认。
    return (_db.customSelect(
      "SELECT COUNT(*) AS total FROM diagnosis_results WHERE status = 'confirmed'",
    )).getSingleOrNull();
  }
}

extension GrowthStatsExtension on GrowthService {
  /// 成长总览（复刻 RN getGrowthOverview）
  Future<GrowthOverview> getGrowthOverview() async {
    final q = _GrowthOverviewQuery(_db);
    final wordRow = await q.queryTotalWords();
    final diagRow = await q.queryDiagnosisStats();
    final phaseRow = await q.queryTeachingPhase();
    final writingDayStamps = await q.queryWritingDays();
    final writingDays = writingDayStamps.map(_localDateStr).toSet().length;
    final timeRow = await q.queryChapterTimeRange();
    final totalDiagnoses = await q.queryDiagnosisTotal();

    final trainingCount = await _countTrainingRecords();
    final diagTotal = totalDiagnoses?.read<int>('total') ?? 0;

    return _buildGrowthOverview(
      wordRow: wordRow,
      diagRow: diagRow,
      phaseRow: phaseRow,
      writingDays: writingDays,
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
      } catch (e, st) {
        logDecodeFailure(field: 'teachingHistory', error: e, stack: st);
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
    required int writingDays,
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
      writingDays: writingDays,
      firstWritingAt: timeRow?.read<int?>('first'),
      lastWritingAt: timeRow?.read<int?>('last'),
      // AI 介入 = 诊断 + 训练（学员每次请求 AI 处理作品即一次介入）
      aiInterventions: diagTotal + trainingCount,
    );
  }

  /// 最近 N 天写作曲线（复刻 RN getWritingCurve）
  ///
  /// 按本地自然日聚合（B1：与用户本地日历日对齐；时间戳本身是时刻，
  /// 桶化时按本地 y/m/d 归桶，不迁移历史数据），
  /// 返回完整的最近 [days] 天序列，从旧到新（RN Array.from(map.values) 插入序）
  Future<List<WritingDataPoint>> getWritingCurve({int days = 14}) async {
    final nowLocal = DateTime.now();
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final cutoff = nowSec - days * 86400;

    final rows = await _fetchCurveRows(cutoff);

    // 新用户无写作和诊断记录时返回空数组，触发 UI 空态引导文案
    if (rows.chapterRows.isEmpty && rows.diagnosisRows.isEmpty) return const [];

    // 初始化最近 days 天本地日期序列（B1：与本地自然日对齐）
    final byDate = _initCurveDateSequence(days, nowLocal);

    for (final row in rows.chapterRows) {
      // B1：由时刻在 Dart 侧归到本地自然日（与 _initCurveDateSequence 同口径）。
      final date = _localDateStr(row.read<int>('ts'));
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

    for (final row in rows.diagnosisRows) {
      final date = _localDateStr(row.read<int>('ts'));
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

  /// 拉取曲线原始行：章节省字数 + 诊断记录（R-019 拆出：getWritingCurve）。
  ///
  /// B1：SQL 只取原始时刻（本工程 sqlite 的 strftime('localtime') 不可用），
  /// 本地自然日桶化在调用方用 [_localDateStr] 完成。
  Future<({List<QueryRow> chapterRows, List<QueryRow> diagnosisRows})>
  _fetchCurveRows(int cutoff) async {
    final chapterRows = await (_db.customSelect(
      'SELECT updated_at AS ts, word_count AS words FROM chapters '
      'WHERE updated_at >= ? AND word_count > 0 ORDER BY updated_at ASC',
      variables: [Variable.withInt(cutoff)],
    )).get();

    final diagnosisRows = await (_db.customSelect(
      'SELECT timestamp AS ts FROM diagnosis_results '
      'WHERE timestamp >= ? ORDER BY timestamp ASC',
      variables: [Variable.withInt(cutoff)],
    )).get();
    return (chapterRows: chapterRows, diagnosisRows: diagnosisRows);
  }

  /// 初始化最近 days 天本地日期序列（R-019 拆出：getWritingCurve）。
  ///
  /// B1：以本地今日 0 点为锚，逐天向前铺 [days] 个本地自然日；
  /// timestamp 取该日本地 0 点的秒级时刻。
  Map<String, WritingDataPoint> _initCurveDateSequence(
    int days,
    DateTime nowLocal,
  ) {
    final byDate = <String, WritingDataPoint>{};
    for (var i = days - 1; i >= 0; i--) {
      final d = nowLocal.subtract(Duration(days: i));
      final dateStr = _formatLocalDate(d);
      byDate[dateStr] = WritingDataPoint(
        date: dateStr,
        timestamp:
            DateTime(d.year, d.month, d.day).millisecondsSinceEpoch ~/ 1000,
        wordCount: 0,
        diagnosisCount: 0,
      );
    }
    return byDate;
  }

  static String _formatLocalDate(DateTime local) {
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  /// B1：unix 秒 → 本地自然日 yyyy-MM-dd（DateTime 默认本地时区）。
  ///
  /// 历史时间戳本身是绝对时刻，这里仅做本地日历日归桶，不迁移历史数据。
  static String _localDateStr(int tsSec) {
    final d = DateTime.fromMillisecondsSinceEpoch(tsSec * 1000);
    return _formatLocalDate(d);
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
    } catch (e, st) {
      logDecodeFailure(field: 'growthJson', error: e, stack: st);
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
  /// E-1：实现已抽至 [querySyndromeRecurrences]（syndrome_recurrence.dart），
  /// 与评估链路（`DiagnosisRepository.getSyndromeRecurrences`）共用同一聚合，
  /// 避免复发语义出现双实现。本方法保留为成长页既有调用入口。
  Future<List<SyndromeRecurrence>> getSyndromeRecurrences() =>
      querySyndromeRecurrences(_db);

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
