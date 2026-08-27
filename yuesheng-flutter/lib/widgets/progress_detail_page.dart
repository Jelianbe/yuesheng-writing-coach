// ─────────────────────────────────────────────────────────────
// ProgressDetailPage — 学习进度详情页（会话级）
// 真源：yuesheng-android/src/app/progress-detail.tsx
//
// 结构（对齐 RN）：
//   1. ProgressSummaryCard（当前阶段/诊断次数/总问题数/已解决/待改进）
//   2. DiagnosisHistory（诊断记录：日期/置信度/症候数）
//   3. SyndromeTrendList（症候趋势，点击 → 复用批次 8 SyndromeDetailModal）
//   4. ProblemStats（问题统计：严重度筛选 + 状态 + 发现/解决时间）
//   5. 生成学习报告 → ProgressReport 视图（复制 + 系统分享，批次 47 对齐 RN）
//
// 数据源：ProgressService（复刻 RN progress-service.ts）+ SyndromeTracker（批次 8）
// 入口：书架页「学习进度」卡片（最新会话）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../config/app_theme.dart';
import 'yue_sheet.dart';
import '../data/repositories/diagnosis_repository.dart';
import '../providers/app_providers.dart';
import '../services/progress_service.dart';
import '../services/syndrome_tracker.dart';
import '../types/teaching_types.dart';
import 'syndrome_detail_modal.dart';

/// 学习进度详情页
class ProgressDetailPage extends ConsumerStatefulWidget {
  final String sessionId;

  const ProgressDetailPage({super.key, required this.sessionId});

  @override
  ConsumerState<ProgressDetailPage> createState() => _ProgressDetailPageState();
}

