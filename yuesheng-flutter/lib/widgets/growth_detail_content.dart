// ─────────────────────────────────────────────────────────────
// growth_detail_content — 成长详情页主体内容（从 State extension 真分解）
//
// 从 growth_content.dart（原 part）真分解而来（R-019：原 part 伪拆分根除）。
//
// 原 `extension _GrowthContent on _GrowthDetailPageState` 的纯渲染方法被
// 提取为独立 StatelessWidget [GrowthDetailContent]：数据经构造注入
// （[state]），两个导航回调经构造注入（[onOpenProgressDetail] /
// [onOpenStyleCorrection]）——不再隐式寄生在 State 上。
//
// 进一步拆分（R-019 文件 ≤300）：
//   - growth_detail_sections.dart        各内容区块组件
//   - growth_detail_syndrome_groups.dart 症候分组渲染
//
// 本文件只保留装配职责与区块列表构造。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../providers/growth_providers.dart';
import '../types/teaching_types.dart';
import 'ability_chart.dart';
import 'growth_detail_overview.dart';
import 'growth_detail_sections.dart';
import 'growth_detail_syndrome_groups.dart';
import 'growth_detail_timeline.dart';
import 'growth_detail_widgets.dart';
import 'growth_overview_card.dart';
import 'syndrome_history_list.dart';
import 'training_pass_rate_card.dart';
import 'writing_curve_chart.dart';

/// 成长详情页内容区（无状态，数据与回调构造注入）
class GrowthDetailContent extends StatelessWidget {
  /// 成长聚合状态
  final GrowthState state;

  /// 打开学习进度详情（批次77，由宿主/导航器提供）
  final VoidCallback onOpenProgressDetail;

  /// 打开风格纠正弹层（批次57，由宿主/导航器提供）
  final VoidCallback onOpenStyleCorrection;

  const GrowthDetailContent({
    super.key,
    required this.state,
    required this.onOpenProgressDetail,
    required this.onOpenStyleCorrection,
  });

  @override
  Widget build(BuildContext context) {
    final profile = state.profile;
    final hasDiagnoses =
        state.diagnosisHistory.isNotEmpty || state.activeProblems.isNotEmpty;

    // 空状态：无诊断 + 无画像
    if (!hasDiagnoses && (profile == null || profile.totalSessions == 0)) {
      return const GrowthEmptyState();
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        ..._buildOverviewSection(),
        const SizedBox(height: 12),
        GrowthAbilityProfileCard(profile: profile),
        const SizedBox(height: 12),
        ..._buildStyleSection(),
        ..._buildSyndromeSection(profile),
        const SizedBox(height: 12),
        ..._buildTrainingSection(),
        ..._buildRecurrenceSection(),
        ..._buildDiagnosisSection(),
        const SizedBox(height: 12),
        AbilityChart(scores: state.abilityScores),
        const SizedBox(height: 12),
        WritingCurveChart(points: state.writingCurve),
        const SizedBox(height: 12),
        SyndromeHistoryList(events: state.syndromeHistory, limit: 10),
        const SizedBox(height: 12),
        GrowthProgressLink(onTap: onOpenProgressDetail),
      ],
    );
  }

  /// 成长总览卡 + 写作总览网格（批次 51c）
  List<Widget> _buildOverviewSection() {
    final overview = state.overview;
    if (overview == null) return const [];
    return [
      GrowthOverviewCard(
        totalWords: overview.totalWords,
        diagnosisCount: overview.totalDiagnoses,
        resolvedCount: overview.totalResolved,
        aiInterventions: overview.aiInterventions,
        onViewDetail: onOpenProgressDetail,
      ),
      const SizedBox(height: 12),
      GrowthOverviewGrid(overview: overview),
    ];
  }

  /// 写作风格卡片（批次53c；无 style_profile 时不渲染）
  List<Widget> _buildStyleSection() {
    final styleProfile = state.styleProfile;
    if (styleProfile == null) return const [];
    return [
      GrowthStyleProfileCard(
        profile: styleProfile,
        onOpenStyleCorrection: onOpenStyleCorrection,
      ),
      const SizedBox(height: 12),
    ];
  }

  /// 症候分布列表（批次 48：按教学状态分组）
  List<Widget> _buildSyndromeSection(StudentProfile? profile) {
    if (state.activeProblems.isEmpty) return const [];
    return [
      const GrowthSectionTitle('症候分布', top: false),
      GrowthSyndromeGroupList(state: state, profile: profile),
    ];
  }

  /// X-041b：症候-训练通过率看板（近 30 天聚合，跨会话）
  List<Widget> _buildTrainingSection() {
    if (state.trainingStats.isEmpty) return const [];
    return [
      TrainingPassRateCard(stats: state.trainingStats),
      const SizedBox(height: 12),
    ];
  }

  /// 同类症候复发率（批次65 B62h：至少出现 2 次才有复发意义）
  List<Widget> _buildRecurrenceSection() {
    final recurrences = state.syndromeRecurrences
        .where((r) => r.occurrences >= 2)
        .toList();
    if (recurrences.isEmpty) return const [];
    return [
      const GrowthSectionTitle('同类症候复发率', top: true),
      GrowthRecurrenceCard(recurrences: recurrences),
      const SizedBox(height: 12),
    ];
  }

  /// 诊断历史时间线
  List<Widget> _buildDiagnosisSection() {
    if (state.diagnosisHistory.isEmpty) return const [];
    return [
      const GrowthSectionTitle('诊断历史', top: false),
      GrowthInfoCard(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: GrowthTimeline(items: state.diagnosisHistory),
        ),
      ),
    ];
  }
}
