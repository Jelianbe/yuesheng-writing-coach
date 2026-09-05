// ─────────────────────────────────────────────────────────────
// progress_service — 会话级学习进度统计（缺口清单 E 类）
// 真源：yuesheng-android/src/services/progress-service.ts
//
// 职责：
//   - getProgressSummary：教学状态 + 诊断统计 + 问题统计 + 锁定症候
//   - getDiagnosisHistory：诊断记录（日期/置信度/症候数）
//   - getProblemStats：问题统计（含已解决/待改进、发现/解决时间）
//   - generateReport：纯文本学习报告（无 IO，可单测）
//
// 数据源复用：TeachingStateRepository / DiagnosisRepository / active_problems 表
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import '../data/database/database.dart';
import '../data/repositories/diagnosis_repository.dart';
import '../data/repositories/teaching_state_repository.dart';
import '../types/teaching_types.dart';

/// 锁定症候（复刻 RN LockedSyndrome）
class LockedSyndrome {
  final String syndromeId;
  final String name;
  final Severity severity;
  final int lockedAt;
  final String lockStatus;
  const LockedSyndrome({
    required this.syndromeId,
    required this.name,
    required this.severity,
    required this.lockedAt,
    required this.lockStatus,
  });
}

/// 进度概览（复刻 RN ProgressSummary）
class ProgressSummary {
  final TeachingPhase currentPhase;
  final String? beginnerLevel;
  final int totalProblems;
  final int resolvedProblems;
  final int activeProblems;
  final int totalDiagnoses;
  final int? firstDiagnosisAt;
  final int? lastDiagnosisAt;
  final List<LockedSyndrome> lockedSyndromes;

  const ProgressSummary({
    required this.currentPhase,
    this.beginnerLevel,
    required this.totalProblems,
    required this.resolvedProblems,
    required this.activeProblems,
    required this.totalDiagnoses,
    this.firstDiagnosisAt,
    this.lastDiagnosisAt,
    this.lockedSyndromes = const [],
  });
}

/// 诊断记录（复刻 RN DiagnosisRecord）
class DiagnosisRecord {
  final String id;
  final int timestamp;
  final int syndromeCount;
  final double confidence;
  const DiagnosisRecord({
    required this.id,
    required this.timestamp,
    required this.syndromeCount,
    required this.confidence,
  });
}

/// 问题统计（复刻 RN ProblemStat）
class ProblemStat {
  final String syndromeId;
  final String syndromeName;
  final Severity severity;
  final String status; // 'active' | 'resolved'
  final int firstDetectedAt;
  final int? resolvedAt;
  const ProblemStat({
    required this.syndromeId,
    required this.syndromeName,
    required this.severity,
    required this.status,
    required this.firstDetectedAt,
    this.resolvedAt,
  });
}

/// 阶段中文名（对齐 RN phaseNames）
const Map<TeachingPhase, String> progressPhaseLabels = {
  TeachingPhase.p0Engage: '建立投入',
  TeachingPhase.p1World: '暴露问题',
  TeachingPhase.p2PracticeLoop: '训练循环',
  TeachingPhase.p3Training: '深度训练',
  TeachingPhase.p4Review: '复盘阶段',
};

/// 零基础等级中文名（对齐 RN beginnerLevelNames）
const Map<BeginnerLevel, String> beginnerLevelLabels = {
  BeginnerLevel.n0Engage: '建立投入（零基础）',
  BeginnerLevel.n1Elements: '基础元件练习',
  BeginnerLevel.n2Scene: '场景构建',
  BeginnerLevel.n3Diagnose: '问题诊断',
  BeginnerLevel.n4Independent: '独立创作',
};

/// 严重度中文名（对齐 RN severityLabels）
const Map<Severity, String> severityLabels = {
  Severity.l1: '轻微',
  Severity.l2: '中等',
  Severity.l3: '严重',
};

/// 学习进度服务
class ProgressService {
  final AppDatabase _db;
  ProgressService(this._db);

