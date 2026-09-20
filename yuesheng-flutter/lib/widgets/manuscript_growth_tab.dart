// ─────────────────────────────────────────────────────────────
// manuscript_growth_tab — 书籍级成长页签（教学线 P0-2）
//
// 三层成长叙事的中间层出前台：熟练度圆环 + 症候概览 + 活跃问题
// + 复发。复用全库级 ProficiencyRing / SeverityBar（方案批次 D
// 定案：跨层视觉一致，仅换数据源）。
//
// 竖屏克制：卡片式纵向列表；空态引导去写作，不硬凑数据。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../data/repositories/diagnosis_repository.dart';
import '../providers/manuscript_growth_provider.dart';
import '../services/syndrome_recurrence.dart';
import '../types/teaching_types.dart';
import '../widgets/proficiency_ring.dart';
import '../widgets/severity_bar.dart';
import '../theme/app_typography.dart';

/// 书籍级成长页签。
class ManuscriptGrowthTab extends ConsumerWidget {
  final String manuscriptId;

  const ManuscriptGrowthTab({super.key, required this.manuscriptId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(manuscriptGrowthProvider(manuscriptId));
    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(message: '$e'),
      data: (data) {
        if (!data.hasData) return const _EmptyView();
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            _GrowthCard(
              child: _buildProficiency(
                context,
                data.profile,
                data.diagnosisCount,
              ),
            ),
            const SizedBox(height: 12),
            _GrowthCard(child: _buildSeverityOverview(data.activeProblems)),
            if (data.activeProblems.isNotEmpty) ...[
              const SizedBox(height: 12),
              _GrowthCard(
                child: _buildActiveProblems(context, data.activeProblems),
              ),
            ],
            if (data.recurrences.isNotEmpty) ...[
              const SizedBox(height: 12),
              _GrowthCard(child: _buildRecurrences(context, data.recurrences)),
            ],
          ],
        );
      },
    );
  }

  /// 熟练度卡：圆环 + 本书诊断数。
  Widget _buildProficiency(
    BuildContext context,
    StudentProfile? profile,
    int diagnosisCount,
  ) {
    final level = profile?.proficiency ?? ProficiencyLevel.beginner;
    final confidence = profile?.confidence ?? 0;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '本书能力画像',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: ProficiencyRing(level: level, confidence: confidence),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text('本书诊断 $diagnosisCount 次', style: context.text.subBody),
          ),
        ],
      ),
    );
  }

  /// 症候概览卡：SeverityBar + 活跃数 + 图例。
  Widget _buildSeverityOverview(List<ActiveProblemView> problems) {
    final counts = _countSeverities(problems);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '本书症候概览',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                '${problems.length} 个活跃',
                style: const TextStyle(fontSize: 12, color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SeverityBar(counts: counts, height: 10),
          const SizedBox(height: 8),
          Row(
            children: [
              _Legend(color: AppColors.l1, label: 'L1 ${counts.l1}'),
              const SizedBox(width: 12),
              _Legend(color: AppColors.l2, label: 'L2 ${counts.l2}'),
              const SizedBox(width: 12),
              _Legend(color: AppColors.l3, label: 'L3 ${counts.l3}'),
            ],
          ),
        ],
      ),
    );
  }

  /// 活跃问题列表（最多 5 条，克制信息量）。
  Widget _buildActiveProblems(
    BuildContext context,
    List<ActiveProblemView> problems,
  ) {
    final shown = problems.take(5).toList();
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '活跃问题',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          for (final p in shown)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  _SeverityDot(color: _severityColor(p.severity)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(p.syndromeName, style: context.text.subBody),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 复发卡：出现次数 + 复发次数（复用 SyndromeRecurrence 语义）。
  Widget _buildRecurrences(
    BuildContext context,
    List<SyndromeRecurrence> recurrences,
  ) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '本书复发追踪',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          for (final r in recurrences)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '${r.syndromeName}：出现 ${r.occurrences} 次 · 复发 ${r.recurrences} 次',
                style: context.text.subBody,
              ),
            ),
        ],
      ),
    );
  }

  /// 统计严重度计数（与全库级成长页同一口径）。
  SeverityCounts _countSeverities(List<ActiveProblemView> problems) {
    int l1 = 0, l2 = 0, l3 = 0;
    for (final p in problems) {
      switch (p.severity) {
        case 'L1':
          l1++;
          break;
        case 'L2':
          l2++;
          break;
        case 'L3':
          l3++;
          break;
      }
    }
    return SeverityCounts(l1: l1, l2: l2, l3: l3);
  }

  Color _severityColor(String severity) {
    switch (severity) {
      case 'L1':
        return AppColors.l1;
      case 'L3':
        return AppColors.l3;
      default:
        return AppColors.l2;
    }
  }
}

/// 通用卡片容器（复刻全库级成长页样式：ClipRRect + 左主色条）。
class _GrowthCard extends StatelessWidget {
  final Widget child;

  const _GrowthCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [Expanded(child: child)]),
      ),
    );
  }
}

/// 图例项。
class _Legend extends StatelessWidget {
  final Color color;
  final String label;

  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: context.text.subBody),
      ],
    );
  }
}

/// 严重度圆点。
class _SeverityDot extends StatelessWidget {
  final Color color;

  const _SeverityDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// 空态：无本书诊断 / 无活跃问题。
class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.auto_graph, size: 48, color: AppColors.textSecondary),
            SizedBox(height: 12),
            Text(
              '这本书还没有诊断记录',
              style: TextStyle(fontSize: 15, color: AppColors.textPrimary),
            ),
            SizedBox(height: 4),
            Text(
              '去写作并让教练诊断，就能看到本书的成长',
              style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

/// 错误态。
class _ErrorView extends StatelessWidget {
  final String message;

  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(
          '成长数据加载失败：$message',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