class _ProgressDetailPageState extends ConsumerState<ProgressDetailPage> {
  ProgressSummary? _summary;
  List<DiagnosisRecord> _history = [];
  List<ProblemStat> _problems = [];
  List<SyndromeTracked> _trends = [];
  String _report = '';
  bool _showReport = false;
  bool _loading = true;
  bool _generating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// 并行加载四项数据（对齐 RN loadData Promise.all）
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = ref.read(appDatabaseProvider);
      final service = ProgressService(db);
      final tracker = SyndromeTracker(DiagnosisRepository(db));
      final results = await Future.wait([
        service.getProgressSummary(widget.sessionId),
        service.getDiagnosisHistory(widget.sessionId),
        service.getProblemStats(widget.sessionId),
        tracker.loadSyndromeTrends(widget.sessionId),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0] as ProgressSummary;
        _history = results[1] as List<DiagnosisRecord>;
        _problems = results[2] as List<ProblemStat>;
        _trends = results[3] as List<SyndromeTracked>;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '加载失败，请稍后重试';
        });
      }
    }
  }

  /// 生成学习报告（对齐 RN handleGenerateReport）
  Future<void> _handleGenerateReport() async {
    if (_generating) return;
    setState(() => _generating = true);
    try {
      final service = ProgressService(ref.read(appDatabaseProvider));
      final report = await service.generateReport(widget.sessionId);
      if (!mounted) return;
      setState(() {
        _report = report;
        _showReport = true;
        _generating = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _generating = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('生成失败，请稍后重试')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 报告视图（对齐 RN showReport 分支）
    if (_showReport) {
      return _ProgressReportView(
        report: _report,
        onBack: () => setState(() => _showReport = false),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('学习进度'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        toolbarHeight: 48,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 22),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/bookshelf'),
          tooltip: '返回',
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
            : _error != null
            ? _ErrorView(message: _error!, onRetry: _load)
            : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    final summary = _summary;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        if (summary != null) ...[
          _ProgressSummaryCard(summary: summary),
          const SizedBox(height: 12),
        ],
        if (_history.isNotEmpty) ...[
          _DiagnosisHistory(records: _history),
          const SizedBox(height: 12),
        ],
        // 症候趋势追踪（对齐 RN「症候趋势追踪」section）
        _SectionCard(
          title: '症候趋势追踪',
          child: _trends.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                  child: Column(
                    children: [
                      Icon(
                        Icons.trending_up,
                        size: 32,
                        color: AppColors.textTertiary,
                      ),
                      SizedBox(height: 8),
                      Text('暂无症候追踪', style: AppTextStyles.body),
                      SizedBox(height: 4),
                      Text(
                        '完成几次诊断后，这里会显示你的问题变化趋势',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    for (final s in _trends)
                      _TrendRow(
                        tracked: s,
                        onTap: () => _openSyndromeDetail(s),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        if (_problems.isNotEmpty) ...[
          _ProblemStats(problems: _problems),
          const SizedBox(height: 12),
        ],
        // 生成学习报告（对齐 RN reportButton）
        FilledButton(
          onPressed: _generating ? null : _handleGenerateReport,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            backgroundColor: AppColors.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
          child: _generating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.onPrimary,
                  ),
                )
              : const Text(
                  '生成学习报告',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onPrimary,
                  ),
                ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  /// 症候趋势行点击 → 复用批次 8 SyndromeDetailModal（对齐 RN handleSelectSyndrome）
  void _openSyndromeDetail(SyndromeTracked syndrome) {
    showYueModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SyndromeDetailModal(syndrome: syndrome),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 子组件
// ─────────────────────────────────────────────────────────────

/// 进度概览卡（对齐 RN ProgressSummaryCard：2+3 数据点）
class _ProgressSummaryCard extends StatelessWidget {
  final ProgressSummary summary;
  const _ProgressSummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final phaseLabel =
        progressPhaseLabels[summary.currentPhase] ?? summary.currentPhase.value;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _SummaryItem(value: phaseLabel, label: '当前阶段'),
              _SummaryItem(value: '${summary.totalDiagnoses}', label: '诊断次数'),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _SummaryItem(value: '${summary.totalProblems}', label: '总问题数'),
              _SummaryItem(value: '${summary.resolvedProblems}', label: '已解决'),
              _SummaryItem(value: '${summary.activeProblems}', label: '待改进'),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String value;
  final String label;
  const _SummaryItem({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: AppTextStyles.caption),
      ],
    );
  }
}

/// 诊断历史（对齐 RN DiagnosisHistory）
class _DiagnosisHistory extends StatelessWidget {
  final List<DiagnosisRecord> records;
  const _DiagnosisHistory({required this.records});

  static String _formatDate(int timestamp) {
    final d = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.month}月${d.day}日 $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '诊断历史',
      child: Column(
        children: [
          for (var i = 0; i < records.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              decoration: BoxDecoration(
                border: i == records.length - 1
                    ? null
                    : const Border(
                        bottom: BorderSide(color: AppColors.divider),
                      ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatDate(records[i].timestamp),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '置信度 ${(records[i].confidence * 100).round()}%',
                          style: AppTextStyles.caption,
                        ),
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      Text(
                        '${records[i].syndromeCount}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      const Text(
                        '症候',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.disabledText,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 症候趋势行（对齐 RN SyndromeTrendList item：标签/出现次数/迷你趋势/趋势文案）
class _TrendRow extends StatelessWidget {
  final SyndromeTracked tracked;
  final VoidCallback onTap;
  const _TrendRow({required this.tracked, required this.onTap});

  Color _severityColor(String severity) {
    switch (severity) {
      case 'L3':
        return AppColors.l3Text;
      case 'L2':
        return AppColors.l2Text;
      default:
        return AppColors.l1Text;
    }
  }

  Color _trendColor(String trend) {
    switch (trend) {
      case 'improving':
        return AppColors.primary;
      case 'worsening':
        return AppColors.danger;
      default:
        return AppColors.textTertiary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tracked.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _severityColor(tracked.currentSeverity),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '出现 ${tracked.occurrenceCount} 次',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.disabledText,
                    ),
                  ),
                ],
              ),
            ),
            // 迷你趋势条（对齐 MiniTrendChart：最近几次严重度色点）
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final p in tracked.recentPoints)
                  Container(
                    width: 6,
                    height: 18,
                    margin: const EdgeInsets.only(right: AppSpacing.xxs),
                    decoration: BoxDecoration(
                      color: _severityColor(p.severity),
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                    ),
                  ),
                const SizedBox(width: 8),
                Text(
                  getTrendLabel(tracked.trend),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _trendColor(tracked.trend),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 问题统计（对齐 RN ProblemStats：严重度筛选 + 状态 + 时间）
class _ProblemStats extends StatefulWidget {
  final List<ProblemStat> problems;
  const _ProblemStats({required this.problems});

  @override
  State<_ProblemStats> createState() => _ProblemStatsState();
}

class _ProblemStatsState extends State<_ProblemStats> {
  String _filter = '全部';

  static const _filters = ['全部', 'L3严重', 'L2注意', 'L1建议'];

  List<ProblemStat> get _filtered {
    switch (_filter) {
      case 'L3严重':
        return widget.problems.where((p) => p.severity == Severity.l3).toList();
      case 'L2注意':
        return widget.problems.where((p) => p.severity == Severity.l2).toList();
      case 'L1建议':
        return widget.problems.where((p) => p.severity == Severity.l1).toList();
      default:
        return widget.problems;
    }
  }

  static String _formatDate(int timestamp) {
    final d = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.month}月${d.day}日 $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final resolved = widget.problems
        .where((p) => p.status == 'resolved')
        .length;
    final active = widget.problems.where((p) => p.status == 'active').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionCard(
          title: '问题统计',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 严重度筛选 chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final f in _filters)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.sm),
                        child: InkWell(
                          onTap: () => setState(() => _filter = f),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: AppSpacing.xsm,
                            ),
                            decoration: BoxDecoration(
                              color: _filter == f
                                  ? AppColors.primarySoft
                                  : AppColors.surface,
                              borderRadius: BorderRadius.circular(
                                AppRadius.pill,
                              ),
                              border: Border.all(
                                color: _filter == f
                                    ? AppColors.primary
                                    : AppColors.divider,
                              ),
                            ),
                            child: Text(
                              f,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: _filter == f
                                    ? AppColors.primary
                                    : AppColors.textTertiary,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // 批次78 L5：筛选后无匹配项时渲染空态提示（原为空白）
              if (_filtered.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                  child: Center(
                    child: Text(
                      '该档暂无问题',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                )
              else
                for (var i = 0; i < _filtered.length; i++) ...[
                  _ProblemRow(problem: _filtered[i]),
                  if (i != _filtered.length - 1)
                    const Divider(height: 1, color: AppColors.divider),
                ],
            ],
          ),
        ),
        // 底部汇总（对齐 RN summaryFooter）
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: AppSpacing.md),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            '共 ${widget.problems.length} 条诊断 · $resolved 已处理 · $active 待处理',
            textAlign: TextAlign.center,
            style: AppTextStyles.caption,
          ),
        ),
      ],
    );
  }
}

class _ProblemRow extends StatelessWidget {
  final ProblemStat problem;
  const _ProblemRow({required this.problem});

  Color _severityColor(Severity s) {
    switch (s) {
      case Severity.l3:
        return AppColors.l3Text;
      case Severity.l2:
        return AppColors.l2Text;
      case Severity.l1:
        return AppColors.l1Text;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isResolved = problem.status == 'resolved';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          // 状态标签（对齐 RN problemStatus）
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: isResolved ? AppColors.primarySoft : AppColors.l3,
              borderRadius: BorderRadius.circular(AppRadius.xs),
            ),
            child: Text(
              isResolved ? '已解决' : '待改进',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isResolved ? AppColors.primary : AppColors.l3Text,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  problem.syndromeName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  severityLabels[problem.severity] ?? problem.severity.value,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _severityColor(problem.severity),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _ProblemStatsState._formatDate(problem.firstDetectedAt),
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.disabledText,
                ),
              ),
              if (problem.resolvedAt != null)
                Text(
                  '→ ${_ProblemStatsState._formatDate(problem.resolvedAt!)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.disabledText,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 学习报告视图（对齐 RN ProgressReport：返回/标题/复制/分享）
class _ProgressReportView extends StatelessWidget {
  final String report;
  final VoidCallback onBack;
  const _ProgressReportView({required this.report, required this.onBack});

  Future<void> _handleCopy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: report));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('报告内容已复制到剪贴板')));
    }
  }

  /// 系统分享报告文本（批次 47，对齐 RN ProgressReport handleShare）
  /// 分享面板打开失败/用户取消分享时静默忽略（RN 真源 catch 注释一致）
  Future<void> _handleShare() async {
    try {
      await SharePlus.instance.share(ShareParams(text: report));
    } catch (_) {
      // 用户取消分享或平台无可用分享目标，忽略
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('学习报告'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        toolbarHeight: 48,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 22),
          onPressed: onBack,
          tooltip: '返回',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy, size: 20),
            onPressed: () => _handleCopy(context),
            tooltip: '复制报告',
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined, size: 20),
            onPressed: _handleShare,
            tooltip: '分享',
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: SelectableText(
            report,
            style: const TextStyle(
              fontSize: 14,
              height: 1.7,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// 卡片容器（对齐 RN section：bgCard + radius + padding）
class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}

/// 错误视图
class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 40,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: 12),
          Text(message, style: AppTextStyles.body),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onRetry,
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }
}