  /// 进度概览（复刻 RN getProgressSummary）
  Future<ProgressSummary> getProgressSummary(String sessionId) async {
    final stateRepo = TeachingStateRepository(_db);
    final diagRepo = DiagnosisRepository(_db);

    final teaching = await stateRepo.getTeachingState(sessionId);
    final history = await diagRepo.listDiagnosisHistory(sessionId);
    // active_problem 全量（含已解决），对齐 RN SQL 直查
    final problems = await (_db.select(
      _db.activeProblems,
    )..where((t) => t.sessionId.equals(sessionId))).get();

    final timestamps = [for (final h in history) h.timestamp];

    // 锁定症候：status='active'，按 created_at DESC（对齐 RN ORDER BY）
    final locked = [
      for (final p in problems.where((p) => p.status == 'active'))
        LockedSyndrome(
          syndromeId: p.syndromeId,
          name: p.syndromeName,
          severity: Severity.fromString(p.severity) ?? Severity.l2,
          lockedAt: p.createdAt,
          lockStatus: p.status,
        ),
    ]..sort((a, b) => b.lockedAt.compareTo(a.lockedAt));

    return ProgressSummary(
      currentPhase:
          TeachingPhase.fromString(teaching?.currentPhase) ??
          TeachingPhase.p0Engage,
      beginnerLevel: teaching?.beginnerLevel,
      totalProblems: problems.map((p) => p.syndromeId).toSet().length,
      resolvedProblems: problems.where((p) => p.status == 'resolved').length,
      activeProblems: problems.where((p) => p.status == 'active').length,
      totalDiagnoses: history.length,
      firstDiagnosisAt: timestamps.isEmpty ? null : timestamps.reduce(min),
      lastDiagnosisAt: timestamps.isEmpty ? null : timestamps.reduce(max),
      lockedSyndromes: locked,
    );
  }

  /// 诊断历史（复刻 RN getDiagnosisHistory：syndromes JSON → 症候计数）
  Future<List<DiagnosisRecord>> getDiagnosisHistory(String sessionId) async {
    final diagRepo = DiagnosisRepository(_db);
    final rows = await diagRepo.listDiagnosisHistory(sessionId);
    return [
      for (final row in rows)
        DiagnosisRecord(
          id: row.id,
          timestamp: row.timestamp,
          syndromeCount: _parseSyndromeCount(row.syndromes),
          confidence: row.confidence,
        ),
    ];
  }

  /// 问题统计（复刻 RN getProblemStats：active_problem 全量按 created_at DESC）
  Future<List<ProblemStat>> getProblemStats(String sessionId) async {
    final rows =
        await (_db.select(_db.activeProblems)
              ..where((t) => t.sessionId.equals(sessionId))
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.createdAt,
                  mode: OrderingMode.desc,
                ),
              ]))
            .get();
    return [
      for (final p in rows)
        ProblemStat(
          syndromeId: p.syndromeId,
          syndromeName: p.syndromeName,
          severity: Severity.fromString(p.severity) ?? Severity.l2,
          status: p.status,
          firstDetectedAt: p.createdAt,
          resolvedAt: p.resolvedAt,
        ),
    ];
  }

  /// 学习报告文本（复刻 RN generateReport：纯拼装，无 IO）
  Future<String> generateReport(String sessionId) async {
    final summary = await getProgressSummary(sessionId);
    final problemStats = await getProblemStats(sessionId);

    final phaseName = progressPhaseLabels[summary.currentPhase] ?? '未知';
    final activeProblems = problemStats
        .where((p) => p.status == 'active')
        .toList();
    final resolvedProblems = problemStats
        .where((p) => p.status == 'resolved')
        .toList();
    final resolveRate = summary.totalProblems > 0
        ? (summary.resolvedProblems * 100 / summary.totalProblems).round()
        : 0;

    final buffer = StringBuffer('📝 悦生写作教练 - 学习报告\n\n');
    _writeOverviewSection(buffer, summary, phaseName);
    _writeProblemStatsSection(buffer, summary, resolveRate);
    _writeActiveProblemsSection(buffer, activeProblems);
    _writeResolvedProblemsSection(buffer, resolvedProblems);
    _writeReportFooter(buffer);
    return buffer.toString();
  }

  /// 报告「学习概览」段（R-019 拆出：generateReport）。
  void _writeOverviewSection(
    StringBuffer buffer,
    ProgressSummary summary,
    String phaseName,
  ) {
    buffer.write('━━━━━━━━━━━━━━━━━━━━\n\n');
    buffer.write('📊 学习概览\n\n');
    buffer.write('当前阶段：$phaseName\n');
    final beginner = summary.beginnerLevel;
    if (beginner != null) {
      final label =
          beginnerLevelLabels[BeginnerLevel.fromString(beginner) ??
              BeginnerLevel.n0Engage] ??
          beginner;
      buffer.write('零基础路径：$label\n');
    }
    if (summary.lockedSyndromes.isNotEmpty) {
      buffer.write(
        '已锁定症候：${summary.lockedSyndromes.map((s) => s.name).join('、')}\n',
      );
    }
    buffer.write('诊断次数：${summary.totalDiagnoses} 次\n');
    buffer.write('首次诊断：${_formatDate(summary.firstDiagnosisAt)}\n');
    buffer.write('最近诊断：${_formatDate(summary.lastDiagnosisAt)}\n\n');
  }

  /// 报告「问题统计」段（R-019 拆出：generateReport）。
  void _writeProblemStatsSection(
    StringBuffer buffer,
    ProgressSummary summary,
    int resolveRate,
  ) {
    buffer.write('━━━━━━━━━━━━━━━━━━━━\n\n');
    buffer.write('🎯 问题统计\n\n');
    buffer.write('总问题数：${summary.totalProblems}\n');
    buffer.write('已解决：${summary.resolvedProblems}\n');
    buffer.write('待改进：${summary.activeProblems}\n');
    buffer.write('解决率：$resolveRate%\n\n');
  }

  /// 报告「待改进问题」段（R-019 拆出：generateReport）。
  void _writeActiveProblemsSection(
    StringBuffer buffer,
    List<ProblemStat> active,
  ) {
    if (active.isEmpty) return;
    buffer.write('━━━━━━━━━━━━━━━━━━━━\n\n');
    buffer.write('🔴 待改进问题（${active.length}个）\n\n');
    for (var i = 0; i < active.length; i++) {
      final p = active[i];
      buffer.write(
        '${i + 1}. ${p.syndromeName}（${severityLabels[p.severity] ?? p.severity.value}）\n',
      );
      buffer.write('   发现时间：${_formatDate(p.firstDetectedAt)}\n\n');
    }
  }

  /// 报告「已解决问题」段（R-019 拆出：generateReport）。
  void _writeResolvedProblemsSection(
    StringBuffer buffer,
    List<ProblemStat> resolved,
  ) {
    if (resolved.isEmpty) return;
    buffer.write('━━━━━━━━━━━━━━━━━━━━\n\n');
    buffer.write('🟢 已解决问题（${resolved.length}个）\n\n');
    for (var i = 0; i < resolved.length; i++) {
      final p = resolved[i];
      buffer.write(
        '${i + 1}. ${p.syndromeName}（${severityLabels[p.severity] ?? p.severity.value}）\n',
      );
      buffer.write('   发现：${_formatDate(p.firstDetectedAt)}\n');
      buffer.write('   解决：${_formatDate(p.resolvedAt)}\n\n');
    }
  }

  /// 报告结尾段（R-019 拆出：generateReport）。
  void _writeReportFooter(StringBuffer buffer) {
    buffer.write('━━━━━━━━━━━━━━━━━━━━\n');
    buffer.write('✨ 继续加油，坚持写作！');
  }

  /// 解析 syndromes JSON 计数（对齐 RN：Array.isArray ? length : 0）
  int _parseSyndromeCount(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return 0;
      return decoded.length;
    } catch (_) {
      return 0;
    }
  }

  static String _formatDate(int? timestamp) {
    if (timestamp == null) return '未记录';
    final d = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}
